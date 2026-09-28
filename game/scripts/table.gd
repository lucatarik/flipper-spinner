extends Node2D
## Main scene controller. Owns the Rules instance, wires physics node signals to
## Rules events, spawns balls, drives the HUD, sound and lighting.

signal switch_hit(kind: String)

const RulesScript = preload("res://scripts/rules.gd")
const BallScene = preload("res://scenes/ball.tscn")
const FlipperScript = preload("res://scripts/flipper.gd")
const PlungerScript = preload("res://scripts/plunger.gd")
const BumperScript = preload("res://scripts/bumper.gd")
const SideBumperScript = preload("res://scripts/side_bumper.gd")
const SlingshotScript = preload("res://scripts/slingshot.gd")
const ScoopScript = preload("res://scripts/scoop.gd")
const BankScript = preload("res://scripts/drop_target_bank.gd")
const LaneSensorScript = preload("res://scripts/lane_sensor.gd")
const OrbitScript = preload("res://scripts/orbit.gd")
const LightsScript = preload("res://scripts/lights.gd")
const SlotScene = preload("res://scenes/slot.tscn")
const RampScript = preload("res://scripts/ramp.gd")
const MiniBumperScript = preload("res://scripts/mini_bumper.gd")
const KickbackHoleScript = preload("res://scripts/kickback_hole.gd")
const RetroArrowsScript = preload("res://scripts/retro_arrows.gd")
const SoftBonusScript = preload("res://scripts/floating_bonus.gd")
const LayoutEditorScript = preload("res://scripts/layout_editor.gd")

const TEX_PLAYFIELD = preload("res://assets/playfield.jpg")
const TEX_BUMPER = preload("res://assets/sprites/bumper.png")
const TEX_TORCH = preload("res://assets/sprites/torch.png")
const TEX_SKULL = preload("res://assets/sprites/skull.png")
const TEX_COBRA = preload("res://assets/sprites/cobra.png")

const HS_PATH := HighScore.DEFAULT_PATH

const CENTER := Vector2(360.0, 420.0)
const TOP_RADIUS := 340.0
const WALL_THICK := 24.0
const DIVIDER_THICK := 14.0
const LEFT_WALL_INNER := 20.0
const DIVIDER_INNER := 634.0
const OUTER_RIGHT_INNER := 700.0
## Lowered 25px (1215->1240, user request: "abbassa anche la dropzone") to
## follow the main flippers lowering further down below — keeps the same kind
## of gap between the flipper tips and the drain instead of squeezing it.
const DRAIN_TOP := 1240.0
const LANE_FLOOR_Y := 1175.0
const SERVE_POS := Vector2(674.0, 1135.0)

const STUCK_SPEED := 30.0
const STUCK_SECONDS := 2.0
const STUCK_MAX_NUDGES := 3
const STUCK_NUDGE_SPEED := 350.0

## Positions baked in from the user's layout-editor session (was
## game/layout_overrides.json, now removed — these ARE the source of truth).
const BUMPER_POSITIONS := [Vector2(257, 376), Vector2(487, 393), Vector2(361, 440)]
const POP_BUMPER_POSITIONS := [Vector2(248, 226), Vector2(502, 250)]
const SIDE_BUMPERS := [
	{"pos": Vector2(70, 760), "normal": Vector2.RIGHT},
	{"pos": Vector2(619, 821), "normal": Vector2.LEFT},
]
## Lowered further (user request: "di sotto facciamo al 5%", i.e. 5% from the
## bottom screen edge). Screen height is 1280, so 5% up from the bottom is
## y=1216 — that's where the flipper TIP sits at rest (pivot + LENGTH*sin(28°)
## = pivot + 54.09), giving pivot_y = 1216 - 54.09 ≈ 1162. DRAIN_TOP was moved
## to 1240 in lockstep (see above) so there's still a ~24px gap between the
## tips and the drain at rest — tighter than the previous ~31px but still
## clear of the drain sensor. Both main flippers are draggable in the layout
## editor (E) too, so nudge further yourself if you want more/less clearance.
const FLIPPER_LEFT_PIVOT := Vector2(214, 1162)
const FLIPPER_RIGHT_PIVOT := Vector2(440, 1162)
const PLUNGER_POS := Vector2(674, 1150)

## Extra "wing" flipper pair, higher up in the open lanes either side of the slot
## pit, fired together with the main flipper on their side (same buttons) so a
## weak shot in the middle can be batted back up toward the bumpers/ramps instead
## of draining straight down. Pivots sit just above the slingshots, below where
## both ramps' rails end (R1's mouth is (528,812) on the right, its return rail
## curves away from x112 toward the wall below y755 on the left) so the ramp
## artwork (drawn above the bumpers) never covers them. WING_LEFT_PIVOT is pulled
## in as close to the ramp's return rail as clearance allows (~24px margin) so it
## reads as anchored to the wall/ramp instead of floating in open space.
const WING_FLIPPER_SCALE := 0.75
const WING_LEFT_PIVOT := Vector2(140, 870)
const WING_RIGHT_PIVOT := Vector2(535, 870)

## A third, left-side wing flipper further up the table (also fires with
## flip_left), clear of the pop bumper at (150,330), the scoop and the top
## lanes. Same size as the lower pair (WING_FLIPPER_SCALE, user request — was
## smaller); if it now clips something in that tighter upper pocket, nudge it
## with the layout editor (E) rather than shrinking it back down.
## Raised 30px (user request: "il flipper in alto può essere alzato fino al 3%
## dal bordo superiore dello schermo"). Literal 3% of the 1280-tall screen is
## y=38.4 from the top — geometrically impossible anywhere on this table: the
## playfield's curved top wall is a semicircle (CENTER, TOP_RADIUS=340) whose
## highest point is y=80 at dead centre (x=360) and y≈138 at this flipper's
## x=170, so even the best-case spot on the whole table is only ~6.25% from
## the top edge, let alone this off-centre one. 250->220 is close to the
## practical ceiling once the wing's swept arm (~86px at WING_FLIPPER_SCALE)
## is kept clear of that curved wall — it's draggable in the layout editor (E)
## if you want to push it further and accept some risk of clipping the arc.
const WING_TOP_LEFT_PIVOT := Vector2(170, 220)

## A right-side wing flipper hugging the right wall (the shooter-lane divider,
## inner face x=634) at about slot height, in the pocket between the INDY
## target bank above (ends y=674) and ramp R1's rail column (x~508-548 in this
## band) to its left. Also fires with flip_right. Same size caveat as above.
const WING_RIGHT_WALL_PIVOT := Vector2(620, 745)

## Small bumpers that patrol back and forth over the (non-colliding) slot pit.
const MINI_BUMPERS := [
	{"a": Vector2(210, 620), "b": Vector2(150, 393), "speed": 70.0},
	{"a": Vector2(510, 495), "b": Vector2(512, 539), "speed": 85.0},
]

## "Vortex" sucker holes: open pits over the same non-colliding slot pit, clear of
## both mini-bumper tracks and the wing flippers.
const VORTEX_HOLES := [Vector2(142, 504), Vector2(491, 471)]

