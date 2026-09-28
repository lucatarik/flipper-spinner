extends StaticBody2D
## Pop bumper. Solid cap that kicks the ball away from its centre (biased
## upward, see _on_body) and reports a "bumper" event through the hit signal.
## Carries a PointLight2D that flashes on hit, a brief overbright flash on its
## own sprite, and a small one-shot spark/fire particle burst.

signal hit


const KICK_IMPULSE := 1066.0    # +30% bounce power (user request), was 820.0
const COOLDOWN_MS := 120
const COLOR_OFF := Color("#ffcf5a")
const COLOR_LIT := Color("#5bffa0")
const FLASH_COLOR := Color(2.4, 2.1, 1.1)   # >1 channel = overbright via modulate
const FLASH_TIME := 0.12
## A hit's radial kick direction gets its downward component softened and its
## upward component boosted, so the ball tends to fly up off a bumper more
## than it falls back down, whichever side it was hit from (user request).
const DOWNWARD_SOFTEN := 0.35
const UPWARD_BOOST := 1.15

@export var radius := 30.0

var _cooldowns := {}
var _light: PointLight2D
var _glow := 0.45
var _lit := false
var _sprite: Sprite2D
var _flash_t := 0.0
var _fire: CPUParticles2D

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

	_fire = _build_fire()
	add_child(_fire)

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

func _build_fire() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector2(0.0, -1.0)
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 160.0
	p.gravity = Vector2(0.0, -40.0)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color_ramp = _fire_gradient()
	return p

func _fire_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.5, 1.0))
	g.add_point(0.4, Color(1.0, 0.55, 0.1, 0.9))
	g.set_color(1, Color(0.6, 0.1, 0.05, 0.0))
	return g

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
	dir = dir.normalized()
	dir.y *= DOWNWARD_SOFTEN if dir.y > 0.0 else UPWARD_BOOST
	dir = dir.normalized()
	rb.apply_central_impulse(dir * KICK_IMPULSE)
	_glow = 2.6
	_flash_t = FLASH_TIME
	if _fire:
		_fire.restart()
		_fire.emitting = true
	hit.emit()

func _process(delta: float) -> void:
	if _glow > 0.45:
		_glow = max(0.45, _glow - delta * 4.0)
		if _light:
			_light.energy = _glow
	if _flash_t > 0.0:
		_flash_t = max(0.0, _flash_t - delta)
		_apply_sprite_flash(_flash_t / FLASH_TIME)
	elif _sprite:
		_sprite.modulate = Color.WHITE

## The bumper.png sprite is reparented onto this node by table.gd right after
## _ready() runs, so it isn't a child yet when _ready() fires — looked up
## lazily here instead of cached upfront.
func _apply_sprite_flash(strength: float) -> void:
	if _sprite == null:
		_sprite = _find_sprite()
		if _sprite == null:
			return
	_sprite.modulate = Color.WHITE.lerp(FLASH_COLOR, strength)

func _find_sprite() -> Sprite2D:
	for c in get_children():
		if c is Sprite2D:
			return c
	return null
