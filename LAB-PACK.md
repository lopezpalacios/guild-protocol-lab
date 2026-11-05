# THE GUILD PROTOCOL
### A 60-minute blockchain lab for 200 people — ETH Zurich, Digital Assets Forum

**Version:** 1.0 · **Chain:** Base Sepolia (84532) · **Assets:** valueless testnet only
**Format:** 25 guilds × 8 people + a 20-person player cohort on stage · **Treasury:** pre-funded at T-1

---

## 0. THE ONE-PARAGRAPH VERSION

Two hundred people arrive, get split into guilds of eight, and are handed a card with a wallet on it. Over the next hour they collectively choose which protocols they will visit, and the choosing is itself done with the thing being taught: a signature. They receive loot, break an automated market maker, watch a loan get liquidated, and mint a badge whose metadata proves which route *this specific room* chose. The last thing they do is the most advanced thing they do — a gasless smart-account claim they never had to understand in order to complete. The lab's single learning claim is narrow and honest: **a signature is not a transaction, and you should know what yours authorises.**

---

## 1. LEARNING DESIGN SPINE
*Written first. Everything downstream aligns to it.*

### 1.1 Learning outcomes

| # | Outcome | Bloom | Assessed by |
|---|---|---|---|
| **LO1** | Distinguish a signature from a transaction, and state what a signature authorises | Understand | Post-item 1 (primary) |
| **LO2** | Explain why a claim-based distribution (merkle) differs from a push payment, and who pays gas in each | Understand | Post-item 3 |
| **LO3** | Predict how an AMM's price responds to a trade, before seeing the result | Apply | Live prediction, guild card |

**The single must-do outcome** — the one thing a cohort-A attendee must be able to do at minute 60:

> *Given a wallet prompt, say whether it moves funds or merely authorises something, and name who pays the gas.*

If they can do that and nothing else, the lab succeeded. Everything else is enrichment.

### 1.2 The scope claim, stated honestly

This is **a demonstration with an evaluation instrument**, not a study. It has no control group, no randomisation, no delayed post-test, and a self-selected population of people who chose to attend a blockchain lab at ETH Zurich. It can support the claim "this format produced a measurable shift in a room of 200 in under an hour." It cannot support the claim "this format teaches blockchain." Write the former, never the latter — the academic reviewers will check.

### 1.3 Pre/post instrument
Five items, 90 seconds, QR at minute 0 (during seating, off the clock) and minute 55.

1. *True or false:* a signature alone can move funds out of your wallet. → **False**
2. Who pays the gas in a sponsored (paymaster) transaction? → **the paymaster, not the user**
3. What does a merkle root let a contract do? → **prove an address is in a set without storing the set**
4. An AMM's price is set by: an order book / **a formula over its reserves** / the team
5. Match: EIP-712 · ERC-721 · ERC-4337 → **typed-data signature · NFT · account abstraction**

**Success threshold:** ≥60% of respondents improve by ≥2 items, **and** ≥80% answer item 1 correctly at post. Failure is reported, not hidden.

---

## 2. QUEST MAP
Ten encounters, tiered I–V. **Tap cost** = on-chain actions per person performing it.

### Tier I — *the ground floor*

**E1 · Signature, not transaction** — `EIP-191` / `EIP-712`
*Guaranteed. 4 min. Tap cost: 1 signature, 0 transactions.*
Cohort A and the room sign a structured message with their guild wallet. A verifier contract on Base Sepolia calls `ECDSA.recover` and emits an event containing the recovered address. **Nothing moves.** The screen shows: signature produced → address recovered → zero balance change.
Teaches: an authorisation is data, not a payment. This is the spine of the entire hour.
Failure mode: delegate's browser blocks the deep link. Fallback: presenter signs from the player cohort on stage; guilds watch.

**E2 · Loot — the merkle airdrop** — `EIP-20` + MerkleDistributor
*Guaranteed. 5 min. Tap cost: 1 claim.*
A `Loot` ERC-20 is distributed by a merkle distributor. Only the root is on-chain; the 45-address list exists as a file. Delegates claim; non-claimants are still provably owed.
Teaches: claim vs. push, why airdrops use merkle roots, and who pays the gas — the claimant does, here, and that is a design choice with a victim.
Failure mode: delegate's wallet has no ETH for gas. Fallback: guild wallets are pre-funded at T-1 with 0.002 ETH; the claim also works through the sponsor if we enable it.

