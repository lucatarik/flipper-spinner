extends AnimatableBody2D
## Pinball flipper. Kinematic bat rotated in _physics_process. While the bat is
## actually swinging up it transfers its tangential velocity to a contacting ball
## (omega x r, at most once per swing per ball); at the top of the swing the bat is
## a solid static surface so a held flipper cradles the ball.

const BASE_LENGTH := 96.0
const BASE_PIVOT_RADIUS := 11.0
const BASE_TIP_RADIUS := 7.0
const REST_ANGLE := deg_to_rad(28.0)
const SWING_SPEED := 15.0       # rad/s while swinging
const KICK_MULT := 1.15

const GOLD := Color("#d4a017")
const DARK := Color("#3a2c0c")

@export var side := "left"
## Scales LENGTH/PIVOT_RADIUS/TIP_RADIUS for smaller "wing" flippers; 1.0 = full size.
@export var size_scale := 1.0

var LENGTH := BASE_LENGTH
var PIVOT_RADIUS := BASE_PIVOT_RADIUS
var TIP_RADIUS := BASE_TIP_RADIUS

var _pressed := false
var disabled := false
## Unwrapped bat angle: `rotation` is read back wrapped to (-PI, PI], which made
## the right bat (rest 152 deg, active 208 deg) swing the long way round.
var _angle := 0.0
var _kicked := {}
var _bat: Polygon2D
var _outline: Line2D
var _hit_area: Area2D

func _ready() -> void:
	LENGTH = BASE_LENGTH * size_scale
	PIVOT_RADIUS = BASE_PIVOT_RADIUS * size_scale
	TIP_RADIUS = BASE_TIP_RADIUS * size_scale
	collision_layer = 4
	collision_mask = 0
	_build_shape()
	_build_visual()
	_angle = _rest_angle()
	rotation = _angle

func _build_shape() -> void:
	var poly := PackedVector2Array([
		Vector2(0.0, -PIVOT_RADIUS),
		Vector2(LENGTH, -TIP_RADIUS),
		Vector2(LENGTH, TIP_RADIUS),
		Vector2(0.0, PIVOT_RADIUS),
	])
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	add_child(cp)
	# Rounded pivot and tip: square corners formed a notch with the inlane guide end
	# where a ball could come to rest on top of the pivot.
	for cap in [[Vector2.ZERO, PIVOT_RADIUS], [Vector2(LENGTH, 0.0), TIP_RADIUS]]:
		var cs := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = cap[1]
		cs.shape = circle
		cs.position = cap[0]
		add_child(cs)

	_hit_area = Area2D.new()
	_hit_area.name = "HitArea"
	_hit_area.collision_layer = 8
	_hit_area.collision_mask = 2
	var hit_shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = PIVOT_RADIUS + 4.0
	cap.height = LENGTH
	hit_shape.shape = cap
	hit_shape.position = Vector2(LENGTH * 0.5, 0.0)
	hit_shape.rotation = deg_to_rad(90.0)
	_hit_area.add_child(hit_shape)
	add_child(_hit_area)

func _build_visual() -> void:
	var poly := PackedVector2Array([
		Vector2(0.0, -PIVOT_RADIUS),
		Vector2(LENGTH, -TIP_RADIUS),
		Vector2(LENGTH, TIP_RADIUS),
		Vector2(0.0, PIVOT_RADIUS),
	])
	_bat = Polygon2D.new()
	_bat.polygon = poly
	_bat.color = GOLD
	add_child(_bat)
	_outline = Line2D.new()
	_outline.points = poly
	_outline.closed = true
	_outline.width = 3.0
	_outline.default_color = DARK
	add_child(_outline)
	_add_cap(Vector2.ZERO, PIVOT_RADIUS, DARK)
	_add_cap(Vector2(LENGTH, 0.0), TIP_RADIUS, GOLD)

func _add_cap(center: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	var cap := Polygon2D.new()
	cap.polygon = pts
	cap.color = color
	add_child(cap)

func set_pressed(pressed: bool) -> void:
	if disabled:
		_pressed = false
		return
	if pressed and not _pressed:
		_kicked.clear()
	_pressed = pressed

## Tilt kill-switch: while disabled the flipper ignores set_pressed and falls
## back to its rest angle.
func set_disabled(value: bool) -> void:
	disabled = value
	if value:
		_pressed = false

func is_pressed() -> bool:
	return _pressed

func _rest_angle() -> float:
	return PI - REST_ANGLE if side == "right" else REST_ANGLE

func _active_angle() -> float:
	return PI + REST_ANGLE if side == "right" else -REST_ANGLE

func has_ball(body: Node) -> bool:
	return body in _hit_area.get_overlapping_bodies()

func _physics_process(delta: float) -> void:
	var target := _active_angle() if _pressed else _rest_angle()
	var prev := _angle
	_angle = move_toward(_angle, target, SWING_SPEED * delta)
	rotation = _angle
	if _pressed and not is_equal_approx(_angle, target) and not is_equal_approx(_angle, prev):
		_apply_hits()

func _apply_hits() -> void:
	var omega := SWING_SPEED * signf(_active_angle() - _rest_angle())
	for body in _hit_area.get_overlapping_bodies():
		if not (body is RigidBody2D):
			continue
		var rb := body as RigidBody2D
		var id := rb.get_instance_id()
		if _kicked.has(id):
			continue
		_kicked[id] = true
		var bat_dir := Vector2(cos(rotation), sin(rotation))
		var s: float = clampf((rb.global_position - global_position).dot(bat_dir), 0.0, LENGTH)
		var contact: Vector2 = bat_dir * s
		var tangential: Vector2 = omega * Vector2(-contact.y, contact.x)
		var along: Vector2 = rb.linear_velocity.dot(bat_dir) * bat_dir
		rb.linear_velocity = tangential * KICK_MULT + along
