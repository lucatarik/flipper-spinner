extends Node2D
## The golden idol at the top of the table "kidnaps" the ball now and then.
## Dormant most of the time; every DORMANT_MIN-MAX seconds of real play it
## AWAKENS for up to AWAKE_SECONDS (pulsing aura, glowing eyes). A ball that
## touches it while awake is grabbed like a hole, held HOLD seconds with the
## idol blazing, then flung out at KICK_SPEED in a random direction — never
## within NO_DOWN_DEG of straight down, so it can't be an instant centre drain.
## Pure sensor: no collision of its own, so the ball rolls over it while dormant.

signal awakened
signal captured
signal released

const RADIUS := 34.0
const HOLD := 1.4
const KICK_SPEED := 1500.0
const NO_DOWN_DEG := 25.0
const DORMANT_MIN := 12.0
const DORMANT_MAX := 25.0
const AWAKE_SECONDS := 12.0
const COOLDOWN := 1.0
const EYE_OFFSETS := [Vector2(-8.0, -58.0), Vector2(8.0, -58.0)]
const AURA_RADIUS := 95.0

## Gated by the table: only counts down / grabs while a ball is really in play.
var enabled := false
var armed := false
var holding := false
var rng := RandomNumberGenerator.new()

var _timer := 0.0
var _hold_t := 0.0
var _cooldown := 0.0
var _t := 0.0
var _ball: RigidBody2D = null
var _aura: Sprite2D
var _eyes: Array = []

func _ready() -> void:
	rng.randomize()
	reset()
	_build()

func reset() -> void:
	armed = false
	_timer = rng.randf_range(DORMANT_MIN, DORMANT_MAX)
	if holding:
		_release()

func arm() -> void:
	if holding:
		return
	armed = true
	_timer = AWAKE_SECONDS
	awakened.emit()

func _build() -> void:
	_aura = Sprite2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.35, 1.0))
	g.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_aura.texture = tex
	_aura.scale = Vector2.ONE * (AURA_RADIUS / 32.0)
	_aura.position = Vector2(0.0, -25.0)
	_aura.modulate.a = 0.0
	add_child(_aura)
	for off in EYE_OFFSETS:
		var eye := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 10:
			var a := TAU * float(i) / 10.0
			pts.append(Vector2(cos(a) * 4.0, sin(a) * 2.6))
		eye.polygon = pts
		eye.position = off
		eye.color = Color(0, 0, 0, 0)
		add_child(eye)
		_eyes.append(eye)
	var area := Area2D.new()
	area.name = "Grab"
	area.collision_layer = 8
	area.collision_mask = 2
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS
	cs.shape = c
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body)

func _on_body(body: Node) -> void:
	if not armed or holding or _cooldown > 0.0 or not enabled:
		return
	if not (body is RigidBody2D) or not body.is_in_group("balls"):
		return
	if body.get_meta("on_ramp", false) or body.get_meta("held_by_hole", false):
		return
	_capture(body)

func _capture(b: RigidBody2D) -> void:
	holding = true
	armed = false
	_hold_t = 0.0
	_ball = b
	b.collision_layer = 0
	b.set_deferred("freeze", true)
	b.linear_velocity = Vector2.ZERO
	b.global_position = global_position
	b.set_meta("held_by_hole", true)
	captured.emit()

func _physics_process(delta: float) -> void:
	_t += delta
	if _cooldown > 0.0:
		_cooldown -= delta
	if holding:
		_hold_t += delta
		if is_instance_valid(_ball):
			# the idol "shakes" its prize
			_ball.global_position = global_position + Vector2(sin(_hold_t * 45.0) * 2.5, 0.0)
		if _hold_t >= HOLD:
			_release()
	elif enabled:
		_timer -= delta
		if _timer <= 0.0:
			if armed:
				armed = false
				_timer = rng.randf_range(DORMANT_MIN, DORMANT_MAX)
			else:
				arm()
	_update_visual()

func _release() -> void:
	var b := _ball
	holding = false
	_ball = null
	_cooldown = COOLDOWN
	_timer = rng.randf_range(DORMANT_MIN, DORMANT_MAX)
	if b != null and is_instance_valid(b):
		b.set_meta("held_by_hole", false)
		b.collision_layer = 2
		b.set_deferred("freeze", false)
		# deferred calls run in order: velocity is applied once unfrozen
		call_deferred("_launch", b, random_kick_dir() * KICK_SPEED)
	released.emit()

func _launch(b: RigidBody2D, v: Vector2) -> void:
	if is_instance_valid(b):
		b.linear_velocity = v

## Uniformly random direction, re-rolled while it points (almost) straight down.
func random_kick_dir() -> Vector2:
	var ang := 0.0
	for i in 32:
		ang = rng.randf_range(0.0, TAU)
		if absf(angle_difference(ang, PI * 0.5)) > deg_to_rad(NO_DOWN_DEG):
			break
	return Vector2(cos(ang), sin(ang))

func _update_visual() -> void:
	var aura_a := 0.0
	var eye_col := Color(0, 0, 0, 0)
	if holding:
		aura_a = 0.65 + 0.3 * absf(sin(_hold_t * 14.0))
		eye_col = Color(1.0, 0.95, 0.8, 1.0)
	elif armed:
		aura_a = 0.3 + 0.25 * (0.5 + 0.5 * sin(_t * 5.0))
		eye_col = Color(1.0, 0.15, 0.05, 0.6 + 0.4 * absf(sin(_t * 9.0)))
	_aura.modulate.a = move_toward(_aura.modulate.a, aura_a, 0.08)
	for e in _eyes:
		e.color = eye_col
