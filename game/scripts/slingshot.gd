extends StaticBody2D
## Slingshot. Solid stone triangle that kicks balls off its inner face and reports
## a "sling" event. The kicking face carries a gold rubber line that flashes on hit.

signal hit

const KICK_IMPULSE := 650.0
const COOLDOWN_MS := 120
const STONE := Color("#6b6b6b")
const GOLD := Color("#d4a017")

var kick_dir := Vector2(1.0, -0.4)
var _cooldowns := {}
var _configured := false
var _rubber: Line2D
var _flash := 0.0

func configure(poly: PackedVector2Array, kick: Vector2, rubber_a := Vector2.ZERO, rubber_b := Vector2.ZERO) -> void:
	if _configured:
		return
	_configured = true
	kick_dir = kick.normalized()
	collision_layer = 1
	collision_mask = 0

	var vis := Polygon2D.new()
	vis.polygon = poly
	vis.color = STONE
	add_child(vis)

	var outline := Line2D.new()
	outline.points = poly
	outline.closed = true
	outline.width = 3.0
	outline.default_color = Color("#3a2c0c")
	add_child(outline)

	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	add_child(cp)

	if rubber_a == Vector2.ZERO and rubber_b == Vector2.ZERO:
		rubber_a = poly[0]
		rubber_b = poly[2]
	_rubber = Line2D.new()
	_rubber.points = PackedVector2Array([rubber_a, rubber_b])
	_rubber.width = 8.0
	_rubber.default_color = GOLD
	add_child(_rubber)

	var detect := Area2D.new()
	detect.name = "Detect"
	detect.collision_layer = 8
	detect.collision_mask = 2
	var cs := CollisionShape2D.new()
	var shape := ConvexPolygonShape2D.new()
	var grown := PackedVector2Array()
	for p in poly:
		grown.append(p * 1.02)
	shape.points = grown
	cs.shape = shape
	detect.add_child(cs)
	add_child(detect)
	detect.body_entered.connect(_on_body)

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = max(_flash - delta * 4.0, 0.0)
		if _rubber:
			_rubber.default_color = GOLD.lerp(Color("#fff2b0"), _flash)

func _on_body(body: Node) -> void:
	if not (body is RigidBody2D):
		return
	var now := Time.get_ticks_msec()
	var id := body.get_instance_id()
	if now - int(_cooldowns.get(id, -99999)) < COOLDOWN_MS:
		return
	_cooldowns[id] = now
	body.apply_central_impulse(kick_dir * KICK_IMPULSE)
	_flash = 1.0
	if _rubber:
		_rubber.default_color = Color("#fff2b0")
	hit.emit()
