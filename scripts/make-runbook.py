#!/usr/bin/env python3
"""Generate RUNBOOK.pptx — the operator cue sheet for the 60-minute lab.

This is not the presentation. It is the thing you keep on the laptop at the podium:
what to click, on which screen, and what you should see afterwards.
"""
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

INK = RGBColor(0x14, 0x17, 0x1C)
MUT = RGBColor(0x6B, 0x6A, 0x63)
GOLD = RGBColor(0xA8, 0x84, 0x3E)
BG = RGBColor(0xFA, 0xF9, 0xF6)
LINE = RGBColor(0xD9, 0xD5, 0xCB)
RED = RGBColor(0xB4, 0x4A, 0x3A)
GREEN = RGBColor(0x2F, 0x6B, 0x45)

SANS = "Helvetica Neue"
MONO = "Menlo"

W, H = Inches(13.333), Inches(7.5)

prs = Presentation()
prs.slide_width, prs.slide_height = W, H


# --------------------------------------------------------------------------- primitives

def blank():
    s = prs.slides.add_slide(prs.slide_layouts[6])
    bg = s.shapes.add_shape(1, 0, 0, W, H)
    bg.fill.solid()
    bg.fill.fore_color.rgb = BG
    bg.line.fill.background()
    bg.shadow.inherit = False
    return s


def tb(slide, x, y, w, h, align=PP_ALIGN.LEFT):
    box = slide.shapes.add_textbox(x, y, w, h)
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = MSO_ANCHOR.TOP
    tf.paragraphs[0].alignment = align
    return tf


def put(tf, text, size, color=INK, font=SANS, bold=False, space_before=0, space_after=0,
        first=False, align=None, italic=False):
    p = tf.paragraphs[0] if first else tf.add_paragraph()
    p.space_before = Pt(space_before)
    p.space_after = Pt(space_after)
    if align is not None:
        p.alignment = align
    r = p.add_run()
    r.text = text
    r.font.size = Pt(size)
    r.font.color.rgb = color
    r.font.name = font
    r.font.bold = bold
    r.font.italic = italic
    return p


def rule(slide, y, x=Inches(0.9), w=Inches(11.5), color=LINE, thick=Pt(1)):
    ln = slide.shapes.add_shape(1, x, y, w, Emu(1))
    ln.fill.solid()
    ln.fill.fore_color.rgb = color
    ln.line.fill.background()
    ln.shadow.inherit = False
    ln.height = thick


def kicker(slide, text, color=GOLD):
    tf = tb(slide, Inches(0.9), Inches(0.55), Inches(9), Inches(0.3))
    p = put(tf, text.upper(), 11, color, MONO, first=True)
    p.font._rPr.set("spc", "300")


def footer(slide, n):
    tf = tb(slide, Inches(0.9), Inches(6.95), Inches(6), Inches(0.3))
    put(tf, "GUILD PROTOCOL  ·  OPERATOR RUNBOOK", 8.5, MUT, MONO, first=True)
    tf2 = tb(slide, Inches(11.4), Inches(6.95), Inches(1.0), Inches(0.3), PP_ALIGN.RIGHT)
    put(tf2, f"{n:02d}", 8.5, MUT, MONO, first=True)


# --------------------------------------------------------------------------- layouts

def title_slide(k, title, sub, note):
    s = blank()
    kicker(s, k)
    tf = tb(s, Inches(0.9), Inches(1.9), Inches(11.5), Inches(2.4))
    put(tf, title, 54, INK, SANS, bold=False, first=True)
    tf2 = tb(s, Inches(0.9), Inches(3.55), Inches(9.5), Inches(1.2))
    put(tf2, sub, 18, MUT, SANS, first=True)
    rule(s, Inches(5.55))
    tf3 = tb(s, Inches(0.9), Inches(5.8), Inches(11), Inches(0.8))
    put(tf3, note, 13, GOLD, MONO, first=True)
    return s


