#!/usr/bin/env bash
# One screen of truth for the operator during the lab.
#
#   RPC=https://sepolia.base.org ./scripts/state.sh
#
# Reads the deployment file for the current chain, so it works on anvil and on Base Sepolia.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

: "${RPC:=http://127.0.0.1:8545}"

CHAIN_ID="$(cast chain-id --rpc-url "$RPC")"
DEP="deployments/${CHAIN_ID}.json"
[ -f "$DEP" ] || { echo "no deployment for chain $CHAIN_ID — deploy first"; exit 1; }

field() { python3 -c "import json;print(json.load(open('$DEP'))['$1'])"; }

LOOT="$(field loot)"
PAIR="$(field pair)"
BALLOT="$(field ballot)"
BADGE="$(field badge)"
POLL1="$(field poll1)"
POLL2="$(field poll2)"

show_poll() {
  local name="$1" id="$2"
  echo "$name            ${id:0:20}…"
  cast call "$BALLOT" "tallyOf(bytes32)(uint256[])" "$id" --rpc-url "$RPC" | sed 's/^/  tally      /'
  echo "  winner     $(cast call "$BALLOT" "winner(bytes32)(uint8)" "$id" --rpc-url "$RPC")"
  echo
}

echo "chain        $CHAIN_ID"
echo "block        $(cast block-number --rpc-url "$RPC")"
echo
show_poll "poll 1" "$POLL1"
show_poll "poll 2" "$POLL2"

echo "GOLD/SILVER  $(cast call "$PAIR" 'spotPrice()(uint256)' --rpc-url "$RPC")"
echo "swaps        $(cast call "$PAIR" 'swapCount()(uint256)' --rpc-url "$RPC")"
echo "reserves     $(cast call "$PAIR" 'getReserves()(uint256,uint256)' --rpc-url "$RPC" | tr '\n' ' ')"
echo "badges       $(cast call "$BADGE" 'nextId()(uint256)' --rpc-url "$RPC") / 251"
echo "loot supply  $(cast call "$LOOT" 'totalSupply()(uint256)' --rpc-url "$RPC")"
