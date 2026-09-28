extends Node2D
## "Soft" bonus pickup: pure Area2D, no collision body at all, so the ball rolls
## straight through it (no resistance). Appears at a random spot on the table as
## one of the game's own Egyptian slot-symbol icons (not a generic orb), glowing
## and gently pulsing, and grants a small bonus on touch — or just fades away if
## nothing touches it before LIFETIME runs out.

signal collected(kind: String)

const KINDS := ["points", "multiplier", "ball_save"]
const TARGET_SIZE := 42.0
const LIFETIME := 12.0

## Reuse the game's existing slot-symbol art instead of a plain shape: emerald
## (treasure -> points), scarab (Egyptian luck/multiply symbol -> multiplier),
## ankh (symbol of life -> ball save).
const TEX_POINTS = preload("res://assets/slot/emerald.png")
const TEX_MULTIPLIER = preload("res://assets/slot/scarab.png")
const TEX_BALL_SAVE = preload("res://assets/slot/ankh.png")

const KIND_COLORS := {
	"points": Color("#ffd24a"),
	"multiplier": Color("#ff6fae"),
	"ball_save": Color("#5bffa0"),
}

var kind := "points"

var _sprite: Sprite2D
var _glow: PointLight2D
var _base_scale := 1.0
var _time := 0.0
var _life := LIFETIME
var _collected := false

func _ready() -> void:
	z_index = 4
	kind = KINDS[randi() % KINDS.size()]
	_build_visual()
	_build_detect()

func _kind_texture() -> Texture2D:
	match kind:
		"multiplier":
			return TEX_MULTIPLIER
		"ball_save":
			return TEX_BALL_SAVE
		_:
			return TEX_POINTS

func _build_visual() -> void:
	var color: Color = KIND_COLORS.get(kind, Color.WHITE)

	_glow = PointLight2D.new()
	_glow.texture = Glow.radial_texture()
	_glow.color = color
	_glow.energy = 1.4
	_glow.texture_scale = 2.4
	add_child(_glow)

	var tex := _kind_texture()
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_base_scale = TARGET_SIZE / maxf(float(tex.get_width()), float(tex.get_height()))
	_sprite.scale = Vector2.ONE * _base_scale
	add_child(_sprite)

func _build_detect() -> void:
	var area := Area2D.new()
	area.name = "Touch"
	area.collision_layer = 8
	area.collision_mask = 2
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = TARGET_SIZE * 0.5 + 8.0
	cs.shape = c
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body)

func _on_body(body: Node) -> void:
	if _collected or not (body is RigidBody2D) or not body.is_in_group("balls"):
		return
	_collected = true
	collected.emit(kind)
	queue_free()

func _physics_process(delta: float) -> void:
	_time += delta
	if _sprite:
		_sprite.scale = Vector2.ONE * _base_scale * (1.0 + 0.1 * sin(_time * 4.0))
	if _glow:
		_glow.energy = 1.1 + 0.7 * absf(sin(_time * 3.0))
	_life -= delta
	if _life <= 0.0 and not _collected:
		_collected = true
		queue_free()
