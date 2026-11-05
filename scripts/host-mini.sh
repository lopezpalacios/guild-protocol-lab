#!/usr/bin/env bash
# Runs ON THE MINI. Started by scripts/host.sh from the Mac.
#
#   MODE=local    (default) anvil on localhost + rpcguard. Free gas, disposable chain.
#   MODE=fork     anvil forked from Base mainnet at a pinned block. Real Uniswap/Aave/USDC state,
#                 free gas, still disposable.
#   MODE=public   deploy to a real testnet (Base Sepolia) and skip the local node entirely.
#
# Idempotent: stops what it owns, rebuilds, deploys, restarts the services.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

MODE="${MODE:-local}"
LAB_PORT="${LAB_PORT:-8090}"
GUARD_PORT="${GUARD_PORT:-8546}"
RPC_LOCAL="http://127.0.0.1:8545"
ANVIL0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 31337 is "Hardhat" in every wallet. Anyone who has opened Remix already has a network with
# that id pointing at their own laptop, so the hosted chain uses a distinctive one.
CHAIN_ID="${CHAIN_ID:-48901}"

mkdir -p logs data

# ── secrets, generated once, never printed ──────────────────────────────────
# The deployer key must not be anvil's account 0: that key is public, and it owns the badge
# contract's `operator` role.
if [ ! -f data/operator-key ]; then
  cast wallet new | awk '/Private key:/{print $3}' > data/operator-key
  chmod 600 data/operator-key
fi
OPS_KEY="$(cat data/operator-key)"
OPS_ADDR="$(cast wallet address --private-key "$OPS_KEY")"

if [ ! -f data/operator-token ]; then
  python3 -c 'import secrets;print(secrets.token_urlsafe(9))' > data/operator-token
  chmod 600 data/operator-token
fi
TOKEN="$(cat data/operator-token)"

# ── stop what we own ───────────────────────────────────────────────────────
pkill -f "anvil --port 8545" 2>/dev/null || true
pkill -f "server/lab.py" 2>/dev/null || true
pkill -f "server/rpcguard.py" 2>/dev/null || true
sleep 1
rm -f data/ballots.jsonl

[ -f data/participants.json ] || ./scripts/gen-participants.sh

# ── chain ──────────────────────────────────────────────────────────────────
if [ "$MODE" = "local" ] || [ "$MODE" = "fork" ]; then
  PUBLIC_RPC="${PUBLIC_RPC:-https://rpc.kameloso.com}"
  CHAIN_NAME="Guild Lab"
  EXPLORER="$PUBLIC_RPC"
  FORK_ARGS=()

  if [ "$MODE" = "fork" ]; then
    FORK_URL="${FORK_URL:-https://mainnet.base.org}"
    # Pin the block. A moving fork is a non-reproducible lab: same room, different answers.
    if [ -z "${FORK_BLOCK:-}" ] && [ -f data/fork-block ]; then
      FORK_BLOCK="$(cat data/fork-block)"
    fi
    if [ -z "${FORK_BLOCK:-}" ]; then
      HEAD=$(cast block-number --rpc-url "$FORK_URL")
      FORK_BLOCK=$((HEAD - 100))
    fi
    echo "$FORK_BLOCK" > data/fork-block
    # Public RPCs only guarantee recent state, so fork just behind head rather than at an
    # archive depth. 100 blocks back is a full node's window on every provider.
    FORK_ARGS=(--fork-url "$FORK_URL" --fork-block-number "$FORK_BLOCK")
    CHAIN_NAME="Guild Lab (Base fork)"
    echo "→ forking Base mainnet at block $FORK_BLOCK"
  fi

  # Fresh lab every run. A stale chain with a new deployment on top is the most confusing
  # possible state to debug at 17:55.
  [ "${KEEP_STATE:-0}" = "1" ] || rm -f data/anvil-state.json

  nohup anvil --port 8545 --host 127.0.0.1 --chain-id "$CHAIN_ID" \
    --state data/anvil-state.json ${FORK_ARGS[@]+"${FORK_ARGS[@]}"} > logs/anvil.log 2>&1 &
  # A fork node is not listening the instant it starts: it has to fetch a block first. Poll for
  # readiness instead of guessing with sleep, or every fork deploy fails on a cold start.
  ready=0
  for _ in $(seq 1 90); do
    if cast chain-id --rpc-url "$RPC_LOCAL" > /dev/null 2>&1; then ready=1; break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "anvil did not become ready:" >&2
    tail -20 logs/anvil.log >&2
    exit 1
  fi
  # A fork starts with the *fork block's* timestamp, which can be an hour behind wall clock.
  # The first mined block then jumps to real time, so any window created at deploy is already
  # half-consumed. Align the clock before deploying.
  if [ "$MODE" = "fork" ]; then
    cast rpc anvil_setNextBlockTimestamp "$(date +%s)" --rpc-url "$RPC_LOCAL" > /dev/null
    cast rpc anvil_mine --rpc-url "$RPC_LOCAL" > /dev/null
    echo "  clock aligned: $(cast block latest --field timestamp --rpc-url "$RPC_LOCAL")"
  fi

  cast send "$OPS_ADDR" --value 500ether --private-key "$ANVIL0" --rpc-url "$RPC_LOCAL" > /dev/null