### Tier II — *things people actually use*

**E3 · Mint the badge** — `EIP-721`, fully on-chain `tokenURI`
*Folded into E9. 8 min. Tap cost: 1.*
The Adventurer Badge is an ERC-721 whose `tokenURI` returns a base64 on-chain SVG. No IPFS, no pinning service, no link that can rot.
Teaches: what "on-chain metadata" actually buys you, versus a token that points at a URL someone else controls.
Failure mode: SVG gas blowout. Fallback: badge art is generated off-chain at deploy, stored as a `string` in the contract; supply is capped at 250 so the deploy is a one-time cost.

**E4 · Names** — ENS
*4 min. Tap cost: 0 — read-only, deliberately.*
A live resolution of a real ENS name on Ethereum Sepolia via a public RPC, on screen. Then the contrast: Basenames on Base, CCIP-Read for off-chain resolution, and why a name is a UX layer over an address, not a security layer.
Teaches: the gap between "human-readable" and "trustworthy."
Why no tap: **tap budget.** This is the scheduled breathing space after two active segments — and the first thing cut if we run long.
Failure mode: RPC rate-limits. Fallback: pre-recorded resolution, clearly labelled as pre-recorded.

**E5 · Break the AMM** — Uniswap V2-style constant product
*Voted. 8 min. Tap cost: 1 (pre-approved at T-1).*
We deploy two mock ERC-20s — **Gold** and **Silver** — and seed a pair at T-7 with 50,000 each. Guilds swap in sequence, one after another, and watch the price curve move *because of the room's own trades*. Guilds predict the next price on their card before the trade; the Scribe's prediction is compared to the outcome.
Teaches: price as a function of reserves, slippage, and why depth is the whole game.
This is better than using a real testnet DEX: liquidity is guaranteed, the curve is legible, and the room is visibly the market maker's counterparty.
Failure mode: someone drains the pool. Fallback: cap swap size at 200 tokens per guild in the UI; the contract enforces it.

**E6 · Get liquidated** — minimal lending pool
*Voted alternative to E5. 8 min. Tap cost: 2.*
A minimal Compound-style pool we deploy and seed at T-1. A guild supplies Gold as collateral and borrows Silver at 50% LTV. The health factor appears on screen. Then the presenter moves the oracle price — a button, and we say it is a button — and the room watches the health factor cross 1.0 and the position become liquidatable.
Teaches: overcollateralisation, oracle dependency, and that "the price" in DeFi is an input someone supplies.
This is the most dramatic three minutes available in the lab. If the room votes for it, protect the time.
Failure mode: oracle update races the demo. Fallback: a `setPrice` admin function on a testnet-only oracle, with the centralisation stated aloud.

### Tier III — *the systems layer*

**E7 · Bridge, asynchronously** — OP Stack cross-domain messenger
*Voted. 8 min. Tap cost: 1, initiated early.*
A guild initiates an L1 Sepolia → Base Sepolia deposit at minute 15; the room checks whether it has arrived at minute 52. **If it fails to arrive in time, that is the lesson**, and we say so.
Teaches: bridging is not swapping; it is a message with a delay and a trust assumption about who relays it.
Failure mode: L1 Sepolia gas unavailable or deposit exceeds the hour. Fallback: pre-stage a deposit at T-1 and show its arrival live; the guild's own deposit becomes a side quest.

**E8 · Govern something real** — OpenZeppelin `Governor` + `Timelock`
*Voted. 8 min. Tap cost: 1, gasless.*
Guilds vote on a parameter that actually changes the lab: **which encounter runs last**, or the swap fee on the Gold/Silver pair. One-guild-one-vote first, then a token-weighted re-run using Loot balances, so the room *feels* the difference in governance models in ninety seconds.
Teaches: delegation, quorum, timelock delay, and the political difference between one-person-one-vote and one-token-one-vote.
Failure mode: quorum not reached. Fallback: quorum is 5 of 25 by design, and non-reach is itself demonstrated on screen.
*Chain note: E7 and E8 are mutually exclusive in the voted slot — same 8 minutes.*

### Tier IV — *the frontier*

