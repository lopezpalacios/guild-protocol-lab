# Hosting

The lab is live on a self-hosted node and published through a Cloudflare tunnel.

| | |
|---|---|
| **Site** | <https://lab.kameloso.com/> |
| **RPC** | <https://rpc.kameloso.com> (chain id **48901**) |
| **Console** | <https://lab.kameloso.com/admin.html> |
| **Cards** | <https://lab.kameloso.com/cards.html> — base URL `https://lab.kameloso.com/` |
| **Deck** | <https://lab.kameloso.com/deck.html> |
| **Machine** | `ssh <lab-host>` → `~/guild-lab` |
| **Tunnel** | the tunnel's service unit, ingress in `~/.cloudflared/config.yml` |

Redeploy:

```bash
./scripts/host.sh
```

That rsyncs the repo, rebuilds the chain from zero, redeploys the contracts, funds the 25 guild
wallets, restarts both services, and prints the operator token.

---

## Which chain? (the decision)

Three candidates were on the table. Two are out for hard technical reasons.

| Option | Verdict |
|---|---|
| **anvil on the host** | Works, free gas, but the chain is a single process with no durability. If it dies mid-session every vote is gone. |
| **Base mainnet fork** (verified) | `MODE=fork`. Real Uniswap/Aave/USDC state at a pinned block, free gas, cheat codes available. Badges are disposable and the node depends on a public RPC for cold state. |
| **Besu** | Besu cannot be the execution client for Base — Base is OP Stack and runs `op-geth`. So Besu means either a private chain (still one machine, custom genesis + consensus, and the badges die with the box) or a full Ethereum L1 sync (days, ~1TB). Neither fits a 60-minute lab. |
| **Base Sepolia** | ✅ Recommended. Real chain, real explorer, one-tap network add in most wallets, and the badge is still viewable a week later — which is the entire point of a souvenir. |

**The only thing that argued for the private chain was free gas**, because 200 attendees claiming a
badge would each need testnet ETH. That is now solved explicitly: `POST /api/mint` has the
operator key pay for the mint and deliver the token to the attendee's address.

That is a paymaster with the abstraction removed, and it is a better lesson than a paymaster:
someone is paying for you, someone decides when to stop, and the console shows the bill.
`claim.html` now offers both buttons side by side — *the lab pays* and *you pay* — so the
difference is a click apart.

Guardrails on the sponsor: one badge per address (checked on chain), two per IP per hour, and a
hard cap of 240 sponsored mints (`SPONSOR_CAP`) so a griefer cannot burn the room's allowance
before doors.

### Forking Base mainnet

```bash
MODE=fork ./scripts/host.sh                    # pins head-100 and stores the block
MODE=fork FORK_BLOCK=53276807 ./scripts/host.sh # or pin an exact block
```

Verified working from the host against the free public RPC — no archive node, no API key:

```
$ cast call 0x8335…2913 "symbol()(string)" --rpc-url https://rpc.kameloso.com
"USDC"
$ cast call 0x4200…0006 "symbol()(string)" --rpc-url https://rpc.kameloso.com
"WETH"
```

**Why it works without an archive provider:** the fork is pinned 100 blocks behind head, and
public RPCs serve full state inside that window. Forking at an arbitrary historical depth is what
would need an archive node; you don't want that depth anyway, because you want current protocol
state.

**What it buys:** the real Uniswap pools, the real Aave market, real USDC. That is the one thing
the custom `LabPair` could not offer, and it is the strongest possible answer to "is this a toy?"

**What it costs, and the two things that bit me:**

1. **Clock skew.** The fork starts at the *fork block's* timestamp, which can be an hour behind wall
   clock. The first mined block then jumps to real time, so a poll created at deploy with
   `closesAt = now + 3600` is born already closed. `host-mini.sh` now aligns the chain clock with
   `anvil_setNextBlockTimestamp` before deploying.
2. **Anvil's demo accounts are not empty on a fork.** `0x90F7…b906` is anvil account 3 on a fresh
   chain — and on Base mainnet it is a **deployed contract** that implements `onERC721Received`
   and immediately forwards the token to itself. `_safeMint` calls it, and the mint reverts.
   Never use anvil's accounts as users on a fork; the 25 guild wallets are freshly generated, so
   they are safe by construction.

Three more caveats worth knowing:

- **Overriding the chain id breaks real protocols' EIP-712 domains.** `--chain-id 48901` keeps
  wallets sane, but USDC `permit` and Uniswap `Permit2` signatures are computed against the real
  chain id and will not verify. Approve-then-swap works; permit paths do not.
- **Cold state is a live upstream call.** Every storage slot the fork has not seen yet goes to
  `mainnet.base.org`. Warm the exact demo path at T-1, and do not restart the node during the hour.
- **The badge is disposable.** It lives on the fork, so it dies with the node. If the souvenir
  matters, this is the wrong mode.

### Switching to Base Sepolia

```bash
MODE=public ./scripts/host.sh
```

That skips anvil and rpcguard entirely, deploys to `https://sepolia.base.org`, and points
`config.js` at the public chain and Basescan.

**Prerequisite:** the deployer key needs testnet ETH.

```bash
ssh <lab-host> 'cd ~/guild-lab && cast wallet address --private-key $(cat data/operator-key)'
# fund that address from a Base Sepolia faucet, then:
MODE=public ./scripts/host.sh
```

