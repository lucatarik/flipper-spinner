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

---
# Part C — user feedback round 2 (more bumpers, slot trio bonuses, extra balls, nudge/tilt)

## C1 More bumpers (physics, all use existing bumper.gd behaviour + glow + sound + `switch_hit("bumper")`)
- Playfield pop bumpers (radius 26, bumper.png 56 px): (150,330) and (510,330).
- Side wall bumpers (half-disc kicker, radius 22, flat side on the wall, kick 750 px/s away from
  the wall along the disc normal): left on the left wall at (20,860) bulging right; right on the
  divider at (634,820) bulging left. Rules event: `bumper` (same scoring/mode qualify).
- Must not block: left orbit lane (x 20..95, y 330..780), INDY bank, inlanes, slot area.

## C2 Slot: every 3-of-a-kind ("tris") on a payline gives a pinball bonus
Bonus per symbol for the best line of that symbol with count ≥ 3 (book substitutes; a line of
5 books counts as explorer). Several different symbols in one spin → all their bonuses.
| symbol | 3 of a kind | 4+ of a kind |
|---|---|---|
| explorer | EXTRA BALL | ETERNAL LIFE MULTIBALL (+2 balls) |
| pharaoh | ball save +10 s | ball save +20 s |
| anubis | light LOCK | lock a ball (locks+1, 3rd lock starts multiball as usual) |
| scarab | spot 1 INDY target | spot 2 targets |
| eye | bonus multiplier +1 | +2 |
| ankh | ADD-A-BALL (1 extra ball into play now) | add 2 balls |
| pyramid | +10 s on running mode, or start next mode if none | same + 25 000 |
| feather | playfield ×2 for 20 s (stacks with free spins → max ×3) | 40 s |
| emerald | 25 000 × bet points | 100 000 × bet |
Free spins (3+ books) unchanged. Extra balls capped: at most 3 pending.
`evaluate()` returns bonuses as:
`{ball_save: float, light_lock: bool, lock_balls: int, spot_targets: int, add_multiplier: int,
  start_multiball: bool, extra_balls: int, add_balls: int, mode_time: float, start_mode: bool,
  playfield_x2_seconds: float, bonus_points: int, names: Array[String]}`
(`names` = display names of the triggered bonuses, e.g. "EXTRA BALL", in trigger order).
The old keys `spot_target: bool` is replaced by `spot_targets: int`.

## C3 Rules additions (additive)
```gdscript
signal extra_balls_changed(n: int)
signal request_add_ball(count: int)        # table spawns `count` balls at the idol scoop, each fires ball_added
signal request_spot_target()               # (existing) emitted once per target to spot
signal tilt_warning(level: int)            # 1 = "WARNING", 2 = "DANGER"
signal tilted()
var extra_balls: int = 0                   # 0..3
var tilted: bool = false
func nudge() -> void
```
- End of ball with extra_balls > 0: bonus is still scored, extra_balls -= 1, ball_number does NOT
  advance, message "SHOOT AGAIN", request_serve_ball.
- add_ball: request_add_ball(n); if not already multiball, multiball = true (so jackpot is lit and
  a drain does not end the ball while ≥1 ball remains) — same end rule as multiball.
- lock_balls: locks += n (3rd lock → multiball exactly like the scoop path).
- playfield ×2 timer: `playfield_mult` = 1 + (free spins active ? 1 : 0) + (x2 timer > 0 ? 1 : 0),
  emitted via playfield_mult_changed; timer runs in tick(). Table no longer sets mult directly for
  free spins; it calls `set_free_spins_active(active: bool)` (new) and Rules computes the value.
- mode_time: running mode timer += s; if no mode, start next mode when start_mode is true.
- bonus_points added directly (not × playfield_mult).
- NUDGE / TILT: `nudge()` adds 1.0 to a tilt meter that decays 0.5/s in tick(). After a nudge,
  meter ≥ 2.0 → tilt_warning(1) "WARNING", ≥ 3.0 → tilt_warning(2) "DANGER", > 3.5 → TILT:
  tilted = true, emit tilted(), message "TILT", flippers disabled, all scoring events ignored
  until the ball ends; at end of a tilted ball NO bonus is scored, extra balls are kept, meter
  resets, tilted = false. Ball save does not work while tilted. Nudges ignored unless PLAYING.

## C4 Nudge input (table)
InputMap: `nudge_left` (X, Left Ctrl) pushes balls to the RIGHT, `nudge_right` (C, Right Ctrl)
pushes balls LEFT, `nudge_up` (T, Up) pushes balls up. Effect on every ball in play: impulse
of 180 px/s horizontal (left/right) or −260 px/s vertical (up) plus ±40 random; the table/camera
shakes 6 px for 0.15 s; sound `nudge` (add to gen_sfx.py: short thump) and `tilt` (buzzer).
Each press calls `rules.nudge()` first; when tilted, nudges and flippers do nothing, the GI
lights dim and "TILT" blinks. Touch: two-finger tap = nudge_up.
HUD: extra-ball indicator ("EXTRA BALL x n" lamp), tilt warnings, playfield ×N indicator, slot
bonus names shown as the slot's win banner (e.g. "EXTRA BALL!", "ADD-A-BALL!").

## Acceptance (Part C)
- C-A1 run_tests: every row of the C2 table (3 and 4+), multiple bonuses in one spin, cap of 3
  extra balls, shoot-again flow, add-a-ball flow, lock_balls → multiball, ×2 timer and ×3 stack,
  mode_time/start_mode, tilt warning levels, tilt ignores events and skips bonus, meter decay,
  nudge ignored outside PLAYING. Target math test still in spec ranges.
- C-A2 physics_smoke: each of the 4 new bumpers kicks a ball fired at it and fires `bumper`;
  nudge_up raises a resting ball's upward speed; after a tilt, set_pressed on a flipper does not
  move it; request_add_ball(1) adds one ball to group "balls".
- All previous tests pass; no SCRIPT ERROR/ERROR headless; no GDScript warnings windowed.

---
# Part D — user feedback round 3 (stuck ball, ramps, slot only with ball in play, music)

## D1 Stuck ball on the right (verified by orchestrator simulation)
A dropped INDY target leaves a 33 px deep pocket between its standing neighbours and the
divider (x≈601..634); the ball comes to rest in it (seen at (610,580)). Fix:
- A dropped target must leave a FLUSH surface: keep a thin static strip along the bank's face
  line (x≈601) over the dropped target's span, so the bank face is always a continuous wall.
- Add angled deflector caps (stone, 45°) above the top target and below the bottom target so a
  ball can't rest on the bank's ends.
- Stuck-ball safety (table): speed < 30 px/s for 2.0 s outside scoop/shooter lane/ramps →
  nudge impulse 350 px/s up-left/up-right (away from nearest wall); after 3 failed nudges on the
  same ball → rescue: move it into the idol scoop capture (normal scoop hold + kick, no score).
- Regression test: randomized drops (≥150 seeds, positions x 430..630, y 230..900, random
  velocities) with targets in random down/up states: no ball may stay slower than 30 px/s for
  3 s anywhere except the shooter lane/plunger and the scoop.

## D2 Ramps (elevated, drawn above the playfield)
Two ramps. A ramp = centreline polyline + width 36 px, two rail walls (StaticBody2D) on a NEW
physics layer 5 (bit value 16) that playfield balls never collide with. Ball states:
- ENTER: ball overlaps the ramp mouth Area2D while moving "into" the ramp (dot(v, mouth_dir) > 250)
  → ball.collision_mask = 16 (ramp rails only), z_index above everything but HUD, visual
  scale 1.15 + soft drop shadow offset (8,10), sound `ramp_enter`.
- FALL BACK: ball leaves through the mouth moving out before reaching the COMMIT sensor
  (≈40 % along) → restore playfield mask (1|2|4), scale 1.0.
