extends Node2D
## Idol scoop at (360,300): a short inverted-U wall cup opening downward. A ball
## entering from below is captured (frozen) for HOLD seconds while a light glows,
## the `captured` signal fires (Rules scoop), then the ball is kicked down-left.

signal captured


const HOLD := 1.0
const KICK_SPEED := 900.0
const CAPTURE_OFFSET := Vector2(0.0, 8.0)
const WALL_THICK := 12.0

var holding := false
var kicks := 0

var _timer := 0.0
var _ball: RigidBody2D = null
var _glow: PointLight2D
var _area: Area2D
var _cooldown := 0.0

func _ready() -> void:
	_build_walls()
	_build_visual()
	_build_detect()

func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "ScoopWalls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	_add_band(walls, Vector2(-26.0, -42.0), Vector2(-26.0, 54.0), WALL_THICK)
	_add_band(walls, Vector2(26.0, -42.0), Vector2(26.0, 54.0), WALL_THICK)
	_add_band(walls, Vector2(-26.0, -42.0), Vector2(26.0, -42.0), WALL_THICK)

func _add_band(parent: Node, a: Vector2, b: Vector2, thickness: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * (thickness * 0.5)
	var poly := PackedVector2Array([a + n, b + n, b - n, a - n])
	var vis := Polygon2D.new()
	vis.polygon = poly
	vis.color = Color("#6b6b6b")
	parent.add_child(vis)
	var ol := Line2D.new()
	ol.points = poly
	ol.closed = true
	ol.width = 3.0
	ol.default_color = Color("#d4a017")
	parent.add_child(ol)
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	parent.add_child(cp)

func _build_visual() -> void:
	var hole := Polygon2D.new()
	var pts := PackedVector2Array()
	var n := 20
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(CAPTURE_OFFSET + Vector2(cos(a), sin(a)) * 20.0)
	hole.polygon = pts
	hole.color = Color(0.02, 0.01, 0.0, 0.95)
	add_child(hole)

	_glow = PointLight2D.new()
	_glow.texture = Glow.radial_texture()
	_glow.color = Color("#ffd24a")
	_glow.energy = 0.0
	_glow.texture_scale = 2.0
	_glow.position = CAPTURE_OFFSET
	add_child(_glow)

func _build_detect() -> void:
	_area = Area2D.new()
	_area.name = "Capture"
	_area.collision_layer = 8
	_area.collision_mask = 2
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(46.0, 80.0)
	cs.shape = rect
	cs.position = Vector2(0.0, 12.0)
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body)

func _on_body(body: Node) -> void:
	if holding or _cooldown > 0.0 or not (body is RigidBody2D):
		return
	if not body.is_in_group("balls"):
		return
	_capture(body)

## D1 stuck-ball rescue: pull a wedged ball into the scoop hold + kick without
## emitting `captured`, so no scoop score/lock/mode is triggered.
func rescue(body: RigidBody2D) -> void:
	if holding or _cooldown > 0.0 or body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("balls"):
		return
	_capture(body, true)

func _capture(body: RigidBody2D, silent := false) -> void:
	holding = true
	_timer = 0.0
	_ball = body
	body.collision_layer = 0
	body.set_deferred("freeze", true)
	body.linear_velocity = Vector2.ZERO
	body.global_position = global_position + CAPTURE_OFFSET
	_glow.energy = 1.6
	if not silent:
		captured.emit()

func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = max(_cooldown - delta, 0.0)
	if not holding:
		return
	_timer += delta
	if is_instance_valid(_ball):
		_ball.global_position = global_position + CAPTURE_OFFSET
		_ball.linear_velocity = Vector2.ZERO
	if _timer >= HOLD:
		_release()

func _release() -> void:
	var b := _ball
	holding = false
	_ball = null
	_glow.energy = 0.0
	_cooldown = 0.5
	if b != null and is_instance_valid(b):
		b.set_deferred("freeze", false)
		b.collision_layer = 2
		# drop the ball below the cup mouth before it is unfrozen
		b.global_position = global_position + Vector2(0.0, 60.0)
		var ang := deg_to_rad(randf_range(15.0, 30.0))
		var dir := Vector2(-sin(ang), cos(ang))
		b.linear_velocity = dir * KICK_SPEED
		kicks += 1
