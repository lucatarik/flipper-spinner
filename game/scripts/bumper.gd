extends StaticBody2D
## Pop bumper. Solid cap that kicks the ball away from its centre and reports a
## "bumper" event through the hit signal. Carries a PointLight2D that flashes on hit.

signal hit


const KICK_IMPULSE := 1066.0    # +30% bounce power (user request), was 820.0
const COOLDOWN_MS := 120
const COLOR_OFF := Color("#ffcf5a")
const COLOR_LIT := Color("#5bffa0")

@export var radius := 30.0

var _cooldowns := {}
var _light: PointLight2D
var _glow := 0.45
var _lit := false

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	add_child(cs)

	_light = PointLight2D.new()
	_light.texture = Glow.radial_texture()
	_light.color = COLOR_OFF
	_light.energy = _glow
	_light.texture_scale = 2.2
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

## Persistent "lit" state for the bonus-bumper bank: tints the glow green while lit,
## independent of the transient hit flash.
func set_lit(value: bool) -> void:
	_lit = value
	if _light:
		_light.color = COLOR_LIT if _lit else COLOR_OFF

func _on_body(body: Node) -> void:
	var rb := body as RigidBody2D
	if rb == null:
		return
	var now := Time.get_ticks_msec()
	var id := rb.get_instance_id()
	if now - int(_cooldowns.get(id, -99999)) < COOLDOWN_MS:
		return
	_cooldowns[id] = now
	var dir := rb.global_position - global_position
	if dir.length() < 0.001:
		dir = Vector2(0.0, -1.0)
	rb.apply_central_impulse(dir.normalized() * KICK_IMPULSE)
	if _light:
		_glow = 1.8
	hit.emit()

func _process(delta: float) -> void:
	if _light == null:
		return
	if _glow > 0.45:
		_glow = max(0.45, _glow - delta * 5.0)
		_light.energy = _glow
