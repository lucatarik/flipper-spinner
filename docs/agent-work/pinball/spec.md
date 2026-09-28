# Spec — "Temple of the Idol" pinball (Godot 4.7, 2D)

Inspired by *Indiana Jones: The Pinball Adventure* (Williams 1993): jungle-temple theme,
golden idol scoop, "Path of Adventure" orbits, drop-target bank, mode ladder, "Eternal Life"
multiball. Original names/art only (no film logos, no actor likeness, no licensed text).

## Objective
A playable single-player 2D top-down pinball table in `game/` (Godot 4.7.2, GDScript only),
portrait 720x1280 logical resolution, keyboard + simple touch controls, full game loop
(attract → 3 balls → game over → high score).

## Non-goals
Audio, 3D, multiplayer, tilt, extra balls, video modes, localisation, export presets, addons.

## Architecture
```
game/
  project.godot            (exists; main scene res://scenes/main.tscn)
  assets/playfield.jpg     720x1280 background (exists)
  assets/sprites/*.png     idol, bumper, skull, cobra, fedora, grail_snake, jewel_cup,
                           whip, torch, map, monkey (exist, transparent)
  scripts/rules.gd         class_name Rules extends RefCounted — PURE game logic, no nodes
  scripts/table.gd         main scene controller: wires physics signals -> Rules, spawns balls
  scripts/ball.gd          RigidBody2D ball
  scripts/flipper.gd       flipper body + input
  scripts/plunger.gd       charge/launch
  scripts/bumper.gd, slingshot.gd, drop_target.gd, scoop.gd, lane_sensor.gd  (T2 for some)
  scripts/hud.gd           CanvasLayer HUD bound to Rules signals
  scenes/main.tscn, ball.tscn, flipper.tscn, bumper.tscn ... 
  tests/run_tests.gd       extends SceneTree; unit tests for Rules; exit code 0/1
  tests/physics_smoke.gd   extends SceneTree; instantiates main.tscn headless, scripted checks
```
Rules is the single source of truth for score/state; physics nodes only report events.
Table reads Rules signals to act physically (serve ball, spawn multiball balls, reset targets).

## Rules contract (scripts/rules.gd) — fixed
```gdscript
class_name Rules extends RefCounted
signal score_changed(score: int)
signal ball_changed(ball_number: int, balls_per_game: int)
signal message(text: String, seconds: float)
signal request_serve_ball()              # table puts a new ball in the plunger lane
signal request_multiball(extra_balls: int)  # table spawns extra balls at the idol scoop
signal targets_reset()                   # table raises all drop targets
signal lanes_changed(lit: Array)         # Array[bool] size 3, top lanes
signal mode_changed(name: String, time_left: float, progress: int, goal: int) # name "" = none
signal state_changed(state: int)
signal game_over(final_score: int, is_high_score: bool)

enum State { ATTRACT, PLAYING, GAME_OVER }
const BALLS_PER_GAME := 3
const BALL_SAVE_SECONDS := 8.0
var state: int; var score: int; var ball_number: int; var multiplier: int  # 1..5
var balls_in_play: int; var locks: int; var lock_lit: bool; var multiball: bool
var high_score: int

func start_game() -> void          # ATTRACT/GAME_OVER -> PLAYING, resets, ball 1, emits request_serve_ball
func tick(delta: float) -> void    # timers: ball save, mode timer
func on_event(name: String, data: Dictionary = {}) -> void
func flip_lanes(direction: int) -> void  # rotate lit lanes left(-1)/right(+1) (lane change)
```
Events (`on_event` names): `bumper`, `sling`, `lane` {index 0..2}, `target` {index 0..3},
`scoop`, `orbit` {side "left"/"right"}, `plunger_exit` (ball left shooter lane),
`drain`, `ball_added` (table put a ball in play: serve or multiball spawn).

Scoring & rules:
- bumper 1000, sling 100, lane 500 (lights lane; all 3 lit → multiplier+1 max 5, lanes clear),
  target 2500 (all 4 "I-N-D-Y" down → +25000, `lock_lit=true`, emit targets_reset),
  orbit 5000 ("Path of Adventure"), scoop 5000 base. All awards pass through `_award(points)`
  which adds `points` (no playfield multiplier; multiplier is applied to end-of-ball bonus).
- bonus accumulator: +1000 per target, +2000 per orbit, +500 per lane. On ball end:
  score += bonus * multiplier, then bonus=0, multiplier=1.
