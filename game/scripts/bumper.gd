extends StaticBody2D
## Pop bumper. Solid cap that kicks the ball away from its centre (biased
## upward, see _on_body) and reports a "bumper" event through the hit signal.
## Carries a PointLight2D that flashes on hit, a brief overbright flash on its
## own sprite, and a small one-shot spark/fire particle burst.
## After a randomized 5-15 hits it "explodes" (big burst + `exploded` signal),
## vanishes (no collision, hidden) and comes back ~30s later with a fresh
## random threshold — see _explode()/_respawn().

signal hit
signal exploded


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

const EXPLODE_HITS_MIN := 5
const EXPLODE_HITS_MAX := 15
const RESPAWN_SECONDS_MIN := 28.0
const RESPAWN_SECONDS_MAX := 32.0

@export var radius := 30.0

var _cooldowns := {}
var _light: PointLight2D
var _glow := 0.45
var _lit := false
var _sprite: Sprite2D
var _flash_t := 0.0
var _fire: CPUParticles2D
var _big_fire: CPUParticles2D
var _detect: Area2D

var _hit_count := 0
var _explode_threshold := 0
var _exploded := false
var _respawn_timer := 0.0

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

	_fire = _build_fire(14, 0.35, 60.0, 160.0, 2.0, 4.0)
	add_child(_fire)
	_big_fire = _build_fire(40, 0.6, 120.0, 320.0, 3.0, 6.0)
	_big_fire.gravity = Vector2(0.0, 60.0)
	add_child(_big_fire)

	_detect = Area2D.new()
	_detect.name = "Detect"
	_detect.collision_layer = 8
	_detect.collision_mask = 2
	var ds := CollisionShape2D.new()
	var dc := CircleShape2D.new()
	dc.radius = radius + 8.0
	ds.shape = dc
	_detect.add_child(ds)
	add_child(_detect)
	_detect.body_entered.connect(_on_body)

	_explode_threshold = randi_range(EXPLODE_HITS_MIN, EXPLODE_HITS_MAX)

func _build_fire(amount: int, lifetime: float, vmin: float, vmax: float,
		smin: float, smax: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 1.0
	p.direction = Vector2(0.0, -1.0)
	p.spread = 180.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector2(0.0, -40.0)
	p.scale_amount_min = smin
	p.scale_amount_max = smax
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
	_hit_count += 1
	if _hit_count >= _explode_threshold:
		_explode()

func _explode() -> void:
	_exploded = true
	_respawn_timer = randf_range(RESPAWN_SECONDS_MIN, RESPAWN_SECONDS_MAX)
	_glow = 4.5
	if _light:
		_light.energy = _glow
	if _big_fire:
		_big_fire.restart()
		_big_fire.emitting = true
	visible = false
	collision_layer = 0
	if _detect:
		_detect.set_deferred("monitoring", false)
	exploded.emit()

func _respawn() -> void:
	_exploded = false
	_hit_count = 0
	_explode_threshold = randi_range(EXPLODE_HITS_MIN, EXPLODE_HITS_MAX)
	visible = true
	collision_layer = 1
	if _detect:
		_detect.set_deferred("monitoring", true)
	_glow = 2.2
	_flash_t = FLASH_TIME

func _process(delta: float) -> void:
	if _exploded:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
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
