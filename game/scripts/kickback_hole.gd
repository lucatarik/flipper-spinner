extends Node2D
## "Vortex" sucker hole: an open dirt pit on the playfield (reachable from any
## direction, unlike the idol scoop's cup) — jagged earthy mound + dark pit,
## NOT a sci-fi glowing orb/black hole (user feedback: it read as a black hole,
## should read as a hole dug in the ground, jungle-temple themed). A ball
## rolling over it is captured (frozen, pulled to centre) for HOLD seconds
## while the pit glows warm amber and pulses, then it's launched hard, mostly
## straight up.

signal captured

const RADIUS := 24.0
const HOLD := 2.0
const KICK_SPEED := 1150.0
const SPREAD_DEG := 16.0
const COOLDOWN := 0.4

const COLOR_MOUND := Color("#8a6640")
const COLOR_MOUND_SHADE := Color("#5a4028")
const COLOR_PIT := Color("#1c1208")
const COLOR_GLOW := Color("#ffb057")   # warm amber (torch-lit pit), not neon

var holding := false

var _timer := 0.0
var _ball: RigidBody2D = null
var _glow: PointLight2D
var _area: Area2D
var _cooldown := 0.0

func _ready() -> void:
	z_index = 4
	_build_visual()
	_build_detect()

func _build_visual() -> void:
	var mound := Polygon2D.new()
	mound.polygon = _jagged_circle(RADIUS * 1.35, 0.22)
	mound.color = COLOR_MOUND
	add_child(mound)

	var mound_shade := Polygon2D.new()
	mound_shade.polygon = _jagged_circle(RADIUS * 1.12, 0.18)
	mound_shade.color = COLOR_MOUND_SHADE
	add_child(mound_shade)

	var pit := Polygon2D.new()
	pit.polygon = _jagged_circle(RADIUS, 0.12)
	pit.color = COLOR_PIT
	add_child(pit)

	# a few loose rocks/clumps scattered around the rim for texture
	for i in 7:
		var a := TAU * float(i) / 7.0 + randf_range(-0.25, 0.25)
		var rock := Polygon2D.new()
		rock.polygon = _jagged_circle(randf_range(3.0, 6.0), 0.35)
		rock.position = Vector2(cos(a), sin(a)) * RADIUS * randf_range(1.05, 1.3)
		rock.color = COLOR_MOUND_SHADE.darkened(randf_range(0.0, 0.25))
		add_child(rock)

	_glow = PointLight2D.new()
	_glow.texture = Glow.radial_texture()
	_glow.color = COLOR_GLOW
	_glow.energy = 0.3
	_glow.texture_scale = 1.7
	add_child(_glow)

## Irregular ring instead of a perfect circle (each vertex radius jittered by
## up to `jitter` fraction) so the pit/mound reads as dug earth, not a drawn
## shape — called once per instance so each hole ends up subtly different.
func _jagged_circle(r: float, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var a := TAU * float(i) / float(n)
		var rr := r * (1.0 + randf_range(-jitter, jitter))
		pts.append(Vector2(cos(a), sin(a)) * rr)
	return pts

func _build_detect() -> void:
	_area = Area2D.new()
	_area.name = "Suck"
	_area.collision_layer = 8
	_area.collision_mask = 2
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS
	cs.shape = c
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body)

func _on_body(body: Node) -> void:
	if holding or _cooldown > 0.0 or not (body is RigidBody2D):
		return
	if not body.is_in_group("balls"):
		return
	_capture(body)

func _capture(body: RigidBody2D) -> void:
	holding = true
	_timer = 0.0
	_ball = body
	body.collision_layer = 0
	body.set_deferred("freeze", true)
	body.linear_velocity = Vector2.ZERO
	body.global_position = global_position
	body.set_meta("held_by_hole", true)
	_glow.energy = 1.8
	captured.emit()

func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = max(_cooldown - delta, 0.0)
	if not holding:
		return
	_timer += delta
	if is_instance_valid(_ball):
		_ball.global_position = global_position
	_glow.energy = 0.3 + absf(sin(_timer * 6.0)) * 1.6
	if _timer >= HOLD:
		_release()

func _release() -> void:
	var b := _ball
	holding = false
	_ball = null
	_glow.energy = 0.3
	_cooldown = COOLDOWN
	if b != null and is_instance_valid(b):
		b.set_meta("held_by_hole", false)
		b.set_deferred("freeze", false)
		b.collision_layer = 2
		var ang := deg_to_rad(-90.0 + randf_range(-SPREAD_DEG, SPREAD_DEG))
		var dir := Vector2(cos(ang), sin(ang))
		b.linear_velocity = dir * KICK_SPEED