## "Soft" bonus pickups: no collision (the ball rolls straight through), appear
## one at a time at a random spot from this list, grant a small bonus on touch
## or expire after a while.
const SOFT_BONUS_SPOTS := [
	Vector2(303, 104), Vector2(480, 387),
	Vector2(209, 499), Vector2(276, 468),
	Vector2(553, 391),
	Vector2(294, 897), Vector2(390, 858),
]
const SOFT_BONUS_MIN_DELAY := 7.0
const SOFT_BONUS_MAX_DELAY := 14.0

## TAB cheat: zoomed-in follow camera (150%, user request), V cheat: half gravity.
const ZOOM_FOLLOW := Vector2(1.5, 1.5)
const ZOOM_NORMAL := Vector2(1.0, 1.0)
const CAMERA_FOLLOW_LERP := 6.0
const GRAVITY_HALF_FACTOR := 0.5

const SLING_LEFT_POLY := [Vector2(75, 880), Vector2(75, 990), Vector2(165, 1037)]
const SLING_LEFT_KICK := Vector2(0.868, -0.497)
const SLING_RIGHT_POLY := [Vector2(579, 880), Vector2(579, 990), Vector2(489, 1037)]
const SLING_RIGHT_KICK := Vector2(-0.868, -0.497)

## D2 ramp centrelines (logical px). Arcs are approximated by short chamfer points.
## R1 redesigned into a figure-8 around the idol scoop (user request: "quella
## sotto deve fare un disegno ad 8... intorno all'oracolo"). Two ~90px-radius
## loops pinched at SCOOP_POS (360,300): the right loop (centre 445,300) is
## swept over its TOP half, the left loop (centre 275,300) over its BOTTOM
## half, so the two arcs cross once right at the scoop, reading as a proper
## "∞" when drawn — a real figure-8, not just a single sweep like before. The
## loops pass close over 2 of the 3 round bumpers and both pop bumpers; that's
## intentional (wireform rails arching directly over other playfield elements
## is the whole point of the style, same as the reference Indiana-Jones ramp
## photo) since the rail Line2D nodes draw at z_index 7-8, well above bumpers.
## Mouth/rise and the return tail down to the left inlane are unchanged.
const R1_NAME := "TEMPLE RAMP"
const R1_POINTS := [
	Vector2(528, 812), Vector2(528, 700), Vector2(528, 610),
	Vector2(532, 480), Vector2(535, 300),
	Vector2(523, 255), Vector2(490, 222), Vector2(445, 210), Vector2(400, 222), Vector2(367, 255), Vector2(355, 300),
	Vector2(365, 300), Vector2(353, 345), Vector2(320, 378), Vector2(275, 390), Vector2(230, 378), Vector2(197, 345), Vector2(185, 300),
	Vector2(150, 340), Vector2(118, 430), Vector2(106, 520), Vector2(112, 590),
	Vector2(112, 700), Vector2(112, 755),
	Vector2(108, 790), Vector2(101, 825), Vector2(92, 858), Vector2(81, 888),
	Vector2(69, 910), Vector2(55, 930),
]
const R1_COMMIT := Vector2(528, 640)
const R1_EXIT_DIR := Vector2(0, 1)
## R2 redesigned as a half-arch that then snakes back down and closes near the
## centre (user request: "quella superiore deve fare mezza arcata per poi
## chiudersi al centro, stile serpente", plus the earlier "fai scendere la
## palla quasi al centro del flipper"). Rise unchanged; then a single arch
## sweeps right-to-left across the top of the table (mirroring R1's mouth-side
## rise, staying clear of the scoop/R1 loops which own that space); a short
## snake wiggles back toward the right, then a straight run descends on the
## RIGHT side of the slot window (window spans world x 130-530, y 566-806;
## this column sits at x~540-565, a clean ~10-35px outside it, and roughly
## parallel to R1's own rise column at x~528-535 further left — two ramps
## running side by side down the right side is already this table's style).
## Final points curve left to land at x=327, the midpoint between the two
## main flipper pivots (214, 440), so the ball drops "almost dead centre
## between the flippers" from y=860 — comfortable fall height for a catch.
const R2_NAME := "IDOL RAMP"
const R2_POINTS := [
	Vector2(590, 452), Vector2(590, 340), Vector2(588, 300),
	Vector2(582, 245), Vector2(560, 190), Vector2(520, 148), Vector2(465, 118),
	Vector2(400, 103), Vector2(335, 110), Vector2(280, 133), Vector2(240, 172), Vector2(212, 220),
	Vector2(260, 270), Vector2(300, 235), Vector2(345, 275), Vector2(320, 330),
	Vector2(370, 360), Vector2(410, 410), Vector2(460, 440), Vector2(500, 490), Vector2(540, 530),
	Vector2(560, 570), Vector2(565, 650), Vector2(560, 740), Vector2(555, 810),
	Vector2(450, 850), Vector2(380, 870), Vector2(327, 860),
]
const R2_COMMIT := Vector2(590, 380)
const R2_EXIT_DIR := Vector2(0, 1)

const SCOOP_POS := Vector2(360, 300)
const TARGET_X := 610.0
const TARGET_YS := [500.0, 558.0, 616.0, 674.0]
const LANE_POST_XS := [270.0, 330.0, 390.0, 450.0]
const LANE_SENSOR_XS := [300.0, 360.0, 420.0]
const LANE_TOP := 115.0
const LANE_BOTTOM := 190.0

const STONE := Color("#6b6b6b")
const GOLD := Color("#d4a017")
const JUNGLE := Color("#1b3a2a")

var rules
var hud
var lights

var left_flipper
var right_flipper
var wing_left_flipper
var wing_right_flipper
var wing_top_left_flipper
var wing_right_wall_flipper
var plunger
var scoop
var target_bank
var orbit
var lane_sensors: Array = []
var slot
var ramps: Array = []
var pop_bumpers: Array = []
var side_bumpers: Array = []
var new_bumpers: Array = []
var mini_bumpers: Array = []
var bonus_bumper_nodes: Array = []
var vortex_holes: Array = []

var _walls: StaticBody2D
var _drain_area: Area2D
var _was_charging := false
var _left_down := false
var _right_down := false
var _touch_count := 0
var _stuck := {}
var _high_score := 0

var _mb_queue := 0
var _mb_timer := 0.0
var _add_queue := 0
var _add_timer := 0.0
var _ball_save_time := 0.0
var _music_track := ""
var _sfx: Node = null
var _slot_ready := false
var _slot_active := false

var _ball_seq := 0
var _cam_follow := false
var _gravity_normal := 1400.0
var _gravity_half := false
var _soft_bonus: Node = null
var _soft_bonus_timer := 4.0
var _soft_spot_markers: Array = []
var _layout_entries: Array = []
var _layout_editor

