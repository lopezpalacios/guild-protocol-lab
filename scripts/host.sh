#!/usr/bin/env bash
# Deploy the lab to the mac mini and publish it through the kameloso Cloudflare tunnel.
#
#   ./scripts/host.sh
#
# What it does:
#   1. rsync this repo to mini:~/guild-lab (code only — no keys, no state, no build cache)
#   2. run host-mini.sh there: anvil, deploy, rpcguard, lab server
#   3. print the public URLs
#
# The tunnel config lives in ~/.cloudflared/config.yml on the mini and is managed separately:
#   guild.kameloso.com -> localhost:8090   (the site)
#   rpc.kameloso.com   -> localhost:8546   (the guarded RPC)
set -euo pipefail
cd "$(dirname "$0")/.."

MINI="${MINI:-mini}"
REMOTE="guild-lab"
PUBLIC_RPC="${PUBLIC_RPC:-https://rpc.kameloso.com}"
LAB_PORT="${LAB_PORT:-8090}"
MODE="${MODE:-local}"   # local | fork | public

echo "→ syncing to ${MINI}:~/${REMOTE}"
rsync -az --delete \
  --exclude '.git' \
  --exclude 'contracts/lib' \
  --exclude 'contracts/out' \
  --exclude 'contracts/cache' \
  --exclude 'contracts/broadcast' \
  --exclude 'data' \
  --exclude 'web/merkle.json' \
  --exclude 'web/config.js' \
  --exclude 'logs' \
  ./ "${MINI}:~/${REMOTE}/"

# The build cache is excluded, but forge needs the libs to compile the deploy script.
ssh "$MINI" "cd ~/${REMOTE}/contracts && ([ -d lib/openzeppelin-contracts ] || forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git >/dev/null 2>&1) && ([ -d lib/forge-std ] || forge install foundry-rs/forge-std --no-git >/dev/null 2>&1)"

echo "→ starting the lab on ${MINI}"
ssh "$MINI" "cd ~/${REMOTE} && MODE='${MODE:-local}' PUBLIC_RPC='${PUBLIC_RPC}' LAB_PORT='${LAB_PORT}' \
  FORK_URL='${FORK_URL:-}' FORK_BLOCK='${FORK_BLOCK:-}' CHAIN_ID='${CHAIN_ID:-48901}' \
  bash scripts/host-mini.sh"

echo
echo "  mode          ${MODE}"
echo "  public site   https://lab.kameloso.com/"
echo "  public rpc    ${PUBLIC_RPC}"
echo "  console       https://lab.kameloso.com/admin.html"
echo
echo "  token:  ssh ${MINI} 'cat ~/${REMOTE}/data/operator-token'"
echo "  cards:  https://lab.kameloso.com/cards.html  (base url: https://lab.kameloso.com/)"
