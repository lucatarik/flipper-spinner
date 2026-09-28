extends AnimatableBody2D
## Small pop bumper that patrols back and forth along a short track (ping-pong
## between point_a and point_b), so its position and kick direction keep changing.
## Carries its own track velocity into the kick impulse for extra unpredictability.

signal hit

const KICK_IMPULSE := 620.0
const COOLDOWN_MS := 120
const COLOR_FILL := Color("#3a7dbf")
const COLOR_OUTLINE := Color("#bfe8ff")
const COLOR_GLOW := Color("#7fd4ff")

@export var radius := 16.0
@export var point_a := Vector2.ZERO
@export var point_b := Vector2.ZERO
@export var speed := 70.0   # px/s along the track

var _cooldowns := {}
var _light: PointLight2D
var _glow := 0.4
var _t := 0.0     # 0..1 ping-pong phase along the track
var _dir := 1.0
var _velocity := Vector2.ZERO
var _prev_pos := Vector2.ZERO

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	position = point_a
	_prev_pos = position
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	add_child(cs)

	var vis := Polygon2D.new()
	var pts := _circle_points(radius)
	vis.polygon = pts
	vis.color = COLOR_FILL
	add_child(vis)
	var outline := Line2D.new()
	outline.points = pts
	outline.closed = true
	outline.width = 2.0
	outline.default_color = COLOR_OUTLINE
	add_child(outline)

	_light = PointLight2D.new()
	_light.texture = Glow.radial_texture()
	_light.color = COLOR_GLOW
	_light.energy = _glow
	_light.texture_scale = 1.3
	add_child(_light)

	var detect := Area2D.new()
	detect.name = "Detect"
	detect.collision_layer = 8
	detect.collision_mask = 2
	var ds := CollisionShape2D.new()
	var dc := CircleShape2D.new()
	dc.radius = radius + 8.0
	ds.shape = dc
	detect.add_child(ds)
	add_child(detect)
	detect.body_entered.connect(_on_body)

func _circle_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _physics_process(delta: float) -> void:
	var track := point_b - point_a
	var length := track.length()
	if length > 0.001 and delta > 0.0:
		_t += _dir * speed * delta / length
		if _t >= 1.0:
			_t = 1.0
			_dir = -1.0
		elif _t <= 0.0:
			_t = 0.0
			_dir = 1.0
		position = point_a.lerp(point_b, _t)
	if delta > 0.0:
		_velocity = (position - _prev_pos) / delta
	_prev_pos = position
	if _glow > 0.4:
		_glow = max(0.4, _glow - delta * 5.0)
		if _light:
			_light.energy = _glow

func _on_body(body: Node) -> void:
	var rb := body as RigidBody2D
	if rb == null:
		return
	var now := Time.get_ticks_msec()
	var id := rb.get_instance_id()
	if now - int(_cooldowns.get(id, -99999)) < COOLDOWN_MS:
		return
	_cooldowns[id] = now
	var dir := rb.global_position - global_position
	if dir.length() < 0.001:
		dir = Vector2(0.0, -1.0)
	rb.apply_central_impulse(dir.normalized() * KICK_IMPULSE + _velocity * 1.5)
	_glow = 1.6
	hit.emit()