func _ready() -> void:
	_sfx = get_node_or_null("/root/Sfx")
	_gravity_normal = ProjectSettings.get_setting("physics/2d/default_gravity", 1400.0)
	_high_score = HighScore.load_score(HS_PATH)
	rules = RulesScript.new()
	rules.high_score = _high_score
	hud = get_node_or_null("HUD")
	_connect_rules()
	_build_background()
	_build_decor()
	_build_walls()
	_build_lane_gate()
	_build_bumpers()
	_build_slingshots()
	_build_flippers()
	_build_plunger()
	_build_drain()
	_build_features()
	_build_slot()
	_build_vortex_holes()
	_build_soft_spot_markers()
	_build_ramps()
	_build_lights()
	_build_layout_editor()
	if hud and hud.has_method("setup"):
		hud.setup(rules)
	if hud:
		if hud.has_signal("music_toggle_pressed"):
			hud.music_toggle_pressed.connect(_toggle_music)
		if hud.has_method("set_music_enabled") and _sfx:
			hud.set_music_enabled(_sfx.is_music_enabled())

func _sfx_play(sfx_name: String, pitch := 1.0, db := 0.0) -> void:
	if _sfx:
		_sfx.play(sfx_name, pitch, db)

func _sfx_loop_start(sfx_name: String) -> void:
	if _sfx:
		_sfx.loop_start(sfx_name)

func _sfx_loop_stop(sfx_name: String) -> void:
	if _sfx:
		_sfx.loop_stop(sfx_name)

func _sfx_music(track: String) -> void:
	if _sfx:
		_sfx.music(track)

func _connect_rules() -> void:
	rules.request_serve_ball.connect(_on_request_serve_ball)
	rules.request_multiball.connect(_on_request_multiball)
	rules.targets_reset.connect(_on_targets_reset)
	rules.ball_changed.connect(_on_ball_changed)
	rules.game_over.connect(_on_game_over)
	rules.message.connect(_on_rules_message)
	rules.lanes_changed.connect(_on_lanes_changed)
	rules.mode_changed.connect(_on_mode_changed)
	rules.request_spot_target.connect(_on_request_spot_target)
	rules.request_add_ball.connect(_on_request_add_ball)
	rules.playfield_mult_changed.connect(_on_playfield_mult_changed)
	rules.tilted_changed.connect(_on_tilted)
	rules.state_changed.connect(_on_state_changed)
	rules.bonus_bumpers_changed.connect(_on_bonus_bumpers_changed)