- EXIT: ball reaches the exit sensor → restore playfield mask, scale 1.0, place it at the exit
  point with the ramp's exit velocity (≥ 200 px/s along the exit direction), fire
  `rules.on_event("ramp", {"name": ramp_name})`, sound `ramp_made`, light chase along the ramp.
- Ramps are drawn as raised stone/gold tracks (Polygon2D surface semi-opaque, rails Line2D gold,
  support pillars, shadow on the playfield), z above slot and bumpers.
Geometry (centreline, logical px):
- R1 "TEMPLE RAMP" (long, crosses above the slot, returns to the left inlane):
  mouth (528,812) opening downward (mouth_dir = (0,-1)); path
  (528,812) → (528,575) → arc → (490,555) → (160,555) → arc → (112,590) → (112,760) → (55,930);
  exit at (55,930) direction (0,1) into the left inlane (between wall x20 and the left sling).
  Commit sensor at (528,640). Move the pop bumper (330,525) to (330,495) so it isn't under the ramp.
- R2 "IDOL RAMP" (upper right, feeds the top lanes): mouth (590,452) opening downward
  (mouth_dir = (0,-1)); path (590,452) → (590,300) → (560,200) → (500,140) → (425,122);
  exit at (425,122) direction (-1,0.3) dropping into/over the right top lane (x≈420).
  Commit sensor at (590,380).
- Ball on a ramp still feels gravity; tune rail friction/bounce so a flipper shot at full
  speed makes both ramps (verify in physics_smoke) and a weak shot falls back.
- Rules (additive): event `ramp` {name}: +10 000, bonus += 2 500, slot energy +2 (table),
  mode 1 "MINE CART CHASE" qualifies on orbit OR ramp; COMBO: a ramp within 3 s of another
  ramp/orbit → +25 000 and message "COMBO"; every 4th ramp in a game → EXTRA BALL (same cap 3),
  message "EXTRA BALL". New signal `ramp_count_changed(n: int)`.

## D3 Slot only while a ball is in play
The slot spins ONLY when rules.state == PLAYING and a ball is actually in play: from the
first `plunger_exit` of a served ball until balls_in_play == 0 (drain), and not while the only
ball is waiting in the shooter lane, and not while tilted. When the condition drops, the current
spin finishes and evaluates (payouts still applied if PLAYING), then the slot idles (reels still,
marquee dim, "PLUNGE TO SPIN"). In ATTRACT / GAME_OVER the reels are still (no demo spins).
Expose `slot_view.set_active(active: bool)`; table drives it from Rules/ball events.

## D4 Background music "Camel Groove" (original, inspired-by style only)
User request: light background music inspired by Sandy Marton's "Camel by Camel" (1985).
Copyright: DO NOT reproduce its melody, lyrics, riff or chord sequence. Create an ORIGINAL piece
in the same *style*: mid-80s Italo-disco, 118 BPM, 4-on-the-floor kick, off-beat open hi-hat,
gated clap on 2 and 4, octave-jumping synth bass, lush pad, and an original lead motif in an
"oriental" scale (Phrygian dominant on E: E F G# A B C D), soft and not dominant.
- `game/tools/gen_music.py` (Python 3 stdlib only; if `ffmpeg` exists convert to .ogg q4,
  otherwise keep .wav) writes `game/assets/music/camel_groove.ogg|wav`: 32 bars (~65 s),
  seamless loop, mono or stereo 22 050 Hz, peak ≤ −3 dBFS, deterministic.
- Music plan: attract/game over = desert_mystic.ogg; normal play = camel_groove; multiball /
  free spins = desert_mystic3.ogg. Music volume −14 dB ("leggera").
- Toggle: action `music_toggle` (key N) + clickable/tappable speaker icon (drawn with Polygon2D/
  Label, top-right under the ball counter). Mutes/unmutes MUSIC only (SFX stay), message
  "MUSIC ON/OFF", setting persisted in `user://settings.cfg` ([audio] music=true/false).
  `Sfx.set_music_enabled(on: bool)`, `Sfx.is_music_enabled() -> bool`.
- Add CREDITS.md line: "camel_groove — original composition generated by gen_music.py (style
  homage to 80s Italo-disco; no material from any existing song)".

## Acceptance (Part D)
- D-A1 stuck regression test (D1) passes; target drop leaves a flush face (physics test).
- D-A2 physics_smoke: full-speed shot into each ramp mouth → `ramp` event and ball exits at the
  exit point on playfield layers; weak shot (≈350 px/s) falls back and returns to playfield
  layers; ball on a ramp does not collide with bumpers/slot/targets underneath.
- D-A3 run_tests: ramp scoring, combo window, 4th ramp extra ball (cap), mode 1 qualifies on ramp.
- D-A4 slot: no spin in ATTRACT; no spin with ball waiting in shooter lane; spins after plunge;
  stops after drain (current spin completes); test via slot_view state/cycle counts.
- D-A5 gen_music.py produces the file (duration 60–70 s); music toggle persists (unit test on
  the settings helper); game runs with no errors/warnings.

---
# Part E — user feedback round 4 (upper wing flippers, bonus bumpers, moving mini bumpers)

Implemented directly by the orchestrator (no opencode/Godot available in this cloud sandbox —
see the session's request to the user); not run/verified headless. Run the full test suite and
a manual play session before trusting this part.

## E1 Wing flippers
Two small flippers (`flipper.gd` now takes `@export var size_scale := 1.0`, scaling
LENGTH/PIVOT_RADIUS/TIP_RADIUS; `BASE_LENGTH` etc. hold the original full-size constants),
`WING_FLIPPER_SCALE = 0.75`, pivots `(185,870)` left / `(535,870)` right (table.gd), fired
together with the main flipper on their side — same `flip_left`/`flip_right` input and touch
zones, no new controls. Included in the tilt kill-switch (`set_disabled`) and reset-on-serve
paths alongside the main flippers.
Placement note (user feedback after first playtest): the original `(160,750)`/`(560,750)`
pivots at 0.55 scale sat under ramp R1's artwork (drawn above the bumpers) and were invisible.
Moved down to y=870, just above the slingshots and below where both ramps' rails end (R1's
right mouth is (528,812); its left return rail curves away from x112 toward the wall below
y755), clear of the ramp corridors with 40+ px margin either side; also bumped up in size.

## E2 Bonus bumpers
The 3 central "jungle" bumpers (`BUMPER_POSITIONS`) double as a light-them-all bank, mirroring
the existing top-lanes mechanic: `Rules.bonus_bumpers: Array[bool]` (3), event
`on_event("bumper", {"bonus_index": i})` (table.gd binds `i` via `.bind()` on the `hit` signal
for these 3 only; a plain `bumper` event with no `bonus_index` is unaffected — existing callers
unchanged). All 3 lit -> `multiplier += 1` (cap `MULTIPLIER_MAX`) + `BONUS_BUMPER_POINTS` (10000)
flat points, bank resets, message "BUMPER BONUS x%d". Reset with the rest of the ball state in
`start_game()`. New signal `bonus_bumpers_changed(lit)`; `lights.gd` shows 3 small insert lamps
above the 3 bumpers (`set_bonus_bumpers`), and `bumper.gd` gained `set_lit(bool)` to tint its own
glow green while lit (`COLOR_LIT`) vs the normal gold (`COLOR_OFF`).

## E3 Moving mini bumpers
`scripts/mini_bumper.gd` (new, `AnimatableBody2D`, radius 16): patrols back and forth between
`point_a`/`point_b` at `speed` px/s (ping-pong), same kick-on-contact + cooldown behaviour as
`bumper.gd` but also imparts its own track velocity (`_velocity * 1.5`) into the kick impulse.
Two placed over the (non-colliding) slot pit, clear of every other static/moving element:
`(210,620)`↔`(300,620)` @ 70 px/s and `(370,700)`↔`(460,700)` @ 85 px/s. Both feed the plain
`bumper` event (no bonus index) and are added to `table.new_bumpers`, so the existing
`_scenario_new_bumpers` physics-smoke regression (fires a ball at each bumper's *current*
position from `get_meta("approach")`, expects a `hit`) covers them automatically — each sets
`set_meta("approach", Vector2(0,-1))` like the other pop bumpers.