- scoop priority: (1) multiball → JACKPOT 100000; (2) lock_lit → locks+=1, lock_lit=false,
  message "BALL LOCKED n"; on locks==3 → locks=0, multiball=true, emit request_multiball(2),
  message "ETERNAL LIFE MULTIBALL"; (3) no mode running → start next mode; (4) else +5000.
- modes, in order, cycle (30 s each, reward 10000 per qualifying hit, 50000 on completion):
  0 "WELL OF SOULS": qualifying = bumper, goal 15; 1 "MINE CART CHASE": orbit, goal 4;
  2 "GRAIL QUEST": target, goal 6. Timer runs down in tick(); expiry → mode ends, message.
- ball save: starts on `plunger_exit` of a served ball (not multiball spawns), 8 s. A `drain`
  while active (and not multiball) → emit request_serve_ball, message "BALL SAVED", no ball loss.
- drain: balls_in_play -= 1 (never below 0). If multiball and balls_in_play<=1 → multiball=false.
  If balls_in_play==0 (after save check) → end of ball (bonus), ball_number+=1; if >3 → GAME_OVER
  (update high_score, emit game_over) else emit request_serve_ball.
- `ball_added` → balls_in_play += 1. Events are ignored unless state==PLAYING.
- high score persisted by table/hud in `user://highscore.save` (Rules exposes `high_score`,
  set by caller before start_game).

## Physics / table contracts
- Coordinates in 720x1280 logical px. Ball radius 12, RigidBody2D, continuous CD
  (CCD_MODE_CAST_SHAPE), bounce ~0.3, friction low, `linear_velocity` clamped to 3200 px/s.
- Layers: 1 walls/static, 2 ball, 3 flippers, 4 sensors (Area2D). Ball collides 1|2|3.
- Playfield bounds: side walls x≈20 and x≈700, rounded top, shooter lane on the right
  (x≈648..700, divider wall from y≈380 down), top-right curved guide feeds ball into field.
- Flippers: left pivot ≈(215,1115), right pivot ≈(430,1115), length ≈105, rest angle ≈30° down,
  active ≈30° up, swing ≈ 0.06–0.08 s; drain gap between tips ≥ 34 px. Must actually launch
  the ball (kinematic body moved in `_physics_process` or equivalent; no ball pass-through).
- Controls (InputMap actions defined in project.godot): `flip_left` (Left, Z, A, Shift-L),
  `flip_right` (Right, M, D, /), `plunger` (Down, Space — hold to charge 0..1 over 1 s, release
  launches with impulse proportional to charge, min 40%), `start` (Enter, Space when not playing).
  Touch: touch on left half = flip_left, right half = flip_right, while held; touching the bottom
  right 120x200 px area acts as plunger instead.
- Drain: Area2D below flippers → `on_event("drain")` and the ball node is freed.
- Everything visible uses the generated art where sensible (playfield.jpg as background,
  bumper.png on pop bumpers, idol.png above scoop, sprites as decor); walls/flippers/targets
  may be drawn with Polygon2D/Line2D in a gold/stone palette. No text baked into images;
  HUD text via Label.

## Failure behaviour
- Ball escaping the table (outside rect -50..770, -50..1330) → treated as drain (free + event).
- Stuck ball (speed < 5 px/s for 5 s while not in scoop/shooter lane) → small random nudge impulse.
- Missing high-score file → high_score 0; corrupt → 0, no crash.

## Acceptance
- A1 `godot --headless --path game -s res://tests/run_tests.gd` exits 0; covers every rule above.
- A2 `godot --headless --path game --quit-after 600` → no SCRIPT ERROR / ERROR lines.
- A3 `godot --headless --path game -s res://tests/physics_smoke.gd` exits 0: ball launched by
  plunger reaches the playfield (x<640, y<400) within 3 s; ball dropped onto raised-then-fired
  left flipper ends with y-velocity < -800; a ball resting on the down flippers eventually drains;
  a 3000 px/s ball fired at a side wall stays inside bounds (no tunnelling).
- A4 (T2) scoop/targets/lanes/orbits trigger their Rules events in the smoke test; multiball
  spawns 2 extra balls; HUD shows score, ball, mode, messages; game over and restart work.
- A5 manual run via Godot MCP shows a playable table with the generated art.

---
# Part B — Central slot machine "Book of the Temple", sound and light (added after user request)

