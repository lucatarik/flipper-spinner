extends Node2D
## Left "Path of Adventure" orbit. A guide wall at x=95 (y 330..780) forms a lane
## between the side wall and the guide, open at the bottom and exiting into the
## top arc. A one-way gate blocks re-entry from the arc. A bottom+top sensor pair
## within WINDOW seconds scores the orbit once per pass.

signal orbit_scored

const WINDOW := 1.5
const GUIDE_X := 95.0
const GUIDE_TOP := 330.0
const GUIDE_BOTTOM := 780.0
const GUIDE_THICK := 14.0
const GATE_Y := 340.0

var _armed := false
var _bottom_t := -999.0

func _ready() -> void:
	_build_guide()
	_build_gate()
	var bottom := _make_sensor(Vector2(57.0, 740.0), Vector2(60.0, 44.0))
	bottom.body_entered.connect(_on_bottom)
	var top := _make_sensor(Vector2(57.0, 370.0), Vector2(60.0, 44.0))
	top.body_entered.connect(_on_top)

func _build_guide() -> void:
	var walls := StaticBody2D.new()
	walls.name = "OrbitGuide"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	var a := Vector2(GUIDE_X, GUIDE_TOP)
	var b := Vector2(GUIDE_X, GUIDE_BOTTOM)
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * (GUIDE_THICK * 0.5)
	var poly := PackedVector2Array([a + n, b + n, b - n, a - n])
	var vis := Polygon2D.new()
	vis.polygon = poly
	vis.color = Color("#6b6b6b")
	walls.add_child(vis)
	var ol := Line2D.new()
	ol.points = poly
	ol.closed = true
	ol.width = 3.0
	ol.default_color = Color("#d4a017")
	walls.add_child(ol)
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	walls.add_child(cp)

func _build_gate() -> void:
	var gate := StaticBody2D.new()
	gate.name = "OrbitGate"
	gate.collision_layer = 1
	gate.collision_mask = 0
	gate.position = Vector2((20.0 + GUIDE_X) * 0.5, GATE_Y)
	add_child(gate)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2((GUIDE_X - 20.0) + GUIDE_THICK, 10.0)
	cs.shape = rect
	cs.one_way_collision = true
	gate.add_child(cs)

func _make_sensor(pos: Vector2, size: Vector2) -> Area2D:
	var area := Area2D.new()
	area.collision_layer = 8
	area.collision_mask = 2
	area.position = pos
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	area.add_child(cs)
	add_child(area)
	return area

func _on_bottom(body: Node) -> void:
	if not body.is_in_group("balls"):
		return
	_armed = true
	_bottom_t = Time.get_ticks_msec() / 1000.0

func _on_top(body: Node) -> void:
	if not body.is_in_group("balls") or not _armed:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _bottom_t > WINDOW:
		_armed = false
		return
	_armed = false
	orbit_scored.emit()
