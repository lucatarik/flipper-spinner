extends RigidBody2D


const MAX_SPEED := 3200.0

var _visuals: Array = []
var _shadow: Polygon2D
var _lifted := false

func _ready() -> void:
	add_to_group("balls")
	z_index = 6
	_build_visual()
	_build_light()

func _build_light() -> void:
	var light := PointLight2D.new()
	light.texture = Glow.radial_texture()
	light.color = Color("#cfe4ff")
	light.energy = 0.5
	light.texture_scale = 1.4
	add_child(light)
	_visuals.append(light)

func _build_visual() -> void:
	_shadow = Polygon2D.new()
	var sh := PackedVector2Array()
	var n := 24
	for i in n:
		var a := TAU * float(i) / float(n)
		sh.append(Vector2(cos(a), sin(a)) * 12.0)
	_shadow.polygon = sh
	_shadow.color = Color(0, 0, 0, 0.4)
	_shadow.position = Vector2(8.0, 10.0)
	_shadow.z_index = -1
	_shadow.visible = false
	add_child(_shadow)

	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * 12.0)
	var body := Polygon2D.new()
	body.polygon = pts
	body.color = Color("#c8ccd0")
	add_child(body)
	_visuals.append(body)
	var shine := Polygon2D.new()
	var s := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		s.append(Vector2(cos(a), sin(a)) * 4.0 + Vector2(-4.0, -4.0))
	shine.polygon = s
	shine.color = Color("#ffffff")
	add_child(shine)
	_visuals.append(shine)

## D2: enlarged visual + soft drop shadow while the ball rides an elevated ramp.
func set_lifted(on: bool) -> void:
	_lifted = on
	var f := 1.15 if on else 1.0
	for v in _visuals:
		if v is Node2D:
			v.scale = Vector2(f, f)
	if _shadow:
		_shadow.visible = on

func _process(_delta: float) -> void:
	if _lifted and _shadow:
		_shadow.rotation = -rotation

func _physics_process(_delta: float) -> void:
	# Only clamp when actually over the limit: reassigning linear_velocity every
	# frame would cancel any impulse another node queued for this step.
	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.limit_length(MAX_SPEED)