Budget: the deploy is ~9M gas, 25 guild wallets at 0.002 ETH, and ~250 sponsored mints. At Base
Sepolia prices that is well under 0.05 ETH. If the deployer balance is zero the script stops with
a clear message rather than half-deploying.

On a public chain you can also drop `rpc.kameloso.com` from the ingress — the guard has nothing to
protect, and attendees should use the network's own RPC.

---

## What is actually running

```
anvil            127.0.0.1:8545   the chain (ephemeral, rebuilt on every host.sh)
rpcguard         127.0.0.1:8546   JSON-RPC allowlist -> tunnel hostname
lab server       127.0.0.1:8090   static site + ballot queue + SSE
cloudflared                      lab.kameloso.com -> 8090, rpc.kameloso.com -> 8546
```

Logs live in `~/guild-lab/logs/` on the host: `anvil.log`, `lab.log`, `rpcguard.log`,
`deploy.log`.

---

## Three decisions worth knowing about

### 1. Chain id 48901, not 31337

31337 is Hardhat's default. Any attendee who has ever used Remix or a local node already has a
network with that id, pointing at their own laptop. Their wallet would either refuse to add ours
or silently send transactions into the void. A distinctive id removes a five-minute support queue
at the door.

### 2. `rpcguard` sits in front of anvil

Anvil exposes `anvil_setBalance`, `anvil_impersonateAccount`, `anvil_mine`. On a laptop that is a
convenience. On a hostname printed on a projector for 200 crypto engineers, it is an invitation to
mint gas and drain the demo pool mid-session.

`server/rpcguard.py` forwards only `eth_*`, `net_*` and `web3_*`, and answers everything else with:

```
rpcguard: method 'anvil_setBalance' is not available on this endpoint
```

Deploys come in over SSH, not through the guard, so nothing about the operator path is restricted.

### 3. Assets are version-stamped, because Cloudflare overrides cache headers

The first hosted attempt served a **stale `config.js`** for four hours after a redeploy: the origin
sent `Cache-Control: no-store` and Cloudflare still returned `cf-cache-status: HIT` with
`max-age=14400`. Every button on the site would have pointed at contracts that no longer existed.

Two fixes, both in place:

- The server sends `no-store` on everything, so the edge bypasses it (`cf-cache-status: BYPASS`).
- The server rewrites `./lib.js`, `./config.js` and `./style.css` to `?v=<mtime of config.js>` as
  it serves them, and rewrites `lib.js`'s internal import to match. A new deploy is a new URL that
  the edge has never cached. HTML is not cached by Cloudflare, so it always carries the current
  stamp.

This is why `config.js` served without a query string may look old. Nothing loads it that way.

---

## Limits of this deployment

- **The chain is ephemeral.** `host.sh` wipes and rebuilds it. If anvil dies mid-event, the chain
  restarts from the deployment and **every vote cast so far is gone**. There is a `--state
  data/anvil-state.json` file written on clean shutdown, which is why a clean restart is survivable
  and a crash is not. Do not restart anything during the hour.
- **No launchd for the lab services.** They are `nohup` processes started by `host.sh`. If the host
  reboots, re-run `host.sh`.
- **The operator token is stable across restarts** (`data/operator-token`), so the console does not
  need re-authenticating mid-session.
- **The deployer key is random and lives in `data/operator-key` (0600).** It owns the badge contract's
  `operator` role. It is not anvil's account 0, which is public — otherwise anyone could call
  `claimFor` and burn the 250 cap.
- **`guild.kameloso.com` is retired** and returns 404. It still has four hours of poisoned cache from
  the first attempt; `lab.kameloso.com` is the canonical host.

---

## Switching to Base Sepolia

Same scripts, real chain:

```bash
PUBLIC_RPC=https://sepolia.base.org \
PUBLIC_CHAIN_NAME="Base Sepolia" \
PUBLIC_EXPLORER=https://sepolia.basescan.org \
 ./scripts/host.sh
```

But `host-mini.sh` starts a local anvil, so for a real testnet you want to skip the chain step and
deploy straight at the public RPC:

```bash
ssh <lab-host>
cd ~/guild-lab
PRIVATE_KEY=$(cat data/operator-key) RPC=https://sepolia.base.org \
  PUBLIC_RPC=https://sepolia.base.org \
  PUBLIC_CHAIN_NAME="Base Sepolia" \
  PUBLIC_EXPLORER=https://sepolia.basescan.org \
  ./scripts/deploy.sh
```

Then point the server at it (`RPC=https://sepolia.base.org`) and drop `rpcguard` from the ingress —
on a real chain it has nothing to guard, and the public RPC is the one attendees should use.

You need a funded key for that, which is the one thing a local chain gives you for free.

---

## Getting the guild cards

The cards are generated on the host, because that is where the keys are:

```bash
ssh <lab-host> 'cat ~/guild-lab/data/guilds.csv' > data/guilds.csv
```

Paste into <https://lab.kameloso.com/cards.html> with base URL `https://lab.kameloso.com/`.
Then press Print. The sheet contains live private keys — treat it like cash.

---

## Health checks

```bash
curl -s https://lab.kameloso.com/api/health          # {"ok":true,"chainId":48901,...}
curl -s -X POST https://rpc.kameloso.com -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
ssh <lab-host> 'tail -20 ~/guild-lab/logs/lab.log'
```

If `/api/health` is fine but the projector is blank, it is the browser, not the lab.
