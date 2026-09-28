extends Node2D
## The 4-target INDY drop-target bank along the shooter-lane divider.

signal target_dropped(index: int)

const TargetScript = preload("res://scripts/drop_target.gd")

var targets: Array = []
var _letters := ["I", "N", "D", "Y"]

func build(x: float, ys: Array) -> void:
	for i in ys.size():
		var t = TargetScript.new()
		t.index = i
		t.position = Vector2(x, float(ys[i]))
		t.letter = _letters[i] if i < _letters.size() else ""
		add_child(t)
		t.dropped.connect(_on_dropped)
		targets.append(t)

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
