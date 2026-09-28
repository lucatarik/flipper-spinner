extends StaticBody2D
## INDY drop target. Solid while standing; drops (collision off + darkens) on a
## ball hit and emits `dropped`; `raise()` restores it.

signal dropped(index: int)

const SIZE := Vector2(18.0, 40.0)
const GOLD := Color("#d4a017")
const DARK := Color("#3a2c0c")
const DIM := Color("#6a5010")

var index := 0
var letter := ""
var down := false

var _vis: Polygon2D
var _label: Label

func _ready() -> void:
	_build()

func _build() -> void:
	collision_layer = 1
	collision_mask = 0
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	var cs := CollisionShape2D.new()
	cs.shape = rect
	add_child(cs)

	_vis = Polygon2D.new()
	_vis.polygon = PackedVector2Array([
		Vector2(-SIZE.x * 0.5, -SIZE.y * 0.5),
		Vector2(SIZE.x * 0.5, -SIZE.y * 0.5),
		Vector2(SIZE.x * 0.5, SIZE.y * 0.5),
		Vector2(-SIZE.x * 0.5, SIZE.y * 0.5),
	])
	_vis.color = GOLD
	add_child(_vis)

	var outline := Line2D.new()
	outline.points = _vis.polygon
	outline.closed = true
	outline.width = 2.0
	outline.default_color = DARK
	add_child(outline)

	_label = Label.new()
	_label.text = letter
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", DARK)
	_label.position = Vector2(-7.0, -13.0)
	add_child(_label)

	var detect := Area2D.new()
	detect.name = "Detect"
	detect.collision_layer = 8
	detect.collision_mask = 2
	var ds := CollisionShape2D.new()
	var dr := RectangleShape2D.new()
	dr.size = SIZE + Vector2(12.0, 12.0)
	ds.shape = dr
	detect.add_child(ds)
	add_child(detect)
	detect.body_entered.connect(_on_body)

func _on_body(body: Node) -> void:
	if down or not (body is RigidBody2D):
		return
	if not body.is_in_group("balls"):
		return
	drop()

func drop() -> void:
	if down:
		return
	down = true
	set_deferred("collision_layer", 0)
	if _vis:
		_vis.color = DIM
	if _label:
		_label.modulate = Color(1.0, 1.0, 1.0, 0.3)
	dropped.emit(index)

func raise() -> void:
	if not down:
		return
	down = false
	set_deferred("collision_layer", 1)
	if _vis:
		_vis.color = GOLD
	if _label:
		_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