def cue_slide(n, time, title, where, click, see, say, fail, time_color=GOLD, ck="LIVE"):
    """The workhorse: one timestamp, four fields."""
    s = blank()
    kicker(s, ck)

    t = tb(s, Inches(0.9), Inches(0.85), Inches(2.6), Inches(0.9))
    put(t, time, 46, time_color, MONO, first=True)

    ti = tb(s, Inches(3.55), Inches(1.02), Inches(8.9), Inches(0.9))
    put(ti, title, 30, INK, SANS, first=True)

    rule(s, Inches(2.0))

    y = 2.25
    fields = [
        ("WHERE", where, INK, 16),
        ("CLICK", click, GOLD, 17),
        ("YOU SHOULD SEE", see, GREEN, 16),
        ("SAY", say, INK, 16),
        ("IF IT FAILS", fail, RED, 15),
    ]
    for label, value, color, size in fields:
        if not value:
            continue
        lt = tb(s, Inches(0.9), Inches(y + 0.05), Inches(2.1), Inches(0.4))
        p = put(lt, label, 9.5, MUT, MONO, first=True)
        p.font._rPr.set("spc", "200")

        vt = tb(s, Inches(3.05), Inches(y), Inches(9.35), Inches(0.9))
        put(vt, value, size, color, MONO if label in ("CLICK", "YOU SHOULD SEE", "WHERE") else SANS,
            first=True)
        y += 0.88

    footer(s, n)
    return s


def list_slide(n, k, title, items, mono=False, note=None):
    s = blank()
    kicker(s, k)
    tf = tb(s, Inches(0.9), Inches(0.95), Inches(11.5), Inches(0.8))
    put(tf, title, 34, INK, SANS, first=True)
    rule(s, Inches(1.95))

    y = 2.15
    for it in items:
        box = tb(s, Inches(0.9), Inches(y), Inches(11.4), Inches(0.55))
        p = put(box, it, 15 if not mono else 13.5, INK, MONO if mono else SANS, first=True)
        y += 0.46 if not mono else 0.42

    if note:
        nt = tb(s, Inches(0.9), Inches(6.35), Inches(11.5), Inches(0.5))
        put(nt, note, 12, RED, SANS, first=True)

    footer(s, n)
    return s


def table_slide(n, k, title, rows, colw=(2.5, 9.0), step=0.62, size=14.5):
    s = blank()
    kicker(s, k)
    tf = tb(s, Inches(0.9), Inches(0.95), Inches(11.5), Inches(0.8))
    put(tf, title, 34, INK, SANS, first=True)
    rule(s, Inches(1.95))

    y = 2.2
    for left, right in rows:
        lt = tb(s, Inches(0.9), Inches(y), Inches(colw[0]), Inches(0.5))
        p = put(lt, left.upper(), 9.5, GOLD, MONO, first=True)
        p.font._rPr.set("spc", "200")
        rt = tb(s, Inches(0.9 + colw[0]), Inches(y - 0.04), Inches(colw[1]), Inches(0.6))
        put(rt, right, size, INK, MONO, first=True)
        y += step

    footer(s, n)
    return s


# --------------------------------------------------------------------------- deck

n = 1

title_slide(
    "Operator runbook",
    "Sixty minutes,\nclick by click.",
    "ETH Zurich · Digital Assets Forum · 200 people, 25 guilds",
    "Times are the run of show, not the wall clock. The cut line is 00:33.",
)
n += 1

table_slide(n, "Before anything", "Four surfaces", [
    ("Projector", "lab.kameloso.com/spectator.html"),
    ("Your laptop", "lab.kameloso.com/admin.html"),
    ("Your phone", "a guild card → g.html#k=…&g=1"),
    ("Printed", "25 guild cards · 200 door cards"),
], colw=(2.2, 9.3))
n += 1

list_slide(n, "T-60", "Preflight", [
    "□  curl -s lab.kameloso.com/api/health   →  {\"ok\":true,\"chainId\":48901}",
    "□  Projector: spectator.html, readable from the back row",
    "□  Laptop: admin.html, paste operator token, press 'Save token'",
    "□  Phone: scan guild 01 card → page loads → address shown",
    "□  ssh <host> 'cd ~/guild-lab && ./scripts/state.sh'  →  tally 0/0, badges 0",
    "□  Five spare guild cards at the desk",
    "□  Six helpers briefed, each knows the 00:33 cut line",
], mono=True, note="□  Do NOT run ./scripts/host.sh now. It rebuilds the chain and wipes every vote.")
n += 1