func _physics_process(delta: float) -> void:
	rules.tick(delta)
	var start := Input.is_action_just_pressed("start")
	if start and rules.state != RulesScript.State.PLAYING:
		_sfx_play("game_start")
		rules.start_game()

	if Input.is_action_just_pressed("music_toggle"):
		_toggle_music()

	if Input.is_action_just_pressed("nudge_left"):
		_do_nudge(Vector2(1.0, 0.0))
	if Input.is_action_just_pressed("nudge_right"):
		_do_nudge(Vector2(-1.0, 0.0))
	if Input.is_action_just_pressed("nudge_up"):
		_do_nudge(Vector2(0.0, -1.0))

	if Input.is_action_just_pressed("cheat_multiball"):
		rules.cheat_multiball()
	if Input.is_action_just_pressed("cheat_free_ball"):
		rules.add_ball(1)
	if Input.is_action_just_pressed("cheat_extra_ball"):
		rules.cheat_add_extra_ball()
	if Input.is_action_just_pressed("cheat_reset_ball"):
		_cheat_reset_ball()
	if Input.is_action_just_pressed("cheat_gravity"):
		_toggle_gravity()
	if Input.is_action_just_pressed("cheat_zoom_follow"):
		_toggle_zoom_follow()

	var dead: bool = rules.tilted
	var left := Input.is_action_pressed("flip_left") and not dead
	if left != _left_down:
		_left_down = left
		left_flipper.set_pressed(left)
		if wing_left_flipper:
			wing_left_flipper.set_pressed(left)
		if wing_top_left_flipper:
			wing_top_left_flipper.set_pressed(left)
		if left:
			_sfx_play("flipper")
			rules.flip_lanes(-1)
	var right := Input.is_action_pressed("flip_right") and not dead
	if right != _right_down:
		_right_down = right
		right_flipper.set_pressed(right)
		if wing_right_flipper:
			wing_right_flipper.set_pressed(right)
		if wing_right_wall_flipper:
			wing_right_wall_flipper.set_pressed(right)
		if right:
			_sfx_play("flipper")
			rules.flip_lanes(1)
	var charging := Input.is_action_pressed("plunger")
	if charging != _was_charging:
		_was_charging = charging
		var release_charge: float = plunger.charge
		plunger.set_charging(charging)
		if charging:
			_sfx_loop_start("plunger_charge")
		else:
			_sfx_loop_stop("plunger_charge")
			_sfx_play("launch", 0.6 + 0.6 * release_charge)

	_update_multiball(delta)
	_update_add_ball(delta)
	_update_ball_save(delta)
	_update_slot()
	_update_music()
	_update_soft_bonus(delta)
	_update_camera_follow(delta)
	_check_balls(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_count += 1
			if _touch_count >= 2:
				_do_nudge(Vector2(0.0, -1.0))
				return
		var vp := get_viewport().get_visible_rect().size
		var p: Vector2 = event.position / vp * Vector2(720, 1280)
		if event.pressed:
			if p.x > 720 - 120 and p.y > 1280 - 200:
				plunger.set_charging(true)
			elif p.x < 360:
				left_flipper.set_pressed(true)
				if wing_left_flipper:
					wing_left_flipper.set_pressed(true)
				if wing_top_left_flipper:
					wing_top_left_flipper.set_pressed(true)
			else:
				right_flipper.set_pressed(true)
				if wing_right_flipper:
					wing_right_flipper.set_pressed(true)
				if wing_right_wall_flipper:
					wing_right_wall_flipper.set_pressed(true)
		else:
			plunger.set_charging(false)
			left_flipper.set_pressed(false)
			right_flipper.set_pressed(false)
			if wing_left_flipper:
				wing_left_flipper.set_pressed(false)
			if wing_right_flipper:
				wing_right_flipper.set_pressed(false)
			if wing_top_left_flipper:
				wing_top_left_flipper.set_pressed(false)
			if wing_right_wall_flipper:
				wing_right_wall_flipper.set_pressed(false)
			_touch_count = 0

## C4: table nudge. Rules decides whether the meter tolerates it; the table then
## shoves every ball in play, shakes and plays the thump.
func _do_nudge(dir: Vector2) -> void:
	rules.nudge()
	if rules.tilted:
		return
	_sfx_play("nudge")
	for ball in get_tree().get_nodes_in_group("balls"):
		if not is_instance_valid(ball):
			continue
		var imp := dir.normalized() * (260.0 if dir.y < 0.0 else 180.0)
		imp += Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		ball.linear_velocity += imp
	if lights:
		lights.shake(6.0, 0.15)

## Cheat (R): rescue every ball on the field right now (stuck-ball fix). Frees
## the ball nodes directly (marked "drained" so `_check_balls` leaves them
## alone this frame) without going through `_drain_ball`, so no drain event
## fires and no life is lost; Rules then serves a fresh ball as usual.
func _cheat_reset_ball() -> void:
	for ball in get_tree().get_nodes_in_group("balls"):
		if not is_instance_valid(ball):
			continue
		ball.set_meta("drained", true)
		ball.queue_free()
	_stuck.clear()
	rules.cheat_reset_ball()

## Cheat (V): toggle gravity between 50% and 100% by changing the live physics
## space directly (works instantly, no project-settings reload needed).
func _toggle_gravity() -> void:
	_gravity_half = not _gravity_half
	var g: float = _gravity_normal * (GRAVITY_HALF_FACTOR if _gravity_half else 1.0)
	PhysicsServer2D.area_set_param(get_world_2d().space, PhysicsServer2D.AREA_PARAM_GRAVITY, g)
	rules.message.emit("GRAVITY %d%%" % (50 if _gravity_half else 100), 1.5)

## Cheat (TAB): toggle a zoomed-in camera that follows the oldest ball still in
## play (see `_find_follow_ball`). Toggling off snaps back to the normal
## full-table view.
func _toggle_zoom_follow() -> void:
	_cam_follow = not _cam_follow
	if lights == null:
		return
	lights.set_zoom(ZOOM_FOLLOW if _cam_follow else ZOOM_NORMAL)
	if not _cam_follow:
		lights.set_camera_position(LightsScript.HOME_CAMERA_POS)

func _update_camera_follow(delta: float) -> void:
	if not _cam_follow or lights == null:
		return
	var target := _find_follow_ball()
	if target == null:
		return
	var cur: Vector2 = lights.get_camera_position()
	lights.set_camera_position(cur.lerp(target.global_position, clampf(delta * CAMERA_FOLLOW_LERP, 0.0, 1.0)))

## The ball to follow is the oldest still-alive one (lowest spawn_seq), so a
## multiball camera keeps tracking the first ball that entered play even as
## later ones join or drain.
func _find_follow_ball() -> Node:
	var best: Node = null
	var best_seq := 2147483647
	for ball in get_tree().get_nodes_in_group("balls"):
		if not is_instance_valid(ball) or ball.get_meta("drained", false):
			continue
		var seq: int = ball.get_meta("spawn_seq", 2147483647)
		if seq < best_seq:
			best_seq = seq
			best = ball
	return best

func spawn_ball(pos: Vector2, vel := Vector2.ZERO) -> RigidBody2D:
	var ball := BallScene.instantiate()
	ball.position = pos
	add_child(ball)
	ball.linear_velocity = vel
	_ball_seq += 1
	ball.set_meta("spawn_seq", _ball_seq)
	return ball

func _on_request_serve_ball() -> void:
	if left_flipper:
		left_flipper.set_disabled(false)
	if right_flipper:
		right_flipper.set_disabled(false)
	if wing_left_flipper:
		wing_left_flipper.set_disabled(false)
	if wing_right_flipper:
		wing_right_flipper.set_disabled(false)
	if wing_top_left_flipper:
		wing_top_left_flipper.set_disabled(false)
	if wing_right_wall_flipper:
		wing_right_wall_flipper.set_disabled(false)
	if lights:
		lights.set_tilt(false)
	_slot_ready = false
	spawn_ball(SERVE_POS, Vector2.ZERO)
	rules.on_event("ball_added")

func _on_request_multiball(extra_balls: int) -> void:
	_mb_queue += extra_balls
	_mb_timer = 0.0

func _update_multiball(delta: float) -> void:
	if _mb_queue <= 0:
		return
	_mb_timer -= delta
	if _mb_timer <= 0.0:
		_mb_timer = 0.4
		_mb_queue -= 1
		_spawn_from_scoop()

func _spawn_from_scoop() -> void:
	var ang := deg_to_rad(randf_range(15.0, 30.0))
	var dir := Vector2(-sin(ang), cos(ang))
	var b := spawn_ball(SCOOP_POS + Vector2(0, 40), dir * 900.0)
	b.set_meta("spawn_grace", 1)
	b.linear_velocity += Vector2(randf_range(-60.0, 60.0), 0.0)
	rules.on_event("ball_added")

func _on_targets_reset() -> void:
	if target_bank:
		target_bank.raise_all()
		_refresh_target_lights()
	_sfx_play("target_bank")
	if lights:
		lights.flash()

func _on_ball_changed(_ball: int, _total: int) -> void:
	if slot:
		slot.reset_bet()
	_update_music()

func _on_game_over(final_score: int, _is_high: bool) -> void:
	_sfx_play("game_over")
	if lights:
		lights.gi_flicker()
	if final_score >= _high_score:
		_high_score = final_score
		HighScore.save_score(_high_score, HS_PATH)

func _on_rules_message(text: String, _seconds: float) -> void:
	if text.begins_with("BALL SAVED"):
		_sfx_play("ball_save")
	elif text.begins_with("LOCK LIT"):
		_sfx_play("target_bank")
		if lights:
			lights.set_lock(true)
	elif text.begins_with("BALL LOCKED"):
		_sfx_play("lock")
		if lights:
			lights.set_lock(false)
	elif text.begins_with("JACKPOT"):
		_sfx_play("jackpot")
		if lights:
			lights.flash()
			lights.shake()
	elif text.begins_with("ETERNAL LIFE"):
		_sfx_play("multiball")
		if lights:
			lights.flash()
			lights.shake()
			lights.set_lock(false)
	elif text.begins_with("COMBO"):
		_sfx_play("combo")
	elif text.ends_with(" START"):
		_sfx_play("mode_start")
	elif text.ends_with(" COMPLETE"):
		_sfx_play("mode_complete")

func _on_lanes_changed(lit: Array) -> void:
	if lights:
		lights.set_lanes(lit)

func _on_mode_changed(mode_name: String, _time_left: float, _progress: int, _goal: int) -> void:
	if lights:
		lights.set_mode(mode_name != "")

func _refresh_target_lights() -> void:
	if lights and target_bank:
		lights.set_targets(target_bank.standing())

func _update_ball_save(delta: float) -> void:
	if _ball_save_time > 0.0:
		_ball_save_time = max(_ball_save_time - delta, 0.0)
	if lights:
		lights.set_ball_save(_ball_save_time > 0.0)

func _update_music() -> void:
	var track := "desert_mystic"
	if rules.state == RulesScript.State.PLAYING:
		if rules.multiball or (slot and slot.free_spins_active()):
			track = "desert_mystic3"
		else:
			track = "camel_groove"
	if track != _music_track:
		_music_track = track
		_sfx_music(track)

## D3: the slot spins only while a served ball is actually in play, never while the
## only ball waits in the shooter lane and never while tilted. In ATTRACT/GAME_OVER
## with no ball it idles still (no demo spin).
func _update_slot() -> void:
	if rules.balls_in_play <= 0 or rules.state != RulesScript.State.PLAYING:
		_slot_ready = false
	var active: bool = rules.state == RulesScript.State.PLAYING \
		and rules.balls_in_play > 0 and _slot_ready and not rules.tilted
	if active != _slot_active:
		_slot_active = active
		if slot:
			slot.set_active(active)

func _toggle_music() -> void:
	if _sfx == null:
		return
	var on: bool = not _sfx.is_music_enabled()
	_sfx.set_music_enabled(on)
	if hud and hud.has_method("set_music_enabled"):
		hud.set_music_enabled(on)
	rules.message.emit("MUSIC ON" if on else "MUSIC OFF", 1.5)

func _on_bumper_hit(bonus_index: int = -1) -> void:
	switch_hit.emit("bumper")
	_sfx_play("bumper", randf_range(0.95, 1.06))
	var data := {}
	if bonus_index >= 0:
		data["bonus_index"] = bonus_index
	rules.on_event("bumper", data)

func _on_bumper_exploded() -> void:
	switch_hit.emit("bumper_explode")
	_sfx_play("jackpot")
	rules.on_event("bumper_explode")
	if lights:
		lights.flash()
		lights.shake()

func _on_bonus_bumpers_changed(lit: Array) -> void:
	if lights:
		lights.set_bonus_bumpers(lit)
	for i in bonus_bumper_nodes.size():
		var on: bool = i < lit.size() and bool(lit[i])
		if bonus_bumper_nodes[i].has_method("set_lit"):
			bonus_bumper_nodes[i].set_lit(on)

func _on_sling_hit() -> void:
	switch_hit.emit("sling")
	_sfx_play("sling")
	rules.on_event("sling")

func _on_lane_hit(index: int) -> void:
	switch_hit.emit("lane")
	_sfx_play("lane")
	rules.on_event("lane", {"index": index})

func _on_target_dropped(index: int) -> void:
	switch_hit.emit("target")
	_sfx_play("target")
	rules.on_event("target", {"index": index})
	_refresh_target_lights()

func _on_orbit_scored() -> void:
	switch_hit.emit("orbit")
	_sfx_play("orbit")
	rules.on_event("orbit", {"side": "left"})

func _on_scoop_captured() -> void:
	switch_hit.emit("scoop")
	_sfx_play("scoop")
	rules.on_event("scoop")

func _on_vortex_captured() -> void:
	switch_hit.emit("vortex")
	_sfx_play("scoop")
	rules.on_event("vortex")

## One soft bonus pickup at a time: while PLAYING, count down to the next
## spawn whenever none is alive (its own lifetime timer or a ball touching it
## makes it free itself, which we notice next frame via is_instance_valid).
func _update_soft_bonus(delta: float) -> void:
	if rules.state != RulesScript.State.PLAYING:
		if _soft_bonus and is_instance_valid(_soft_bonus):
			_soft_bonus.queue_free()
		_soft_bonus = null
		return
	if _soft_bonus != null and not is_instance_valid(_soft_bonus):
		_soft_bonus = null
		_soft_bonus_timer = randf_range(SOFT_BONUS_MIN_DELAY, SOFT_BONUS_MAX_DELAY)
	if _soft_bonus == null:
		_soft_bonus_timer -= delta
		if _soft_bonus_timer <= 0.0:
			_spawn_soft_bonus()

func _spawn_soft_bonus() -> void:
	var marker: Node2D = _soft_spot_markers[randi() % _soft_spot_markers.size()]
	var b := SoftBonusScript.new()
	b.position = marker.position
	add_child(b)
	b.collected.connect(_on_soft_bonus_collected)
	_soft_bonus = b

## Invisible markers, one per SOFT_BONUS_SPOTS entry: `_spawn_soft_bonus` reads
## their *current* position (draggable in the layout editor), not the literal
## const, so edits to soft-bonus spawn spots persist without touching this file.
func _build_soft_spot_markers() -> void:
	for pos in SOFT_BONUS_SPOTS:
		var m := Node2D.new()
		m.position = pos
		add_child(m)
		_soft_spot_markers.append(m)

func _on_soft_bonus_collected(kind: String) -> void:
	switch_hit.emit("soft_bonus")
	_sfx_play("coin")
	rules.on_event("soft_bonus", {"kind": kind})

func _check_balls(delta: float) -> void:
	for ball in get_tree().get_nodes_in_group("balls"):
		if not is_instance_valid(ball):
			continue
		if ball.get_meta("drained", false):
			continue
		var p: Vector2 = ball.global_position
		if p.x < -50.0 or p.x > 770.0 or p.y < -50.0 or p.y > 1330.0:
			_drain_ball(ball)
			continue
		var id := ball.get_instance_id()
		var in_lane: bool = in_lane_for_ball(ball)
		if in_lane:
			ball.set_meta("was_in_lane", true)
		elif ball.get_meta("was_in_lane", false) and not ball.get_meta("left_lane", false):
			ball.set_meta("left_lane", true)
			rules.on_event("plunger_exit")
			_slot_ready = true
			if not rules.multiball:
				_ball_save_time = RulesScript.BALL_SAVE_SECONDS
		_ball_is_stuck(ball, delta, in_lane)

## D1 stuck-ball safety: a nearly stationary ball outside the scoop, shooter lane
## and ramps gets a 350 px/s up-and-away nudge every 2 s; after 3 failed nudges the
## ball is rescued into the idol scoop (hold + kick, no score). Returns true when
## the ball was nudged/rescued so the caller can skip further handling.
func _ball_is_stuck(ball: Node, delta: float, in_lane: bool) -> bool:
	if in_lane or scoop.holding or ball.get_meta("on_ramp", false) or ball.get_meta("held_by_hole", false):
		_stuck.erase(ball.get_instance_id())
		return false
	if ball.linear_velocity.length() >= STUCK_SPEED:
		_stuck.erase(ball.get_instance_id())
		return false
	var id := ball.get_instance_id()
	var rec: Dictionary = _stuck.get(id, {"t": 0.0, "n": 0})
	rec["t"] = float(rec["t"]) + delta
	if float(rec["t"]) < STUCK_SECONDS:
		_stuck[id] = rec
		return false
	rec["t"] = 0.0
	var p: Vector2 = ball.global_position
	if int(rec["n"]) < STUCK_MAX_NUDGES:
		rec["n"] = int(rec["n"]) + 1
		_stuck[id] = rec
		var dir := Vector2(0.6, -1.0) if p.x < 327.0 else Vector2(-0.6, -1.0)
		ball.linear_velocity += dir.normalized() * STUCK_NUDGE_SPEED
		if lights:
			lights.shake(4.0, 0.12)
		return true
	_stuck.erase(id)
	_rescue_ball(ball)
	return true

func _rescue_ball(ball: Node) -> void:
	if scoop and not scoop.holding:
		scoop.rescue(ball)

## Freshly spawned balls start at the idol scoop: keep the shooter-lane rules
## (plunger_exit / stuck detection) off them until they physically cross into the
## lane, otherwise a new ball at x≈360 would be treated as "was in lane".
func in_lane_for_ball(ball: Node) -> bool:
	if ball.get_meta("spawn_grace", 0) == 1:
		return false
	var p: Vector2 = ball.global_position
	return p.x > 640.0 and p.y > 400.0

func _drain_ball(ball: Node) -> void:
	if not is_instance_valid(ball) or ball.get_meta("drained", false):
		return
	ball.set_meta("drained", true)
	if lights:
		lights.gi_flicker()
	_sfx_play("drain")
	rules.on_event("drain")
	ball.queue_free()

func _on_drain_area_body(body: Node) -> void:
	if body.is_in_group("balls"):
		_drain_ball.call_deferred(body)

# --- scene construction -----------------------------------------------------

func _build_background() -> void:
	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.texture = TEX_PLAYFIELD
	bg.centered = false
	add_child(bg)

func _build_decor() -> void:
	_add_sprite(TEX_TORCH, Vector2(115, 858), 0.24)
	_add_sprite(TEX_TORCH, Vector2(545, 858), 0.24)
	_add_sprite(TEX_SKULL, Vector2(42, 1160), 0.26)
	_add_sprite(TEX_COBRA, Vector2(42, 1080), 0.22)

func _add_sprite(tex: Texture2D, pos: Vector2, scale_factor: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.scale = Vector2(scale_factor, scale_factor)
	add_child(s)
	return s

func _build_walls() -> void:
	_walls = StaticBody2D.new()
	_walls.name = "Walls"
	_walls.collision_layer = 1
	_walls.collision_mask = 0
	add_child(_walls)

	_add_arc_band()
	# left side wall, inner face x=20
	_add_band(Vector2(LEFT_WALL_INNER - WALL_THICK * 0.5, 420), Vector2(LEFT_WALL_INNER - WALL_THICK * 0.5, DRAIN_TOP), WALL_THICK)
	# shooter-lane divider, inner (playfield) face x=634
	_add_band(Vector2(DIVIDER_INNER + DIVIDER_THICK * 0.5, 430), Vector2(DIVIDER_INNER + DIVIDER_THICK * 0.5, LANE_FLOOR_Y), DIVIDER_THICK)
	# outer right wall, inner face x=700
	_add_band(Vector2(OUTER_RIGHT_INNER + WALL_THICK * 0.5, 420), Vector2(OUTER_RIGHT_INNER + WALL_THICK * 0.5, DRAIN_TOP), WALL_THICK)
	# shooter-lane floor
	_add_band(Vector2(DIVIDER_INNER, LANE_FLOOR_Y), Vector2(OUTER_RIGHT_INNER, LANE_FLOOR_Y), 16.0)
	# inlane guides — extended to keep tracking the flipper pivots (user request:
	# "i muri del flipper non li hai allungati, hai spostato solo le palette").
	# End Y follows pivot_y - 30, same offset the original (unmoved) walls had
	# relative to the original pivot, now applied to FLIPPER_LEFT/RIGHT_PIVOT.y.
	_add_band(Vector2(20, 1000), Vector2(210, FLIPPER_LEFT_PIVOT.y - 30.0), 16.0)
	_add_band(Vector2(634, 1000), Vector2(444, FLIPPER_RIGHT_PIVOT.y - 30.0), 16.0)
	# top rollover lane separators
	for x in LANE_POST_XS:
		_add_band(Vector2(x, LANE_TOP), Vector2(x, LANE_BOTTOM), 10.0)

## One-way gate at the top of the shooter lane (user request): a ball launched
## up and OUT of the lane must always pass, but a ball rolling back down INTO
## the lane from the main playfield should not be able to re-enter it. This is
## exactly the standard "one-way platform" behaviour Godot already supports
## (CollisionShape2D.one_way_collision blocks only the downward/landing side,
## same as a jump-through platform) — no custom physics needed, just one thin
## shape placed where the lane meets the dome (divider ends x=634, outer wall
## x=700, both starting at y=420-430).
func _build_lane_gate() -> void:
	var gate := StaticBody2D.new()
	gate.name = "LaneGate"
	gate.collision_layer = 1
	gate.collision_mask = 0
	add_child(gate)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(OUTER_RIGHT_INNER - DIVIDER_INNER, 12.0)
	cs.shape = rect
	cs.position = Vector2((DIVIDER_INNER + OUTER_RIGHT_INNER) * 0.5, 430.0)
	cs.one_way_collision = true
	cs.one_way_collision_margin = 14.0
	gate.add_child(cs)

func _add_arc_band() -> void:
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	var steps := 18
	for i in steps + 1:
		var th := PI - PI * float(i) / float(steps)
		var dir := Vector2(cos(th), -sin(th))
		inner.append(CENTER + dir * TOP_RADIUS)
		outer.append(CENTER + dir * (TOP_RADIUS + 24.0))
	var poly := PackedVector2Array()
	poly.append_array(inner)
	for i in range(outer.size() - 1, -1, -1):
		poly.append(outer[i])
	_add_polygon(poly)

func _add_band(a: Vector2, b: Vector2, thickness: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * (thickness * 0.5)
	_add_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]))

