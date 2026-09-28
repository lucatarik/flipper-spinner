extends Node2D
## Shooter-lane plunger. Table (or tests) call set_charging(true) to hold, then
## set_charging(false) to release and launch any ball sitting in the lane. Drawn as
## a rod + tip with a coil spring that visibly compresses while charging.

const CHARGE_TIME := 1.0
const MAX_SPEED := 2805.0       # +65% power (user request), was 1700.0
const MIN_RATIO := 0.4

const BASE_Y := 78.0
const REST_TIP_Y := 5.0
const TRAVEL := 42.0
const ROD_HALF_W := 6.0
const TIP_HALF_W := 14.0

const STONE := Color("#6b6b6b")
const GOLD := Color("#d4a017")
const DARK := Color("#3a2c0c")

var charge := 0.0
var _charging := false
var _lane: Area2D
var _rod: Polygon2D
var _tip: Polygon2D
var _spring: Line2D

func _ready() -> void:
	_lane = Area2D.new()
	_lane.name = "Lane"
	_lane.collision_layer = 8
	_lane.collision_mask = 2
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(50.0, 240.0)
	cs.shape = rect
	cs.position = Vector2(0.0, -80.0)
	_lane.add_child(cs)
	add_child(_lane)
	_build_visual()

func _build_visual() -> void:
	_rod = Polygon2D.new()
	_rod.color = STONE
	add_child(_rod)
	_tip = Polygon2D.new()
	_tip.color = GOLD
	add_child(_tip)
	_spring = Line2D.new()
	_spring.width = 3.0
	_spring.default_color = GOLD
	add_child(_spring)
	_update_visual()

func set_charging(on: bool) -> void:
	if on:
		if not _charging:
			_charging = true
			charge = 0.0
	elif _charging:
		_charging = false
		_launch()

func is_charging() -> bool:
	return _charging

func _process(delta: float) -> void:
	if _charging:
		charge = min(charge + delta / CHARGE_TIME, 1.0)
		_update_visual()

func _tip_y() -> float:
	return REST_TIP_Y + charge * TRAVEL

func _update_visual() -> void:
	var ty := _tip_y()
	_rod.polygon = PackedVector2Array([
		Vector2(-ROD_HALF_W, ty),
		Vector2(ROD_HALF_W, ty),
		Vector2(ROD_HALF_W, BASE_Y),
		Vector2(-ROD_HALF_W, BASE_Y),
	])
	_tip.polygon = PackedVector2Array([
		Vector2(-TIP_HALF_W, ty - 6.0),
		Vector2(TIP_HALF_W, ty - 6.0),
		Vector2(TIP_HALF_W, ty + 6.0),
		Vector2(-TIP_HALF_W, ty + 6.0),
	])
	var top := ty + 8.0
	var bottom := BASE_Y
	var coils := 7
	var pts := PackedVector2Array()
	pts.append(Vector2(-TIP_HALF_W, top))
	for i in coils:
		var y := lerpf(top, bottom, float(i + 1) / float(coils + 1))
		var side := -1.0 if i % 2 == 0 else 1.0
		pts.append(Vector2(side * (TIP_HALF_W + 2.0), y))
	pts.append(Vector2(-TIP_HALF_W, bottom))
	_spring.points = pts

func _launch() -> void:
	var ratio: float = max(charge, MIN_RATIO)
	var speed := MAX_SPEED * ratio
	for body in _lane.get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("balls"):
			body.linear_velocity = Vector2(0.0, -speed)
	charge = 0.0
	_update_visual()
