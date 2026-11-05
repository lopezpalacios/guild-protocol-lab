#!/usr/bin/env bash
# Generate the guild wallets and the merkle input for the lab.
#
#   GUILDS=25 PLAYERS=20 ./scripts/gen-participants.sh
#
# Outputs:
#   data/guild-keys.txt    25 private keys, one per line. PRINT ONCE. NEVER COMMIT.
#   data/participants.json the merkle input: addresses + allocations
#   data/guilds.csv        id,address,key  -> paste into web/cards.html to print cards
#
# The player addresses default to the first 20 anvil accounts so the dry run can actually claim.
# For the real event, replace them with the 20 pre-registered player wallets.
set -euo pipefail

cd "$(dirname "$0")/.."

GUILDS="${GUILDS:-25}"
PLAYERS="${PLAYERS:-20}"
LOOT_PER_HEAD="1000000000000000000000"   # 1,000e18
MNEMONIC="${MNEMONIC:-test test test test test test test test test test test junk}"

export PATH="$HOME/.foundry/bin:$PATH"

mkdir -p data
: > data/guild-keys.txt
: > data/guilds.csv

addresses=()

for i in $(seq 1 "$GUILDS"); do
  out="$(cast wallet new)"
  addr="$(printf '%s\n' "$out" | awk '/^Address:/{print $2}')"
  key="$(printf '%s\n' "$out" | awk '/^Private key:/{print $3}')"
  printf '%s\n' "$key" >> data/guild-keys.txt
  printf '%s,%s,%s\n' "$i" "$addr" "$key" >> data/guilds.csv
  addresses+=("$addr")
done

for i in $(seq 0 $((PLAYERS - 1))); do
  addr="$(cast wallet address --mnemonic "$MNEMONIC" --mnemonic-index "$i")"
  addresses+=("$addr")
done

{
  printf '{ "addresses": ['
  for i in "${!addresses[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '"%s"' "${addresses[$i]}"
  done
  printf '], "amounts": ['
  for i in "${!addresses[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '%s' "$LOOT_PER_HEAD"
  done
  printf '] }\n'
} > data/participants.json

echo "guilds:   $GUILDS  -> data/guild-keys.txt (keep secret)"
echo "players:  $PLAYERS -> first $PLAYERS anvil accounts"
echo "total:    ${#addresses[@]} leaves -> data/participants.json"
echo
echo "next: forge script script/Deploy.s.sol --rpc-url \$RPC --broadcast"
