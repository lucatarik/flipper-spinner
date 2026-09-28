extends Node2D
## "Vortex" sucker hole: an open pit on the playfield (reachable from any
## direction, unlike the idol scoop's cup). A ball rolling over it is captured
## (frozen, pulled to centre) for HOLD seconds while the rim spins and the glow
## pulses, then it's launched hard, mostly straight up.

signal captured

const RADIUS := 24.0
const HOLD := 2.0
const KICK_SPEED := 1150.0
const SPREAD_DEG := 16.0
const COOLDOWN := 0.4
const COLOR := Color("#8a4fff")

var holding := false

var _timer := 0.0
var _ball: RigidBody2D = null
var _glow: PointLight2D
var _rim: Line2D
var _area: Area2D
var _cooldown := 0.0
var _spin := 0.0

func _ready() -> void:
	z_index = 4
	_build_visual()
	_build_detect()

func _build_visual() -> void:
	var hole := Polygon2D.new()
	hole.polygon = _circle(RADIUS)
	hole.color = Color(0.02, 0.0, 0.05, 0.97)
	add_child(hole)

	_rim = Line2D.new()
	_rim.points = _circle(RADIUS)
	_rim.closed = true
	_rim.width = 3.0
	_rim.default_color = COLOR
	add_child(_rim)

	_glow = PointLight2D.new()
	_glow.texture = Glow.radial_texture()
	_glow.color = COLOR
	_glow.energy = 0.5
	_glow.texture_scale = 2.4
	add_child(_glow)

func _circle(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 24
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * r)
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
	_glow.energy = 2.0
	captured.emit()

func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = max(_cooldown - delta, 0.0)
	_spin += delta * 6.0
	_rim.rotation = _spin
	if not holding:
		return
	_timer += delta
	if is_instance_valid(_ball):
		_ball.global_position = global_position
	_glow.energy = 0.5 + absf(sin(_timer * 6.0)) * 1.5
	if _timer >= HOLD:
		_release()

func _release() -> void:
	var b := _ball
	holding = false
	_ball = null
	_glow.energy = 0.5
	_cooldown = COOLDOWN
	if b != null and is_instance_valid(b):
		b.set_meta("held_by_hole", false)
		b.set_deferred("freeze", false)
		b.collision_layer = 2
		var ang := deg_to_rad(-90.0 + randf_range(-SPREAD_DEG, SPREAD_DEG))
		var dir := Vector2(cos(ang), sin(ang))
		b.linear_velocity = dir * KICK_SPEED