func _add_polygon(poly: PackedVector2Array) -> void:
	var vis := Polygon2D.new()
	vis.polygon = poly
	vis.color = STONE
	_walls.add_child(vis)
	var outline := Line2D.new()
	outline.points = poly
	outline.closed = true
	outline.width = 3.0
	outline.default_color = GOLD
	_walls.add_child(outline)
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	_walls.add_child(cp)

func _build_bumpers() -> void:
	for i in BUMPER_POSITIONS.size():
		_add_pop_bumper(BUMPER_POSITIONS[i], 30.0, 64.0, Vector2(0.0, -1.0), false, i)
	for pos in POP_BUMPER_POSITIONS:
		_add_pop_bumper(pos, 26.0, 56.0, Vector2(0.0, -1.0), true)
	for cfg in SIDE_BUMPERS:
		var sb := SideBumperScript.new()
		sb.radius = 22.0
		sb.normal = cfg["normal"]
		sb.position = cfg["pos"]
		sb.set_meta("approach", cfg["normal"])
		add_child(sb)
		sb.hit.connect(_on_bumper_hit)
		side_bumpers.append(sb)
		new_bumpers.append(sb)
	_build_mini_bumpers()

## `bonus_index` (0..2) marks the 3 central jungle bumpers as the "light them all"
## bank: their hit signal is bound with their index so Rules can track which ones
## are lit; -1 (the default) means a plain bumper with no bonus-index binding.
func _add_pop_bumper(pos: Vector2, radius: float, tex_px: float, approach: Vector2, is_new: bool, bonus_index: int = -1) -> void:
	var b := BumperScript.new()
	b.radius = radius
	b.position = pos
	b.set_meta("approach", approach)
	add_child(b)
	if bonus_index >= 0:
		b.hit.connect(_on_bumper_hit.bind(bonus_index))
		bonus_bumper_nodes.append(b)
	else:
		b.hit.connect(_on_bumper_hit)
	b.exploded.connect(_on_bumper_exploded)
	pop_bumpers.append(b)
	var spr := _add_sprite(TEX_BUMPER, Vector2.ZERO, tex_px / float(TEX_BUMPER.get_width()))
	spr.reparent(b)
	spr.position = Vector2.ZERO
	if is_new:
		new_bumpers.append(b)

