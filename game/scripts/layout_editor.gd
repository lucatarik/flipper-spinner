extends Node2D
## Dev tool, not part of gameplay: press E to pause the game and drag the cyan
## handles to reposition registered elements; press S (while active) to save
## every registered position to res://layout_overrides.json. table.gd loads
## that file back at _ready() and applies it on top of the hardcoded defaults,
## so edits persist across restarts without touching code.
## Always processes (PROCESS_MODE_ALWAYS) so the toggle/save keys still work
## while the rest of the tree is paused.

const HANDLE_RADIUS := 14.0
## Click tolerance is bigger than the drawn handle: flippers especially are
## easy to miss by a few pixels since the pivot isn't where the eye lands.
const CLICK_RADIUS := 26.0
const SAVE_PATH := "res://layout_overrides.json"
const HANDLE_COLOR := Color(0.2, 0.9, 1.0, 0.55)
const HANDLE_DRAG_COLOR := Color(1.0, 0.85, 0.2, 0.8)

var entries: Array = []   # [{"name": String, "get": Callable, "set": Callable}]
var active := false

var _handles: Array = []  # Polygon2D per entry, same order as `entries`
var _drag_index := -1
var _label: Label
var _saved_flash := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 100
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 10
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 40)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.visible = false
	layer.add_child(_label)

## `list` = the entries built by table.gd, each a Dictionary with "name" and
## "get"/"set" Callables (no args -> Vector2, and Vector2 -> void), plus an
## optional "radius" (click tolerance AND drawn handle size — a long object
## like a flipper needs a much bigger one than a small round bumper, since
## the natural click target is the whole visible shape, not just its pivot).
func setup(list: Array) -> void:
	entries = list
	for h in _handles:
		h.queue_free()
	_handles.clear()
	for e in entries:
		var r: float = float(e.get("radius", HANDLE_RADIUS))
		var h := Polygon2D.new()
		var pts := PackedVector2Array()
		var n := 8
		for i in n:
			var a := TAU * float(i) / float(n)
			pts.append(Vector2(cos(a), sin(a)) * r)
		h.polygon = pts
		h.color = HANDLE_COLOR
		h.visible = active
		h.z_index = 100
		add_child(h)
		_handles.append(h)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_toggle()
			return
		if active and event.keycode == KEY_S:
			_save()
			return
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_drag(get_global_mouse_position())
		else:
			if _drag_index >= 0:
				_handles[_drag_index].color = HANDLE_COLOR
			_drag_index = -1
	elif event is InputEventMouseMotion and _drag_index >= 0:
		entries[_drag_index]["set"].call(get_global_mouse_position())

## Picks the CLOSEST handle whose own (possibly per-entry) radius the click
## falls within, not just the first match, so two nearby handles don't fight
## over an ambiguous click. Distance is measured as a fraction of that
## handle's radius so a big handle (flipper) and a small one (bumper) compete
## fairly instead of the bigger one always winning ties.
func _try_start_drag(world_pos: Vector2) -> void:
	var best := -1
	var best_frac := 1.0
	for i in entries.size():
		var r: float = float(entries[i].get("radius", CLICK_RADIUS))
		var p: Vector2 = entries[i]["get"].call()
		var frac: float = world_pos.distance_to(p) / r
		if frac <= best_frac:
			best = i
			best_frac = frac
	if best >= 0:
		_drag_index = best
		_handles[best].color = HANDLE_DRAG_COLOR

func _toggle() -> void:
	active = not active
	get_tree().paused = active
	_drag_index = -1
	_label.visible = active
	for h in _handles:
		h.visible = active

func _process(delta: float) -> void:
	if not active:
		return
	for i in entries.size():
		_handles[i].position = entries[i]["get"].call()
	if _saved_flash > 0.0:
		_saved_flash = maxf(_saved_flash - delta, 0.0)
	_label.text = "LAYOUT EDIT - drag the cyan handles, S to save, E to exit%s" % (
		"  (saved!)" if _saved_flash > 0.0 else "")

func _save() -> void:
	var data := {}
	for e in entries:
		var p: Vector2 = e["get"].call()
		data[e["name"]] = [p.x, p.y]
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
	_saved_flash = 1.5

## Static so table.gd can call it once at startup without an instance.
static func load_overrides() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
