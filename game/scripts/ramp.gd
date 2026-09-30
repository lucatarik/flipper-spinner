extends Node2D
## Elevated ramp (D2). A centreline polyline drawn as two gold wire rails. The
## rails have NO colliders: the ball is held on the centreline kinematically
## (below), and physical rails only ever got in the way — they pinched the ball
## at sharp bends and blocked it wherever two wires cross (the figure-8, or one
## ramp passing over another's entrance). A ball entering through the mouth while
## moving into the ramp is switched to layer-16 collision (nothing lives on that
## layer any more, so it touches nothing while riding), lifted above the table
## (scale + drop shadow) and then SCRIPTED along the whole centreline: any ball
## that goes in with enough force to start rolling always completes the ramp
## (user request) at a steady ride speed, then drops back onto the playfield at
## the end point (EXIT) at a gentle, catchable speed and emits `made`. A shot
## too weak to enter (under MOUTH_SPEED into the mouth) simply isn't taken.

signal entered(ramp_name: String)
signal made(ramp_name: String)

const WIDTH := 36.0
const RAIL_THICK := 5.0
## Entry: moving into the mouth faster than this (px/s) inside MOUTH_RADIUS.
const MOUTH_SPEED := 150.0
const MOUTH_RADIUS := 44.0
## Scripted ride speed = the entry speed clamped to this range; it eases a
## little faster on descents and slower on climbs so it still feels physical.
const RIDE_MIN_SPEED := 900.0
const RIDE_MAX_SPEED := 1500.0
const RIDE_SLOPE_ACCEL := 500.0
## Leaving the wire: slow enough for the player to catch on the flipper.
const EXIT_SPEED := 420.0
const PLAYFIELD_MASK := 7  # layers 1|2|3 (walls, ball, flippers)

const STONE_DARK := Color("#4a4030")
const GOLD := Color("#d4a017")

var ramp_name := ""
var mouth_dir := Vector2(0.0, -1.0)
var exit_dir := Vector2(0.0, 1.0)
var points: PackedVector2Array = PackedVector2Array()

var _seg_len: Array = []
var _total := 0.0
var commit_s := 0.0
var _balls := {}
var _ball_nodes := {}
var _lamps: Array = []
var _chase := 0.0
var _arrow: Node2D
var _pulse_t := 0.0
var _mouth: Area2D

func configure(p_name: String, centre: PackedVector2Array, mouth_direction: Vector2,
		commit_point: Vector2, exit_direction: Vector2) -> void:
	ramp_name = p_name
	points = _smooth(centre, 2)
	mouth_dir = mouth_direction.normalized()
	exit_dir = exit_direction.normalized()
	_compute_lengths()
	commit_s = _project(commit_point)
	call_deferred("_build")

func _ready() -> void:
	if points.size() > 1 and _lamps.is_empty():
		call_deferred("_build")

