extends Node2D
## Elevated ramp (D2). A centreline polyline with two gold rails on physics layer 5
## (bit 16) that playfield balls never touch. A ball entering through the mouth while
## moving into the ramp is switched to layer-16 collision, lifted above the table
## (scale + drop shadow) and guided along the centreline; gravity acts on its
## along-path speed, so a weak shot rolls back out (FALL BACK) and a strong one
## exits at the end point onto the playfield layers (EXIT) and emits `made`.

signal entered(ramp_name: String)
signal made(ramp_name: String)

const WIDTH := 36.0
const RAIL_THICK := 5.0
const MOUTH_SPEED := 250.0
const MIN_EXIT_SPEED := 200.0
const GRAVITY := 1400.0
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
var _mouth: Area2D

func configure(p_name: String, centre: PackedVector2Array, mouth_direction: Vector2,
		commit_point: Vector2, exit_direction: Vector2) -> void:
	ramp_name = p_name
	points = centre
	mouth_dir = mouth_direction.normalized()
	exit_dir = exit_direction.normalized()
	_compute_lengths()
	commit_s = _project(commit_point)
	call_deferred("_build")

func _ready() -> void:
	if points.size() > 1 and _lamps.is_empty():
		call_deferred("_build")

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
	ball.set_meta("on_ramp", true)
	ball.set_meta("ramp_name", ramp_name)
	ball.z_index = 7
	if ball.has_method("set_lifted"):
		ball.set_lifted(true)
	var s := clampf(_project(ball.global_position), 0.0, _total)
	_balls[id] = {"s": s, "committed": false}
	_ball_nodes[id] = ball
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
		# The physics server already applied gravity, so read the along-path speed.
		var speed: float = ball.linear_velocity.dot(t)
		s += speed * delta
		if s <= 0.0 and speed < 0.0:
			_fall_back(int(id), ball, t, speed)
			continue
		if s >= _total:
			_exit(int(id), ball, speed)
			continue
		rec["s"] = s
		if not bool(rec["committed"]) and s >= commit_s:
			rec["committed"] = true
		ball.global_position = _point_at(s)
		ball.linear_velocity = t * speed

func _fall_back(id: int, ball: RigidBody2D, tangent: Vector2, speed: float) -> void:
	_cleanup(id, ball)
	ball.global_position = points[0] - mouth_dir * 26.0
	ball.linear_velocity = tangent.normalized() * minf(speed, -MIN_EXIT_SPEED)

func _exit(id: int, ball: RigidBody2D, speed: float) -> void:
	_cleanup(id, ball)
	ball.global_position = points[points.size() - 1]
	ball.linear_velocity = exit_dir * maxf(absf(speed), MIN_EXIT_SPEED)
	made.emit(ramp_name)
	_chase = 1.0

func _cleanup(id: int, ball: RigidBody2D) -> void:
	_balls.erase(id)
	_ball_nodes.erase(id)
	ball.collision_mask = PLAYFIELD_MASK
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
	_build_rails()
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

func _build_rails() -> void:
	var sb := StaticBody2D.new()
	sb.name = "RampRails"
	sb.collision_layer = 16
	sb.collision_mask = 0
	add_child(sb)
	for i in points.size() - 1:
		for side in [1.0, -1.0]:
			_add_rail_quad(sb, points[i], points[i + 1], side)

func _add_rail_quad(sb: StaticBody2D, a: Vector2, b: Vector2, side: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * side
	var c := n * (WIDTH * 0.5)
	var half := n * (RAIL_THICK * 0.5)
	var poly := PackedVector2Array([a + c + half, b + c + half, b + c - half, a + c - half])
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	sb.add_child(cp)

func _build_mouth() -> void:
	_mouth = Area2D.new()
	_mouth.name = "Mouth"
	_mouth.collision_layer = 8
	_mouth.collision_mask = 2
	_mouth.position = points[0]
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 24.0
	cs.shape = c
	_mouth.add_child(cs)
	add_child(_mouth)
	_mouth.body_entered.connect(_on_mouth_body)

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
	if _chase <= 0.0:
		return
	_chase = maxf(_chase - delta * 0.7, 0.0)
	var head := (1.0 - _chase) * float(_lamps.size())
	for i in _lamps.size():
		var lamp: Polygon2D = _lamps[i]
		var lit := maxf(0.0, 1.0 - absf(float(i) - head) / 4.0)
		lamp.color = GOLD.darkened(0.55).lerp(Color(1, 1, 1), lit)
