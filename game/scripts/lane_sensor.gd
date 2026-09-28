extends Area2D
## Top rollover lane sensor. Reports a `lane` event (with index) once per ball.

signal lane_entered(index: int)

const COOLDOWN := 0.35

var index := 0
var _ids := {}

func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(34.0, 80.0)
	cs.shape = rect
	add_child(cs)
	body_entered.connect(_on_body)
	body_exited.connect(_on_exit)

func setup(i: int) -> void:
	index = i

func _on_body(body: Node) -> void:
	if not body.is_in_group("balls"):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var id := body.get_instance_id()
	if _ids.has(id) and now - float(_ids[id]) < COOLDOWN:
		return
	_ids[id] = now
	lane_entered.emit(index)

func _on_exit(body: Node) -> void:
	if _ids.has(body.get_instance_id()):
		_ids.erase(body.get_instance_id())
