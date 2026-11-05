# Presentation

Two artefacts and one script.

- **`web/deck.html`** — a 15-slide deck you can present from any browser. Arrow keys / space to
  advance, `N` toggles speaker notes, `Home`/`End` jump, click left third to go back.
- **This file** — the same deck as a script: what is on screen, what you say, and what to do when
  it breaks.
- **`LAB-PACK.md` §11** — the minute-by-minute run of show. The deck is the backdrop, not the
  timetable: you will skip slides the room did not vote for, and that is correct.

Press `Cmd-P` on `deck.html` to print it as a handout.

---

## The opening, word for word

> "There are two hundred of you and one of me, so we are going to cheat. You are not an audience,
> you are twenty-five guilds. Each table has a wallet. Each guild gets one vote, one card, and one
> job — argue about what we do next.
>
> In the next hour you will sign something, claim something, break something, and mint something.
> And the whole hour hangs on one sentence: **a signature is not a transaction.** If you leave
> knowing what your signature authorises and who pays for it, this worked. Everything else is
> decoration."

Then move. Do not add a bio.

---

## The slide map

| # | Slide | Minute | Type |
|---|---|---|---|
| 01 | The Guild Protocol | 0:00 | Framing |
| 02 | A signature is not a transaction | 0:01 | **The thesis** |
| 03 | 200 → 25 → 1 | 0:02 | Logistics |
| 04 | The map | 0:04 | Orientation |
| 05 | Sign. Nothing moves. | 0:05 | **Live — E1** |
| 06 | A root, not a list | 0:08 | **Live — E2** |
| 07 | One transaction, 25 signatures | 0:13 | **Vote 1** |
| 08 | 50,000 Gold. Break it. | 0:15 | Live — E5 |
| 09 | One whale, twenty-four guilds | 0:23 | **Vote 2 / E8** |
| 10 | The bridge that arrives late | 0:25 | Live — E7 |
| 11 | The art is inside the contract | 0:33 | **Live — E3/E9** |
| 12 | You sign an outcome | 0:45 | Narrative — E10 |
| 13 | What testnet lied to you about | 0:48 | **The honesty slide** |
| 14 | Three questions | 0:51 | Retrieval |
| 15 | Reproducible | 0:57 | Close |

Slides 8, 9 and 10 are the voted branch. Whatever the room picks, at least one of them is skipped.
That is the format working, not the format failing.

---

## The four sentences you must say verbatim

Not because they are elegant — because each one is a claim the room will test against the screen
two minutes later.

1. **"A signature is not a transaction."** — slide 02, then proven live on slide 05.
2. **"Signing changed nothing. Submitting changed everything."** — when the batch lands, slide 07.
3. **"Someone is paying for you, and they are buying your attention."** — the paymaster, slide 11.
4. **"Weighting is a choice, not a law."** — slide 09, immediately after the whale wins.

---

## Per-slide notes

**01 · The Guild Protocol** — 30 seconds. No bio. The room is deciding whether to open a laptop.

**02 · The thesis** — Say the sentence, then show it. Do not explain ECDSA. The explanation is
the next 55 minutes, delivered as things they do.

**03 · 200 → 25 → 1** — The honest arithmetic: 200 individual wallets is a five-hour onboarding
queue. Twenty-five guilds is one wallet per table of eight. Name the four roles out loud —
Delegate, Scribe, Sceptic, Zeitgeist — and say that the Sceptic must object before every vote.

**04 · The map** — Do not read all ten encounters. Read the five tiers. Say: three are guaranteed,
two or three are yours to choose, the rest are take-home.

**05 · Sign. Nothing moves.** — *I do.* Sign on stage yourself. Show the recovered address, then
the unchanged balance. Keep it under three minutes. The room is watching a mechanic, not a lecture.

**06 · A root, not a list.** — *We do.* Delegates claim while the room watches the tally. Ask:
who pays the gas to claim? The claimant does. That is a design decision with a victim, and it is
why production airdrops use claim contracts and sponsors.

**07 · One transaction, 25 signatures.** — Poll 1 closes. The console pre-flights every ballot and
sends the survivors as one transaction. While it lands, say the sentence. If a ballot is rejected,
read the reason aloud — it is the best slide in the deck and it arrived by itself.

**08 · Break it.** — 50,000 of each, seeded at T-7 so it cannot run dry. Ask the room to predict the
direction before the first trade. Twenty-five swaps take it from 1.0000 to 0.8655.

**09 · One whale.** — Run the same room under one-guild-one-vote, then token-weighted. One address
with 100 LOOT beats twenty-four with 1 LOOT each. Then: *weighting is a choice, not a law.* Add the
sting — production governance uses snapshots precisely because a naive balance read is a flash loan
away from being somebody else's choice.