**E9 · The claim that costs you nothing** — `ERC-4337`
*Guaranteed. 8 min. Tap cost: 1, sponsored.*
Attendees claim the badge through a smart account and a paymaster. No ETH, no gas prompt, no network switch. Under the hood: a `UserOperation`, a bundler, a paymaster signature.
Teaches: what a smart account changes, and that "free" means someone else is paying and deciding.
This is deliberately **the last action of the lab** — the most advanced thing, with the least friction. The didactic point lands without a lecture: the frontier of UX is the removal of the thing you spent an hour learning about.
Failure mode: bundler or paymaster outage. Fallback: direct mint from a pre-funded relayer EOA; the badge is the same, the lesson is delivered verbally with the transaction on screen.

**E10 · What is coming** — intents, `ERC-7683`
*6 min. Tap cost: 0.*
**Selection criterion, stated out loud:** *a frontier protocol earns its place only if it changes who signs, who pays, or what can be proven.* Faster does not qualify.
Intents win on that criterion because they change **who signs**: you sign a desired outcome, and a solver signs the transaction. That inverts E1, which is why it closes the lab rather than opening it.
Named alternatives and why they lost the slot: **zkVMs** (changes what can be proven — the strongest academic pick, weakest live-demo pick in six minutes), **restaking** (changes who secures — most topical to this forum, thinnest conceptual payload for cohort A).
If the room skews cohort C, swap in the zkVM.

---

## 3. DECISION ARCHITECTURE

### 3.1 Cohort measurement — off the clock
Three questions on the door card, answered while people sit, between T-15 and T-00. No identifiers. Aggregated only.

1. Do you have a wallet on your phone right now? **Y / N**
2. Have you signed a transaction in the last 30 days? **Y / N**
3. Have you deployed a contract? **Y / N**

Scoring: `0 yes` → **A**. `1–2 yes` → **B**. `3 yes` → **C**.

### 3.2 The branch rule — explicit logic

```
if  A > 50%:
      guaranteed = E1, E2, E9
      voted      = [E5 | E8]  then  [E7 | E10]
      side quest = E7, E10-short
      pacing     = +60s narration on every encounter, zero jargon without a definition

elif C > 25%:
      guaranteed = E1, E2, E8, E9
      voted      = [E5 | E8]  then  [E7 | E10-zk]
      side quest = E4
      pacing     = skip definitions, add the "what testnet lies about" slide early

else:  # cohort B dominant — the default script
      guaranteed = E1, E2, E9
      voted      = [E5 | E8]  then  [E7 | E10-full]
      side quest = E10-full, E4
```

The announcement at minute 4 is a *performance moment*, not an administrative one: the room is told its own composition and what that composition bought it.

### 3.3 How the vote works

Guild delegates sign an `EIP-712` ballot off-chain. Signatures post to a Cloudflare Worker. At poll close the worker batches all ballots into **one** transaction calling:

```solidity
function castVotes(bytes32 pollId, address[] signers, uint8[] choices, bytes[] sigs)
```

Four consequences, all of them taught in the 40 seconds of dead time while the batch lands:

- **A signature is not a transaction** — reiterated, now with a counterexample the room just produced.
- **The relayer is a trust surface.** Ours can drop your ballot. Each signature is also posted to a public paste so anyone can resubmit it. We name the censorship vector rather than hiding it.
- **Batching is why this is possible at 200.** One transaction, 25 votes, ~40k gas.
- **The tally is on-chain and readable by anyone**, including the spectator page, which reads the contract directly rather than trusting our screen.

Display: one number, ≥60pt, Okabe–Ito palette, plus a scrolling text ticker (`GUILD 07 → E5`) for anyone who can't resolve the colour or the glyph.

---

## 4. TWO-TRACK ONBOARDING

| | Track P — Players (20) | Track G — Guilds (25) | Track S — Spectators (155) |
|---|---|---|---|
| Wallet | MetaMask, own device | Pre-generated EOA, key in QR | None |
| Funded | T-1 airdrop | T-1, 0.002 ETH each | — |
| Prep | Rehearsed at T-7 | Cards printed T-3, scanned T-1 | Link only |
| Acts on | Stage transactions | Votes, claims | Reads, predicts, argues |
| Taps/hour | 6–8 | 5–6 | **0–1** |

**The tap budget is the design.** Roughly four on-chain actions per person is where comprehension stops and tapping begins. The room taps **twice** (loot claim, badge). Delegates tap five or six times. The player cohort absorbs the rest on stage, as performance.

**Guild card** carries: guild number, banner glyph, four role assignments, wallet QR, short URL, and the three prediction questions.