list_slide(n, "T-15", "Doors open", [
    "□  Door cards out — three questions, answered while people sit",
    "□  One guild card per table, face down until 00:00",
    "□  Projector on poll 1, tally 0 / 0",
    "□  Helpers at one per eight tables",
    "□  Note the room count on your hand: it decides the branch at 00:04",
], note="If fewer than 80 people turn up, merge tables to eight guilds and say so at 00:02.")
n += 1

cue_slide(
    n, "00:00", "Cold open — one signature",
    "Projector + the phone in your hand",
    "Guild 01 card → g.html → 'Break the AMM' → 'Sign ballot'",
    "'signed. no transaction was sent. nothing on chain changed.'",
    "\"A signature is not a transaction.\"  Then stop talking.",
    "Sign from any working card. If none work, move on and sign at 00:08.",
    ck="LIVE DEMO — YOU",
)
n += 1

cue_slide(
    n, "00:04", "Character creation reveal",
    "deck.html, slide 03 — and your laptop",
    "Nothing. Read the door-survey percentages off the screen.",
    "The room's own composition, and the branch it bought them",
    "\"This is who you are. This is what we can cover.\"",
    "Assume cohort B and run the default script. Nobody will know.",
    ck="OPERATOR ONLY — NO CLICK",
)
n += 1

cue_slide(
    n, "00:08", "Loot — the merkle claim",
    "Every guild phone",
    "g.html → 'Claim 1,000 LOOT'",
    "Queued counter climbing on the projector · LOOT balance appears",
    "\"Who pays the gas to claim? You do. That is a design choice with a victim.\"",
    "Helpers claim on their own cards so the room sees it working.",
    ck="AUDIENCE ACTION",
)
n += 1

cue_slide(
    n, "00:13", "Vote 1 — one transaction",
    "admin.html on your laptop",
    "Press 'Submit N queued as one tx'",
    "'submitted 23 ballots in one transaction in 4.1s'",
    "\"Twenty-five signatures. One transaction. Same authorisation, different cost.\"",
    "Read the rejected list aloud, then press again. Fails twice → show of hands.",
    ck="THE ONE CRITICAL CLICK",
)
n += 1

cue_slide(
    n, "00:15", "Encounter A — whatever they chose",
    "spectator.html, and the guild phones",
    "E5: guilds swap. E8: re-run the poll token-weighted.",
    "GOLD/SILVER moving from 1.0000 · or one whale beating 24 guilds",
    "\"The price moved because you moved it.\"",
    "Narrate from the numbers already on screen. Never debug live.",
    ck="FACILITATION",
)
n += 1

cue_slide(
    n, "00:23", "Vote 2",
    "spectator.html?poll=2  ·  admin.html",
    "Open ?poll=2 on the projector, then Submit again",
    "Second tally with a fresh batch of signatures",
    "Nothing. Let the silence do it — they know the pattern now.",
    "Same as vote 1. Skip the commentary if you are behind.",
    ck="CRITICAL CLICK",
)
n += 1

cue_slide(
    n, "00:25", "Encounter B",
    "Spectator + guild phones",
    "E7: check the bridge deposit. E10: nothing, just talk.",
    "A deposit that has or has not arrived",
    "\"A bridge is a message with a delay, and a trust assumption about who relays it.\"",
    "If it has not arrived, that IS the segment. Say so and move.",
    ck="FACILITATION",
)
n += 1

cue_slide(
    n, "00:33", "CUT LINE — Names (E4)",
    "Nothing on screen",
    "Skip it entirely if you are more than 4 minutes behind.",
    "—",
    "One sentence over the closing slide: \"A name is a UX layer over an address, not a security layer.\"",
    "This is the failure valve. Use it without hesitating.",
    time_color=RED,
    ck="DECISION POINT",
)
n += 1

cue_slide(
    n, "00:37", "The badge",
    "claim.html?g=7 on every phone",
    "'Connect wallet' → 'Mint — the lab pays the gas'",
    "'sponsored · 0x… · 239 left in the allowance' · badge count rises",
    "\"Someone paid for you. Someone decides when to stop. That is a paymaster.\"",
    "Operator fallback: ./scripts/claim-for-all.sh. Nobody leaves without one.",
    ck="AUDIENCE ACTION",
)
n += 1

