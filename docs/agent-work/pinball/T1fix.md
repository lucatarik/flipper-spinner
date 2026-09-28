# T1: Rules engine + core playable table (physics, flippers, plunger, bumpers, slings, drain, HUD)

Workspace: /home/lt1/PhpstormProjects/pinball-godot (Godot project lives in `game/`)
Baseline: repo has no commits; pre-existing untracked: .claude/ AGENTS.md CLAUDE.md orchestra/
  docs/ game/project.godot game/scenes/main.tscn (empty Node2D root) game/assets/**
Depends on: none
Report path: docs/agent-work/pinball/T1.report.md (APPEND a "Correction 1" section, keep existing content)

READ FIRST: `docs/agent-work/pinball/spec.md` — its Rules contract, event names, scoring and
physics contracts are fixed and part of this brief.

## Goal
1. Implement `game/scripts/rules.gd` COMPLETELY (every rule in the spec, including scoop,
   locks, multiball, modes, ball save, bonus/multiplier, game over) with unit tests.
2. Build the core table in `game/scenes/main.tscn`: background, walls with rounded top, shooter
   lane + plunger, top-right guide, two flippers, 3 pop bumpers (bumper.png, active kick
   impulse ≈ 700–900 px/s away from centre), 2 slingshots above the flippers (kick on their
   inner face), inlane/outlane guides, drain sensor, ball scene, basic HUD (score, ball n/3,
   transient message label). Table calls Rules events for bumper/sling/plunger_exit/drain/
   ball_added and reacts to request_serve_ball. Game starts with `start` action from ATTRACT
   (HUD shows "PRESS ENTER"); on GAME_OVER HUD shows final score and "PRESS ENTER".
3. Define InputMap actions in `game/project.godot` exactly as the spec says; keep existing
   settings (720x1280, 240 physics ticks, gravity 1400).
4. Implement failure behaviours from spec (escape = drain, stuck-ball nudge).

## Non-goals
Drop targets, idol scoop node, top lanes, orbits, multiball ball spawning, mode HUD panel,
high-score persistence — these are T2 (Rules must still implement their logic + tests).
Leave clear space for them: scoop ≈(330,250) idol area, top lanes y≈150, INDY target bank on
the right side ≈x 560..600, y 520..700, orbit lanes along both side walls y≈300..700.

## Done when
- A1: `godot --headless --path game -s res://tests/run_tests.gd` exits 0, prints a PASS/FAIL
  line per test and a summary. Tests cover: start_game resets; each award value; lanes all-lit →
  multiplier (cap 5); INDY completion → lock_lit + targets_reset; scoop priority chain
  (jackpot/lock/multiball start at 3 locks/mode start/5000); mode progress, completion, timeout,
  cycling order; ball save within 8 s vs after; multiball drain handling; bonus × multiplier at
  end of ball; game over after ball 3 with high score flag; events ignored when not PLAYING;
  balls_in_play never negative.
- A2: `godot --headless --path game --quit-after 600 2>&1 | grep -E "SCRIPT ERROR|ERROR"` → empty.
- A3: `godot --headless --path game -s res://tests/physics_smoke.gd` exits 0 with the four
  scenarios in spec A3 (plunger launch reaches field; flipper launches ball y-vel < -800;
  ball on idle flippers drains; 3000 px/s ball vs side wall stays in bounds).
- Smoke test drives inputs via `Input.action_press/ action_release` or direct method calls on
  flipper/plunger nodes (expose `set_pressed(bool)` on flipper and `set_charging(bool)` on plunger).

## Contracts (fixed — do not change)
- Rules API, signals, event names, constants, scoring: exactly as spec.md.
- Node API: `flipper.gd` exports `side` ("left"/"right"), method `set_pressed(pressed: bool)`;
  `plunger.gd` method `set_charging(on: bool)`, signal-free; `table.gd` exposes
  `var rules: Rules` and `func spawn_ball(pos: Vector2, vel := Vector2.ZERO) -> RigidBody2D`;
  ball nodes are in group "balls". Main scene root node named `Table` with script table.gd.
- Physics layers & ball radius per spec. No addons, no C#, no external dependencies.

## Files
May change: game/project.godot, game/scenes/**, game/scripts/**, game/tests/**,
  docs/agent-work/pinball/T1.report.md
Must not change: game/assets/** (read only), everything else.

## Freedom
Node structure, wall polygon shapes, exact coordinates (±30 px of spec), physics materials,
flipper implementation technique, visual styling (Polygon2D/Line2D colours: stone greys,
gold #d4a017 trims, dark jungle green), HUD layout. Use sprites from game/assets/sprites as
decor where it fits (torch.png near slings, skull/cobra as corner decor).

## Verification
Working dir: /home/lt1/PhpstormProjects/pinball-godot
- `godot --headless --path game --import` (first, to import assets) -> exits 0
- `godot --headless --path game -s res://tests/run_tests.gd; echo $?` -> all PASS, 0
- `godot --headless --path game --quit-after 600 2>&1 | grep -E "SCRIPT ERROR|ERROR"` -> no output
- `godot --headless --path game -s res://tests/physics_smoke.gd; echo $?` -> 0
Required test cases: happy (scoring, modes, multiball), negative (events outside PLAYING,
drain with 0 balls), boundary (multiplier cap 5, ball save at 7.9 s vs 8.1 s, ball 3 drain).
Note: in `-s` scripts extending SceneTree, instantiate the scene and add it to `root`, then step
frames in `_process`/`_physics_process` of the SceneTree or await `physics_frame`; call
`quit(code)` at the end. `class_name` may not be registered before import — preload scripts by path.

## Stop rules
Iterate autonomously. Report `blocked` for missing contracts, unavailable
environment or the same failure 3 times in a row.

---
# CORRECTION CYCLE — this is the actual task now
T1 was already implemented by a previous worker (code is in game/, read it first). Apply the review below; everything else in the brief above stays as context/contracts.

# T1 review 1 — changes requested (one batch, fix all)

Tests are green, but a visual run + code review found these defects. Keep all contracts.

1. BUG rules.gd ball save: on a saved drain `balls_in_play` is not decremented, then the
   re-serve fires `ball_added` → balls_in_play becomes 2 and the ball can never end.
   Fix: saved drain also does balls_in_play -= 1 (clamped ≥0) before emitting request_serve_ball.
   Add a unit test: serve → plunger_exit → drain (saved) → ball_added → drain after 9 s ⇒ ball 2.

2. Flippers and plunger are INVISIBLE. Draw them: flipper = tapered bat Polygon2D (radius 11
   at pivot, 7 at tip) gold #d4a017 with dark outline + pivot cap; plunger = spring/rod
   Polygon2D in the shooter lane that visibly pulls down with charge.

3. Flipper physics: current kick fires every 150 ms whenever pressed and overlapping (a held
   flipper keeps launching; no cradling) and always shoots the same fixed direction (no aiming).
   Replace with: kick only while the bat is actually swinging up (angle not yet at target);
   ball velocity = tangential velocity of the bat at the contact point
   (ω × r, perpendicular to the bat, ω = SWING_SPEED) × 1.15, plus the ball's component
   along the bat preserved; at most one kick per swing per ball. Held flipper = solid static
   surface (ball can be cradled). Keep A3 flipper test (< −800 when hit in outer half).

4. Layout — use EXACTLY these coordinates (logical px) and remove what they replace:
   - Flippers: left pivot (214,1110), right pivot (440,1110), LENGTH 96, rest angle 28° down,
     active 28° up. (Tip-to-tip free gap ≈34 px: the ball must drain through the centre.)
   - Inlane guides (walls, thickness 16): left (20,1000)→(200,1100); right (634,1000)→(454,1100).
     Remove the old bands (22,1200)→(300,1235), (698,1200)→(420,1235), (30,975)→(115,1075).
   - Side walls inner faces x=20 and x=634 (divider = left edge of shooter lane, from y 430 to
     the lane floor), outer right wall x=700. Keep top arc (centre (360,420), r 340) spanning the
     whole width, and the shooter lane floor.
   - Slingshots (triangles, kicking face = the A–C edge, kick along its outward normal
     ≈ 650 px/s): left A(75,905) B(75,1015) C(165,1062); right A(579,905) B(579,1015) C(489,1062).
     Styled: stone body, gold rubber line on the kicking face that flashes on hit.
   - Pop bumpers (radius 30, bumper.png scaled to 64 px): (240,430), (420,430), (330,525).
   - Remove the idol.png sprite at (330,250) (the playfield art already has a painted idol at
     ≈(360,240); T2 puts the scoop in front of it). Keep other decor only in dead areas
     (never over playable lanes).
   - Drain Area2D: y 1215..1280, x 20..634.
   - Keep free for T2/T3: x 20..95 y 300..780 (left orbit), x 560..634 y 460..700 (INDY bank),
     y 110..200 near top (lanes), (360,300) scoop, x 160..500 y 580..800 (slot).

5. physics_smoke.gd additions: (a) ball released at (327,1000) with idle flippers crosses
   y=1200 with 300<x<355 (drains through the centre gap); (b) ball resting on the held-up left
   flipper for 2 s stays on it (speed < 300, not launched); (c) ball released in the left inlane
   (45,950) reaches the left flipper (touches it) instead of draining at the side.

Verification: same four commands as the brief, all green; also run the game once windowed if a
display is available is NOT required. Update the report (append a "Correction 1" section).
