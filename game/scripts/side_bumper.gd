extends StaticBody2D
## Side-wall half-disc kicker bumper. The flat side sits flush on the wall and
## the domed side kicks a contacting ball away from the wall along `normal`,
## firing the same "bumper" event as a pop bumper. Carries a glow light.

signal hit

const KICK_IMPULSE := 750.0
const COOLDOWN_MS := 120

@export var radius := 22.0
## Direction the disc bulges / the direction a ball is kicked (away from the wall).
@export var normal := Vector2.RIGHT

var _cooldowns := {}
var _light: PointLight2D
var _glow := 0.45

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cp := CollisionPolygon2D.new()
	cp.polygon = _half_disc(radius)
	add_child(cp)

	_light = PointLight2D.new()
	_light.texture = Glow.radial_texture()
	_light.color = Color("#ffcf5a")
	_light.energy = _glow
	_light.texture_scale = 1.8
	add_child(_light)

	var detect := Area2D.new()
	detect.name = "Detect"
	detect.collision_layer = 8
	detect.collision_mask = 2
	var ds := CollisionShape2D.new()
	var dc := CircleShape2D.new()
	dc.radius = radius + 8.0
	ds.shape = dc
	detect.add_child(ds)
	add_child(detect)
	detect.body_entered.connect(_on_body)

## Semicircle of radius r bulging along `normal`; the flat diameter lies on the
## wall (perpendicular to `normal`) through the node origin.
func _half_disc(r: float) -> PackedVector2Array:
	var n := Vector2(normal).normalized()
	var t := Vector2(-n.y, n.x)
	var pts := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var a := -PI * 0.5 + PI * float(i) / float(steps)
		pts.append(n * (r * cos(a)) + t * (r * sin(a)))
	return pts

func _on_body(body: Node) -> void:
	var rb := body as RigidBody2D
	if rb == null:
		return
	var now := Time.get_ticks_msec()
	var id := rb.get_instance_id()
	if now - int(_cooldowns.get(id, -99999)) < COOLDOWN_MS:
		return
	_cooldowns[id] = now
	rb.apply_central_impulse(Vector2(normal).normalized() * KICK_IMPULSE)
	if _light:
		_glow = 1.8
	hit.emit()

func _process(delta: float) -> void:
	if _light == null:
		return
	if _glow > 0.45:
		_glow = max(0.45, _glow - delta * 5.0)
		_light.energy = _glow