**Roles** — assigned, not volunteered, because unassigned groups produce one dominant tapper and seven spectators:

- **Delegate** — holds the phone, taps, is the only person who signs.
- **Scribe** — records predictions and the guild's reasoning on the card.
- **Sceptic** — must state one objection *before* the guild votes. Not optional.
- **Zeitgeist** — reports the guild's gut feeling; the only role allowed to say "this feels like a scam," which is a legitimate and necessary contribution.

**Track S is not a consolation prize.** The spectator page shows the live tally, the current encounter, and the treasury balance, read directly from the chain. It works with JavaScript and no wallet, and it is the page most of the room will actually look at.

---

## 5. IMPLEMENTATION SPEC

### 5.1 Contracts (all Base Sepolia, all verified at deploy)

**Rescoped at build time.** The original seven-contract table was scope creep for a two-week build. Five contracts ship; the lessons that lost their contracts are delivered another way, and the differences are named on screen.

| Contract | Standard | Purpose | Shipped |
|---|---|---|---|
| `LabToken` | ERC-20 | Deployed three times: Loot, Gold, Silver | ✅ |
| `MerkleDistributor` | — | Root + proofs, 45 leaves, permissionless relay | ✅ |
| `AdventurerBadge` | ERC-721, on-chain SVG | Souvenir, route metadata, operator fallback | ✅ |
| `Ballot` | — | `castVotes` batch, `EIP-712`, equal **and** token-weighted | ✅ |
| `LabPair` | Uniswap V2-style | The AMM the room breaks, hard trade cap | ✅ |
| ~~`MiniPool` + `TestOracle`~~ | Compound-style | The liquidation (E6) | ❌ cut — the real casualty |
| ~~`LabGovernor` + `Timelock`~~ | OZ Governor | Replaced by `Ballot` in `TokenWeighted` mode | ❌ merged |

**E6 (liquidation) is the one genuine loss.** It was the most dramatic three minutes in the design and the most fragile. If the build has a second sprint, it comes back first.

**E8 (governance) survives without `Governor`.** `Ballot` runs the same room under one-guild-one-vote and then token-weighted. The political point — that weighting is a choice, not a law — is delivered by the contract that already exists. `test_tokenWeightedFlipsTheResult` shows one whale outvoting twenty-four guilds.

**E7 (bridge) has no contract of ours.** It is a scheduled async observation on the official OP Stack bridge, checked again at minute 52.

**E9 (4337) has no contract of ours either.** Coinbase Smart Wallet plus CDP Paymaster. `AdventurerBadge.operator` and `claimFor` exist as the stated fallback if sponsorship fails on the night.

**No addresses are listed here on purpose.** Addresses are recorded in `deployments/<chainId>.json` at T-14 and the pack is regenerated from that file. Any address in a document is a stale address.

### 5.2 Key management
- **Treasury:** a single funded key in the scaffold (`deployments/` + `PRIVATE_KEY`), promoted to a Safe 2-of-3 before the event. The scaffold prioritises a one-command deploy; the event prioritises not losing the key.
- **Guild wallets:** 25 EOAs from `scripts/gen-participants.sh`. Key printed in the QR fragment (`g.html#k=0x…&g=7`) so it never reaches a server log.
- **Player wallets:** attendee-owned MetaMask, topped up at T-1 by script.
- **Badge operator:** one hot key, used only for the `claimFor` fallback. Named on screen as a centralisation we accept.

### 5.3 Distribution
- **Loot:** merkle, 45 leaves (25 guilds + 20 players). Root on-chain, proofs served statically.
- **Badge:** open claim, capped at 250, one per address, sponsored.
- **Fallback:** if sponsorship fails, all 250 are pre-minted to the 25 guild wallets and each card's badge link resolves.

### 5.4 The dry run — non-negotiable
A script that, on a fresh fork, **simulates 200 badge claims and 25 votes** and asserts the tally matches the ballots. Run at T-7 and T-1. A lab that has not been load-simulated is a rehearsal, not a plan.

---

## 6. TESTNET HONESTY SECTION
*Every claim below is false on mainnet. Say each correction out loud, once, at the moment it appears. A DLT reviewer checks for this section before reading anything else.*

