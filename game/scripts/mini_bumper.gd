extends AnimatableBody2D
## Small pop bumper that patrols back and forth along a short track (ping-pong
## between point_a and point_b), so its position and kick direction keep changing.
## Carries its own track velocity into the kick impulse for extra unpredictability.
## After a randomized 5-15 hits it "explodes" (big burst + `exploded` signal),
## vanishes (frozen on the track, hidden, no collision) and comes back ~30s
## later at point_a with a fresh random threshold — see _explode()/_respawn().

signal hit
signal exploded

const KICK_IMPULSE := 620.0
const COOLDOWN_MS := 120
const COLOR_FILL := Color("#3a7dbf")
const COLOR_OUTLINE := Color("#bfe8ff")
const COLOR_GLOW := Color("#7fd4ff")

const EXPLODE_HITS_MIN := 5
const EXPLODE_HITS_MAX := 15
const RESPAWN_SECONDS_MIN := 28.0
const RESPAWN_SECONDS_MAX := 32.0

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
var _detect: Area2D
var _big_fire: CPUParticles2D

var _hit_count := 0
var _explode_threshold := 0
var _exploded := false
var _respawn_timer := 0.0

func _ready() -> void:
	# Above the slot (z_index 2), which it patrols over, so it isn't hidden under
	# the reels; below the ball (z_index 6) so the ball still reads on top.
	z_index = 3
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

	_big_fire = CPUParticles2D.new()
	_big_fire.emitting = false
	_big_fire.one_shot = true
	_big_fire.amount = 40
	_big_fire.lifetime = 0.6
	_big_fire.explosiveness = 1.0
	_big_fire.direction = Vector2(0.0, -1.0)
	_big_fire.spread = 180.0
	_big_fire.initial_velocity_min = 120.0
	_big_fire.initial_velocity_max = 320.0
	_big_fire.gravity = Vector2(0.0, 60.0)
	_big_fire.scale_amount_min = 3.0
	_big_fire.scale_amount_max = 6.0
	_big_fire.color_ramp = _fire_gradient()
	add_child(_big_fire)

	_detect = Area2D.new()
	_detect.name = "Detect"
	_detect.collision_layer = 8
	_detect.collision_mask = 2
	var ds := CollisionShape2D.new()
	var dc := CircleShape2D.new()
	dc.radius = radius + 8.0
	ds.shape = dc
	_detect.add_child(ds)
	add_child(_detect)
	_detect.body_entered.connect(_on_body)

	_explode_threshold = randi_range(EXPLODE_HITS_MIN, EXPLODE_HITS_MAX)

func _fire_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.5, 1.0))
	g.add_point(0.4, Color(1.0, 0.55, 0.1, 0.9))
	g.set_color(1, Color(0.6, 0.1, 0.05, 0.0))
	return g

func _circle_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _physics_process(delta: float) -> void:
	if _exploded:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
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
	_hit_count += 1
	if _hit_count >= _explode_threshold:
		_explode()

func _explode() -> void:
	_exploded = true
	_respawn_timer = randf_range(RESPAWN_SECONDS_MIN, RESPAWN_SECONDS_MAX)
	_glow = 3.0
	if _light:
		_light.energy = _glow
	if _big_fire:
		_big_fire.restart()
		_big_fire.emitting = true
	visible = false
	collision_layer = 0
	if _detect:
		_detect.monitoring = false
	exploded.emit()

func _respawn() -> void:
	_exploded = false
	_hit_count = 0
	_explode_threshold = randi_range(EXPLODE_HITS_MIN, EXPLODE_HITS_MAX)
	_t = 0.0
	_dir = 1.0
	position = point_a
	_prev_pos = position
	visible = true
	collision_layer = 1
	if _detect:
		_detect.monitoring = true
	_glow = 1.6
