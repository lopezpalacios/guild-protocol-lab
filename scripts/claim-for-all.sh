#!/usr/bin/env bash
# The badge fallback. If sponsorship fails on the night, mint on behalf of the room from one
# funded operator key instead of watching 200 people fail.
#
#   OPERATOR_KEY=0x... RPC=https://sepolia.base.org ./scripts/claim-for-all.sh data/attendees.txt
#
# attendees.txt: one address per line. guild id is derived from the line number (1..25, cycling),
# which is right if the file is ordered by guild. Pass a second column to override: 0xabc…,7
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

: "${OPERATOR_KEY:?set OPERATOR_KEY}"
: "${RPC:=https://sepolia.base.org}"
FILE="${1:?usage: claim-for-all.sh <addresses.txt>}"

CHAIN_ID="$(cast chain-id --rpc-url "$RPC")"
BADGE="$(python3 -c "import json;print(json.load(open('deployments/${CHAIN_ID}.json'))['badge'])")"
ROUTE="0x0102050709"

n=0
while IFS=, read -r addr guild; do
  addr="$(echo "$addr" | tr -d '[:space:]')"
  [ -z "$addr" ] && continue
  [ -z "${guild:-}" ] && guild=$(( (n % 25) + 1 ))

  if cast call "$BADGE" "hasClaimed(address)(bool)" "$addr" --rpc-url "$RPC" | grep -q true; then
    echo "skip $addr (already claimed)"
    continue
  fi

  cast send "$BADGE" "claimFor(address,uint8,bytes)" "$addr" "$guild" "$ROUTE" \
    --private-key "$OPERATOR_KEY" --rpc-url "$RPC" >/dev/null
  n=$((n + 1))
  echo "minted g$(printf '%02d' "$guild") -> $addr"
done < "$FILE"

echo "done. $n badges minted."