| What the lab shows | What is true on mainnet | The sentence you say |
|---|---|---|
| Gas is free | Gas is a market and a UX tax | "Nothing here cost you anything. On mainnet, every tap is a bid." |
| Sponsored transactions | Sponsorship is a business subsidy, not a protocol feature | "Someone is paying for you, and they are buying your attention." |
| Swaps execute cleanly | Searchers sandwich predictable order flow | "On mainnet, a bot read this transaction before you sent it." |
| Price impact is small | Real pools are thin relative to real size | "We built a deep pool. Nobody does that for you." |
| Liquidation happens on a button | Liquidation is a competitive bot market with latency races | "I am the keeper. On mainnet there are a thousand of me, and we are faster." |
| Testnet tokens are free | Tokens are money, which changes your users' psychology and your legal posture | "Valued assets change the people holding them. That is the part you cannot simulate." |
| The badge is permanent | Testnets reset | "This is a souvenir, not an asset. The chain it lives on may be deleted." |

---

## 7. SECURITY & THREAT MODEL

| Surface | Reality | Posture |
|---|---|---|
| **Printed private keys** | Anyone who photographs a card owns that guild's wallet | Accepted by design on testnet. Guild wallets hold ≤0.002 ETH and no loot beyond the badge. **Said aloud at minute 8** — the flaw is the curriculum. |
| **Vote relayer** | Can censor a ballot | Ballots also posted publicly; anyone can resubmit. Named on screen. |
| **Unlimited approvals** | We pre-approve max at T-1, which is bad practice | Stated explicitly as a convenience we would not take with real money. |
| **Centralised oracle** | `setPrice` is an admin function | Testnet-only; the centralisation *is* encounter E6's payload. |
| **Contract verification** | Unverified contracts are unreadable | All verified on Basescan; source in the public repo. |
| **Burner reuse** | 25 keys exist in printed form | Treated as compromised from the moment of printing. Never reused. |

---

## 8. DIDACTIC SPEC

**Cognitive-load budget.** No segment exceeds 8 minutes. Every segment opens with a one-sentence advance organiser and closes with a single retrievable fact. Vocabulary is pre-trained before minute 1 — *signature, transaction, gas, wallet, chain* are defined on the door card, not from the stage.

**Sequencing — I do / we do / you do.**
E1 is *I do*: the presenter signs, the room watches, nothing is asked of them. E2 is *we do*: delegates claim while the room watches the tally. E5–E8 are *you do*: guilds act and predict. The badge claim (E9) is the only *you alone*, and it is deliberately frictionless because it is the last thing before the door.

**Prevention of free-riding.** Assigned roles (§4), one wallet per guild, and a Scribe who must write predictions down — the prediction is the artefact that proves participation, not the transaction.

**Retrieval close, not a summary.** Minute 51: three questions, answered by show of hands and then by QR.
1. What did your signature at minute 2 authorise?
2. Who paid for your badge?
3. If your guild's swap moved the price, who moved it?

**The cut line.** At minute 40, if we are more than 4 minutes behind, **E4 (ENS) is dropped** and its one-sentence version is said over the closing slide. Second cut: E10 reduced to 3 minutes with the criterion and one example. The presenter does not negotiate this live — the helpers enforce it.

---

## 9. ACCESSIBILITY & INCLUSION

- Every QR is paired with a spoken short URL (`lab.ethz.ch/g07`) — QR codes are unreadable to screen readers and to the back row.
- Key figures ≥60pt; body ≥28pt. Contrast ≥4.5:1 (AA) for body, ≥3:1 for large text.
- Vote palette is Okabe–Ito (colourblind-safe) **and** labelled with glyphs and text. No colour-only encoding anywhere.
- Standard text size is 28pt minimum, not 24. At 200 people, the back row is at roughly 25 metres.
- Phone-only path: every guild action is completable on a 2019 Android phone on 3G.
- Motor impairment: the Delegate role means one person taps per guild, and helpers may tap on request without comment.
- Low vision: every on-screen number is also read aloud.
- **Every point where a cohort-A attendee could be stranded is flagged in the run of show with a `⚠A` marker.**

---

## 10. ETHICS & DATA