The user asked for a working slot machine in the middle of the playfield, in the style of
*Book of Ra Deluxe* (5 reels, book = wild + scatter, free spins with an expanding symbol),
plus sound effects and light effects for both slot and pinball. The original Novomatic art is
copyrighted: we use ONLY our generated original symbols in `game/assets/slot/`.

## Slot placement
Node2D `Slot` at the centre of the playfield, reel window x 170..490, y 590..782 (5 reels × 3
rows, cell 64×64), drawn above the background and below balls, NO collision (the ball rolls
over it like a playfield-embedded screen). Golden frame, dark lapis backing, ring of marquee
bulbs around it, 5 "TEMPLE POWER" lamps under it, win/credit Label under the lamps.

## Symbols (files in game/assets/slot/)
book.png (WILD+SCATTER), explorer.png, pharaoh.png, anubis.png, scarab.png,
eye.png, ankh.png, pyramid.png, feather.png, emerald.png. coins.png = win particles.
(ankh_alt.png unused.)

Paytable — credits per line for 2/3/4/5 of a kind, left-to-right on a payline:
| symbol | 2 | 3 | 4 | 5 |
|---|---|---|---|---|
| explorer | 10 | 100 | 1000 | 5000 |
| pharaoh, anubis | 5 | 40 | 400 | 2000 |
| scarab | 5 | 30 | 100 | 750 |
| eye, ankh | 0 | 5 | 40 | 150 |
| pyramid, feather, emerald | 0 | 5 | 25 | 100 |
Book substitutes any symbol on lines. Books anywhere (scatter): 3/4/5 → 2/20/200 × 10 credits
and trigger 10 FREE SPINS (retrigger +10). 10 fixed paylines (row index per reel, 0=top):
```
[1,1,1,1,1] [0,0,0,0,0] [2,2,2,2,2] [0,1,2,1,0] [2,1,0,1,2]
[1,2,2,2,1] [1,0,0,0,1] [2,2,1,0,0] [0,0,1,2,2] [2,1,1,1,0]
```
Points awarded to pinball = credits × bet × 100.

## Slot cycle (always running while PLAYING; demo spins without payouts in ATTRACT/GAME_OVER)
IDLE(0.8 s) → SPINNING (all reels spin ≥1.2 s, stop left→right 0.25 s apart with overshoot
bounce + click) → EVALUATE → SHOW_WIN (winning lines drawn one after another, symbols pulse,
coin burst, count-up of points; 1.5–3 s, 0.6 s if no win) → IDLE → …
- Anticipation: if 2+ books are visible on the already-stopped reels, each remaining reel spins
  0.8 s longer with a rising tension sound and the reel frame glows.
- FREE SPINS: a book-flip reveal picks a random special symbol (not book); during free spins,
  after each spin, if the special symbol is on ≥ its min count of reels (2 for explorer/pharaoh/
  anubis/scarab, 3 otherwise) it expands to fill those reels and pays on all 10 lines as if
  adjacent. While free spins run: pinball playfield scores ×2, marquee goes rainbow,
  "FREE SPINS n" shown.
- TEMPLE POWER (bet) 1..5: each pinball switch hit (bumper, sling, lane, target, orbit, scoop)
  adds 1 energy; every 8 energy → bet+1 (max 5), energy wraps. Bet resets to 1 at end of ball.
- Pinball bonuses from slot line wins (in addition to points):
  3+ pharaoh → ball save +10 s ("PHARAOH'S BLESSING"); 3+ anubis → light LOCK;
  3+ scarab → spot one drop target; 3+ explorer → bonus multiplier +1;
  4+ explorer → start ETERNAL LIFE MULTIBALL (if not already in multiball).
- Target math (verified by a 20 000-spin simulation test with seeded RNG, base game):
  any-win hit frequency 25–45 %; free-spin trigger 1 in 60–150 spins; average credits per spin
  (per 1 bet) 6–14 — tune reel strips (weighted, per reel) to hit these.