## Small mini bumpers that patrol back and forth over the (non-colliding) slot pit.
func _build_mini_bumpers() -> void:
	for cfg in MINI_BUMPERS:
		var mb := MiniBumperScript.new()
		mb.point_a = cfg["a"]
		mb.point_b = cfg["b"]
		mb.speed = cfg["speed"]
		mb.set_meta("approach", Vector2(0.0, -1.0))
		add_child(mb)
		mb.hit.connect(_on_bumper_hit)
		mb.exploded.connect(_on_bumper_exploded)
		mini_bumpers.append(mb)
		new_bumpers.append(mb)

func _build_vortex_holes() -> void:
	for pos in VORTEX_HOLES:
		var h := KickbackHoleScript.new()
		h.position = pos
		add_child(h)
		h.captured.connect(_on_vortex_captured)
		vortex_holes.append(h)

func _build_slingshots() -> void:
	var left_poly := PackedVector2Array(SLING_LEFT_POLY)
	var right_poly := PackedVector2Array(SLING_RIGHT_POLY)
	var sl := SlingshotScript.new()
	add_child(sl)
	sl.configure(left_poly, SLING_LEFT_KICK, left_poly[0], left_poly[2])
	sl.hit.connect(_on_sling_hit)
	var sr := SlingshotScript.new()
	add_child(sr)
	sr.configure(right_poly, SLING_RIGHT_KICK, right_poly[0], right_poly[2])
	sr.hit.connect(_on_sling_hit)

