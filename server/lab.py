#!/usr/bin/env python3
"""
The Guild Protocol — lab server.

Zero dependencies, Python 3.8+ standard library only. Talks to the chain through `cast`
(Foundry), so there is no wallet library, no key handling in Python, and nothing to install
at the venue.

    python3 server/lab.py                      # http://127.0.0.1:8080
    RPC=https://sepolia.base.org python3 server/lab.py --host 0.0.0.0

What it does
------------
1. Serves the static site in web/.
2. Collects EIP-712 ballots. Signing costs nothing and sends nothing; a ballot sits in a queue.
3. Submits the queue as ONE transaction at poll close. That is the whole lesson: 25 signatures,
   1 transaction, and a console that shows you exactly which ballots were dropped and why.
4. Streams live state over SSE so the projector updates without polling lag.

Why a server at all
-------------------
Because "a signature is not a transaction" is only true if the signature has somewhere to wait.
"""
from __future__ import annotations

import argparse
import json
import re
import os
import re
import secrets
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
DATA = ROOT / "data"
BALLOT_LOG = DATA / "ballots.jsonl"

FOUNDRY_BIN = Path.home() / ".foundry" / "bin"
if FOUNDRY_BIN.is_dir():
    os.environ["PATH"] = f"{FOUNDRY_BIN}:{os.environ.get('PATH', '')}"

RPC = os.environ.get("RPC", "http://127.0.0.1:8545")


def _secret(env: str, filename: str, default: str = "") -> str:
    """Env first, then a 0600 file. Files keep keys out of `ps -E` and shell history."""
    v = os.environ.get(env, "")
    if v:
        return v
    f = DATA / filename
    if f.exists():
        return f.read_text().strip()
    return default


OPERATOR_KEY = _secret("OPERATOR_KEY", "operator-key")
OPERATOR_TOKEN = _secret("OPERATOR_TOKEN", "operator-token") or secrets.token_urlsafe(9)

SIG_RE = re.compile(r"^0x[0-9a-fA-F]{130}$")

# Sponsored badge mint. On a public chain someone has to pay, and pretending otherwise is how
# labs teach the wrong model. The operator pays, the room is told so, and the cap is enforced
# both on-chain (MAX_SUPPLY) and here (so a griefer cannot burn the whole allowance before doors).
SPONSOR_ROUTE = os.environ.get("LAB_ROUTE", "0x0102050709")
SPONSOR_CAP = int(os.environ.get("SPONSOR_CAP", "240"))
_sponsor_lock = threading.Lock()
_sponsor_count = {"n": 0}
_sponsor_ips: dict[str, list[float]] = {}
SELECTOR_RE = re.compile(r"custom error (0x[0-9a-fA-F]{8})")

# Built from `cast sig` at startup, so it always matches the deployed contract's errors.
ERRORS: dict[str, str] = {}
ADDR_RE = re.compile(r"^0x[0-9a-fA-F]{40}$")

# --------------------------------------------------------------------------- chain


