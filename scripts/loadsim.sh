#!/usr/bin/env bash
# THE DRY RUN. Run at T-7 and again at T-1. Run it once more at T-0 if you are nervous,
# which you should be.
#
#   ./scripts/loadsim.sh
#
# It does two things, because they fail differently:
#   1. the contract-level simulation — 25 ballots, 200 claims, 25 swaps, on a fork
#   2. a live end-to-end — real anvil, real deploy, real server, 25 real signatures queued
#      and submitted as one transaction, then the tally read back
#
# Exit code 0 means both passed. Anything else means do not run the lab.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

APORT="${APORT:-8547}"
SPORT="${SPORT:-8097}"
RPC="http://127.0.0.1:${APORT}"
TOKEN="loadsim-$(date +%s)"
KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
REPORT="data/loadsim-report.md"
FAILED=0

# The dry run deploys to a throwaway chain, and the deploy script writes web/config.js.
# On a machine that is also hosting the lab, that would silently repoint the live site at
# contracts which only exist on the throwaway chain. Back up and restore around the run.
BACKUP="$(mktemp -d)"
for f in web/config.js data/merkle.json web/merkle.json deployments/31337.json; do
  [ -f "$f" ] && cp "$f" "$BACKUP/$(echo "$f" | tr '/' '_')"
done

cleanup() {
  pkill -f "anvil --port ${APORT}" 2>/dev/null || true
  pkill -f "server/lab.py --port ${SPORT}" 2>/dev/null || true
  for f in web/config.js data/merkle.json web/merkle.json deployments/31337.json; do
    b="$BACKUP/$(echo "$f" | tr '/' '_')"
    [ -f "$b" ] && cp "$b" "$f"
  done
  rm -rf "$BACKUP"
}
trap cleanup EXIT

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAILED=1; }
note() { printf '        %s\n' "$*"; }

: > /tmp/loadsim.rows
row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3" >> /tmp/loadsim.rows; }

say "1/4  contract simulation (forge)"
if forge test --root contracts --match-contract LoadSimTest -vv > /tmp/loadsim.forge 2>&1; then
  GAS=$(grep -o "castVotes gas for 25 ballots: [0-9]*" /tmp/loadsim.forge | grep -o "[0-9]*$")
  PRICE=$(grep -o "spot price after 25 swaps (1e18): [0-9]*" /tmp/loadsim.forge | grep -o "[0-9]*$")
  pass "LoadSimTest — 25 ballots, 200+50 badge claims, 25 swaps"
  note "one batch of 25 ballots: ${GAS:-?} gas"
  note "GOLD/SILVER after 25 swaps: $(python3 -c "print(f'{${PRICE:-0}/1e18:.4f}')")"
  row "contract simulation" "pass" "${GAS:-?} gas for 25 ballots"
else
  fail "LoadSimTest"; tail -20 /tmp/loadsim.forge
  row "contract simulation" "FAIL" "see /tmp/loadsim.forge"
fi

say "2/4  full test suite"
if forge test --root contracts > /tmp/loadsim.all 2>&1; then
  N=$(grep -oE "[0-9]+ tests passed" /tmp/loadsim.all | tail -1)
  pass "all suites — $N"
  row "test suite" "pass" "$N"
else
  fail "test suite"; tail -20 /tmp/loadsim.all
  row "test suite" "FAIL" ""
fi

say "3/4  live deploy on anvil :${APORT}"
pkill -f "anvil --port ${APORT}" 2>/dev/null
sleep 1
anvil --port "$APORT" --silent > /tmp/loadsim.anvil 2>&1 &
sleep 3

if PRIVATE_KEY=$KEY RPC=$RPC ./scripts/deploy.sh > /tmp/loadsim.deploy 2>&1; then
  pass "deploy + seed + merkle root"
  row "deploy" "pass" "chain 31337"
else
  fail "deploy"; tail -15 /tmp/loadsim.deploy
  row "deploy" "FAIL" ""
fi

DEP="deployments/31337.json"
BALLOT=$(python3 -c "import json;print(json.load(open('$DEP'))['ballot'])" 2>/dev/null)
POLL1=$(python3 -c "import json;print(json.load(open('$DEP'))['poll1'])" 2>/dev/null)
BADGE=$(python3 -c "import json;print(json.load(open('$DEP'))['badge'])" 2>/dev/null)

