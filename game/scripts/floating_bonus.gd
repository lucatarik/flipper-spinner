extends Node2D
## "Soft" bonus pickup: pure Area2D, no collision body at all, so the ball rolls
## straight through it (no resistance). Appears at a random spot on the table,
## picks a random kind, pulses/spins, and grants a small bonus on touch — or
## just fades away if nothing touches it before LIFETIME runs out.

signal collected(kind: String)

const KINDS := ["points", "multiplier", "ball_save"]
const RADIUS := 16.0
const LIFETIME := 12.0

const KIND_COLORS := {
	"points": Color("#ffd24a"),
	"multiplier": Color("#ff6fae"),
	"ball_save": Color("#5bffa0"),
}

var kind := "points"

var _glow: PointLight2D
var _shape: Polygon2D
var _time := 0.0
var _life := LIFETIME
var _collected := false

func _ready() -> void:
	z_index = 4
	kind = KINDS[randi() % KINDS.size()]
	_build_visual()
	_build_detect()

func _build_visual() -> void:
	var color: Color = KIND_COLORS.get(kind, Color.WHITE)
	var pts := _blob_points()
	_shape = Polygon2D.new()
	_shape.polygon = pts
	_shape.color = Color(color.r, color.g, color.b, 0.85)
	add_child(_shape)

	var outline := Line2D.new()
	outline.points = pts
	outline.closed = true
	outline.width = 2.0
	outline.default_color = Color.WHITE
	add_child(outline)

	_glow = PointLight2D.new()
	_glow.texture = Glow.radial_texture()
	_glow.color = color
	_glow.energy = 1.0
	_glow.texture_scale = 1.6
	add_child(_glow)

## Soft 10-point "blob" (alternating radius) instead of a plain circle, so it
## reads as a pickup rather than another bumper.
func _blob_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var total := 10
	for i in total:
		var a := TAU * float(i) / float(total)
		var r := RADIUS if i % 2 == 0 else RADIUS * 0.55
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _build_detect() -> void:
	var area := Area2D.new()
	area.name = "Touch"
	area.collision_layer = 8
	area.collision_mask = 2
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS + 6.0
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
	scale = Vector2.ONE * (1.0 + 0.08 * sin(_time * 4.0))
	rotation = _time * 0.6
	if _glow:
		_glow.energy = 0.8 + 0.5 * absf(sin(_time * 3.0))
	_life -= delta
	if _life <= 0.0 and not _collected:
		_collected = true
		queue_free()
