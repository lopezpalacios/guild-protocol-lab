# The Guild Protocol

A 60-minute blockchain lab for 200 people at ETH Zurich, built as a one-shot D&D session.
Twenty-five guilds of eight, each with a wallet on a printed card, collectively choosing which
protocols the room visits — and doing the choosing with the thing being taught.

Testnet only. Every asset is valueless. Every key is disposable.

- **It is already hosted:** <https://lab.kameloso.com/> — see [`HOSTING.md`](./HOSTING.md).
- **Do this first:** [`TUTORIAL.md`](./TUTORIAL.md) — zero to a running lab in ~25 minutes.
- **On the night:** [`GUIDE.md`](./GUIDE.md) — every surface, minute by minute, and troubleshooting.
- **On stage:** [`PRESENTATION.md`](./PRESENTATION.md) + `web/deck.html` — 15 slides with speaker notes.
- **At the podium:** [`RUNBOOK.pptx`](./RUNBOOK.pptx) — 21 slides, one per timestamp: what to click, on which screen, and what you should see.
- **The argument:** [`LAB-PACK.md`](./LAB-PACK.md) — learning outcomes, run of show, risk register,
  the committee response appendix.
- **Contracts:** `contracts/` — Foundry, five contracts, 37 tests including the 200-person load simulation.
- **Backend:** `server/lab.py` — Python stdlib only, zero dependencies. Collects signatures, submits
  them as one transaction, streams state to the projector.
- **Frontend:** `web/` — static pages, no build step, viem from CDN.

---

## The five contracts

| Contract | What it is | Encounter |
|---|---|---|
| `LabToken` | One ERC-20, deployed three times: Loot, Gold, Silver | E2, E5 |
| `MerkleDistributor` | Claim-based airdrop, permissionless relays | E2 |
| `AdventurerBadge` | ERC-721 with fully on-chain SVG metadata | E3, E9 |
| `Ballot` | EIP-712 signatures, batched on-chain, two weighting modes | E1, E8 |
| `LabPair` | Constant-product AMM with a hard trade cap | E5 |

**What was cut from the original design, and why:**

- **The lending pool and liquidation (E6).** Nine contracts was scope creep for a two-week build.
  This is the real casualty: it was the most dramatic segment and the most fragile.
- **OpenZeppelin `Governor` + `Timelock` (E8).** `Ballot` does the governance lesson instead by
  running one-guild-one-vote and token-weighted on the same room. Two contracts collapse into one
  and the *political* point survives intact.
- **Bridging (E7).** No contract of ours — it is a scheduled async observation on the official
  OP Stack bridge, checked again at minute 52.
- **ERC-4337.** Not built. Coinbase Smart Wallet + CDP Paymaster. Hand-rolling an EntryPoint is
  how lab projects die.

---

## Hosted

Live on a self-hosted node, published through a Cloudflare tunnel:

| | |
|---|---|
| Site | <https://lab.kameloso.com/> |
| RPC | <https://rpc.kameloso.com> · chain id **48901** |
| Console | <https://lab.kameloso.com/admin.html> |

Redeploy with `./scripts/host.sh`. The chain is rebuilt from zero on every run, so treat the
hosted instance as disposable and the repo as the source of truth.

Switch to Base Sepolia with `MODE=public ./scripts/host.sh` — the decision, the Besu constraint,
and the sponsored-mint design are in [`HOSTING.md`](./HOSTING.md).

## Quickstart — local, no network

Three terminals. Verified end to end.

```bash
# 0. dependencies (once — the Foundry libs are not vendored)
cd contracts && forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git && cd ..

# 1. the chain
anvil --port 8545

# 2. deploy, seed the AMM, build the merkle tree, generate web/config.js
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
RPC=http://127.0.0.1:8545 \
./scripts/deploy.sh

# 3. the server: static site + ballot queue + live state
RPC=http://127.0.0.1:8545 \
OPERATOR_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
python3 server/lab.py --port 8080
```

Then open <http://127.0.0.1:8080/index.html>. It prints an operator token — paste it into
`/admin.html` once.

> Browse `127.0.0.1`, not `localhost`. On macOS `localhost` can resolve to an unrelated IPv6
> service and you will debug someone else's server.

The first time only, if `data/participants.json` is missing:

```bash
./scripts/gen-participants.sh        # 25 guild keys + 20 anvil player addresses
```

To open a guild page, take a line from `data/guilds.csv`:

```
1,0xF313…,0xKEY
```

and visit `http://localhost:8080/g.html#k=0xKEY&g=1`. That is exactly what the printed QR encodes.

```bash
# fund the guild wallets before the session
TREASURY_KEY=0xac09… RPC=http://127.0.0.1:8545 ./scripts/fund-guilds.sh

# one screen of truth during the session
RPC=http://127.0.0.1:8545 ./scripts/state.sh
```

---

## Deploy to Base Sepolia