class Chain:
    def __init__(self) -> None:
        self.deploy = self._load_deploy()
        self._lock = threading.Lock()
        self._cache: tuple[float, dict] | None = None

    def _load_deploy(self) -> dict:
        chain_id = sh("cast", "chain-id", "--rpc-url", RPC, timeout=15).strip()
        path = ROOT / "deployments" / f"{chain_id}.json"
        if not path.exists():
            sys.exit(
                f"no deployment for chain {chain_id}.\n"
                f"expected {path}\n"
                f"run: PRIVATE_KEY=0x... RPC={RPC} ./scripts/deploy.sh"
            )
        return json.loads(path.read_text())

    # cast helpers ---------------------------------------------------------

    def call(self, address: str, signature: str, *args: str) -> str:
        return sh("cast", "call", address, signature, *args, "--rpc-url", RPC, timeout=25).strip()

    def balance(self, address: str) -> int:
        return to_int(sh("cast", "balance", address, "--rpc-url", RPC, timeout=15))

    # state ----------------------------------------------------------------

    def state(self) -> dict:
        with self._lock:
            if self._cache and time.time() - self._cache[0] < 1.5:
                return self._cache[1]
            s = self._state_uncached()
            self._cache = (time.time(), s)
            return s

    def _state_uncached(self) -> dict:
        d = self.deploy
        polls = {}
        for name, pid in (("poll1", d["poll1"]), ("poll2", d["poll2"])):
            try:
                tally = to_int_list(self.call(d["ballot"], "tallyOf(bytes32)(uint256[])", pid))
                meta = self.call(
                    d["ballot"],
                    "polls(bytes32)(string,uint8,uint8,uint64,uint64,bool,bool)",
                    pid,
                )
                lines = [x.strip() for x in meta.splitlines() if x.strip()]
                polls[name] = {
                    "id": pid,
                    "tally": tally,
                    "label": lines[0] if lines else "",
                    "optionCount": to_int(lines[1]) if len(lines) > 1 else 2,
                    "mode": to_int(lines[2]) if len(lines) > 2 else 0,
                    "opensAt": to_int(lines[3]) if len(lines) > 3 else 0,
                    "closesAt": to_int(lines[4]) if len(lines) > 4 else 0,
                    "exists": (lines[5].lower() == "true") if len(lines) > 5 else False,
                    "finalized": (lines[6].lower() == "true") if len(lines) > 6 else False,
                }
            except Exception as e:  # noqa: BLE001 - a broken poll must not kill the projector
                polls[name] = {"id": pid, "tally": [0, 0], "error": str(e)}

        reserves = to_int_list(self.call(d["pair"], "getReserves()(uint256,uint256)"))
        return {
            "ts": int(time.time()),
            "chainId": int(d["chainId"]),
            "block": to_int(sh("cast", "block-number", "--rpc-url", RPC, timeout=15)),
            "polls": polls,
            "price": to_int(self.call(d["pair"], "spotPrice()(uint256)")),
            "reserves": reserves,
            "swaps": to_int(self.call(d["pair"], "swapCount()(uint256)")),
            "badges": to_int(self.call(d["badge"], "nextId()(uint256)")) - 1,
            "sponsored": _sponsor_count["n"],
            "queued": store.counts(),
        }


# --------------------------------------------------------------------------- ballots


class BallotStore:
    """Signatures that exist and have not been submitted yet.

    Keyed by (pollId, signer): one ballot per address per poll. A delegate may re-sign before
    the batch lands, and the later signature replaces the earlier one. After submission the
    record is frozen.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._items: dict[tuple[str, str], dict] = {}
        self._load()

    def _load(self) -> None:
        if not BALLOT_LOG.exists():
            return
        for line in BALLOT_LOG.read_text().splitlines():
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            self._items[(r["pollId"], r["signer"].lower())] = r

    def add(self, poll_id: str, signer: str, choice: int, signature: str) -> dict:
        rec = {
            "pollId": poll_id,
            "signer": signer,
            "choice": choice,
            "signature": signature,
            "receivedAt": int(time.time()),
            "submitted": False,
            "txHash": None,
        }
        with self._lock:
            key = (poll_id, signer.lower())
            if self._items.get(key, {}).get("submitted"):
                raise ValueError("this address has already been submitted on chain")
            self._items[key] = rec
            self._append(rec)
        return rec

    def _append(self, rec: dict) -> None:
        DATA.mkdir(exist_ok=True)
        with BALLOT_LOG.open("a") as fh:
            fh.write(json.dumps(rec) + "\n")

    def queued(self, poll_id: str) -> list[dict]:
        with self._lock:
            return [
                r
                for (p, _), r in self._items.items()
                if p == poll_id and not r["submitted"]
            ]

    def all(self, poll_id: str) -> list[dict]:
        with self._lock:
            return [r for (p, _), r in self._items.items() if p == poll_id]

    def mark_submitted(self, records: list[dict], tx: str) -> None:
        with self._lock:
            for r in records:
                key = (r["pollId"], r["signer"].lower())
                if key in self._items:
                    self._items[key]["submitted"] = True
                    self._items[key]["txHash"] = tx
                    self._append(self._items[key])

    def counts(self) -> dict:
        with self._lock:
            q = sum(1 for r in self._items.values() if not r["submitted"])
            s = sum(1 for r in self._items.values() if r["submitted"])
        return {"queued": q, "submitted": s}


# --------------------------------------------------------------------------- cast io


def sh(*cmd: str, timeout: int = 30) -> str:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError("cast timed out — is the RPC reachable?") from None
    if p.returncode != 0:
        raise RuntimeError((p.stderr or p.stdout or "cast failed").strip()[:500])
    return p.stdout


def to_int(raw: str) -> int:
    """cast appends a hint like `1000000000000000000 [1e18]`. Strip it."""
    raw = raw.strip()
    if "[" in raw:
        raw = raw.split("[")[0].strip()
    return int(raw)


def to_int_list(raw: str) -> list[int]:
    """cast prints arrays as `[1, 2]` or a JSON array; accept both, plus Anvil's `1e18` hints."""
    raw = raw.strip()
    inner = raw[1:-1] if raw.startswith("[") and raw.endswith("]") else raw
    out = []
    for part in inner.replace("\n", " ").split(","):
        part = part.strip()
        if not part:
            continue
        if "[" in part:  # cast appends a human hint like `1000000000000000000 [1e18]`
            part = part.split("[")[0].strip()
        out.append(int(part))
    return out


