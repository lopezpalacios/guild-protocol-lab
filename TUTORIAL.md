# Tutorial

From nothing to a running lab, with the terminal you will actually see. About 25 minutes.
Every command below has been run on this repo; the outputs are real.

You need: macOS or Linux, [Foundry](https://book.getfoundry.sh/getting-started/installation),
Python 3.8+. No Node. No npm. No Docker.

---

## Step 0 — Check your tools

```bash
forge --version
python3 --version
```

```
forge 1.3.5-stable
Python 3.11.6
```

If `forge` is missing, install Foundry and re-open the terminal.

---

## Step 1 — Generate 25 guild wallets and a merkle input

```bash
cd blockchain-lab-ethz
./scripts/gen-participants.sh
```

```
guilds:   25  -> data/guild-keys.txt (keep secret)
players:  20 -> first 20 anvil accounts
total:    45 leaves -> data/participants.json
```

Three files appear:
- `data/guild-keys.txt` — 25 private keys. **This is a secret.** It is gitignored for a reason.
- `data/guilds.csv` — `id,address,key`, for printing cards.
- `data/participants.json` — who gets loot. 45 addresses.

> **Do not regenerate this after deploying.** The merkle root gets baked into the contract, and a
> new tree means nobody can claim. If you must regenerate, redeploy.

---

## Step 2 — Start a chain

Terminal 1:

```bash
anvil --port 8545
```

Leave it running. It is your lab's chain, and it lives in memory: **closing it erases everything,
including the deployment.** That is fine locally and impossible on Base Sepolia.

---

## Step 3 — Deploy

Terminal 2:

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
RPC=http://127.0.0.1:8545 \
./scripts/deploy.sh
```

That private key is anvil's account 0, publicly known, funded with 10,000 fake ETH. Never use it
anywhere real.

Expected tail:

```
ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.
deployment -> deployments/31337.json
config     -> web/config.js
merkle     -> data/merkle.json + web/merkle.json
```

**Checkpoint.** Six addresses and a merkle root now exist in `deployments/31337.json`. If the
chain id in that filename is not what you expect, stop — see Troubleshooting in the guide.

---

## Step 4 — Start the lab server

Terminal 3:

```bash
RPC=http://127.0.0.1:8545 \
OPERATOR_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
python3 server/lab.py --port 8080
```

```
  chain        31337  (http://127.0.0.1:8545)
  site         http://127.0.0.1:8080/
  operator key set
  token        qJ7xK2mP9a
```

Copy the token. You will paste it once, into the console.

**If the port is busy:** use `--port 8090`, and always browse `127.0.0.1`, never `localhost` — on
macOS `localhost` can resolve to an IPv6 squatter and you will spend twenty minutes debugging
someone else's server. (Ask me how I know.)

---

## Step 5 — Open the hub

<http://127.0.0.1:8080/index.html>

You should see a green status line:

```
connected · block 12 · badges 0/250 · GOLD/SILVER 1.0000
```

If it is red, the chain or the RPC is wrong and nothing downstream will work. Fix it here.

---

## Step 6 — Become a guild

Open `data/guilds.csv`, take the first line:

```
1,0xF3131Ea49095c51A527F57560A835B62f1a69AAd,0xbaca1a…
```

Build the URL — this is exactly what the printed QR encodes:

```
http://127.0.0.1:8080/g.html#k=0xbaca1a…&g=1
```

You are now Guild 01.

**Step 6a — Sign.**

Press **Break the AMM**, then **Sign ballot**. Watch what happens:

```
signed. no transaction was sent. nothing on chain changed. vote is still NOT counted.
queued for the room's batch — 1 waiting. signature: 0x2c7d128ffd7eb2eb…
```

Your ETH balance did not move. Your "Voted" row still says **not yet**. Check the projector: the
tally has not changed. **That is the entire lab in one screen.**

**Step 6b — Send it yourself (optional).**

Press **Or send it yourself**. This one costs gas. Now the tally moves and "Voted" says **yes**.

Two identical signatures, one that cost nothing and one that cost a transaction. Say that
sentence out loud when you demo it.

**Step 6c — Claim loot.**

Press **Claim 1,000 LOOT**. The page fetches `web/merkle.json`, finds your address, and submits
the proof. The contract verifies you belong to a 45-address set while storing exactly one 32-byte
root.

---

## Step 7 — Run the room from the console

<http://127.0.0.1:8080/admin.html>

Paste the token, press **Save token**.

You will see `poll1` with **Submit 1 queued as one tx**. Before pressing it, go back to the guild
page as a second guild (line 2 of the CSV, `g=2`), sign, and return. Now it says **2 queued**.

Press submit:

```
submitted 2 ballots in one transaction in 1.4s · 0x5a339747…
```

Two signatures. One transaction. Twenty-five guilds in the real session, still one transaction.

**Then try to break it.** Change the choice on the guild page *after* signing, and submit again.
The console will refuse — `signature does not match signer` — and it will tell you which address
and why. Nothing is lost; the bad ballot is isolated before it can poison the batch.

---

## Step 8 — Mint the badge

<http://127.0.0.1:8080/claim.html?g=1>

Connect a wallet with Base Sepolia ETH (on anvil, import one of the keys into MetaMask — add
network `http://127.0.0.1:8545`, chain id `31337`).

Press **Mint badge**. The card on the right fills with the SVG that came out of `tokenURI()`.

The artwork is assembled in Solidity and base64-encoded into a data URI. There is no IPFS hash
and no hosting. A test asserts the string contains neither `ipfs` nor `https`.

---

## Step 9 — Print the cards

<http://127.0.0.1:8080/cards.html>

Paste all of `data/guilds.csv`, press **Render cards**, then **Print**. Twenty-five cards, three
to a row, each with a QR that lands on that guild's page.

The base URL box must match where the site will actually be served. Get it wrong and you print
25 dead cards, which is the single most expensive mistake available here.

---

## Step 10 — The dry run

This is the thing you do at T-7 and again at T-1.

```bash
./scripts/loadsim.sh
```

```
1/4  contract simulation (forge)
  PASS  LoadSimTest — 25 ballots, 200+50 badge claims, 25 swaps
        one batch of 25 ballots: 1344870 gas
        GOLD/SILVER after 25 swaps: 0.8655
2/4  full test suite
  PASS  all suites — 37 tests passed
3/4  live deploy on anvil :8547
  PASS  deploy + seed + merkle root
4/4  live ballots through the server
        25 signatures collected in 2.7s (that is the queue, not the chain)
  PASS  one transaction carried all 25 ballots in 2.86s
  PASS  tally reads back 25 / 25

  ALL CHECKS PASSED — the lab is runnable.
```

It writes `data/loadsim-report.md` with a timestamp. Keep those files. They are evidence for the
committee that the thing was rehearsed rather than hoped for.

---

## Step 11 — Go to Base Sepolia

Same commands, one variable changed.

```bash
./scripts/gen-participants.sh            # replace the 20 player addresses with real ones first
PRIVATE_KEY=0x… RPC=https://sepolia.base.org ./scripts/deploy.sh
```

Then fund the guild wallets:

```bash
TREASURY_KEY=0x… RPC=https://sepolia.base.org ./scripts/fund-guilds.sh
```

Roughly 0.002 ETH per guild. Total cost of the entire lab, including 250 badge mints, is under a
dollar — which is why the budget conversation is not the interesting one.

Verify contracts on Basescan by appending:

```bash
--verify --etherscan-api-key $BASESCAN_KEY
```

---

## Step 12 — Break it on purpose, twice

You will remember these better than the happy path.

**Make the room a whale.** Open a guild, claim loot, buy more, then vote again — in a
`TokenWeighted` poll one address with 100 LOOT outvotes twenty-four with 1 LOOT each. It is
`test_tokenWeightedFlipsTheResult`, and it is the most convincing ninety seconds in the deck.

**Censor yourself.** Stop the server, sign a ballot on a guild page, and watch it queue locally
with nowhere to go. Then submit the same signature with `cast` from a different key. It works.
The relayer was never the authority.

---

## Where to go next

- `GUIDE.md` — every surface, minute by minute, plus troubleshooting.
- `PRESENTATION.md` and `web/deck.html` — the deck, with speaker notes.
- `LAB-PACK.md` — why any of this is supposed to work, and what the committee will ask.