func _build_flippers() -> void:
	left_flipper = FlipperScript.new()
	left_flipper.side = "left"
	left_flipper.position = FLIPPER_LEFT_PIVOT
	add_child(left_flipper)
	right_flipper = FlipperScript.new()
	right_flipper.side = "right"
	right_flipper.position = FLIPPER_RIGHT_PIVOT
	add_child(right_flipper)

	wing_left_flipper = FlipperScript.new()
	wing_left_flipper.side = "left"
	wing_left_flipper.size_scale = WING_FLIPPER_SCALE
	wing_left_flipper.position = WING_LEFT_PIVOT
	add_child(wing_left_flipper)
	wing_right_flipper = FlipperScript.new()
	wing_right_flipper.side = "right"
	wing_right_flipper.size_scale = WING_FLIPPER_SCALE
	wing_right_flipper.position = WING_RIGHT_PIVOT
	add_child(wing_right_flipper)

	wing_top_left_flipper = FlipperScript.new()
	wing_top_left_flipper.side = "left"
	wing_top_left_flipper.size_scale = WING_FLIPPER_SCALE
	wing_top_left_flipper.position = WING_TOP_LEFT_PIVOT
	add_child(wing_top_left_flipper)

	wing_right_wall_flipper = FlipperScript.new()
	wing_right_wall_flipper.side = "right"
	wing_right_wall_flipper.size_scale = WING_FLIPPER_SCALE
	wing_right_wall_flipper.position = WING_RIGHT_WALL_PIVOT
	add_child(wing_right_wall_flipper)

	_build_retro_arrows()

## Decorative "shoot here" chevron chase in the space freed by lowering the
## main flippers (user request) — purely visual, no collision.
func _build_retro_arrows() -> void:
	var left_arrows := RetroArrowsScript.new()
	left_arrows.position = Vector2(175, 1015)
	add_child(left_arrows)
	var right_arrows := RetroArrowsScript.new()
	right_arrows.position = Vector2(475, 1015)
	add_child(right_arrows)

func _build_plunger() -> void:
	plunger = PlungerScript.new()
	plunger.position = PLUNGER_POS
	add_child(plunger)

func _build_drain() -> void:
	_drain_area = Area2D.new()
	_drain_area.name = "Drain"
	_drain_area.collision_layer = 8
	_drain_area.collision_mask = 2
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(DIVIDER_INNER - LEFT_WALL_INNER, 1280.0 - DRAIN_TOP)
	cs.shape = rect
	cs.position = Vector2((LEFT_WALL_INNER + DIVIDER_INNER) * 0.5, (DRAIN_TOP + 1280.0) * 0.5)
	_drain_area.add_child(cs)
	add_child(_drain_area)
	_drain_area.body_entered.connect(_on_drain_area_body)

func _build_features() -> void:
	scoop = ScoopScript.new()
	scoop.name = "Scoop"
	scoop.position = SCOOP_POS
	add_child(scoop)
	scoop.captured.connect(_on_scoop_captured)

	target_bank = BankScript.new()
	target_bank.name = "IndyBank"
	add_child(target_bank)
	target_bank.build(TARGET_X, TARGET_YS)
	target_bank.target_dropped.connect(_on_target_dropped)

	for i in LANE_SENSOR_XS.size():
		var s = LaneSensorScript.new()
		s.setup(i)
		s.position = Vector2(LANE_SENSOR_XS[i], (LANE_TOP + LANE_BOTTOM) * 0.5)
		add_child(s)
		s.lane_entered.connect(_on_lane_hit)
		lane_sensors.append(s)

	orbit = OrbitScript.new()
	orbit.name = "LeftOrbit"
	add_child(orbit)
	orbit.orbit_scored.connect(_on_orbit_scored)

func _build_lights() -> void:
	lights = LightsScript.new()
	lights.name = "Lights"
	add_child(lights)
	lights.setup(self)
	lights.set_lanes(rules.lanes)
	lights.set_bonus_bumpers(rules.bonus_bumpers)
	_refresh_target_lights()

## Dev tool (press E in-game): registers every element we've been hand-tuning
## by position so they can be dragged and saved to layout_overrides.json
## instead of always coming back here to edit consts. Applies any saved
## overrides on top of the just-built defaults before showing anything.
func _build_layout_editor() -> void:
	_build_layout_entries()
	_apply_layout_overrides()
	_layout_editor = LayoutEditorScript.new()
	_layout_editor.name = "LayoutEditor"
	add_child(_layout_editor)
	_layout_editor.setup(_layout_entries)

## Flippers get a much bigger click radius than everything else: the visible
## bat extends ~80-100px from the pivot, so that's the natural click target,
## not the small pivot point itself (this is why dragging them never worked
## with the generic radius used for small round objects).
const WING_CLICK_RADIUS := 60.0