def abi_array(values: list[str]) -> str:
    return "[" + ",".join(values) + "]"


# --------------------------------------------------------------------------- submit


def submit(chain: Chain, poll_id: str) -> dict:
    """Pre-flight every ballot individually, then send the survivors as one transaction.

    The pre-flight is the point. One malformed or already-used signature would revert the whole
    batch, and a batch that reverts takes the room down with it. So each ballot is simulated
    with `cast call` first, and the rejects are returned with their reason — which is also the
    most honest thing you can put on a projector.
    """
    queued = store.queued(poll_id)
    if not queued:
        raise ValueError("no ballots queued for this poll")

    valid, rejected = [], []
    for rec in queued:
        try:
            already = chain.call(
                chain.deploy["ballot"],
                "hasVoted(bytes32,address)(bool)",
                poll_id,
                rec["signer"],
            ).strip().lower()
            if already == "true":
                rejected.append({"signer": rec["signer"], "reason": "already voted"})
                continue
        except RuntimeError:
            pass

        try:
            sh(
                "cast", "call", chain.deploy["ballot"],
                "castVotes(bytes32,address[],uint8[],bytes[])",
                poll_id,
                abi_array([rec["signer"]]),
                abi_array([str(rec["choice"])]),
                abi_array([rec["signature"]]),
                "--rpc-url", RPC,
                timeout=25,
            )
            valid.append(rec)
        except RuntimeError as e:
            rejected.append({"signer": rec["signer"], "reason": short_reason(str(e))})

    if not valid:
        raise ValueError(
            "every queued ballot failed pre-flight: "
            + "; ".join(f"{r['signer']}: {r['reason']}" for r in rejected)
        )

    if not OPERATOR_KEY:
        raise ValueError("OPERATOR_KEY is not set — the server cannot send transactions")

    out = sh(
        "cast", "send", chain.deploy["ballot"],
        "castVotes(bytes32,address[],uint8[],bytes[])",
        poll_id,
        abi_array([r["signer"] for r in valid]),
        abi_array([str(r["choice"]) for r in valid]),
        abi_array([r["signature"] for r in valid]),
        "--private-key", OPERATOR_KEY,
        "--rpc-url", RPC,
        "--json",
        timeout=90,
    )
    tx = json.loads(out).get("transactionHash", "")
    store.mark_submitted(valid, tx)

    return {
        "submitted": len(valid),
        "rejected": rejected,
        "txHash": tx,
        "explorer": f"https://sepolia.basescan.org/tx/{tx}" if chain.deploy["chainId"] == 84532 else None,
    }


def build_error_map() -> None:
    known = [
        ("AlreadyVoted()", "already voted"),
        ("BadSignature()", "signature does not match signer"),
        ("PollClosed()", "poll closed"),
        ("PollNotOpen()", "poll not open"),
        ("BadChoice()", "choice out of range"),
        ("PollUnknown()", "unknown poll"),
    ]
    for sig, label in known:
        try:
            ERRORS[sh("cast", "sig", sig, timeout=10).strip().lower()] = label
        except RuntimeError:
            pass


def short_reason(msg: str) -> str:
    m = SELECTOR_RE.search(msg)
    if m and m.group(1).lower() in ERRORS:
        return ERRORS[m.group(1).lower()]
    for known, label in (
        ("AlreadyVoted", "already voted"),
        ("BadSignature", "signature does not match signer"),
        ("PollClosed", "poll closed"),
        ("PollNotOpen", "poll not open"),
        ("BadChoice", "choice out of range"),
        ("revert", "reverted"),
    ):
        if known in msg:
            return label
    return msg.splitlines()[0][:120]


