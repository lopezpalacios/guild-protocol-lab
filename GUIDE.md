# Operator guide

How to use every surface, in the order you will meet it on the night.

> **Hosted instance:** <https://lab.kameloso.com/> · RPC `https://rpc.kameloso.com` · chain id
> **48901** · console at `/admin.html`. Deployment details live in [`HOSTING.md`](./HOSTING.md);
> everything below applies identically to the local and hosted copies.

If you have never run this before, read [`TUTORIAL.md`](./TUTORIAL.md) first — it takes you from
zero to a working local lab in about 25 minutes. This document assumes it already runs.

---

## 1. The six surfaces

| Surface | URL | Who | What it is for |
|---|---|---|---|
| Hub | `/index.html` | You | Status line + links. Open it first to confirm the chain is alive. |
| Projector | `/spectator.html` | The room | Live tally, pool price, badges. No wallet. Put this on the big screen. |
| Guild | `/g.html#k=0x…&g=7` | Delegates | Sign, queue, submit, claim loot. Opened from a printed card. |
| Badge | `/claim.html?g=7` | Everyone | Mint the souvenir. Renders the on-chain SVG. |
| Console | `/admin.html` | You | Queued ballots, one-transaction submit, rejected ballots and why. |
| Cards | `/cards.html` | You | Prints 25 QR cards in your browser. Nothing is uploaded. |

The first four are for the room. The last two are yours, and nobody else should see them.

---

## 2. Starting the server

```bash
RPC=http://127.0.0.1:8545 \
OPERATOR_KEY=0x… \
python3 server/lab.py --port 8080
```

It prints a banner with the operator token:

```
  site         http://127.0.0.1:8080/
  projector    http://127.0.0.1:8080/spectator.html
  console      http://127.0.0.1:8080/admin.html
  operator key set
  token        qJ7xK2mP9a
```

Paste that token into the console once. It is stored in the browser's localStorage, so you do it
once per browser, not once per page.

**Two things the server prints that matter:**
- `operator key set` — if this says `NOT SET`, the console can collect ballots but cannot submit
  them. Check it before the room fills.
- the token — treat it as the only thing standing between a curious attendee and your operator
  functions.

**Port already in use?** On macOS something commonly squats on 8080 on IPv6 while your server
binds IPv4, and `localhost` resolves to the squatter. Always test with `127.0.0.1`, and pick
another port if the banner's URLs do not load: `--port 8090`.

---

## 3. The console, which is the whole demo

Open `/admin.html`. You will see one card per poll.

**Reading it:**

```
poll1 · Which encounter next?          [open]
Break the AMM                          12
Govern something real                  13
total                                  25
[ Submit 25 queued as one tx ]
```

The tally is on-chain. The "queued" count is signatures that exist and have not been sent —
they cost nobody anything and they are not votes yet. That gap is the lesson.

**Submitting:**

Press the button. The server does two things, and the order matters:

1. **Pre-flights every ballot individually** with `cast call`. A bad signature, a repeated
   address, or a closed poll is caught *before* it can poison the batch.
2. **Sends the survivors as one transaction.**

You get back something like:

```
submitted 23 ballots in one transaction in 4.1s · rejected 2:
0x2b04…c9a1 already voted, 0x132d…650f signature does not match signer · 0x5a33…
```

Say that out loud. The rejected list is not a bug report, it is the censorship-and-validity
lesson arriving on its own.

**If it says `every queued ballot failed pre-flight`**, nothing was sent and nothing was lost.
Read the reasons. The two common ones are `already voted` (someone used the "send it yourself"
button on their guild page) and `signature does not match signer` (a delegate changed their
choice after signing and the page queued the old one).

---

## 4. The projector

`/spectator.html` — and `/spectator.html?poll=2` for the second poll.

It connects over SSE and updates the moment the tally changes. If SSE fails it silently falls
back to polling every 3 seconds; the status line tells you which mode you are in.

**Set this up before doors**, from the back row, on the actual projector. Two things to check:
- The leading option gets a gold rule on the left. If you cannot see it from 25 metres, move to
  the 60pt view by zooming the browser, not by changing the CSS at 18:55.