**10 · The bridge that arrives late.** — Initiated at minute 15, checked at minute 52. If it has not
arrived, that **is** the segment. A bridge is a message with a delay and a trust assumption about
who relays it.

**11 · The art is inside the contract.** — Mint on stage, then decode `tokenURI` in the browser so
the SVG appears out of nothing. No IPFS, no pinning, no link that can rot. Then the sting: the last
action of the hour is the most advanced one, and it cost them nothing, because a paymaster paid.

**12 · You sign an outcome.** — State the criterion before naming the protocol: *a frontier
protocol earns its place only if it changes who signs, who pays, or what can be proven.* Intents
change who signs. zkVM changes what can be proven. Restaking changes who secures. Then say why
intents close the hour: they invert minute one.

**13 · What testnet lied to you about.** — The slide the engineers came for. One correction per row,
said once, at the moment it appears. Never apologise for it. A lab that hides this is teaching a
wrong model of the system, confidently.

**14 · Three questions.** — Hands up, not a summary. The answers are in their mouths.
1. What did your signature at minute 2 authorise?
2. Who paid for your badge?
3. When your guild moved the price, who moved it?

**15 · Reproducible.** — Point at the repo, not at yourself. Contracts verified, 37 tests, load-sim
reports timestamped. Then stop talking. The room is already standing.

---

## When it breaks

| What happens | What you say | What you do |
|---|---|---|
| Batch submit reverts | "Good — the relay is refusing, which is exactly the thing you should not trust." | Read the rejected list. Submit again. If it fails twice, votes by show of hands, operator types them in. |
| Projector freezes | "The chain is fine. My screen is not." | Reload. The page reconnects itself. |
| A guild's phone dies | "Guild 12 has lost its wallet. That is a custody failure and it took eleven minutes." | Hand them a spare card. |
| You are 6 minutes over at minute 40 | Nothing. Just cut. | Drop slide 10 (bridge) and slide 11's mint demo; keep the badge as a link. |
| Only 40 people show up | "We are not twenty-five guilds, we are eight. Your vote is worth three times as much." | Merge tables. Nothing else changes. |
| Someone asks "is this real money?" | "No, and that is the point. Nothing here is worth anything, which is why you are willing to press the button." | Move on. |

---

## Q&A — the eight questions you will get

**"Why testnet? It teaches a false model."**
It does, and slide 13 exists because of it: seven specific claims, each corrected out loud at the
moment it appears. Testnet is chosen for two reasons — a public airdrop of valued assets to 200
strangers is a regulatory question I am not qualified to answer in an hour, and the presence of
value changes what people attend to. The learning claim is about authorisation, not price.

**"Isn't the relayer centralised?"**
Yes, and it is named on screen while it is running. It can drop a ballot. It cannot forge one, and
it is not the only address that can submit — `castVotes` is permissionless, and any holder of the
signature can send it. That is the difference between a relayer and a gatekeeper.

**"Isn't the printed private key a terrible idea?"**
It is, and it is the curriculum. Every card is a published key. On testnet the blast radius is
0.002 ETH, and the room is told at minute 8 that the person at the next table can photograph their
card. Custody is easier to teach as a wound than as a slide.

**"Token-weighted voting with `balanceOf` is exploitable."**
It is. `Ballot` reads the balance at cast time on purpose, and `test_tokenWeightedFlipsTheResult`
demonstrates the consequence. Production governance uses `ERC20Votes` snapshots. We show the naive
version because the failure is more instructive than the fix.

**"What did they actually learn?"**
A narrow, testable thing: distinguish a signature from a transaction and say who pays the gas.
Pre/post instrument, five items, 90 seconds, threshold stated in advance. No control group, no
delayed post-test, and I will not claim retention I did not measure.

**"Why guilds of eight and not pairs?"**
Eight is the largest group where one phone is still a shared object rather than a screen. It also
gives four distinct roles, which is what stops one person tapping for seven others.

**"What would you do differently?"**
Build the lending pool. It was the most dramatic segment and I cut it for schedule. It comes back
first.

**"Can I have the repo?"**
Yes, and that is the answer to most of the above.

---

## What to cut, in order

1. **Slide 10, the bridge** — 8 minutes, and the async arrival is the only segment that can
   genuinely fail on the night.
2. **The live mint on slide 11** — show the badge as a link instead. Saves 4 minutes.
3. **Slide 14, the three questions** — they are worth 4 minutes and you will want them. Cut last.

Never cut slide 02, slide 05, or slide 13. Those are the lab.