## Acceptance (Part E) — not yet run
- E-A1 `run_tests.gd`: new `test_bonus_bumpers_multiplier` (lighting 1/2/3, re-hit no-op,
  multiplier+points on all-3, bank reset, cap at 5, plain `bumper` event unaffected). All
  previous tests unchanged/still green.
- E-A2 `physics_smoke.gd`: existing `_scenario_new_bumpers` now also covers both mini bumpers
  (no test file changes needed). Not yet verified: wing flippers physically launch a ball
  (no new scenario added — recommend one firing a ball at each wing flipper's tip, expecting a
  strong upward kick, before shipping).
- E-A3 `godot --headless --path game --quit-after 600` -> no SCRIPT ERROR/ERROR (not yet run).
- E-A4 manual play: wing flippers reachable and useful, bonus-bumper lamps track hits and clear
  on the third, mini bumpers visibly patrol and kick the ball unpredictably.

---
# Part F — user feedback round 5 (fix mini-bumper visibility, wing flipper placement,
# vortex sucker holes, cheat keys, README)

Also implemented by hand (no Godot/opencode in this sandbox), not run/verified headless.

## F1 Mini bumper invisible — root cause found and fixed
`mini_bumper.gd` never set `z_index`, so it defaulted to 0 while `slot.z_index = 2`
(table.gd `_build_slot`) — the slot's reel art was drawing on top of both mini bumpers,
which sit inside the slot's footprint by design. Fixed: `mini_bumper.gd` now sets
`z_index = 3` in `_ready()` (above the slot, below the ball's `z_index = 6`).

## F2 Wing flipper placement tuning
- `WING_LEFT_PIVOT` moved from `(185,870)` to `(140,870)` — pulled in to ~24px clearance
  from ramp R1's return-rail corridor (as close to the wall/ramp as the geometry allows;
  going any closer overlaps the ramp, which is a hard constraint — R1's rail runs the
  full length of that wall, so nothing can sit directly between the wall and the rail).
- Added a **third, smaller left-side wing flipper** (`wing_top_left_flipper`,
  `WING_TOP_LEFT_SCALE = 0.55`, pivot `(170,250)`), fired with the same `flip_left` input,
  clear of the (150,330) pop bumper, the scoop and the top lanes.