- The number must be readable without colour. It is — the counts are text, the bars are decoration.

---

## 5. The guild page

Each printed card carries a QR encoding:

```
https://your-host/g.html#k=0x<private key>&g=7
```

The key lives in the URL **fragment**, which browsers never send to a server. That is deliberate:
the key does not appear in an access log.

**The four steps a delegate takes:**

1. **Pick an option.** Two buttons.
2. **Sign.** Produces an EIP-712 signature. The page says, in as many words, *no transaction was
   sent, nothing on chain changed, vote is still NOT counted*. It also posts the signature to the
   room's ballot box and tells them how many are waiting.
3. **Submit it yourself** *(optional)*. Sends their own transaction. Costs gas. This is the
   fallback when the server is down, and the exhibit when it is not: same signature, two paths.
4. **Claim 1,000 LOOT.** Merkle proof from `web/merkle.json`.

**What a delegate needs:** about 0.002 ETH on the guild wallet. Fund at T-1 with
`./scripts/fund-guilds.sh`. If they skip step 3 entirely — and they should — they need no ETH at
all, because the vote is carried by the operator's batch.

---

## 6. The badge

`/claim.html?g=7` — connect a wallet, press mint.

The page decodes `tokenURI()` and renders the SVG inline. That is the point of the segment: the
image came out of the contract, not off a server. If the room's phone fails, the fallback is one
command:

```bash
OPERATOR_KEY=0x… ./scripts/claim-for-all.sh data/attendees.txt
```

`attendees.txt` is one address per line, optionally `address,guildId`.

---

## 7. Printing the cards

Open `/cards.html`, paste `data/guilds.csv`, press Render, then Print.

- The base URL field must match where the site is actually served from. Wrong host = 25 dead cards.
- **The sheet contains live private keys.** Print it, cut it, put it on the tables, and do not
  leave a spare in the printer tray. Photographing a card is a valid attack and it is the lesson,
  but only for the guild whose card it is.

---

## 8. Minute by minute

| Minute | Operator action |
|---|---|
| T-60 | `./scripts/state.sh` — confirm chain, price, badges. Server banner checked. Console token pasted. |
| T-15 | `/cards.html` already printed. Door cards out. |
| 0:00 | Projector on `/spectator.html`. Do nothing else. |
| 0:08 | Watch the queued counter climb during the loot claim. |
| 0:13 | **Poll 1 closes.** Console → Submit. Read the rejected list aloud. |
| 0:23 | **Poll 2 closes.** Console → Submit. |
| 0:37 | Badge mints. Watch `/api/state` badges count on the projector. |
| 0:55 | Post-instrument QR. |
| T+0 | `./scripts/state.sh > data/final-state.txt` — your receipt. |

**The one thing you must not do:** submit a poll before it closes. The contract will reject every
ballot with `poll closed` and you will spend four minutes explaining a self-inflicted wound.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Console loads but the tally is all zeros and never moves | Server cannot reach the RPC | `curl 127.0.0.1:8080/api/health`; check `RPC` |
| `submit failed: OPERATOR_KEY is not set` | Server started without the key | Restart with `OPERATOR_KEY=…` |
| `unknown poll` when a delegate signs | Server's `deployments/<chain>.json` is from a different deploy than `web/config.js` | Redeploy with `./scripts/deploy.sh`, which regenerates both |
| `your address is not in the tree` | `data/participants.json` was regenerated **after** deploy | Redeploy. The merkle root is baked into the contract |
| Projector frozen | SSE dropped and the fallback failed | Reload. It reconnects. Status line says which mode |
| Everything reverts with `nonce` errors | Two servers running against one key | `pkill -f server/lab.py` |
| Cards scan to a dead page | Base URL in `/cards.html` was wrong | Reprint. There is no clever fix |

---

## 10. What lives where

```
data/ballots.jsonl        every signature ever queued, append-only. Your audit trail.
data/merkle.json          root + proofs. Regenerated by every deploy.
data/guild-keys.txt       SECRET. Gitignored. Regenerate rather than share.
data/loadsim-report.md    the last dry run, timestamped.
deployments/<chain>.json  addresses. The only source of truth for them.
web/config.js             generated from that file. Never edit by hand.
```