say "4/4  live ballots through the server"
rm -f data/ballots.jsonl
RPC=$RPC OPERATOR_KEY=$KEY OPERATOR_TOKEN=$TOKEN \
  python3 server/lab.py --port "$SPORT" > /tmp/loadsim.server 2>&1 &
sleep 4

T0=$(python3 -c 'import time;print(time.time())')
QUEUED=0
while read -r gkey; do
  QUEUED=$((QUEUED + 1))
  addr=$(cast wallet address --private-key "$gkey")
  choice=$((QUEUED % 2))
  digest=$(cast call "$BALLOT" "ballotDigest(bytes32,uint8,address)(bytes32)" "$POLL1" "$choice" "$addr" --rpc-url "$RPC")
  sig=$(cast wallet sign --no-hash --private-key "$gkey" "$digest")
  curl -sf -X POST "127.0.0.1:${SPORT}/api/ballot" -H 'Content-Type: application/json' \
    -d "{\"pollId\":\"$POLL1\",\"signer\":\"$addr\",\"choice\":$choice,\"signature\":\"$sig\"}" > /dev/null \
    || { fail "POST /api/ballot for $addr"; break; }
done < data/guild-keys.txt
T1=$(python3 -c 'import time;print(time.time())')
note "$QUEUED signatures collected in $(python3 -c "print(f'{$T1-$T0:.1f}')")s (that is the queue, not the chain)"

RESULT=$(curl -s -X POST "127.0.0.1:${SPORT}/api/submit" \
  -H 'Content-Type: application/json' -H "X-Operator-Token: $TOKEN" \
  -d "{\"pollId\":\"$POLL1\"}")
echo "$RESULT" > /tmp/loadsim.submit

SUB=$(python3 -c "import json;print(json.load(open('/tmp/loadsim.submit')).get('submitted',0))" 2>/dev/null)
SECS=$(python3 -c "import json;print(json.load(open('/tmp/loadsim.submit')).get('seconds','?'))" 2>/dev/null)
if [ "${SUB:-0}" = "$QUEUED" ]; then
  pass "one transaction carried all $SUB ballots in ${SECS}s"
  row "batch submit" "pass" "$SUB ballots, ${SECS}s"
else
  fail "batch submit returned ${SUB:-0} of $QUEUED"
  cat /tmp/loadsim.submit; echo
  row "batch submit" "FAIL" "$(head -c 120 /tmp/loadsim.submit)"
fi

TALLY=$(curl -s "127.0.0.1:${SPORT}/api/state" | python3 -c "import json,sys;d=json.load(sys.stdin);print(sum(d['polls']['poll1']['tally']))" 2>/dev/null)
if [ "${TALLY:-0}" = "$QUEUED" ]; then
  pass "tally reads back $TALLY / $QUEUED"
  row "tally readback" "pass" "$TALLY votes"
else
  fail "tally reads back ${TALLY:-?}, expected $QUEUED"
  row "tally readback" "FAIL" "${TALLY:-?} of $QUEUED"
fi

if curl -sf "127.0.0.1:${SPORT}/spectator.html" >/dev/null \
   && curl -sf "127.0.0.1:${SPORT}/admin.html" >/dev/null \
   && curl -sf "127.0.0.1:${SPORT}/api/health" >/dev/null; then
  pass "static site + API serve"
  row "static site" "pass" "spectator, admin, health"
else
  fail "static site does not serve"
  row "static site" "FAIL" ""
fi

{
  echo "# Load simulation — $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "| stage | result | detail |"
  echo "|---|---|---|"
  cat /tmp/loadsim.rows
  echo
  echo "Exit code: $([ $FAILED -eq 0 ] && echo 0 || echo 1)"
} > "$REPORT"

say "report -> $REPORT"
echo
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32m  ALL CHECKS PASSED — the lab is runnable.\033[0m\n'
else
  printf '\033[31m  SOMETHING FAILED — do not run the lab until this is green.\033[0m\n'
fi
exit "$FAILED"
