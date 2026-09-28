# Temple of the Idol — Flipper & Spinner

A 2D pinball table built in Godot 4, with a full 5-reel slot machine spinning live in
the middle of the playfield. Two of the most compulsively replayable game formats
ever invented, fused into one table, so you never have to choose between "one more
ball" and "one more spin" again — you can chase both losses at once. For entertainment
purposes only, obviously: no real money, no real payouts, just a jungle-temple fever
dream for people who like their dopamine delivered by flashing lights and a ball that
won't stay where you put it.

Inspired by classic single-ball adventure pinball (think *Indiana Jones*-style
temple theming) and Egyptian-themed video slots (think *Book of Ra*-style mechanics) —
built from scratch with original art, sound and music. No licensed names, logos or
material from either source.

## What's actually in the box

**Pinball side**
- Two main flippers, plus **four extra "wing" flippers** scattered higher up the
  table (fired automatically with the main flipper on their side) to help the
  ball reach the upper playfield instead of draining straight back down.
- A bank of **"bonus bumpers"**: light all three and you get a bonus multiplier plus
  flat points — then the bank resets so you can do it again.
- **Moving mini bumpers** that patrol back and forth over the middle of the table,
  so the bounce is never quite where you expect.
- **Vortex holes**: sucker pits that grab the ball, hold it for a couple of seconds
  while the rim spins and glows, then fire it hard back up the table.
- **Soft floating bonuses**: glowing Egyptian icons (emerald, scarab, ankh) that
  appear at random spots and grant a bonus (points, a multiplier bump, or a
  ball save) on touch — they have no collision at all, so the ball just rolls
  straight through them.
- Two elevated ramps, a drop-target bank ("I-N-D-Y"), rollover lanes, orbits, a
  central idol scoop, slingshots, a mode ladder, "Eternal Life" multiball, ball
  save, extra balls, nudge, and a proper tilt system that kills the flippers and
  eats your bonus if you shake the machine too hard.

**Slot side**
- A 5-reel, 10-payline slot machine ("Book of the Temple") running live in the
  middle of the playfield, with wilds, scatters, free spins with an expanding
  symbol, and its own paytable — all with original symbols.
- Every pinball switch you hit feeds energy into the slot's bet meter; every slot
  win of three-or-more matching symbols feeds a bonus back into the pinball game
  (extra balls, ball save, lit locks, spotted targets, multiplier bumps,
  multiball, playfield ×2, and more).
- The two games are genuinely wired together, not just sharing a cabinet.

## Controls

| Action | Keys |
|---|---|
| Left flipper(s) | `Left Arrow`, `Z`, `A`, `Shift+L` |
| Right flipper(s) | `Right Arrow`, `D`, `/` |
| Plunger (hold to charge, release to launch) | `Down Arrow`, `Space` |
| Start / launch ball | `Enter`, `Space` |
| Nudge left / right / up | `X` / `C` / `T`, `Up Arrow` |
| Toggle music | click the speaker icon (top right) |

Touch: left half of the screen = left flipper, right half = right flipper, bottom
right corner = plunger, two-finger tap = nudge up.

### Cheats

Because sometimes you just want to see the lights go off:

| Key | Effect |
|---|---|
| `M` | Instantly starts (or adds to) Eternal Life multiball |
| `B` | Drops a free extra ball into play right now |
| `N` | Grants an extra ball in reserve (claimed as "SHOOT AGAIN" at end of ball) |
| `R` | Clears every ball off the field and serves a fresh one — no life lost (stuck-ball rescue) |
| `V` | Toggles gravity between 100% and 50% |
| `Tab` | Toggles a zoomed-in camera that follows the ball (the first one into play, in multiball) |

## Running it

Requires **Godot 4.7.2** (or compatible 4.7.x).

```bash
godot --path game
```

Headless test suite (pure game-logic unit tests + a scripted physics smoke test):

```bash
godot --headless --path game -s res://tests/run_tests.gd
godot --headless --path game -s res://tests/physics_smoke.gd
```

## Project layout

```
game/
  project.godot        Godot 4.7 project (portrait 720×1280 logical resolution)
  scripts/
    rules.gd            Pure game-logic/score state machine (no nodes, fully unit-testable)
    slot_machine.gd      Pure slot-machine logic (paytable, spins, free spins, bonuses)
    table.gd             Scene controller: builds the table, wires physics to Rules
    flipper.gd, bumper.gd, mini_bumper.gd, kickback_hole.gd, ramp.gd, ...  physics nodes
  scenes/                main.tscn, ball.tscn, slot.tscn
  assets/                generated sprites, slot symbols, sound effects and music
  tests/                 run_tests.gd (unit), physics_smoke.gd (scripted headless play)
  tools/                 gen_sfx.py / gen_music.py — deterministic, stdlib-only generators
docs/agent-work/pinball/  design spec and build history
```

## Credits & licensing

- All code, sprites, slot symbols and sound effects were generated for this
  project — no licensed characters, logos or trademarked names.
- Background music: `desert_mystic*.ogg` (CC0, by polygondan) and `camel_groove`
  (original composition, style homage only — no material reused from any existing
  song). Full attribution in `game/assets/music/CREDITS.md`.
- This is a fan-made, original-content project built for fun and is not affiliated
  with or endorsed by any pinball or slot machine brand.

Play responsibly. It's a video game — the only thing you can actually lose is time.
