extends RigidBody2D


const MAX_SPEED := 3200.0

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

func _build_visual() -> void:
	var pts := PackedVector2Array()
	var n := 24
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * 12.0)
	var body := Polygon2D.new()
	body.polygon = pts
	body.color = Color("#c8ccd0")
	add_child(body)
	var shine := Polygon2D.new()
	var s := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		s.append(Vector2(cos(a), sin(a)) * 4.0 + Vector2(-4.0, -4.0))
	shine.polygon = s
	shine.color = Color("#ffffff")
	add_child(shine)

func _physics_process(_delta: float) -> void:
	# Only clamp when actually over the limit: reassigning linear_velocity every
	# frame would cancel any impulse another node queued for this step.
	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.limit_length(MAX_SPEED)
