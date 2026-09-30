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
  so the bounce is never quite where you expect. Both these and the round pop
  bumpers **explode** after a random 5-15 hits — a big bonus, a burst of fire,
  then they vanish for about 30 seconds before coming back.
- **Vortex holes**: dug-earth pits that grab the ball, hold it for a couple of
  seconds with a warm amber glow, then fire it hard back up the table.
- **Soft floating bonuses**: glowing Egyptian icons (emerald, scarab, ankh) that
  appear at random spots and grant a bonus (points, a multiplier bump, or a
  ball save) on touch — they have no collision at all, so the ball just rolls
  straight through them.
- Two elevated **wireform ramps** (an open metal-wire rail, not a solid track —
  the playfield art stays visible underneath as the ball rides the wire),
  each marked by a pulsing gold arrow on the table. The TEMPLE ramp (entrance
  above the right wing flipper) loops in a full figure-8 around the idol scoop
  and returns the ball to the left inlane; the IDOL ramp (entrance above the
  left wing flipper) climbs the left side, arches over the top of the table,
  snakes, and returns the ball to the right inlane. Any shot that goes in with
  enough force to start rolling is carried all the way round.
- **The idol awakens**: every so often the golden idol at the top of the table
  wakes up (pulsing glow, burning eyes, a message on the DMD). Touch it while
  it's awake and it kidnaps the ball, shakes it for a moment, then hurls it out
  at high speed in a random direction.
- A drop-target bank ("I-N-D-Y"), rollover lanes, orbits, a central idol
  scoop, slingshots, a mode ladder, "Eternal Life" multiball, ball save,
  extra balls, nudge, and a proper tilt system that kills the flippers and
  eats your bonus if you shake the machine too hard.

**Slot side**
- A 5-reel, 10-payline slot machine ("Book of the Temple") running live in the
  middle of the playfield, dressed up as a real casino cabinet — bevelled gold
  frame, ruby/emerald corner gems, a backlit glass window, glowing chase bulbs
  around a marquee title header — with wilds, scatters, free spins with an
  expanding symbol, and its own paytable, all with original symbols.
- Every pinball switch you hit feeds energy into the slot's bet meter; every slot
  win of three-or-more matching symbols feeds a bonus back into the pinball game
  (extra balls, ball save, lit locks, spotted targets, multiplier bumps,
  multiball, playfield ×2, and more).
- The two games are genuinely wired together, not just sharing a cabinet.
- **SLOT ONLY mode** (`S`): pauses the pinball and zooms the cabinet up to fill
  the screen as a standalone slot machine — credits, a 1-5 bet, a big SPIN
  button and a HOLD button under every reel (holds unlock after a losing spin,
  max 4, never during free spins). Its credits are separate from the pinball
  score; `INSERT COIN` tops you up with 100 more whenever you like.

**Quests on a dot-matrix display**
- Every so often, a random while after you score, a **quest** starts on an
  amber dot-matrix display (DMD) that floats over the top of the table on a
  transparent background — in the spirit of the video modes on the classic
  1993 adventure-pinball tables. A whip cracks the quest's name into view, the
  goal scrolls past marquee-style, then a live screen tracks hits, the
  countdown and a progress bar while a little animation plays underneath
  (a mine cart on its track, a boulder chasing the explorer, marching skulls,
  a snake...).
- Six quests: *Steal the Stones* (bumpers), *Runaway Mine Cart* (ramps),
  *Temple of Skulls* (drop targets), *Outrun the Boulder* (orbits/top lanes),
  *Well of Snakes* (slingshots), *Eye of the Idol* (scoop or a vortex pit).
- Beat the clock and you get **QUEST COMPLETE**, a golden idol and a big points
  bonus (120,000-250,000, times the playfield multiplier). Run out of time and
  the display dissolves — no bonus. The quest clock only runs while a ball is
  actually in play, and it never pauses or blocks the game.

## Controls

The same list is in the game: press `I`, or the **INFO** button on the start
menu and the pause menu.

| Action | Keys |
|---|---|
| Left flipper(s) | `Left Arrow`, `Z`, `A`, `Shift+L` |
| Right flipper(s) | `Right Arrow`, `D`, `/` |
| Plunger (hold to charge, release to launch) | `Down Arrow`, `Space` |
| Start / launch ball | `Enter`, `Space` |
| Nudge left / right / up | `X` / `C` / `T`, `Up Arrow` |
| Pause menu (Resume / Info / Slot Only) | `P`, `Esc` |
| Info screen (every command) | `I` |
| SLOT ONLY mode on / off | `S` |
| Toggle music + sound | click the speaker icon (top right) |

Touch: left half of the screen = left flipper, right half = right flipper, bottom
right corner = plunger, two-finger tap = nudge up. The start and pause menus have
tappable INFO / SLOT ONLY buttons.

### SLOT ONLY mode

| Key | Effect |
|---|---|
| `Space`, `Enter` (or the SPIN button) | Spin (costs bet × 10 lines; free spins cost nothing) |
| `1`-`5` (or the HOLD buttons) | Hold / release that reel for the next spin (after a losing spin) |
| `Up` / `Down`, `+` / `-` | Bet 1-5 per line |
| `C` (or INSERT COIN) | +100 credits |
| `S`, `Esc` (or EXIT) | Back to the pinball, exactly where you left it |

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

### Layout editor (dev tool, not a gameplay cheat)

Most of the dynamic elements (wing flippers, side bumpers, mini bumpers, vortex holes,
pop bumpers, soft-bonus spawn spots) can be repositioned live instead of editing consts
by hand:

| Key | Effect |
|---|---|
| `E` | Toggle layout-edit mode: pauses the game and shows draggable cyan handles |
| (drag) | Click and drag a handle with the mouse to move that element |
| `S` | While in edit mode: save every handle's current position to `game/layout_overrides.json` |

`layout_overrides.json` is loaded back automatically on the next launch and applied on
top of the hardcoded defaults, so a saved layout persists — just commit that file like
any other, or hand its contents back for someone to bake into `table.gd`'s constants.

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
    quest_manager.gd     Quest state machine (goals, timers, rewards) + signals
    dmd_display.gd       Quest DMD overlay; dmd_animation_player.gd sequences the
                         shows, dmd_canvas.gd is the 128x32 frame buffer + 5x7 font
    slot_only.gd         SLOT ONLY standalone slot screen
    hud.gd               Score/HUD, start menu, pause menu, INFO screen
  shaders/dmd.gdshader   Amber dot-matrix LEDs with glow on a transparent background
  scenes/                main.tscn, ball.tscn, slot.tscn, dmd_display.tscn
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
