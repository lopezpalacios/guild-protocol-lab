#!/usr/bin/env python3
"""
rpcguard — a JSON-RPC allowlist in front of anvil.

Anvil exposes `anvil_setBalance`, `anvil_impersonateAccount`, `anvil_mine` and friends. On a
laptop that is convenient. On a public hostname that a room full of crypto engineers can read
off a projector, it is an invitation: anyone can mint themselves gas and drain the demo pool
mid-session.

This sits on :8546 and forwards only read/transaction methods to :8545. Everything else is
rejected with a clean JSON-RPC error, which is itself a decent teaching moment.

    python3 server/rpcguard.py --upstream http://127.0.0.1:8545 --port 8546
"""
from __future__ import annotations

import argparse
import json
import sys
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

ALLOWED_PREFIXES = ("eth_", "net_", "web3_")

# Named individually because they are the ones people actually reach for.
BLOCKED = {
    "anvil_setBalance",
    "anvil_setCode",
    "anvil_setStorageAt",
    "anvil_impersonateAccount",
    "anvil_mine",
    "anvil_reset",
    "anvil_dumpState",
    "hardhat_setBalance",
    "evm_mine",
}

UPSTREAM = ("127.0.0.1", 8545)
CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
}


def method_allowed(m: str) -> bool:
    if m in BLOCKED:
        return False
    return any(m.startswith(p) for p in ALLOWED_PREFIXES)


def check(payload):
    """Return (ok, offending_method). Handles single and batch JSON-RPC."""
    items = payload if isinstance(payload, list) else [payload]
    for it in items:
        if not isinstance(it, dict):
            return False, "malformed"
        if not method_allowed(str(it.get("method", ""))):
            return False, str(it.get("method", "?"))
    return True, None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "rpcguard/1.0"

    def log_message(self, fmt, *args):
        pass  # quiet: this is behind a tunnel and would otherwise fill the disk

    def _cors(self):
        for k, v in CORS.items():
            self.send_header(k, v)
        self.send_header("Cache-Control", "no-store")

    def do_OPTIONS(self):  # noqa: N802
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):  # noqa: N802
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._cors()
        body = json.dumps({"ok": True, "guard": "rpcguard", "upstream": "anvil"}).encode()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):  # noqa: N802
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > 512_000:
            return self._reply(413, {"error": "body too large or empty"})
        raw = self.rfile.read(n)

        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return self._reply(400, {"error": "invalid json"})

        ok, offending = check(payload)
        if not ok:
            mine = payload[0] if isinstance(payload, list) else payload
            rid = (mine or {}).get("id")
            self._reply(200, {
                "jsonrpc": "2.0",
                "id": rid,
                "error": {
                    "code": -32601,
                    "message": f"rpcguard: method '{offending}' is not available on this endpoint",
                },
            })
            return

        try:
            conn = http.client.HTTPConnection(*UPSTREAM, timeout=20)
            conn.request("POST", "/", body=raw, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            body = resp.read()
            conn.close()
        except OSError as e:
            return self._reply(502, {"error": f"upstream unreachable: {e}"})

        self.send_response(resp.status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _reply(self, code: int, obj: dict):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    global UPSTREAM
    ap = argparse.ArgumentParser()
    ap.add_argument("--upstream", default="http://127.0.0.1:8545")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8546)
    a = ap.parse_args()

    u = urlparse(a.upstream)
    UPSTREAM = (u.hostname or "127.0.0.1", u.port or 8545)

    print(f"rpcguard :{a.port} -> {UPSTREAM[0]}:{UPSTREAM[1]}  (eth_* net_* web3_* only)")
    sys.stdout.flush()
    ThreadingHTTPServer((a.host, a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
