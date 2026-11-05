#!/usr/bin/env bash
# Deploy everything and regenerate web/config.js + both merkle files.
#
#   PRIVATE_KEY=0x... RPC=https://sepolia.base.org ./scripts/deploy.sh
#   PRIVATE_KEY=0xac09... RPC=http://127.0.0.1:8545 ./scripts/deploy.sh     # anvil
#
# Verify on Basescan by adding:  --verify --etherscan-api-key $BASESCAN_KEY
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

: "${PRIVATE_KEY:?set PRIVATE_KEY}"
: "${RPC:=https://sepolia.base.org}"

[ -f data/participants.json ] || { echo "missing data/participants.json — run scripts/gen-participants.sh"; exit 1; }

cd contracts
forge script script/Deploy.s.sol:Deploy --rpc-url "$RPC" --broadcast "$@"

cd ..
CHAIN_ID="$(cast chain-id --rpc-url "$RPC")"
echo
echo "deployment -> deployments/${CHAIN_ID}.json"
echo "config     -> web/config.js"
echo "merkle     -> data/merkle.json + web/merkle.json"
echo
echo "next: ./scripts/fund-guilds.sh   then open web/index.html"