func _build_layout_entries() -> void:
	_layout_entries = []
	_add_layout_pos("flipper_left", left_flipper, WING_CLICK_RADIUS)
	_add_layout_pos("flipper_right", right_flipper, WING_CLICK_RADIUS)
	_add_layout_pos("wing_left", wing_left_flipper, WING_CLICK_RADIUS)
	_add_layout_pos("wing_right", wing_right_flipper, WING_CLICK_RADIUS)
	_add_layout_pos("wing_top_left", wing_top_left_flipper, WING_CLICK_RADIUS)
	_add_layout_pos("wing_right_wall", wing_right_wall_flipper, WING_CLICK_RADIUS)
	_add_layout_pos("side_bumper_left", side_bumpers[0])
	_add_layout_pos("side_bumper_right", side_bumpers[1])
	for i in vortex_holes.size():
		_add_layout_pos("vortex_hole_%d" % i, vortex_holes[i])
	for i in pop_bumpers.size():
		_add_layout_pos("pop_bumper_%d" % i, pop_bumpers[i])
	for i in mini_bumpers.size():
		_add_layout_field("mini_bumper_%d_a" % i, mini_bumpers[i], "point_a")
		_add_layout_field("mini_bumper_%d_b" % i, mini_bumpers[i], "point_b")
	for i in _soft_spot_markers.size():
		_add_layout_pos("soft_spot_%d" % i, _soft_spot_markers[i])

func _add_layout_pos(entry_name: String, node: Node2D, radius: float = -1.0) -> void:
	var e := {
		"name": entry_name,
		"get": func(): return node.position,
		"set": func(v): node.position = v,
	}
	if radius > 0.0:
		e["radius"] = radius
	_layout_entries.append(e)

func _add_layout_field(entry_name: String, obj: Object, field: String) -> void:
	_layout_entries.append({
		"name": entry_name,
		"get": func(): return obj.get(field),
		"set": func(v): obj.set(field, v),
	})

func _apply_layout_overrides() -> void:
	var data := LayoutEditorScript.load_overrides()
	if data.is_empty():
		return
	for entry in _layout_entries:
		var saved = data.get(entry["name"])
		if saved is Array and saved.size() == 2:
			entry["set"].call(Vector2(float(saved[0]), float(saved[1])))

## SLOT_SCALE enlarges the whole slot display 25% (user request). slot_view.gd's
## WINDOW rect (170,590,320,192) is defined in the slot's own local space, so
## scaling the node also shifts everything away from (0,0) — offsetting
## `position` by `window_center * (1 - SLOT_SCALE)` keeps the window centred
## on the exact same spot instead of drifting down-right.
const SLOT_SCALE := 1.25
const SLOT_WINDOW_CENTER := Vector2(330.0, 686.0)

func _build_slot() -> void:
	slot = SlotScene.instantiate()
	slot.name = "Slot"
	slot.z_index = 2
	slot.scale = Vector2(SLOT_SCALE, SLOT_SCALE)
	slot.position = SLOT_WINDOW_CENTER * (1.0 - SLOT_SCALE)
	add_child(slot)
	slot.setup(self, _sfx)
	slot.cycle_finished.connect(_on_slot_cycle_finished)
	slot.free_spins_changed.connect(_on_slot_free_spins)
	switch_hit.connect(_on_switch_hit)
	slot.set_active(false)

func _build_ramps() -> void:
	for cfg in [
		{"name": R1_NAME, "points": R1_POINTS, "commit": R1_COMMIT, "exit": R1_EXIT_DIR},
		{"name": R2_NAME, "points": R2_POINTS, "commit": R2_COMMIT, "exit": R2_EXIT_DIR},
	]:
		var ramp = RampScript.new()
		ramp.name = String(cfg["name"]).replace(" ", "")
		add_child(ramp)
		ramp.configure(String(cfg["name"]), PackedVector2Array(cfg["points"]),
			Vector2(0, -1), cfg["commit"], cfg["exit"])
		ramp.entered.connect(_on_ramp_entered)
		ramp.made.connect(_on_ramp_made)
		ramps.append(ramp)

func _on_ramp_entered(_ramp_name: String) -> void:
	_sfx_play("ramp_enter")

func _on_ramp_made(ramp_name: String) -> void:
	_sfx_play("ramp_made")
	if slot:
		slot.add_energy(2)
	rules.on_event("ramp", {"name": ramp_name})

func _on_switch_hit(_kind: String) -> void:
	if slot:
		slot.add_energy(1)

func _on_request_spot_target() -> void:
	if target_bank:
		target_bank.spot_next_target()
		_refresh_target_lights()
		_sfx_play("target_bank")

func _on_request_add_ball(count: int) -> void:
	_add_queue += count
	_add_timer = 0.0

func _update_add_ball(delta: float) -> void:
	if _add_queue <= 0:
		return
	_add_timer -= delta
	if _add_timer <= 0.0:
		_add_timer = 0.4
		_add_queue -= 1
		_spawn_from_scoop()

func _on_playfield_mult_changed(mult: int) -> void:
	_sfx_play("mode_start")
	_on_rules_message("PLAYFIELD x%d" % mult, 0.0)

func _on_tilted() -> void:
	_sfx_play("tilt")
	if left_flipper:
		left_flipper.set_pressed(false)
	if right_flipper:
		right_flipper.set_pressed(false)
	if wing_left_flipper:
		wing_left_flipper.set_pressed(false)
	if wing_right_flipper:
		wing_right_flipper.set_pressed(false)
	if wing_top_left_flipper:
		wing_top_left_flipper.set_pressed(false)
	if wing_right_wall_flipper:
		wing_right_wall_flipper.set_pressed(false)
	if left_flipper:
		left_flipper.set_disabled(true)
	if right_flipper:
		right_flipper.set_disabled(true)
	if wing_left_flipper:
		wing_left_flipper.set_disabled(true)
	if wing_right_flipper:
		wing_right_flipper.set_disabled(true)
	if wing_top_left_flipper:
		wing_top_left_flipper.set_disabled(true)
	if wing_right_wall_flipper:
		wing_right_wall_flipper.set_disabled(true)
	_left_down = false
	_right_down = false
	if lights:
		lights.gi_flicker()
		lights.set_tilt(true)
		lights.shake(10.0, 0.5)
	_update_music()

func _on_state_changed(state: int) -> void:
	if state != RulesScript.State.PLAYING:
		_slot_ready = false
		if _cam_follow:
			_cam_follow = false
			if lights:
				lights.set_zoom(ZOOM_NORMAL)
				lights.set_camera_position(LightsScript.HOME_CAMERA_POS)
		if _gravity_half:
			_gravity_half = false
			PhysicsServer2D.area_set_param(get_world_2d().space, PhysicsServer2D.AREA_PARAM_GRAVITY, _gravity_normal)
	_update_slot()

func _on_slot_cycle_finished(result: Dictionary) -> void:
	if rules.state != RulesScript.State.PLAYING:
		return
	rules.apply_slot_result(result)
	var bonuses: Dictionary = result.get("bonuses", {})
	if float(bonuses.get("ball_save", 0.0)) > 0.0:
		_ball_save_time = max(_ball_save_time, float(bonuses.get("ball_save", 0.0)))
	if lights and (bool(bonuses.get("start_multiball", false)) or int(bonuses.get("extra_balls", 0)) > 0):
		lights.flash()
		lights.shake()

func _on_slot_free_spins(active: bool) -> void:
	if rules:
		rules.set_free_spins_active(active)
	if active and lights:
		lights.flash()
	_update_music()