## Slot logic contract — `game/scripts/slot_machine.gd` (pure, RefCounted)
```gdscript
class_name SlotMachine extends RefCounted
const SYMBOLS := ["book","explorer","pharaoh","anubis","scarab","eye","ankh","pyramid","feather","emerald"]
const PAYLINES := [...]            # as above
var bet: int = 1; var energy: int = 0
var free_spins: int = 0; var special_symbol: String = ""
func _init(rng: RandomNumberGenerator = null)
func spin() -> Array               # 5 arrays of 3 symbol names (grid[reel][row]); consumes a free spin if any
func evaluate(grid: Array) -> Dictionary
  # {credits:int, points:int, lines:[{line:int, symbol:String, count:int, credits:int}],
  #  books:int, free_spins_awarded:int, expanded_reels:Array[int],
  #  bonuses:{ball_save:float, light_lock:bool, spot_target:bool, add_multiplier:int, start_multiball:bool}}
func add_energy(n: int = 1) -> void
func reset_bet() -> void
```
## Rules extension (scripts/rules.gd) — additive, existing contract unchanged
```gdscript
signal request_spot_target()
signal playfield_mult_changed(mult: int)
var playfield_mult: int = 1        # _award() now adds points * playfield_mult
func set_playfield_mult(m: int) -> void
func apply_slot_result(res: Dictionary) -> void  # adds res.points (NOT × playfield_mult),
   # applies res.bonuses: ball_save extends/starts ball-save timer, light_lock, add_multiplier
   # (cap 5), start_multiball (same path as 3rd lock), spot_target → emit request_spot_target
```
Ignored unless PLAYING.

## Sound (all original, synthesized)
`game/tools/gen_sfx.py` — Python 3 STDLIB ONLY (wave, math, random, struct), deterministic,
writes 22050 Hz mono 16-bit WAVs into `game/assets/sfx/`:
flipper, bumper, sling, launch, plunger_charge, drain, target, target_bank, lane, orbit, scoop,
lock, jackpot, multiball, ball_save, game_start, game_over, mode_start, mode_complete,
reel_spin (seamless loop ~0.5 s), reel_stop, anticipation (rising, ~2 s), win_small, win_big,
coin, free_spins, book_reveal, bet_up, and music `temple_theme.wav` (≈16 s seamless loop,
Middle-Eastern flavoured arpeggio/drone, low volume).
Autoload `Sfx` (`game/scripts/sfx.gd`): `play(name: String, pitch := 1.0, db := 0.0)`
(pool of 16 AudioStreamPlayers, unknown name = warning, no crash), `loop_start(name)`,
`loop_stop(name)`, `music(on: bool)`. Must work headless (dummy audio driver).

## Light (Godot 2D lighting + tweens)
- CanvasModulate dims the table (~0.7); PointLight2D glows (texture from GradientTexture2D radial)
  on bumpers (flash to high energy on hit then decay), on the idol scoop, ball carries a soft light.
- Insert lamps (small circles/polygons) for top lanes, INDY targets, LOCK, modes: off / on /
  blinking via Tween.
- Events: jackpot/multiball/free spins → full-table flash + short camera shake;
  drain → GI flicker; ball save → blinking shield lamp between flippers.
- Slot: marquee bulbs chase during spin, all flash on win, rainbow cycle during free spins,
  winning symbols pulse (scale 1→1.15) with glow; big win (≥ 50× bet credits) → "BIG WIN"
  label zoom + coin fountain (GPUParticles2D/CPUParticles2D with coins.png).

## Acceptance (Part B)
- B1 slot unit + simulation tests pass in run_tests.gd (paytable, wild substitution, scatter,
  free spins trigger/retrigger, expanding symbol, bonuses mapping, bet energy, target math).
- B2 Rules extension tests pass (playfield_mult, apply_slot_result each bonus, ignored when not PLAYING).
- B3 `python3 game/tools/gen_sfx.py` creates every listed WAV; main scene runs headless with no errors.
- B4 physics_smoke additionally: slot completes ≥ 3 cycles in 15 s of simulated play and
  Rules score increases when a forced winning grid is evaluated.
- B5 visual check via Godot MCP run: slot visible and animating in the centre, lights and HUD.

## Sound amendment (supersedes the music line above)
- Music is NOT synthesized: use the CC0 tracks already in `game/assets/music/`
  (see CREDITS.md): `desert_mystic.ogg` = attract/game-over, `desert_mystic2.ogg` = normal play,
  `desert_mystic3.ogg` = multiball / free spins. Looped, −10 dB, crossfade 0.5 s on change.
  `Sfx.music(track: String)` ("" = stop) replaces `music(on)`.
- SFX stay synthesized by gen_sfx.py, but `Sfx` first looks for a drop-in override
  `res://assets/sfx/override/<name>.ogg|.wav` so CC0 recordings (e.g. OpenGameArt) can replace
  any sound without code changes. Every external asset must be credited in CREDITS.md.
