extends Node2D
## The 4-target INDY drop-target bank along the shooter-lane divider.
## D1: a thin static strip keeps the bank's face line flush even when targets are
## down (no 33 px pocket next to the divider), and 45° stone caps fill the corners
## at the top and bottom ends so a ball cannot rest on the bank's ends.

signal target_dropped(index: int)

const TargetScript = preload("res://scripts/drop_target.gd")
const TARGET_SIZE := Vector2(18.0, 40.0)
const FACE_THICK := 8.0
const STONE := Color("#6b6b6b")
const GOLD := Color("#d4a017")

var targets: Array = []
var _letters := ["I", "N", "D", "Y"]
var _static: StaticBody2D

func build(x: float, ys: Array) -> void:
	for i in ys.size():
		var t = TargetScript.new()
		t.index = i
		t.position = Vector2(x, float(ys[i]))
		t.letter = _letters[i] if i < _letters.size() else ""
		add_child(t)
		t.dropped.connect(_on_dropped)
		targets.append(t)
	_build_backing(x, ys)

## Continuous flush wall at the bank's face line plus the two 45° end caps.
func _build_backing(x: float, ys: Array) -> void:
	_static = StaticBody2D.new()
	_static.name = "BankFace"
	_static.collision_layer = 1
	_static.collision_mask = 0
	add_child(_static)
	var face_x := x - TARGET_SIZE.x * 0.5
	var top: float = float(ys[0]) - TARGET_SIZE.y * 0.5
	var bottom: float = float(ys[ys.size() - 1]) + TARGET_SIZE.y * 0.5
	_add_quad(Vector2(face_x - FACE_THICK * 0.5, top - 4.0),
		Vector2(face_x + FACE_THICK * 0.5, top - 4.0),
		Vector2(face_x + FACE_THICK * 0.5, bottom + 4.0),
		Vector2(face_x - FACE_THICK * 0.5, bottom + 4.0))
	# 45° caps in the divider-side corners above the top and below the bottom target
	var wall_x := x + TARGET_SIZE.x * 0.5 + 15.0
	_add_tri(Vector2(face_x, top), Vector2(wall_x, top), Vector2(wall_x, top - (wall_x - face_x)))
	_add_tri(Vector2(face_x, bottom), Vector2(wall_x, bottom), Vector2(wall_x, bottom + (wall_x - face_x)))

func _add_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> void:
	var poly := PackedVector2Array([a, b, c, d])
	var vis := Polygon2D.new()
	vis.polygon = poly
	vis.color = STONE
	_static.add_child(vis)
	var ol := Line2D.new()
	ol.points = poly
	ol.closed = true
	ol.width = 2.0
	ol.default_color = GOLD
	_static.add_child(ol)
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	_static.add_child(cp)

func _add_tri(a: Vector2, b: Vector2, c: Vector2) -> void:
	var poly := PackedVector2Array([a, b, c])
	var vis := Polygon2D.new()
	vis.polygon = poly
	vis.color = STONE
	_static.add_child(vis)
	var ol := Line2D.new()
	ol.points = poly
	ol.closed = true
	ol.width = 2.0
	ol.default_color = GOLD
	_static.add_child(ol)
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	_static.add_child(cp)

func _on_dropped(index: int) -> void:
	target_dropped.emit(index)

func raise_all() -> void:
	for t in targets:
		t.raise()

func spot_next_target() -> void:
	for t in targets:
		if not t.down:
			t.drop()
			return

func standing() -> Array:
	var out: Array = []
	for t in targets:
		out.append(not t.down)
	return out