- **Nothing personal goes on-chain.** Wallet addresses only. The door survey is anonymous and aggregated; no identifiers are collected, so no linkage is possible even in principle.
- **Pre/post linkage** uses a random per-person code printed on the door card, not identity. Codes are destroyed after aggregation.
- **On-chain permanence is demonstrated, not asserted.** At minute 9 we show the block explorer entry for the loot claim and say: this cannot be deleted, which is exactly why your name is not in it.
- **Photography:** signage at the door, opt-out lanyard colour, and a helper briefed to intervene. No filming of faces without consent.
- **Swiss nFADP posture:** anonymous aggregate survey data, no special-category data, no cross-border transfer of personal data. Legal review at T-14.
- **Publication:** contracts verified, repo public, anonymised pre/post results published within 30 days of the event.

---

## 11. RUN OF SHOW

| Time | Segment | Owner | Notes |
|---|---|---|---|
| T-15 | Doors. Door cards + QR survey | Helpers ×6 | Cohort data is collected here, not on the clock |
| **0:00** | **Cold open: one signature, zero movement** | Presenter | E1 performed on stage; recovered address on screen |
| 0:04 | Character Creation reveal + branch announcement | Presenter | The room is told its own composition |
| 0:08 | E2 Loot — merkle claim | Presenter + delegates | ⚠A: helpers roam; claim is one tap |
| 0:13 | **Vote 1** (E5 vs E8) ᵃ | Relayer | 40s of dead time, filled with the batching lesson |
| 0:15 | Voted encounter A | Presenter + guilds | 8 min hard stop |
| 0:23 | **Vote 2** (E7 vs E10) ᵃ | Relayer | Same pattern, faster now |
| 0:25 | Voted encounter B | Presenter + guilds | 8 min hard stop |
| 0:33 | E4 Names — read-only, breathing space | Presenter | ⚠A: no tap required, by design |
| 0:37 | E9 Badge — sponsored 4337 claim | Presenter + all | The last action is the most advanced |
| 0:45 | E10 What is coming — intents | Presenter | Criterion stated aloud |
| 0:51 | Retrieval close — three questions | Presenter | Not a summary |
| 0:55 | Post instrument | QR | 90 seconds |
| 0:57 | Artifacts, repo, publication promise | Presenter | Where the thing lives afterwards |
| **1:00** | **Hard stop** | — | Helpers begin card collection |

> **ᵃ As-built.** The design intended Vote 1 to be E5 vs E6 (liquidation) and Vote 2 to be E7 vs E8 (governance). E6 is not implemented — see §5.1 — so Vote 1 pairs the AMM against governance and Vote 2 pairs the bridge observation against the frontier segment. The repo (`Ballot` + `LabPair`) implements exactly these two polls.

**Helper deployment (6–10 people):** two at the door (cards, survey), two roaming Guild A–M, two roaming Guild N–Z, one on the relayer console, one on the projector. The relayer operator has a single job: if the batch hasn't landed in 45 seconds, say so on the comms channel and the presenter narrates the delay as content.

---

## 12. RISK REGISTER

| Trigger | Response | Fallback |
|---|---|---|
| Venue wifi collapses | Switch to the presenter's phone hotspot | Player cohort runs the whole lab on stage; guilds vote by show of hands, results entered by operator |
| Relayer or bundler down | Announce it; it is a trust-surface lesson | Votes by hand, entered by operator; badge minted via direct relayer EOA |
| Chain congestion / RPC 429 | Say the number on screen | Switch RPC endpoint; the spectator page has three configured |
| Projector unreadable at distance | Go to the 60pt single-number view | Helpers read the number aloud per guild |
| Delegate's phone dies | Swap to a spare card (5 held at the desk) | Guild merges with the neighbouring guild; noted by the Scribe |
| Launched late by 6+ minutes | Cut E4 at minute 40 | Cut E10 to 3 minutes |
| One guild dominates debate | Sceptic role forces an objection before every vote | Helper joins the quiet guild |
| Cohort A far larger than surveyed | Branch rule already handles A > 50% | Drop the vocabulary-free assumption entirely; narrate every screen |
| Airdrop claim rate < 50% | Expected; it is not a failure metric | Loot is pre-minted to guild wallets at T-1 as a floor |

---

## 13. COST & TOOLING

| Item | Tool | Cost |
|---|---|---|
| Chain | Base Sepolia | — |
| Gas, all transactions incl. 200 claims | Treasury Safe | < $1 |
| Sponsorship | Coinbase CDP Paymaster (testnet tier) | free |
| Frontends | Cloudflare Pages (3 static pages) | free |
| Vote relayer | Cloudflare Worker + KV | free |
| Contracts | Foundry, verified on Basescan | free |
| Printing: 25 guild cards, 200 door cards | local | ~CHF 150 |
| **Total** | | **< CHF 200** |

