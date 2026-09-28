extends Node2D
## Pinball lighting / insert lamps and screen effects.
## - CanvasModulate dims the table.
## - Insert lamps (Polygon2D circles) for top lanes, INDY targets, LOCK and modes.
## - flash() = full-table white flash, gi_flicker() = drain flicker,
##   shake() = short camera shake, set_ball_save() = blinking shield lamp.

const GOLD := Color("#ffd24a")
const OFF := Color(0.12, 0.10, 0.06)
const DIM := 0.72

var _modulate: CanvasModulate
var _camera: Camera2D
var _flash: Polygon2D
var _shield: Polygon2D
var _shield_on := false
var _flicker := 0.0
var _time := 0.0
var _tilt := false
var _tilt_label: Label

var _lanes: Array = []
var _targets: Array = []
var _bonus_bumpers: Array = []
var _lock: Polygon2D
var _mode: Polygon2D

func setup(parent: Node2D) -> void:
	_modulate = CanvasModulate.new()
	_modulate.name = "TableModulate"
	_modulate.color = Color(DIM, DIM, DIM)
	parent.add_child(_modulate)

	_camera = Camera2D.new()
	_camera.name = "TableCamera"
	_camera.position = Vector2(360.0, 640.0)
	_camera.enabled = true
	parent.add_child(_camera)

	_build_lamps(parent)

	_flash = Polygon2D.new()
	_flash.name = "Flash"
	_flash.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(720, 0), Vector2(720, 1280), Vector2(0, 1280)])
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash.z_index = 50
	parent.add_child(_flash)

	_shield = _make_lamp(parent, Vector2(327.0, 1120.0), 26.0)
	_shield.modulate = Color(1.0, 1.0, 1.0, 0.0)

func _build_lamps(parent: Node2D) -> void:
	for x in [300.0, 360.0, 420.0]:
		_lanes.append(_make_lamp(parent, Vector2(x, 214.0), 11.0))
	for y in [500.0, 558.0, 616.0, 674.0]:
		_targets.append(_make_lamp(parent, Vector2(576.0, y), 9.0))
	for pos in [Vector2(240.0, 392.0), Vector2(420.0, 392.0), Vector2(330.0, 457.0)]:
		_bonus_bumpers.append(_make_lamp(parent, pos, 8.0))
	_lock = _make_lamp(parent, Vector2(300.0, 256.0), 10.0)
	_mode = _make_lamp(parent, Vector2(420.0, 256.0), 10.0)
	set_lock(false)
	set_mode(false)

func _make_lamp(parent: Node2D, pos: Vector2, radius: float) -> Polygon2D:
	var pts := PackedVector2Array()
	var n := 18
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	var lamp := Polygon2D.new()
	lamp.polygon = pts
	lamp.color = OFF
	lamp.position = pos
	lamp.z_index = 5
	parent.add_child(lamp)
	return lamp

func _lit(on: bool) -> Color:
	return GOLD if on else OFF

func set_lanes(lit: Array) -> void:
	for i in _lanes.size():
		var on: bool = i < lit.size() and bool(lit[i])
		_lanes[i].color = _lit(on)

func set_targets(standing: Array) -> void:
	for i in _targets.size():
		var on: bool = i < standing.size() and bool(standing[i])
		_targets[i].color = _lit(on)

func set_bonus_bumpers(lit: Array) -> void:
	for i in _bonus_bumpers.size():
		var on: bool = i < lit.size() and bool(lit[i])
		_bonus_bumpers[i].color = _lit(on)

func set_lock(on: bool) -> void:
	_lock.color = _lit(on)

func set_mode(on: bool) -> void:
	_mode.color = _lit(on)

func set_ball_save(on: bool) -> void:
	_shield_on = on
	_shield.modulate.a = 0.0 if not on else 1.0

func set_tilt(on: bool) -> void:
	_tilt = on
	if on and _tilt_label == null:
		_tilt_label = Label.new()
		_tilt_label.text = "TILT"
		_tilt_label.position = Vector2(0.0, 470.0)
		_tilt_label.size.x = 720.0
		_tilt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tilt_label.add_theme_font_size_override("font_size", 72)
		_tilt_label.add_theme_color_override("font_color", Color("#ff4040"))
		_tilt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_tilt_label.add_theme_constant_override("shadow_offset_x", 3)
		_tilt_label.add_theme_constant_override("shadow_offset_y", 3)
		_tilt_label.z_index = 60
		add_child(_tilt_label)
	if not on and _tilt_label:
		_tilt_label.visible = false

func flash() -> void:
	_flash.color = Color(1.0, 1.0, 1.0, 0.6)
	var t := create_tween()
	t.tween_property(_flash, "color:a", 0.0, 0.45)

func gi_flicker() -> void:
	_flicker = 0.35

func shake(strength := 9.0, dur := 0.35) -> void:
	if _camera == null:
		return
	var t := create_tween()
	var steps := 6
	for i in steps:
		var off := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		t.tween_property(_camera, "offset", off, dur / steps)
	t.tween_property(_camera, "offset", Vector2.ZERO, dur / steps)

func _process(delta: float) -> void:
	_time += delta
	if _tilt:
		var gi := DIM * (0.55 + 0.15 * sin(_time * 4.0))
		_modulate.color = Color(gi, gi, gi)
		if _tilt_label:
			_tilt_label.visible = sin(_time * 8.0) > 0.0
		return
	if _flicker > 0.0:
		_flicker = max(_flicker - delta, 0.0)
		var f := 0.72 - 0.35 * _flicker * (0.5 + 0.5 * sin(_time * 60.0))
		_modulate.color = Color(f, f, f)
	if _shield_on and _shield:
		_shield.modulate.a = 0.15 + 0.85 * (0.5 + 0.5 * sin(_time * 8.0))
