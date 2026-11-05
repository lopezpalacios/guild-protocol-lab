#!/usr/bin/env bash
# Fund the 25 guild wallets at T-1. Run once, from the treasury key.
#
#   TREASURY_KEY=0x... RPC=https://sepolia.base.org ./scripts/fund-guilds.sh
#
# 0.002 ETH per guild is roughly 40 transactions at Base Sepolia prices. Enough for a vote,
# a loot claim, and one mistake.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

: "${TREASURY_KEY:?set TREASURY_KEY}"
: "${RPC:=https://sepolia.base.org}"
VALUE="${VALUE:-0.002ether}"

[ -f data/guild-keys.txt ] || { echo "missing data/guild-keys.txt"; exit 1; }

i=0
while read -r key; do
  i=$((i + 1))
  addr="$(cast wallet address --private-key "$key")"
  bal="$(cast balance "$addr" --rpc-url "$RPC")"
  if [ "$bal" != "0" ]; then
    echo "g$(printf '%02d' "$i") $addr already funded"
    continue
  fi
  cast send "$addr" --value "$VALUE" --private-key "$TREASURY_KEY" --rpc-url "$RPC" >/dev/null
  echo "g$(printf '%02d' "$i") $addr funded $VALUE"
done < data/guild-keys.txt

echo "done. ${i} guild wallets."