cue_slide(
    n, "00:45", "What is coming — intents",
    "deck.html slide 12",
    "No clicks. Hands out of pockets.",
    "The room quiet, which is the point",
    "\"You sign an outcome, not a transaction. That inverts minute one.\"",
    "If the room is cohort C, swap in zkVMs. Same criterion, different example.",
    ck="TALK — NO CLICK",
)
n += 1

cue_slide(
    n, "00:51", "Three questions",
    "Projector, slide 14",
    "Nothing. Ask all three, hands up, before any summary.",
    "Hands. Then fewer hands. Then the right answer.",
    "1. What did your signature authorise?  2. Who paid for your badge?  3. Who moved the price?",
    "If nobody answers, answer them yourself — but do not skip to the close.",
    ck="TALK — NO CLICK",
)
n += 1

cue_slide(
    n, "00:55", "Post instrument",
    "QR on the projector",
    "Show the QR. Ninety seconds. Do not talk over it.",
    "People actually filling it in",
    "Nothing. Silence is fine here.",
    "If it fails, say the link aloud once and move on. Never debug a survey live.",
    ck="AUDIENCE ACTION",
)
n += 1

cue_slide(
    n, "00:57", "Close",
    "deck.html slide 15",
    "Point at the repo. Then stop.",
    "The room standing up, which they already are",
    "github.com/lopezpalacios/guild-protocol-lab",
    "Do not add a thank-you slide. You are already over time.",
    ck="TALK — AND STOP",
)
n += 1

table_slide(n, "When it breaks", "The six that actually happen", [
    ("Submit reverts", "Read the rejected list aloud → press again → twice? hands."),
    ("Projector frozen", "Reload. It reconnects itself. Say \"the chain is fine, my screen is not.\""),
    ("A phone dies", "Hand over a spare card. \"That is a custody failure and it took 11 minutes.\""),
    ("Wallet won't connect", "Sponsor from the console, or claim-for-all. Never leave them stuck."),
    ("You are 6 min over", "Cut 00:33. Do not negotiate with yourself."),
    ("Pool drained", "maxTrade caps it. Say: \"that is why the contract has a guardrail.\""),
], colw=(2.6, 8.9))
n += 1

list_slide(n, "Emergency", "Restart the server WITHOUT losing the chain", [
    "ssh <host>",
    "cd ~/guild-lab",
    "pkill -f server/lab.py",
    "RPC=http://127.0.0.1:8545 nohup python3 server/lab.py --port 8090 \\",
    "    > logs/lab.log 2>&1 &",
    "",
    "curl -s 127.0.0.1:8090/api/health",
], mono=True, note="Never run ./scripts/host.sh during the hour. It rebuilds the chain and every vote is gone.")
n += 1

table_slide(n, "Every URL", "Bookmark these", [
    ("Projector", "lab.kameloso.com/spectator.html"),
    ("Poll 2", "lab.kameloso.com/spectator.html?poll=2"),
    ("Console", "lab.kameloso.com/admin.html"),
    ("Guild", "lab.kameloso.com/g.html#k=…&g=1"),
    ("Badge", "lab.kameloso.com/claim.html?g=7"),
    ("Cards", "lab.kameloso.com/cards.html"),
    ("Deck", "lab.kameloso.com/deck.html"),
    ("Health", "lab.kameloso.com/api/health"),
    ("RPC", "rpc.kameloso.com"),
    ("Token", "ssh <host> 'cat ~/guild-lab/data/operator-token'"),
], colw=(1.9, 9.6), step=0.47, size=13.5)
n += 1

list_slide(n, "After the hour", "Receipts", [
    "□  ssh <host> 'cd ~/guild-lab && ./scripts/state.sh' > data/final-state.txt",
    "□  Copy data/ballots.jsonl — the append-only record of every signature",
    "□  Note the batch transaction hashes from admin.html",
    "□  Export the pre/post instrument results",
    "□  Publish: contracts verified, repo public, results within 30 days",
], note="The committee asked for reproducibility. These five lines are what that means.")
n += 1

prs.save("RUNBOOK.pptx")
print(f"saved RUNBOOK.pptx — {len(prs.slides.__iter__.__self__._sldIdLst)} slides")