---

## 14. PRE-FLIGHT CHECKLIST

**T-14** — Contracts deployed and verified · addresses committed · legal review of nFADP posture · player cohort invited (20 + 5 spares) · this pack regenerated from `deployments/`.

**T-7** — **Load simulation: 200 claims + 25 votes on a fork, tally asserted.** · AMM seeded · pool seeded · oracle set · dry run of the full run of show with helpers · sponsor quota confirmed.

**T-3** — Guild cards printed and each QR scanned by a different person · door cards printed · post/pre instrument tested on 5 people for completion time.

**T-1** — Treasury funded · 25 guild wallets funded · 20 player wallets topped up · merkle root published · spectator page pointed at live contracts · **second full dry run**.

**T-60 min** — Chain health check · relayer ping · projector at 60pt from the back row · three RPC endpoints live · spare cards at the desk · helpers briefed on the cut line.

**T-5 min** — Presenter's phone on the presentation network · MetaMask unlocked, wrong-network warning acknowledged · session keys loaded · comms channel open.

---

## 15. REVIEWER RESPONSE APPENDIX

### DLT engineers

**"Your lab teaches a system that does not exist."**
Correct, and §6 exists because of it. The testnet delta is taught as content, not confessed as a limitation — seven specific claims, each corrected aloud at the moment it appears. We would rather a participant leave knowing the difference than leave believing gasless swaps are normal.

**"The relayer is centralised and the printed keys are public."**
Both true and both deliberate, and both are named on screen at the moment they matter. The alternative — one wallet per attendee — triples the tap budget and destroys the didactics. We chose a legible trust model over an illegible one.

**"Why not mainnet, or a real L2 with real assets?"**
Because a public airdrop of valued assets to 200 strangers is a regulatory question we are not qualified to answer in an hour, and because the presence of value changes what people attend to. The learning claim in §1.1 is about authorisation, not about price.

### Academics

**"This is not evidence of learning."**
It is not, and §1.2 says so before you do. It is a demonstration with a pre/post instrument and a stated threshold. It is designed to be *reproducible* — contracts, scripts, and anonymised results published within 30 days — which is the contribution we are actually claiming.

**"Your sample is self-selected and n=1 session."**
Yes. The published claim will be scoped to "this format produced a measurable shift in this room," and the instrument will be released so others can run it in theirs. We are contributing a format and a measure, not a finding.

**"Where is the ethics approval?"**
There is no human-subjects research here: the survey is anonymous, unlinked, and contains no personal or special-category data. We have a legal review of the nFADP posture at T-14 and a consent regime for photography. If a reviewer judges the pre/post to constitute research, we will submit it at T-30 and report unapproved.

### Didacts

**"Ten protocols in sixty minutes is a firehose."**
Which is why only three are guaranteed, and why the tap budget is capped at roughly four actions per person. The room taps twice. The player cohort absorbs the performance load. §8 sets a hard 8-minute ceiling per segment and a named cut line enforced by helpers, not by the presenter's optimism.

**"Group work becomes one person tapping."**
Assigned roles, one wallet per guild, and a Scribe whose written predictions are the participation artefact. The Sceptic role is not decorative: an objection is required before every vote, which is the mechanism that makes disagreement legitimate.

**"How do you know they learned anything?"**
Three questions at minute 51, answered aloud before the instrument, plus the pre/post. The primary item is a single discrimination — signature versus transaction — because a narrow, testable outcome beats a broad, unfalsifiable one.

---

## 16. KNOWN LIMITATIONS

Stated here so a reviewer does not have to find them.

1. **No control group.** Improvement cannot be attributed to the format rather than to attendance.
2. **No delayed post-test.** Retention is unknown and unclaimed.
3. **Testnet is not mainnet.** §6 mitigates, it does not solve — the psychology of valued assets is absent by design.
4. **Single session, self-selected population.** Not generalisable to a general public.
5. **The AMM and lending pool are ours.** They are legible and deterministic, and they are not production systems; the difference is stated on screen.
6. **The relayer is a single point of failure** with a manual fallback, and the fallback has not been tested under load at 200.

---

*Generated from the Lab Pack prompt v2. Addresses, artefact hashes, and result data are filled at T-14 and T+30 respectively.*