# --------------------------------------------------------------------------- http


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "GuildProtocol/1.0"

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(WEB), **kw)

    # -- helpers ---------------------------------------------------------

    def end_headers(self):
        """Never let an edge cache hold a stale config.js.

        Cloudflare caches .js by extension with a four-hour default TTL. After a redeploy that
        means browsers get yesterday's contract addresses and every action fails in a way that
        looks like a contract bug. `no-store` makes the edge bypass us entirely.
        """
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        super().end_headers()

    def send_json(self, obj, code: int = 200) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0:
            return {}
        return json.loads(self.rfile.read(n) or b"{}")

    def operator_ok(self) -> bool:
        return (self.headers.get("X-Operator-Token") or "") == OPERATOR_TOKEN

    def log_message(self, fmt, *args):  # quieter, one line
        if "/api/events" in (self.path or ""):
            return
        sys.stderr.write(f"{time.strftime('%H:%M:%S')} {fmt % args}\n")

    # -- routes ----------------------------------------------------------

    def do_GET(self):  # noqa: N802
        u = urlparse(self.path)
        try:
            if u.path == "/api/health":
                return self.send_json({
                    "ok": True,
                    "chainId": chain.deploy["chainId"],
                    "rpc": RPC,
                    "operatorKey": bool(OPERATOR_KEY),
                })

            if u.path == "/api/state":
                return self.send_json(state_payload())

            if u.path == "/api/ballots":
                pid = (parse_qs(u.query).get("poll") or [chain.deploy["poll1"]])[0]
                return self.send_json({"pollId": pid, "ballots": redact(store.all(pid))})

            if u.path == "/api/events":
                return self.stream_events()

            path = u.path if u.path not in ("", "/") else "/index.html"
            if path.endswith((".html", ".js")):
                f = WEB / path.lstrip("/")
                if f.is_file():
                    body = stamp(f.read_text()).encode()
                    self.send_response(200)
                    self.send_header(
                        "Content-Type",
                        "text/html; charset=utf-8" if path.endswith(".html") else "text/javascript; charset=utf-8",
                    )
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return

            return super().do_GET()
        except BrokenPipeError:
            pass
        except Exception as e:  # noqa: BLE001
            import traceback
            traceback.print_exc()
            return self.send_json({"error": str(e)}, 500)

    def do_POST(self):  # noqa: N802
        u = urlparse(self.path)
        try:
            body = self.read_json()

            if u.path == "/api/ballot":
                return self.post_ballot(body)

            if u.path == "/api/mint":
                return self.post_mint(body)

            if u.path == "/api/submit":
                if not self.operator_ok():
                    return self.send_json({"error": "bad operator token"}, 401)
                pid = body.get("pollId") or chain.deploy["poll1"]
                t0 = time.time()
                result = submit(chain, pid)
                result["seconds"] = round(time.time() - t0, 2)
                return self.send_json(result)

            return self.send_json({"error": "not found"}, 404)
        except ValueError as e:
            return self.send_json({"error": str(e)}, 400)
        except Exception as e:  # noqa: BLE001
            import traceback
            traceback.print_exc()
            return self.send_json({"error": str(e)}, 500)

    # -- handlers --------------------------------------------------------

    def post_ballot(self, body: dict) -> None:
        poll_id = str(body.get("pollId") or "")
        signer = str(body.get("signer") or "")
        signature = str(body.get("signature") or "")
        choice = body.get("choice")

        if poll_id not in (chain.deploy["poll1"], chain.deploy["poll2"]):
            raise ValueError("unknown poll")
        if not ADDR_RE.match(signer):
            raise ValueError("signer must be a 20-byte address")
        if not SIG_RE.match(signature):
            raise ValueError("signature must be 65 bytes")
        if not isinstance(choice, int) or not 0 <= choice <= 3:
            raise ValueError("choice must be 0..3")

        rec = store.add(poll_id, signer, choice, signature)
        return self.send_json({
            "ok": True,
            "queued": len(store.queued(poll_id)),
            "receivedAt": rec["receivedAt"],
        })

    def post_mint(self, body: dict) -> None:
        """Mint the badge on someone else's behalf, at the operator's expense.

        This is the honest version of zero-gas UX: a named party pays. Every attendee sees the
        transaction hash, and the console can show exactly how much sponsorship was spent.
        """
        to = str(body.get("address") or "")
        guild = body.get("guild")
        if not ADDR_RE.match(to):
            raise ValueError("address must be a 20-byte address")
        if not isinstance(guild, int) or not 1 <= guild <= 25:
            raise ValueError("guild must be 1..25")
        if not OPERATOR_KEY:
            raise ValueError("this server has no operator key, so it cannot sponsor")

        # Duplicate check first: it costs one RPC call and must not consume a sponsorship slot.
        try:
            if chain.call(chain.deploy["badge"], "hasClaimed(address)(bool)", to).strip().lower() == "true":
                raise ValueError("this address already holds a badge")
        except RuntimeError:
            pass  # if the read fails, the contract still refuses; do not block the claim

        ip = (self.headers.get("CF-Connecting-IP") or self.client_address[0]).split(",")[0].strip()
        now = time.time()
        with _sponsor_lock:
            recent = [t for t in _sponsor_ips.get(ip, []) if now - t < 3600]
            if len(recent) >= 2:
                raise ValueError("this connection has already sponsored 2 badges in the last hour")
            if _sponsor_count["n"] >= SPONSOR_CAP:
                raise ValueError("the sponsored allowance is exhausted — ask a helper for the fallback")
            _sponsor_ips[ip] = recent + [now]
            _sponsor_count["n"] += 1

        try:
            out = sh(
                "cast", "send", chain.deploy["badge"],
                "claimFor(address,uint8,bytes)", to, str(guild), SPONSOR_ROUTE,
                "--private-key", OPERATOR_KEY, "--rpc-url", RPC, "--json", timeout=90,
            )
        except RuntimeError as e:
            with _sponsor_lock:
                _sponsor_count["n"] -= 1
            raise ValueError(f"sponsorship failed: {short_reason(str(e))}") from None

        tx = json.loads(out).get("transactionHash", "")
        return self.send_json({
            "ok": True,
            "txHash": tx,
            "sponsored": _sponsor_count["n"],
            "remaining": SPONSOR_CAP - _sponsor_count["n"],
        })

    def stream_events(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        try:
            while True:
                payload = json.dumps(state_payload())
                self.wfile.write(f"data: {payload}\n\n".encode())
                self.wfile.flush()
                time.sleep(2)
        except (BrokenPipeError, ConnectionResetError):
            return


# --------------------------------------------------------------------------- build stamp

ASSET_RE = re.compile(r"(\./(?:lib|config)\.js|\./style\.css)(?!\?[v=])")


def build_id() -> str:
    """mtime of the generated config: changes on every deploy, stable within one."""
    try:
        return str(int((WEB / "config.js").stat().st_mtime))
    except OSError:
        return "0"


def stamp(text: str) -> str:
    """Append ?v=<build> to local asset references.

    Cloudflare applies its own 4h TTL to .js regardless of what the origin says, so header
    hygiene cannot guarantee a fresh config.js after a redeploy. Versioning the URL can: a new
    build is a new URL, and the edge has never seen it.
    """
    return ASSET_RE.sub(lambda m: f"{m.group(1)}?v={build_id()}", text)


def redact(records: list[dict]) -> list[dict]:
    """Signatures are public by design, but the console does not need all 132 characters."""
    return [
        {
            "signer": r["signer"],
            "choice": r["choice"],
            "signature": r["signature"][:18] + "…",
            "submitted": r["submitted"],
            "txHash": r["txHash"],
            "receivedAt": r["receivedAt"],
        }
        for r in records
    ]


def state_payload() -> dict:
    s = chain.state()
    s["queued"] = store.counts()
    return s


# --------------------------------------------------------------------------- main


def main() -> None:
    global chain, store

    ap = argparse.ArgumentParser(description="Guild Protocol lab server")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8080)
    args = ap.parse_args()

    chain = Chain()
    store = BallotStore()
    build_error_map()

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    httpd.daemon_threads = True

    print("─" * 66)
    print("  THE GUILD PROTOCOL — lab server")
    print("─" * 66)
    print(f"  chain        {chain.deploy['chainId']}  ({RPC})")
    print(f"  site         http://{args.host}:{args.port}/")
    print(f"  projector    http://{args.host}:{args.port}/spectator.html")
    print(f"  console      http://{args.host}:{args.port}/admin.html")
    print(f"  ballots      {len(store.all(chain.deploy['poll1']))} logged, {store.counts()['queued']} queued")
    print(f"  operator key {'set' if OPERATOR_KEY else 'NOT SET — /api/submit will refuse'}")
    print(f"  token        {OPERATOR_TOKEN}")
    print("─" * 66)
    sys.stdout.flush()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


chain: Chain
store: BallotStore

if __name__ == "__main__":
    main()