## F3 Vortex sucker holes (`scripts/kickback_hole.gd`, new)
An open pit (no walls, unlike the idol scoop's cup — reachable from any direction).
Capture → freeze the ball at centre for `HOLD = 2.0 s` while the rim spins and the glow
pulses (the new light-effect ask), then launch it hard (`KICK_SPEED = 1150`) mostly
straight up (±16° random spread). Two placed in the open slot pit, clear of both mini
bumper tracks and the wing flippers: `(335,660)` and `(250,750)`. Rules: new event
`vortex` → `_award(VORTEX_POINTS = 3000)`. `table._ball_is_stuck` now also skips a ball
with `held_by_hole` meta (set while captured, like the ramp's `on_ramp` meta), so the
stuck-ball safety net doesn't fight the hold.

## F4 Cheat keys (table.gd + rules.gd, project.godot InputMap)
- `M` → `Rules.cheat_multiball()` (new): starts/extends Eternal Life multiball.
- `B` → `Rules.add_ball(1)` (existing add-a-ball path, reused as-is).
- `N` → `Rules.cheat_add_extra_ball()` (new): `extra_balls += 1`, capped at `EXTRA_BALLS_MAX`.
All three are no-ops outside `PLAYING` (existing guard pattern). **Key reassignment**:
`M` was also a `flip_right` alias (3 others remain: Right arrow, `D`, `/`) — removed to
avoid firing the right flipper and the multiball cheat on the same keypress. `N` was the
`music_toggle` shortcut — removed (music toggle is still reachable via the on-screen
speaker icon); the user asked for `N` specifically for the extra-ball cheat.

## F5 README.md (repo root, new)
Project overview, controls (incl. the new cheats), how to run/test, project layout,
credits. Tone: the user explicitly asked for it to lean into "two addictive genres in
one cabinet" as a joke — keeps that to the intro tagline only, stays a normal/complete
project README otherwise, and closes with a "play responsibly, it's just a video game"
line rather than actually marketing towards problem gambling.

## Acceptance (Part F) — not yet run
- F-A1 `run_tests.gd`: `test_award_values` extended with the `vortex` award; new
  `test_cheats` (ignored outside PLAYING, `cheat_multiball` sets `multiball` + requests
  a spawn, `cheat_add_extra_ball` increments and caps at `EXTRA_BALLS_MAX`).
- F-A2 physics_smoke / manual play (not yet run): mini bumpers visibly patrol above the
  slot art; wing flippers reachable, left pair visibly closer to the wall/ramp; vortex
  holes capture a ball and fire it upward after ~2 s; `M`/`B`/`N` behave as cheats and no
  longer double as `flip_right`/`music_toggle`.

---
# Part G — user feedback round 6 (stuck-ball cheat, +10% flippers, gravity toggle,
# follow camera, left side-bumper reposition, soft floating bonuses)

Also implemented by hand (no Godot/opencode in this sandbox), not run/verified headless.

## G1 Left side bumper raised (stuck-ball report)
`SIDE_BUMPERS[0].pos` moved from `(20,860)` to `(20,845)` (table.gd) — balls sliding down
the left wall were reported catching on it. Exact snag geometry unconfirmed (no engine
here to reproduce); if still stuck after this, the next thing to try is enlarging the
side bumper's own `radius` (side_bumper.gd, default 22) rather than moving it further.

## G2 Flipper speed + power +10%
`flipper.gd`: `SWING_SPEED` 15.0 -> 16.5 rad/s, `KICK_MULT` 1.15 -> 1.265. Shared consts,
so every flipper (main + all 3 wings) gets both bumps automatically.

## G3 Cheat: R = rescue/reset a stuck ball
`Rules.cheat_reset_ball()` (new): `balls_in_play = 0`, `multiball = false`, emits
`request_serve_ball` — same "waiting for a fresh ball" state as any normal ball start,
no life lost. Table side: `table._cheat_reset_ball()` frees every node in group "balls"
directly (marks each `drained` first so `_check_balls` ignores it that frame) — it does
**not** go through `_drain_ball`, so no `drain` event fires and no bonus/life is touched.
Ignored outside PLAYING (existing guard pattern).

## G4 Cheat: V = gravity toggle (100% / 50%)
`table._toggle_gravity()`: flips `PhysicsServer2D.area_set_param(get_world_2d().space,
PhysicsServer2D.AREA_PARAM_GRAVITY, g)` between the project's configured default gravity
(read once in `_ready()` from `physics/2d/default_gravity`, currently 1400) and half that.
This changes the live physics space directly, no project-settings reload needed. Resets to
100% automatically when a game ends (`_on_state_changed`), so a new game always starts at
normal gravity.

## G5 Cheat: TAB = zoomed follow camera
`lights.gd` gained `set_zoom`, `set_camera_position`, `get_camera_position` (thin wrappers
around the existing `TableCamera` it already owned for `shake()`). `table._toggle_zoom_follow()`
flips between `zoom = (1,1)` (normal) and `zoom = (0.6,0.6)` (zoomed in ~1.67x, "not too
close" per the request); while zoomed, `table._update_camera_follow()` lerps the camera
position toward the tracked ball every physics frame (`CAMERA_FOLLOW_LERP = 6.0`).
**Which ball**: every spawned ball gets a monotonic `spawn_seq` meta (table.gd `spawn_ball`,
`_ball_seq` counter); `_find_follow_ball()` returns the still-alive ball with the *lowest*
`spawn_seq` — i.e. the first one that entered play — so in multiball the camera keeps
tracking that same ball even as later ones join, and automatically switches to the
next-oldest if the tracked one drains. Toggling off (or the state leaving PLAYING) resets
zoom to normal and camera position to `HOME_CAMERA_POS = (360,640)`.

## G6 Soft floating bonuses (`scripts/floating_bonus.gd`, new)
Pure `Area2D`, no `StaticBody2D`/collision shape on layer 1 at all — the ball has nothing
solid to bounce off, it rolls straight through. One at a time: appears at a random spot
from a curated list of 7 open positions (`table.SOFT_BONUS_SPOTS`, picked clear of every
wall/bumper/target/ramp/other dynamic element with margin — see the const's comment),
picks a random `kind` (points / multiplier / ball_save) at spawn (visual color hints the
kind), pulses + slowly spins, and either gets touched (grants the bonus, frees itself) or
times out after `LIFETIME = 12s` (fades away, no bonus). Next one appears after a random
7-14s gap. Rules: new event `soft_bonus` with `{"kind": ...}`:
- `points` (default/unknown kind too) -> `_award(SOFT_BONUS_POINTS = 7500)`.
- `multiplier` -> `multiplier += 1` (capped, same as lanes/bonus bumpers).
- `ball_save` -> extends/starts an 8s ball save (`SOFT_BONUS_BALL_SAVE`), same mechanism
  the plunger and the slot's pharaoh bonus use.
Spawning/despawning is driven entirely by `table._update_soft_bonus()`, gated on
`rules.state == PLAYING` (cleared immediately otherwise, including on game over).

## Acceptance (Part G) — not yet run
- G-A1 `run_tests.gd`: new `test_cheat_reset_ball` (ignored outside PLAYING, clears
  balls_in_play/multiball, requests a serve, does not advance ball_number) and
  `test_soft_bonus` (all 3 kinds, unknown kind falls back to points).
- G-A2 manual play (not yet run, most important one here): confirm the left side bumper
  no longer catches balls (may need G1's follow-up radius tweak instead); flippers feel
  ~10% snappier; `R` actually frees a wedged ball without costing a life; `V` visibly
  changes fall speed and toggles back; `TAB` zooms in, follows the first ball into play
  through a multiball, and returns to normal on a second press; soft bonus orbs appear,
  don't deflect the ball, and grant their bonus on touch.

---
# Part H — user feedback round 7 (camera zoom direction, more flipper/bumper power,
# soft bonuses use the game's own icons)

Also implemented by hand (no Godot/opencode in this sandbox), not run/verified headless.

## H1 Camera zoom was backwards
`ZOOM_FOLLOW` was `(0.6,0.6)`; the user saw the view shrink instead of enlarge when
toggling TAB. Per the Godot docs "smaller than (1,1) zooms in" — but that's not what was
observed in practice, so rather than trust the doc over the user's eyes, flipped it the
other way: `ZOOM_FOLLOW = (1.6,1.6)` (table.gd). If this direction also comes back wrong,
the fix is a one-line value swap in the same const — the follow/lerp logic itself
(`lights.set_zoom`/`_update_camera_follow`) doesn't change either way.

## H2 Flipper power, another +10% on top
`flipper.gd`: `SWING_SPEED` 16.5 -> 18.15 rad/s, `KICK_MULT` 1.265 -> 1.3915 (compounds
with Part G2's first +10%; cumulative vs the pre-Part-G baseline: speed ×1.21, kick ×1.21).
Still shared consts, so this covers the main flippers and all 3 wings together, as asked.

## H3 Round pop bumpers +30% bounce
`bumper.gd`: `KICK_IMPULSE` 820 -> 1066 (+30%). Scoped to the round pop bumpers only (the 3
jungle ones + the 2 extra ones, all `bumper.gd`) — NOT the wall-mounted half-disc side
bumpers (`side_bumper.gd`, not round, not "in alto") and NOT the moving mini bumpers
(`mini_bumper.gd`, a distinct newer feature, own `KICK_IMPULSE`, untouched). Ball speed
stays bounded regardless (`ball.gd` clamps to `MAX_SPEED = 3200`).

## H4 Soft bonuses: real icons instead of a drawn blob, more glow
`floating_bonus.gd` no longer draws a Polygon2D "blob" — it shows one of the game's own
slot-symbol textures (`Sprite2D`, scaled to a ~42px footprint regardless of the source
image's own size/aspect ratio) chosen by kind: `points` -> `emerald.png` (treasure),
`multiplier` -> `scarab.png` (Egyptian luck/multiply symbol), `ball_save` -> `ankh.png`
(symbol of life — a natural fit for "extra life"). The `PointLight2D` glow got stronger
(`energy` base 1.1 pulsing to 1.8, `texture_scale` 1.6 -> 2.4) so it reads clearly against
the playfield art instead of the plain circular glow.

## Acceptance (Part H) — not yet run
- H-A1 no logic changes to Rules in this part; existing G-A1 tests (`test_soft_bonus`,
  `test_cheat_reset_ball`) and all earlier tests should be unaffected — re-run
  `run_tests.gd` to confirm nothing regressed from the bumper.gd/flipper.gd/table.gd edits.
- H-A2 manual play (the one that matters here): TAB now visibly enlarges the view instead
  of shrinking it; flippers noticeably snappier again; round pop bumpers kick harder; soft
  bonus pickups show a recognizable emerald/scarab/ankh icon with a visible glow, not a
  plain circle.

---
# Part I — user feedback round 8 (plunger power, zoom value, 3rd wing on the right,
# right side bumper still catching the ball)

Also implemented by hand (no Godot/opencode in this sandbox), not run/verified headless.

## I1 Plunger power +65%
`plunger.gd`: `MAX_SPEED` 1700 -> 2805 (+65%). `MIN_RATIO` (min launch = 40% charge)
unchanged, so the minimum launch speed scales with it (680 -> 1122). Stays under
`ball.gd`'s `MAX_SPEED = 3200` clamp even at full charge.

## I2 Zoom value: 1.6 -> 1.5 ("make it 150%")
`table.ZOOM_FOLLOW` = `Vector2(1.5,1.5)`. (Direction was fixed in Part H; this is just the
exact requested magnitude.)

## I3 Right side bumper raised (same fix as the left one, Part G1, never applied here)
G1 only raised the LEFT side bumper; the right one (`SIDE_BUMPERS[1]`) was untouched. The
user now reports the same "ball gets stuck" symptom on the right, worse ("doesn't pass at
all"). Moved `(634,820)` -> `(634,795)` — 25px, a bigger move than the left one's 15px given
the more severe report. Same caveat as G1: exact snag geometry unconfirmed without an
engine to reproduce in.

## I4 Third wing flipper: right wall, ~slot height
`WING_RIGHT_WALL_PIVOT = (620,745)`, `WING_RIGHT_WALL_SCALE = 0.55` (table.gd), fires with
`flip_right` alongside the other right-side flippers. Placed in the one open pocket against
the right wall (divider inner face x=634) in that height band: below the INDY target bank
(ends y=674) and to the right of ramp R1's rail column (centred x≈528, ±20.5px in this flat
stretch, so blocked up to x≈548.5) — pivot sits with ~8px clearance from the wall and the
flipper's own swept reach stays ~18.7px clear of the ramp corridor at its closest. This is a
tight pocket (a smaller-scale flipper was the only way it fit both constraints); if it still
looks cramped in play, shrinking `WING_RIGHT_WALL_SCALE` further (e.g. to 0.45) is the safe
follow-up rather than moving the pivot closer to either boundary.

## Acceptance (Part I) — not yet run
- I-A1 no Rules changes in this part; all earlier tests should be unaffected.
- I-A2 manual play (the one that matters): plunger visibly launches much harder; TAB zoom
  reads as "about 1.5x", not too close; a ball rolling down the right side no longer wedges
  near the (now higher) right side bumper; the new right-wall wing flipper is reachable,
  visible (not under the ramp or clipped by the wall/target bank), and doesn't overlap the
  existing right-side wing flipper or the INDY target bank.

---
# Part J — visual layout editor (user request: "how do I move elements visually?")

Also implemented by hand (no Godot/opencode in this sandbox), not run/verified headless.
The whole table is code-generated (no scene nodes to drag in the Godot editor), so this
adds an in-game dev tool instead of touching the editor workflow.

## J1 `scripts/layout_editor.gd` (new)
A `Node2D`, `process_mode = PROCESS_MODE_ALWAYS` so its toggle/save keys and drag handling
keep working even while it pauses the tree (`get_tree().paused`). `setup(entries)` takes a
list of `{"name": String, "get": Callable, "set": Callable}` and draws a small cyan circle
handle per entry, positioned each frame from `get`. `E` toggles edit mode (pause +
show/hide handles); while active, click-drag a handle (hit-test by distance, `HANDLE_RADIUS
= 14`) moves it via `set(get_global_mouse_position())`; `S` serializes every entry's current
value to `res://layout_overrides.json` (flat `{name: [x,y]}`, via `JSON.stringify`). A
static `load_overrides()` reads that file back (missing/corrupt -> `{}`, never crashes,
same tolerant pattern as `settings.gd`).

## J2 table.gd wiring
`_build_layout_editor()` (called last in `_ready()`, after every dynamic element exists):
builds `_layout_entries` (`_build_layout_entries`), applies any saved overrides on top of
the just-built defaults (`_apply_layout_overrides`), then constructs the editor and hands
it the entries. Two entry shapes:
- `_add_layout_pos(name, node)`: for anything with a plain `.position` (both wing-flipper
  pairs — 4 total, both side bumpers, both vortex holes, all 5 round pop bumpers, all 7
  soft-bonus spawn spots).
- `_add_layout_field(name, obj, field)`: for the 2 mini bumpers, which need their `point_a`
  and `point_b` each editable separately (4 handles) — dragging the bumper's live,
  constantly-animated `position` wouldn't make sense, so these target the track endpoints
  directly via `Object.get/set(field)`. (Edit mode pauses the tree, so the mini bumper's
  own `_physics_process` — default process mode — stops animating it while you drag.)

Soft-bonus spawn spots got a structural change to make them actually editable: 7 invisible
`Node2D` markers (`_build_soft_spot_markers`, one per `SOFT_BONUS_SPOTS` entry) are now the
source of truth `_spawn_soft_bonus()` reads from (`marker.position`), not the const array
directly — so dragging/saving a spot's marker changes where bonuses actually spawn from
then on, with no other plumbing needed.

Deliberately NOT made draggable: main flippers, scoop, target bank, ramps, lane sensors,
orbit, slot, walls — all structurally load-bearing (multi-point paths, collision logic tied
to specific geometry) where a generic position drag could silently break something. Matches
the user's own framing ("alcuni elementi", not everything).

## J3 Persistence answer (the user's actual question)
`layout_overrides.json` is a plain file inside `game/`, loaded once at `_ready()` and never
written to except by pressing `S`. It's git-trackable like any other project file — commit
it directly, or paste its contents back so the numbers get folded into the real consts in
`table.gd` (removes the need for the override file once done).

## Acceptance (Part J) — not yet run
- J-A1 no Rules changes; all earlier tests unaffected.
- J-A2 manual play (the one that matters): `E` pauses the game and shows handles at the
  right spots; dragging one visibly moves the real element (not just the handle); `S`
  writes `layout_overrides.json` and it's readable JSON; relaunching the game restores the
  saved positions without any code changes; mini-bumper `point_a`/`point_b` handles show
  the track endpoints (not wherever the bumper happened to be mid-swing when paused).

---
# Part K — user feedback round 9 (apply saved layout, fix wing drag, unify wing size,
# more flipper power/length, bumper light+fire+upward kick, wireform ramps)

Also implemented by hand (no Godot/opencode in this sandbox), not run/verified headless.

## K1 Applied the user's saved layout
`game/layout_overrides.json` now holds the file the user exported from the in-game editor
(all mini-bumper/pop-bumper/side-bumper/vortex-hole/soft-spot positions they dragged).
Loads automatically via the existing `table._apply_layout_overrides()` path — no code
change needed for this part, just committing the file.

## K2 Wing flippers wouldn't drag — click tolerance too tight
The 4 wing entries in the saved file are still at their exact defaults — the user's drags
on them never registered, while every other (smaller, roughly circular) element moved
fine. Likely cause: `layout_editor.gd`'s hit-test only accepted clicks within
`HANDLE_RADIUS = 14px` of the flipper's *pivot*, but a flipper is a long bat — the natural
click target is the visible paddle body, well outside that radius. Fixed two ways:
`CLICK_RADIUS = 26` (separate from the drawn handle size) widens the tolerance, and
`_try_start_drag` now picks the *closest* handle within radius instead of the first match
in iteration order, so two nearby handles no longer fight over an ambiguous click. Not
verified against an engine — if wings still won't drag, the pivot itself may need its own
larger dedicated hit shape rather than a bigger generic radius.

## K3 All 4 wing flippers now the same size
`WING_TOP_LEFT_SCALE` (0.55) and `WING_RIGHT_WALL_SCALE` (0.55) removed; both wings now use
`WING_FLIPPER_SCALE = 0.75`, same as the lower pair (user request — they were smaller for
clearance reasons in tighter pockets). If either now clips something, the layout editor is
the tool to fix it with, not shrinking the scale back down.

## K4 Flipper length +10%, power +10% again (3rd time)
`flipper.gd`: `BASE_LENGTH` 96 -> 105.6 (+10%, scales every flipper via size_scale too);
`KICK_MULT` 1.3915 -> 1.53065 (+10% again — 3rd bump total across this session: 1.15 ->
1.265 -> 1.3915 -> 1.53065). `SWING_SPEED` untouched this round (user asked for "forza"/
power specifically, not speed again). Kick power multiplies the ball's launch velocity
directly, so this alone delivers "the ball flies away faster" — no separate mechanism
needed.

## K5 Round pop bumpers: brighter flash, fire burst, upward-biased kick
`bumper.gd`:
- Light-up: the transient glow bump raised (1.8 -> 2.6 energy) and slowed (decay ×4/s
  instead of ×5/s), **plus** a new overbright flash on the bumper's own sprite (`FLASH_COLOR`
  channels >1, `Color.WHITE.lerp(FLASH_COLOR, ...)` over `FLASH_TIME = 0.12s`) — the sprite
  is reparented onto the node by table.gd *after* `_ready()`, so it's looked up lazily
  (`_find_sprite()`) rather than cached upfront.
- Fire effect: a `CPUParticles2D` (`_build_fire()`, one-shot, 14 particles, orange/red/gold
  gradient, short outward burst) built once in `_ready()` and `restart()` + `emitting = true`
  on every hit — reused, not spawned/freed per hit.
- Upward bias: the radial kick direction's downward component is softened to 35%
  (`DOWNWARD_SOFTEN`) and its upward component boosted 15% (`UPWARD_BOOST`) before
  re-normalizing and applying `KICK_IMPULSE` — so a hit from any angle tends to send the
  ball up more than down, not just hits that were already upward-ish.
Scoped to `bumper.gd` only (the round ones), same as the earlier +30% impulse change —
`side_bumper.gd`/`mini_bumper.gd` untouched.

## K6 Ramps redone as a wireform (user request, reference photo of a real Indiana Jones
## table's overhead wire rail)
`ramp.gd` `_build_visuals()` rewritten: removed the solid `surface` Line2D (width 36,
opaque stone fill — this was the "filled" look the user disliked) and the single wide
`shadow`/`edge` bands entirely. Replaced with, per rail (`_offset_path(±1, WIDTH*0.5)`):
its own thin drop shadow, its own line of small support posts (instead of one central
post line), and the gold rail itself with a thin dark outline for a rounded-wire look —
plus sparse perpendicular cross-wire "rungs" every `_total/90` along the path bracing the
two rails together, matching the reference photo's wire-frame structure. The playfield art
underneath is now fully visible through the gap between the rails. Chase lamps unchanged.
Physics (the actual layer-16 rail collision in `_build_rails()`) is untouched — this is a
rendering-only change; ball elevation still reads from the existing scale-up + drop-shadow
the ball itself gets while `on_ramp` (ball.gd, D2).

## Acceptance (Part K) — not yet run
- K-A1 no Rules changes; all earlier tests unaffected.
- K-A2 manual play (the one that matters, most of this part is visual/feel): saved layout
  positions show up on next launch; wing flippers ARE draggable now and end up the same
  visible size as the lower pair; flippers noticeably longer and stronger again; round
  bumpers flash bright + spit a small spark burst + visibly favour upward trajectories on
  hit from any angle; ramps read as an open wire rail with the playfield art visible
  underneath, not a solid painted track.

---
# Part L — user feedback round 10 (wing drag still broken, revert flipper length,
# exploding bumpers, plunger-lane one-way gate)

Also implemented by hand (no Godot/opencode in this sandbox), not run/verified headless.

## L1 Wing flippers STILL wouldn't drag — second attempt, different root cause
Part K's fix (bigger uniform click radius + nearest-match) apparently wasn't the real
problem. New hypothesis: a flipper's *visible* bat is ~80-100px long from the pivot, so
clicking the paddle body (the natural target) can land well outside even a 26px radius —
the pivot itself was simply never where the user was clicking. Fixed properly this time:
entries can now carry a per-entry `"radius"` (`layout_editor.gd` `setup()`/`_try_start_drag`
both read it, falling back to the old global defaults when absent), and `table.gd` passes
`WING_CLICK_RADIUS = 60` for all 4 wing entries specifically — both the hit-test tolerance
and the drawn handle circle are now that big for wings, so the cyan circle visually covers
most of the paddle instead of a tiny dot at the pivot. `_try_start_drag` also now compares
by *fraction of each entry's own radius* (not raw distance) so a big and a small handle
compete fairly for an ambiguous click instead of the bigger one always winning. Still not
verified against an engine.

## L2 Flipper length reverted
`flipper.gd` `BASE_LENGTH` back to 96.0 (was 105.6) — the +10% length from Part K didn't
feel right. This also shrinks every wing back down proportionally (same as how the
lengthening applied to them), matching how the change was applied originally.

## L3 Exploding bumpers (round AND mobile)
`bumper.gd` and `mini_bumper.gd` both gained: a per-instance hit counter, a randomized
explode threshold picked at `_ready()`/each respawn (`randi_range(5, 15)`), and a new
`exploded` signal. On the hit that reaches the threshold: `_explode()` — a big one-shot
`CPUParticles2D` burst (40 particles, separate from bumper.gd's small per-hit spark, reused
from `mini_bumper.gd` too even though mini bumpers don't get the per-hit sparks from Part
K), `visible = false`, collision disabled (`collision_layer = 0` + the Detect area's
`monitoring = false`), and the `exploded` signal fires. `_respawn()` ~28-32s later
("circa 30 secondi") restores visibility/collision, resets the hit counter and picks a
fresh random threshold; `mini_bumper.gd` additionally resets to `point_a` (a mid-track
pop-back-in would look wrong) and freezes its ping-pong motion entirely while gone
(`_physics_process` early-returns).
Rules: new event `bumper_explode` -> `_award(BUMPER_EXPLODE_POINTS = 25000)` + a message.
table.gd wires both bumper types' `exploded` signal to one shared handler
(`_on_bumper_exploded`): fires `rules.on_event("bumper_explode")`, plays the `jackpot` sfx
(reused, no new asset needed), and triggers `lights.flash()` + `lights.shake()` for the
"big moment" the user asked for.

## L4 Plunger lane one-way gate
User request: a ball launched up and out of the shooter lane must always be able to leave,
but a ball that rolls back down toward the lane from the main playfield shouldn't be able
to re-enter it — asked for either an invisible wall or a closing door. Used neither
literally: Godot's `CollisionShape2D.one_way_collision` is exactly a "one-way platform"
primitive (solid only against a body landing/falling onto it from one side, passed through
freely from the other) — the same mechanic as a platformer's jump-through floor. A single
thin (12px) `RectangleShape2D` spanning the lane's width (divider x=634 to outer wall
x=700), placed at y=430 where both lane walls begin (`table._build_lane_gate()`, called
right after `_build_walls()`), with `one_way_collision = true` and a 14px margin. No new
node type, no custom physics, no change to the existing serve/launch flow (`SERVE_POS` and
the plunger are both well below y=430, unaffected).

## Acceptance (Part L) — not yet run
- L-A1 `run_tests.gd`: new assertion for `bumper_explode` scoring (`BUMPER_EXPLODE_POINTS`).
  All earlier tests should be unaffected.
- L-A2 manual play (the one that matters, especially L1 which failed once already and L4
  which is genuinely new physics): wing flippers actually drag now, with a visibly bigger
  cyan handle; flipper length looks like the original; round and mobile bumpers explode
  after a handful of hits (visibly random, not always the same count), pay a big bonus,
  vanish and come back roughly half a minute later; a ball can always launch out of the
  shooter lane but a ball rolling toward it from the field stops at the gate instead of
  sliding back in.

---
# Part M — user feedback round 11 (bake layout, 3rd wing-drag attempt, audio mute,
# dirt-pit holes, flipper size/position, retro decor, slot scale/bugfix/tuning)

Also implemented by hand (no Godot/opencode in this sandbox), not run/verified headless.
Biggest batch yet — see M8 for what was deliberately NOT attempted this round.

## M1 layout_overrides.json baked into the real consts, file removed
Every position the user tuned in the layout editor (`BUMPER_POSITIONS`, `POP_BUMPER_POSITIONS`,
`SIDE_BUMPERS`, `MINI_BUMPERS`, `VORTEX_HOLES`, `SOFT_BONUS_SPOTS` — all in table.gd) now holds
those values directly (rounded to whole px); `game/layout_overrides.json` deleted. The wing
entries were left untouched since they never actually moved (see M2) — no override values to
bake for those.

## M2 Wing flippers — 3rd attempt: switched from event-driven to polled dragging
New, more diagnostic symptom this time: the click DOES register (handle highlights, matching
Part L's bigger-radius fix), but dragging does nothing — "as if planted in the ground". That
rules out hit-detection and points at `InputEventMouseMotion` specifically not updating
`.position` reliably while the tree is paused, for reasons not fully diagnosable without an
engine (AnimatableBody2D + sync_to_physics interacting with paused physics is the leading
theory, but every other draggable type in this table is *also* a mix of StaticBody2D/
AnimatableBody2D and worked, so it isn't simply "AnimatableBody2D doesn't work"). Rather than
guess further, `layout_editor.gd` no longer relies on motion events at all: `_input()` now only
starts a drag (mouse-down) and reports E/S; a new `_drag_update()` is polled every frame from
the already-proven-working `_process()` (proven because handle-follow and the label text update
through it every frame, active-mode gated same as before) — it directly reads
`Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)` and `get_global_mouse_position()` instead of
waiting for a motion event. This is a fundamentally different code path from the two previous
attempts, not just a bigger number — if this ALSO doesn't move the wings, the bug is genuinely
in `.position =` not sticking on a Flipper specifically, which would need engine-side
inspection (print statements / the Godot debugger) that isn't possible from this sandbox.

## M3 Audio mute now covers SFX too
`sfx.gd`: `play()` and `loop_start()` now also gate on `_music_enabled` (renamed in comments
only — the persisted settings key and method names are unchanged for compatibility).
`set_music_enabled(false)` additionally stops every pool player immediately and tears down
active loops, not just fading the music out — so toggling audio off silences everything at
once, not just future music.

## M4 Vortex holes redrawn as dirt pits, not "black holes"
`kickback_hole.gd`: replaced the flat near-black circle + spinning neon-purple ring with a
jagged earthy mound (irregular polygon rings, `_jagged_circle()` jitters each vertex so every
hole looks slightly different) in browns/tans, a dark (not black) pit centre, and a scatter of
small rock/clump shapes around the rim. Glow recoloured from neon purple to warm amber
(torch-lit look) and only pulses while actively holding a ball, no longer spins constantly at
idle — reads as "something dug in the ground", matching the Indiana Jones/temple theme. No art
assets used/fetched (none available in this sandbox) — everything is procedural Polygon2D, the
same technique already used throughout this project.

## M5 Flipper length +20%, position lowered (partially), main flippers now draggable too
`flipper.gd` `BASE_LENGTH`: 96 -> (a +10% detour, reverted) -> 115.2 (+20% over the original,
user's final call after trying the revert). `table.gd` `FLIPPER_LEFT_PIVOT`/`_RIGHT_PIVOT`
lowered by 20px (1110 -> 1130) — NOT the literal "4% from the bottom edge" the user described
(~1229), because that lands inside the drain zone (y 1215-1280, same x range as the main
flippers) and would break drain detection. Both main flippers are now also registered in the
layout editor (`flipper_left`/`flipper_right`, same big click radius as the wings) specifically
so the user can push them further down themselves and see the result live, rather than me
guessing blindly at a value that risks breaking the drain.

## M6 Retro decoration in the freed space
New `scripts/retro_arrows.gd`: a small 3-chevron "shoot here" chase (classic GI-insert flavour
from 70s/80s tables), purely decorative (no collision at all). Two instances placed above the
lowered flippers (`table._build_retro_arrows()`).

## M7 Slot: +25% display size, a real overlap bug fixed, sharper win lines, bonus tuning
- Size: `table._build_slot()` now sets `slot.scale = 1.25` with a compensating `position`
  offset (`window_center * (1 - scale)`) so the display grows in place around the reel
  window's own centre instead of drifting away from it.
- **Real bug found**: each reel keeps `ROWS+1` (4) symbol holders — one spare only needed for
  smooth scrolling. `_draw_reel_static()` only ever repositioned/hid the first 3, so the 4th
  stayed visible wherever the last scroll frame left it once the reel stopped — an intermittent
  ghost symbol overlapping the real ones. This is almost certainly what "a volte le figure si
  sovrappongono" was — fixed by explicitly hiding index >= ROWS every static draw.
  `_cell_centre()`'s math for win-line points was already exactly correct (verified by hand
  against how the reel holders are actually positioned) — the "imprecise" look was the 5px
  non-antialiased line plus loose diagonal-corner "X" tick marks; now a 3px antialiased line
  (`Line2D.antialiased = true`) with a small centred filled dot per cell instead.
- Bonus probability: `slot_machine.gd` `WEIGHTS["book"]` 3 -> 3.45 (+15%) — book is the
  wild/scatter that substitutes on every payline, so more of it raises the odds of completing
  *any* 3+ bonus-paying run rather than favouring one symbol. **Not re-verified** against
  `test_slot_target_math`'s 20000-spin bounds (hit 25-45%, free spins 1/60-150, avg 6-14
  credits) — no engine here to run it; this is the single highest-risk numeric change in this
  batch precisely because it's the one place a wrong guess is well-defined as "test fails".

## M8 Deliberately NOT attempted this round: the ramp geometry redesign
The user also asked to lengthen the central ramp into a figure-8 around "the oracle" up top,
and make the other ramp trace the full dome arc before dropping the ball near the centre
between the flippers. Every other change in this batch is either a value tweak, a self-
contained visual rewrite, or additive — this one is a full redesign of a `PackedVector2Array`
centreline that a real ball has to physically ride (`ramp.gd`'s along-path physics), with nothing
to check it against. Attempting it blind risks a ramp that clips a wall, crosses another
ramp/feature, or leaves the ball stuck — on top of an already large, entirely unverified batch
in this one turn. Flagged to the user rather than guessed at; will do it as its own focused pass.

## Acceptance (Part M) — not yet run
- M-A1 no Rules changes; all earlier tests unaffected, EXCEPT possibly `test_slot_target_math`
  (see M7) — run this one specifically first.
- M-A2 manual play, in priority order: (1) wings — do they drag now, with the new polling
  approach? (2) slot — no more ghost/overlapping symbols after a spin stops, win lines look
  exactly centred on the symbols, display is visibly ~25% bigger without drifting off-centre;
  (3) toggling audio off silences sound effects immediately, not just music; (4) vortex holes
  look like dirt pits, not glowing orbs/black holes; (5) flippers noticeably longer, main
  flippers draggable in edit mode; (6) chevron chase visible and animating above the flippers.

## Part N — flipper/wall/drain geometry follow-through, both ramps redesigned, slot cabinet rebuild
Continuation of the same round (M8 deferred the ramps; this part does them), plus the user's
next message: `table.gd` inlane walls extended to match the already-lowered flippers, main
flippers pushed to the requested 5%-from-bottom, the top wing raised as far as geometrically
possible toward the requested 3%-from-top, the drain lowered again to match, and both ramps
fully redesigned. Then the single highest-priority item of this entire round: a from-scratch
visual rebuild of the slot cabinet in `slot_view.gd`. **None of this has been run in an actual
Godot engine** — same standing caveat as every part before this one, but it applies with extra
force here given how much of this part is brand-new geometry with no way to preview it.

### N1 Inlane guide walls now actually follow the flippers
`table._build_walls()`'s two inlane guide bands were still hard-coded to the flippers' Y from
*before* this whole session's series of lowering rounds — every earlier round moved
`FLIPPER_LEFT_PIVOT`/`_RIGHT_PIVOT` down but never touched these two `_add_band()` calls, so the
walls increasingly stopped lining up with the palette as they moved (user: "i muri del flipper
non li hai allungati, hai spostato solo le palette"). Fixed at the root instead of re-adding
another one-off number: both bands' end point now reads `FLIPPER_LEFT_PIVOT.y - 30.0` /
`FLIPPER_RIGHT_PIVOT.y - 30.0` (the offset the original band already had relative to the
original pivot), so any future pivot move keeps the walls in sync automatically.

### N2 Main flippers to 5% from the bottom edge, drain lowered to match
User: "di sotto facciamo al 5%" (screen height 1280, so 5% up from the bottom = y=1216).
`FLIPPER_LEFT_PIVOT`/`_RIGHT_PIVOT`: 1130 -> 1162 — the flipper TIP at rest (pivot +
`LENGTH*sin(28°)` = pivot + 54.09, `LENGTH`=115.2 from Part M5) lands almost exactly on y=1216.
`DRAIN_TOP`: 1215 -> 1240 (user: "c'è la dropzone abbassa anche la dropzone") to keep roughly
the same tip-to-drain clearance as before (~24px now vs ~31px previously) rather than squeezing
it as the flippers moved down into where the drain used to start. Both pivots remain draggable
in the layout editor if this clearance needs tuning after an actual play-test.

### N3 Top wing flipper: literal 3%-from-top is impossible anywhere on this table
User: "il flipper in alto può essere alzato fino al 3% dal bordo superiore dello schermo".
Read literally, 3% of the 1280-tall screen is y=38.4 from the top. The playfield's top boundary
is a semicircular arc (`CENTER`=(360,420), `TOP_RADIUS`=340) whose highest point is y=80 at dead
centre and *lower* everywhere else — at `WING_TOP_LEFT_PIVOT`'s x=170 the arc sits at y≈138.
So even the single best spot on the whole table (dead centre) is only ~6.25% from the top edge,
and this off-centre wing can't get anywhere near 3% without its pivot ending up outside the
arc, i.e. outside the table. Applied the practical alternative instead of silently doing
nothing or blocking on a question: raised it as far as the arc + the wing's own swept arm
(~86px at `WING_FLIPPER_SCALE`) allow with a safety margin — `WING_TOP_LEFT_PIVOT.y`: 250 -> 220.
Draggable in the editor if the user wants to push closer to the wall and accept some clipping risk.

### N4 Both ramps redesigned
`ramp.gd` itself needed no changes — it already drives the ball along *any* `PackedVector2Array`
centreline by arc length (see Part D), so any shape, however sharp or self-crossing, is exactly
as safe to the physics as the simple ones before. Only `table.gd`'s point arrays changed.
- **R1 "TEMPLE RAMP"** (user: "quella sotto deve fare un disegno ad 8... intorno all'oracolo"):
  the mouth/rise (528,812)->(528,610) and the return tail down to (55,930) are unchanged; the
  middle is now two ~90px-radius loops pinched at `SCOOP_POS` (360,300) — the right loop (centre
  445,300) swept over its *top* half, the left loop (centre 275,300) swept over its *bottom*
  half, so the two arcs cross exactly once at the scoop and read as a real "∞" figure-8 instead
  of the old single sweep across the top. The loops pass close over 2 of the 3 round bumpers and
  both pop bumpers — intentional, not an oversight: wireform rails arching directly over other
  playfield elements is the entire point of the style (same as the Indiana-Jones reference photo
  the user sent earlier), and the rail `Line2D`s draw at z_index 7-8, well above the bumpers.
- **R2 "IDOL RAMP"** (user: "quella superiore deve fare mezza arcata per poi chiudersi al
  centro, stile serpente", plus the earlier "fai scendere la palla quasi al centro del
  flipper"): rise unchanged; a single arch now sweeps right-to-left across the top of the table
  (mirroring R1's rise, staying clear of the scoop/R1 loops which already own that space), a
  short snake wiggles back toward the right while staying above y=566 (the slot window's top
  edge), then a straight run descends on the *right* side of the slot window (world window is
  roughly x 130-530, y 566-806 once the slot's own scale/position are applied; this column sits
  at local x~540-565, comfortably outside it and roughly parallel to R1's own rise column
  further left at x~528-535 — two ramps running side by side down the right is already this
  table's established look). The last few points curve left to x=327 — the exact midpoint
  between the two main flipper pivots (214, 440) — landing at y=860, so the ball drops "quasi al
  centro del flipper" from a genuine height instead of exiting near the top of the table like
  before. `R1_COMMIT`/`R2_COMMIT` unchanged (both still lie on the untouched rise segments);
  `R2_EXIT_DIR` changed from (-1, 0.3) to (0, 1) — straight down, matching the now-centred exit.
  **Entirely unverified geometry** — this is hand-placed points reasoned from the existing
  consts (`SCOOP_POS`, bumper/wing positions, the slot window rect) with no way to render or
  physically test it; if a segment reads as visually crossing something badly or the ball
  doesn't ride it smoothly, it's the first thing to check and adjust by hand or via new
  layout-editor entries.

### N5 Slot cabinet visual rebuild — the round's top priority
User, verbatim, marked as the single most important thing in this round: "la slot me la devi
fare uscire fuori bellissima che non sfigurerebbe nemmeno in un casino di las vegas". No
external art is available in this sandbox (no image generation, no asset fetch), so the whole
upgrade is procedural Godot primitives — the same constraint and technique already used for
every other visual element in this project, just applied more thoroughly here. All changes are
in `slot_view.gd`; no logic/state-machine code touched, so spin/evaluate/payout behaviour is
identical to before this part.
- **Bevelled cabinet edge**: the old single flat `GOLD` rectangle frame is now three nested
  rectangles (`GOLD_DARK` outer, `GOLD` mid, `GOLD_LIGHT` inner) at the same outer extent as
  before, reading as a moulded metal case instead of a flat rectangle. A black, offset drop
  shadow polygon sits behind the whole cabinet for lift.
- **Corner gems**: four small diamond `Polygon2D`s at the outer corners, alternating new `RUBY`
  (#c0203a) / `EMERALD` (#1f8a52) consts.
- **Backlit reel window**: a warm radial glow (`GradientTexture2D`, `FILL_RADIAL`, built once
  and cached in `_cached_glow_tex`/`_glow_tex()`) sits behind the reels at low opacity, plus a
  soft white "glass" highlight polygon across the window's upper third — together read as a lit
  display case with a glass reflection instead of a flat dark rectangle.
- **Real glow bulbs**: `_make_circle()` (used for both the marquee chase lamps and the TEMPLE
  POWER meter lamps) now returns a small container node holding a soft radial-gradient halo
  sprite behind a bright core circle, both plain white, instead of one flat-coloured
  `Polygon2D`. The two call sites that used to set `.color` directly (`_update_marquee`,
  `_update_energy_lamps`) now set `.modulate` on the container instead — Godot multiplies a
  parent's `modulate` into its children's rendering, so the exact same on/off/chase/rainbow
  logic as before now lights up an actual glowing bulb (core + bleeding halo) rather than a flat
  dot, with no change to the chase timing/colour math itself.
- **Marquee title header**: a new `_build_title()` adds a thin glowing gold bar and a big
  "BOOK OF THE TEMPLE" label above the cabinet (positioned well clear of the existing
  free-spins/idle label row below it — checked by hand against both labels' Y coordinates and
  font heights, not rendered).
- **Marquee-sign typography everywhere**: `_make_label()` (the one helper every label in this
  file goes through — credit count, free spins, idle prompt, bonus banner, BIG WIN, book
  reveal) now also adds a dark outline (`font_outline_color` + `outline_size` theme overrides,
  scaled to each label's own font size) on top of the existing drop shadow, for a chunky
  casino-signage look instead of default flat UI text.
- **Explicitly not attempted this pass**: side cabinet pilasters and an animated shimmer sweep
  across the frame were considered and dropped to keep this batch contained and lower-risk —
  the changes above are already untested in-engine, and stacking more speculative geometry on
  top of them before getting feedback seemed like the wrong trade given the stakes the user
  attached to this specific item. Straightforward to add as a follow-up once this pass is
  confirmed to look right.

## Acceptance (Part N) — not yet run
- N-A1 no Rules/SlotMachine logic touched in this part; every earlier test should be unaffected.
- N-A2 visual/manual checks, in the order they matter most given the user's stated priorities:
  (1) **the slot** — does the cabinet read as a real casino machine now (bevelled frame, corner
  gems, backlit glass, glowing chase bulbs, the "BOOK OF THE TEMPLE" marquee header, chunky
  outlined text everywhere) instead of the old flat rectangle? Any label overlapping another?
  (2) both ramps — do they physically ride smoothly with no visual snag, does R1 read as a
  figure-8 around the scoop, does R2's arch-then-snake avoid visually cutting across the slot's
  new glass front, does the ball land close to centre between the flippers off R2; (3) the
  inlane guide walls now visibly reach the lowered flippers with no gap; (4) main flipper tips
  sit close to the drain with a small but real gap (should not stick into the drain sensor);
  (5) the top-left wing — does it still clear the curved ceiling through its full swing at its
  new, higher position.