elif [ "$MODE" = "public" ]; then
  RPC_LOCAL="${RPC_LOCAL_PUBLIC:-https://sepolia.base.org}"
  PUBLIC_RPC="$RPC_LOCAL"
  CHAIN_NAME="${CHAIN_NAME:-Base Sepolia}"
  EXPLORER="${EXPLORER:-https://sepolia.basescan.org}"

  echo "→ public mode: $CHAIN_NAME at $RPC_LOCAL"
  echo "  deployer $OPS_ADDR"
  BAL=$(cast balance "$OPS_ADDR" --rpc-url "$RPC_LOCAL")
  echo "  balance  $BAL wei"
  if [ "$BAL" = "0" ]; then
    echo
    echo "  deployer has no testnet ETH. Fund it first, then re-run." >&2
    exit 1
  fi

else
  echo "MODE must be local, fork or public" >&2
  exit 1
fi

# ── deploy ─────────────────────────────────────────────────────────────────
PRIVATE_KEY="$OPS_KEY" RPC="$RPC_LOCAL" \
  PUBLIC_RPC="$PUBLIC_RPC" PUBLIC_CHAIN_NAME="$CHAIN_NAME" PUBLIC_EXPLORER="$EXPLORER" \
  ./scripts/deploy.sh > logs/deploy.log 2>&1

# Guild wallets need gas for the loot claim and the optional self-submit. On a public chain this
# spends real testnet ETH; on the local chain it is free.
TREASURY_KEY="$OPS_KEY" RPC="$RPC_LOCAL" ./scripts/fund-guilds.sh > logs/fund.log 2>&1 || true

# ── services ───────────────────────────────────────────────────────────────
if [ "$MODE" != "public" ]; then
  # The guard matters more on a fork than anywhere: a public `anvil_setBalance` on a mainnet
  # fork is a money printer pointed at the room.
  nohup python3 server/rpcguard.py --port "$GUARD_PORT" > logs/rpcguard.log 2>&1 &
fi

RPC="$RPC_LOCAL" nohup python3 server/lab.py --port "$LAB_PORT" > logs/lab.log 2>&1 &
sleep 4

curl -sf "127.0.0.1:${LAB_PORT}/api/health" > /dev/null || {
  echo "server did not come up:"; tail -20 logs/lab.log; exit 1
}

if [ "$MODE" != "public" ]; then
  curl -sf -X POST "127.0.0.1:${GUARD_PORT}" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' > /dev/null || {
    echo "rpcguard did not come up:"; tail -20 logs/rpcguard.log; exit 1
  }
fi

echo
echo "  mode      $MODE"
echo "  lab       http://127.0.0.1:${LAB_PORT}/"
[ "$MODE" != "public" ] && echo "  rpc       http://127.0.0.1:${GUARD_PORT}/  (eth_* only)"
[ "$MODE" = "fork" ] && echo "  fork      Base mainnet @ $(cat data/fork-block)"
echo "  chain     $CHAIN_NAME ($(cast chain-id --rpc-url "$RPC_LOCAL"))"
echo "  operator  $(cat data/operator-token)"
echo "  deployer  ${OPS_ADDR}"
echo "  guilds    $(wc -l < data/guild-keys.txt | tr -d ' ') wallets"