## Chaikin corner cutting (endpoints kept): hand-placed centrelines with sharp
## bends become rounded wire curves, for both the drawing and the ride.
static func _smooth(src: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var pts := src
	for it in iterations:
		if pts.size() < 3:
			return pts
		var out := PackedVector2Array()
		out.append(pts[0])
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			if i > 0:
				out.append(a.lerp(b, 0.25))
			if i < pts.size() - 2:
				out.append(a.lerp(b, 0.75))
		out.append(pts[pts.size() - 1])
		pts = out
	return pts

func _compute_lengths() -> void:
	_seg_len = []
	_total = 0.0
	for i in points.size() - 1:
		var l := points[i].distance_to(points[i + 1])
		_seg_len.append(l)
		_total += l

# --- geometry helpers -------------------------------------------------------

func _point_at(s: float) -> Vector2:
	var d := clampf(s, 0.0, _total)
	var acc := 0.0
	for i in _seg_len.size():
		var l: float = _seg_len[i]
		if d <= acc + l or i == _seg_len.size() - 1:
			var t := 0.0 if l <= 0.0 else (d - acc) / l
			return points[i].lerp(points[i + 1], clampf(t, 0.0, 1.0))
		acc += l
	return points[points.size() - 1]

func _tangent_at(s: float) -> Vector2:
	var d := clampf(s, 0.0, _total - 0.001)
	var acc := 0.0
	for i in _seg_len.size():
		var l: float = _seg_len[i]
		if d <= acc + l or i == _seg_len.size() - 1:
			return (points[i + 1] - points[i]).normalized()
		acc += l
	return (points[points.size() - 1] - points[points.size() - 2]).normalized()

func _project(pos: Vector2) -> float:
	var best := INF
	var best_s := 0.0
	var acc := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 <= 0.0 else clampf((pos - a).dot(ab) / l2, 0.0, 1.0)
		var p := a + ab * t
		var dist := pos.distance_squared_to(p)
		if dist < best:
			best = dist
			best_s = acc + _seg_len[i] * t
		acc += _seg_len[i]
	return best_s

# --- ball state -------------------------------------------------------------

func _on_mouth_body(body: Node) -> void:
	if not body.is_in_group("balls"):
		return
	if body.get_meta("on_ramp", false):
		return
	var rb := body as RigidBody2D
	if rb == null:
		return
	if rb.linear_velocity.dot(mouth_dir) <= MOUTH_SPEED:
		return
	_enter(rb)

func _enter(ball: RigidBody2D) -> void:
	var id := ball.get_instance_id()
	if _balls.has(id):
		return
	ball.collision_mask = 16
	# Off the playfield layer while riding, so the table's sensors (scoop,
	# vortex pits, lanes, bumpers...) can't grab a ball passing overhead —
	# the figure-8 goes right over the idol scoop.
	ball.set_meta("ramp_saved_layer", ball.collision_layer)
	ball.collision_layer = 0
	ball.set_meta("on_ramp", true)
	ball.set_meta("ramp_name", ramp_name)
	ball.z_index = 7
	if ball.has_method("set_lifted"):
		ball.set_lifted(true)
	# always ride from the start of the wire, whatever edge of the (big) mouth
	# the ball clipped
	var ride := clampf(ball.linear_velocity.length(), RIDE_MIN_SPEED, RIDE_MAX_SPEED)
	_balls[id] = {"s": 0.0, "committed": false, "v": ride, "v0": ride}
	_ball_nodes[id] = ball
	ball.global_position = points[0]
	ball.linear_velocity = _tangent_at(0.0) * ride
	entered.emit(ramp_name)

func _physics_process(delta: float) -> void:
	if _balls.is_empty():
		return
	for id in _balls.keys():
		var ball = _ball_nodes.get(id)
		if ball == null or not is_instance_valid(ball) or ball.get_meta("drained", false):
			_balls.erase(id)
			_ball_nodes.erase(id)
			continue
		var rec: Dictionary = _balls[id]
		var s: float = float(rec["s"])
		var t := _tangent_at(s)
		# Scripted ride: never stalls or rolls back. Screen-down (+y) slopes
		# speed it up a bit, climbs slow it, always within the ride range.
		var v: float = float(rec["v"]) + t.y * RIDE_SLOPE_ACCEL * delta
		v = clampf(v, RIDE_MIN_SPEED, RIDE_MAX_SPEED)
		rec["v"] = v
		s += v * delta
		if s >= _total:
			_exit(int(id), ball)
			continue
		rec["s"] = s
		if not bool(rec["committed"]) and s >= commit_s:
			rec["committed"] = true
		ball.global_position = _point_at(s)
		ball.linear_velocity = _tangent_at(s) * v

func _exit(id: int, ball: RigidBody2D) -> void:
	_cleanup(id, ball)
	ball.global_position = points[points.size() - 1]
	ball.linear_velocity = exit_dir * EXIT_SPEED
	made.emit(ramp_name)
	_chase = 1.0

func _cleanup(id: int, ball: RigidBody2D) -> void:
	_balls.erase(id)
	_ball_nodes.erase(id)
	ball.collision_mask = PLAYFIELD_MASK
	ball.collision_layer = int(ball.get_meta("ramp_saved_layer", 2))
	ball.remove_meta("ramp_saved_layer")
	ball.remove_meta("on_ramp")
	ball.remove_meta("ramp_name")
	ball.z_index = 6
	if ball.has_method("set_lifted"):
		ball.set_lifted(false)

# --- construction -----------------------------------------------------------

func _build() -> void:
	if not _lamps.is_empty() or points.size() < 2:
		return
	_build_visuals()
	_build_mouth()

## Wireform look (user request, matching a real elevated-wire pinball ramp):
## no solid deck at all — just the two rails, sparse cross-braces and support
## posts, so the playfield art stays visible underneath and the ball reads as
## riding an actual wire rather than sliding on a painted track.
func _build_visuals() -> void:
	var left_rail := _offset_path(1.0, WIDTH * 0.5)
	var right_rail := _offset_path(-1.0, WIDTH * 0.5)

	# each wire casts its own thin shadow, not one solid band
	for rail_pts in [left_rail, right_rail]:
		var shadow := Line2D.new()
		var sp := PackedVector2Array()
		for p in rail_pts:
			sp.append(p + Vector2(6.0, 8.0))
		shadow.points = sp
		shadow.width = RAIL_THICK + 3.0
		shadow.default_color = Color(0, 0, 0, 0.35)
		shadow.z_index = 1
		add_child(shadow)

	# support posts under each wire (not one central post)
	for i in range(1, points.size() - 1, 2):
		for rail_pts in [left_rail, right_rail]:
			var pil := Polygon2D.new()
			pil.polygon = PackedVector2Array([
				Vector2(-2, 0), Vector2(2, 0), Vector2(2, 14), Vector2(-2, 14)])
			pil.color = STONE_DARK
			pil.position = rail_pts[i] + Vector2(0, 4)
			pil.z_index = 5
			add_child(pil)

	# sparse cross-wires bracing the two rails, like a real wireform ramp
	var rung_step: int = max(2, int(_total / 90.0))
	for i in range(rung_step + 1):
		var s := _total * float(i) / float(rung_step)
		var center := _point_at(s)
		var t := _tangent_at(s)
		var n := Vector2(-t.y, t.x)
		var rung := Line2D.new()
		rung.points = PackedVector2Array([center - n * (WIDTH * 0.5), center + n * (WIDTH * 0.5)])
		rung.width = 2.0
		rung.default_color = GOLD.darkened(0.25)
		rung.z_index = 6
		add_child(rung)

	# the two gold wires themselves — this IS the ramp, no fill between them
	for rail_pts in [left_rail, right_rail]:
		var rail_edge := Line2D.new()
		rail_edge.points = rail_pts
		rail_edge.width = RAIL_THICK + 2.0
		rail_edge.default_color = STONE_DARK
		rail_edge.z_index = 7
		add_child(rail_edge)
		var rail := Line2D.new()
		rail.points = rail_pts
		rail.width = RAIL_THICK
		rail.default_color = GOLD
		rail.z_index = 8
		add_child(rail)

	var steps: int = max(2, int(_total / 70.0))
	for i in range(steps + 1):
		var s := _total * float(i) / float(steps)
		var lamp := _make_dot(_point_at(s), 4.0)
		lamp.color = GOLD.darkened(0.55)
		_lamps.append(lamp)

func _offset_path(side: float, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points.size():
		var d: Vector2
		if i == 0:
			d = (points[1] - points[0]).normalized()
		elif i == points.size() - 1:
			d = (points[i] - points[i - 1]).normalized()
		else:
			d = (points[i + 1] - points[i - 1]).normalized()
		out.append(points[i] + Vector2(-d.y, d.x) * dist * side)
	return out

func _build_mouth() -> void:
	_mouth = Area2D.new()
	_mouth.name = "Mouth"
	_mouth.collision_layer = 8
	_mouth.collision_mask = 2
	_mouth.position = points[0]
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = MOUTH_RADIUS
	cs.shape = c
	_mouth.add_child(cs)
	add_child(_mouth)
	_mouth.body_entered.connect(_on_mouth_body)
	_build_entry_arrow()

## Big pulsing "shoot here" arrow on the playfield just below the mouth,
## pointing into it, with the ramp's name under it (user: mark where each
## ramp starts). Purely visual.
func _build_entry_arrow() -> void:
	_arrow = Node2D.new()
	_arrow.position = points[0] - mouth_dir * 6.0  # below would sit on the wing bats
	_arrow.rotation = Vector2.UP.angle_to(mouth_dir)
	_arrow.z_index = 4
	add_child(_arrow)
	var shape := PackedVector2Array([
		Vector2(0, -26), Vector2(20, -4), Vector2(8, -4), Vector2(8, 22),
		Vector2(-8, 22), Vector2(-8, -4), Vector2(-20, -4)])
	var glow := Polygon2D.new()
	var big := PackedVector2Array()
	for v in shape:
		big.append(v * 1.45)
	glow.polygon = big
	glow.color = Color(1.0, 0.75, 0.2, 0.25)
	_arrow.add_child(glow)
	var body := Polygon2D.new()
	body.polygon = shape
	body.color = Color("#ffd24a")
	_arrow.add_child(body)
	var edge := Line2D.new()
	var loop := shape.duplicate()
	loop.append(shape[0])
	edge.points = loop
	edge.width = 3.0
	edge.default_color = Color("#3a2408")
	edge.joint_mode = Line2D.LINE_JOINT_ROUND
	_arrow.add_child(edge)
	var label := Label.new()
	label.text = ramp_name.replace(" RAMP", "")
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("#ffe9a8"))
	label.add_theme_color_override("font_outline_color", Color("#2a1604"))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(90, 20)
	label.position = _arrow.position + Vector2(-45, 26)
	label.z_index = 4
	add_child(label)

func _make_dot(pos: Vector2, radius: float) -> Polygon2D:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	var p := Polygon2D.new()
	p.polygon = pts
	p.position = pos
	p.color = GOLD
	p.z_index = 9
	add_child(p)
	return p

func _process(delta: float) -> void:
	_pulse_t += delta
	if _arrow:
		var k := 0.5 + 0.5 * sin(_pulse_t * 5.0)
		_arrow.modulate = Color(1, 1, 1).lerp(Color(1.6, 1.4, 1.0), k)
		_arrow.scale = Vector2.ONE * (1.0 + 0.08 * k)
	if _chase <= 0.0:
		return
	_chase = maxf(_chase - delta * 0.7, 0.0)
	var head := (1.0 - _chase) * float(_lamps.size())
	for i in _lamps.size():
		var lamp: Polygon2D = _lamps[i]
		var lit := maxf(0.0, 1.0 - absf(float(i) - head) / 4.0)
		lamp.color = GOLD.darkened(0.55).lerp(Color(1, 1, 1), lit)