```bash
./scripts/gen-participants.sh                 # replace the 20 player addresses with real ones
PRIVATE_KEY=0x… RPC=https://sepolia.base.org ./scripts/deploy.sh --verify --etherscan-api-key $BASESCAN_KEY
```

Printing the cards: open `web/cards.html`, paste `data/guilds.csv`, print, cut, place one per table.
QR codes are generated in the browser — nothing is uploaded. **The sheet contains live private keys;
treat it like cash until it is on the tables.**

---

## Event-day runbook

| When | Do |
|---|---|
| **T-14** | Deploy. Verify contracts. Print 200 door cards. |
| **T-7** | `forge test` — the load simulation must pass. Full dry run of the run of show. |
| **T-3** | Print guild cards. Scan five of them on five different phones. |
| **T-1** | `fund-guilds.sh`. Confirm the treasury holds enough for 250 badge mints. |
| **T-60m** | `state.sh`. Projector at 60pt from the back row. Spare cards at the desk. |
| **T-0** | `https://lab.kameloso.com/spectator.html` on the projector, `/admin.html` on your laptop. |

If the badge claim fails for a crowd, the fallback is one command:

```bash
OPERATOR_KEY=0x… ./scripts/claim-for-all.sh data/attendees.txt
```

---

## The five things the code teaches

Each is a property of the implementation, not a slide.

1. **A signature is not a transaction.** `Ballot.castVotes` takes a signature that was produced
   with zero gas, and the guild page shows "not counted yet" until the transaction lands.
   The gap between those two moments is the entire lab.

2. **A relayer is not a gatekeeper.** `castVotes` is permissionless, and `MerkleDistributor.claim`
   pays `account`, never `msg.sender`. Anyone can submit anyone's ballot. Censorship resistance
   is demonstrated by `test_relayedClaimPaysTheClaimantNotTheRelayer`, not asserted.

3. **On-chain metadata is a different asset.** `AdventurerBadge.tokenURI` returns a base64 SVG
   built in Solidity. No IPFS CID, no pinning service. The test decodes the data URI and asserts
   the SVG is really inside it.

4. **Token-weighted governance is one whale away from not being governance.**
   `test_tokenWeightedFlipsTheResult` gives one guild 100 LOOT and twenty-four guilds 1 LOOT each.
   The whale wins. `Ballot` reads `balanceOf` at cast time on purpose — that is the flash-loan
   attack, and production governance fixes it with `ERC20Votes` snapshots.

5. **Price is a function of reserves, not of belief.** `LabPair` is seeded 50k/50k and capped so
   the room cannot drain it. Twenty-five guild swaps move the number on the projector because
   the room moved it.

---

## Repo map

```
LAB-PACK.md              design document (learning outcomes → run of show → risk)
contracts/
  src/                   five contracts
  test/                  37 tests, incl. LoadSim (25 votes, 200 claims, 25 swaps)
  script/Deploy.s.sol    one-command deploy, writes all artifacts
data/
  participants.json      merkle input (generated)
  guild-keys.txt         SECRET — gitignored
  guilds.csv             paste into web/cards.html
  merkle.json            root + proofs (generated)
deployments/<chain>.json generated
web/
  index.html             operator hub
  spectator.html         projector: live tally, price, badges
  g.html                 guild: sign → submit → claim
  claim.html             badge mint, renders the on-chain art
  cards.html             print 25 QR cards in the browser
  config.js              generated by the deploy script
scripts/
  gen-participants.sh    wallets + merkle input
  deploy.sh              deploy + artifacts
  fund-guilds.sh         0.002 ETH × 25
  state.sh               operator console
  claim-for-all.sh       badge fallback
  loadsim.sh             THE DRY RUN — run at T-7 and T-1
server/lab.py            static site + ballot queue + SSE + one-tx submit
server/rpcguard.py       JSON-RPC allowlist in front of anvil (public RPC safety)
scripts/host.sh          deploy to the host + publish through the tunnel
web/deck.html            the presentation
```

---

## The dry run

```bash
./scripts/loadsim.sh
```

Contract simulation, full test suite, live deploy, 25 real signatures through the server, one
transaction, tally read back. Writes a timestamped `data/loadsim-report.md`. Run it at T-7 and
again at T-1. If it is not green, do not run the lab.

## Known limits

- **The AMM and the badge are ours, not production systems.** The difference is stated on screen.
- **`Ballot` is naive on purpose.** `balanceOf` at cast time is exploitable. Do not reuse it.
- **`LabPair` has no LP tokens.** Liquidity is operator-seeded and never withdrawn.
- **`AdventurerBadge.operator` is a centralisation.** It exists so that a failed phone does not
  end someone's session. It is named in the lab pack, not hidden.
- **The relayer is a `cast` command.** Deliberate: fewer moving parts at 200 people.
- **No 4337 sponsorship is implemented here.** That is infrastructure (CDP Paymaster), not code.
  `claimFor` is the fallback until it is wired up.

---

## Licence

MIT for the code. The design document is yours to adapt; the badge art is generated, not licensed.
