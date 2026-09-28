extends SceneTree
## Physics smoke test. Instantiates the real main scene headless and drives
## inputs through the flipper / plunger APIs.

const RulesScript = preload("res://scripts/rules.gd")
const MainScene = preload("res://scenes/main.tscn")

func _initialize() -> void:
	_run()

func _run() -> void:
	var r1: bool = await _scenario_plunger()
	var r2: bool = await _scenario_flipper()
	var r3: bool = await _scenario_drain()
	var r4: bool = await _scenario_wall()
	var r5: bool = await _scenario_centre_gap()
	var r6: bool = await _scenario_cradle()
	var r7: bool = await _scenario_inlane()
	var r8: bool = await _scenario_scoop()
	var r9: bool = await _scenario_targets()
	var r10: bool = await _scenario_lane()
	var r11: bool = await _scenario_orbit()
	var r12: bool = await _scenario_multiball()
	var r13: bool = await _scenario_restart()
	var r14: bool = await _scenario_slot_cycles()
	var r15: bool = await _scenario_slot_forced_win()
	print("SMOKE: plunger launch reaches field: %s" % ("PASS" if r1 else "FAIL"))
	print("SMOKE: fired flipper launches ball (vy < -800): %s" % ("PASS" if r2 else "FAIL"))
	print("SMOKE: idle-flipper ball drains: %s" % ("PASS" if r3 else "FAIL"))
	print("SMOKE: fast ball stays in bounds: %s" % ("PASS" if r4 else "FAIL"))
	print("SMOKE: ball drains through centre gap: %s" % ("PASS" if r5 else "FAIL"))
	print("SMOKE: held flipper cradles ball: %s" % ("PASS" if r6 else "FAIL"))
	print("SMOKE: inlane ball reaches left flipper: %s" % ("PASS" if r7 else "FAIL"))
	print("SMOKE: scoop captures then kicks the ball: %s" % ("PASS" if r8 else "FAIL"))
	print("SMOKE: dart at each INDY target drops it + event: %s" % ("PASS" if r9 else "FAIL"))
	print("SMOKE: ball through a top lane fires lane: %s" % ("PASS" if r10 else "FAIL"))
	print("SMOKE: left orbit scores exactly once: %s" % ("PASS" if r11 else "FAIL"))
	print("SMOKE: request_multiball(2) -> 3 balls: %s" % ("PASS" if r12 else "FAIL"))
	print("SMOKE: game over then start restarts: %s" % ("PASS" if r13 else "FAIL"))
	print("SMOKE: slot completes >=3 cycles in 15s: %s" % ("PASS" if r14 else "FAIL"))
	print("SMOKE: forced winning grid raises score: %s" % ("PASS" if r15 else "FAIL"))
	var results := [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15]
	var failed := 0
	for r in results:
		if not r:
			failed += 1
	print("SMOKE SUMMARY: %d passed, %d failed" % [results.size() - failed, failed])
	quit(0 if failed == 0 else 1)

func _new_table():
	var t = MainScene.instantiate()
	root.add_child(t)
	await physics_frame
	await physics_frame
	return t

func _first_ball(t):
	var balls: Array = t.get_tree().get_nodes_in_group("balls")
	if balls.is_empty():
		return null
	return balls[0]

func _scenario_plunger() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	await physics_frame
	t.plunger.set_charging(true)
	for i in 288:
		await physics_frame
	t.plunger.set_charging(false)
	var reached := false
	for i in 720:
		await physics_frame
		var b = _first_ball(t)
		if b != null and b.position.x < 640.0 and b.position.y < 400.0:
			reached = true
			break
	t.queue_free()
	await physics_frame
	return reached

func _scenario_flipper() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	var b = t.spawn_ball(Vector2(278, 1118), Vector2.ZERO)
	t.rules.on_event("ball_added")
	for i in 30:
		await physics_frame
	t.left_flipper.set_pressed(true)
	var launched := false
	for i in 480:
		await physics_frame
		if not is_instance_valid(b):
			break
		if b.linear_velocity.y < -800.0:
			launched = true
			break
	t.queue_free()
	await physics_frame
	return launched

func _scenario_drain() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	var b = t.spawn_ball(Vector2(327, 980), Vector2.ZERO)
	t.rules.on_event("ball_added")
	t.left_flipper.set_pressed(false)
	t.right_flipper.set_pressed(false)
	var drained := false
	for i in 1200:
		await physics_frame
		if not is_instance_valid(b):
			drained = true
			break
	t.queue_free()
	await physics_frame
	return drained

func _scenario_wall() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	var b = t.spawn_ball(Vector2(360, 600), Vector2(3000, 0))
	var in_bounds := true
	for i in 600:
		await physics_frame
		if not is_instance_valid(b):
			continue
		var p: Vector2 = b.position
		if p.x < -50.0 or p.x > 770.0 or p.y < -50.0 or p.y > 1330.0:
			in_bounds = false
			break
	t.queue_free()
	await physics_frame
	return in_bounds

func _scenario_centre_gap() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	var b = t.spawn_ball(Vector2(327, 1000), Vector2.ZERO)
	t.rules.on_event("ball_added")
	t.left_flipper.set_pressed(false)
	t.right_flipper.set_pressed(false)
	var crossed := false
	var crossed_x := -1.0
	for i in 1200:
		await physics_frame
		if not is_instance_valid(b):
			break
		if b.position.y > 1200.0:
			crossed = true
			crossed_x = b.position.x
			break
	t.queue_free()
	await physics_frame
	return crossed and crossed_x > 300.0 and crossed_x < 355.0

func _scenario_cradle() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	t.left_flipper.set_pressed(true)
	for i in 240:
		await physics_frame
	var b = t.spawn_ball(Vector2(258, 1063), Vector2.ZERO)
	t.rules.on_event("ball_added")
	var max_speed := 0.0
	var launched := false
	var held := true
	for i in 480:
		await physics_frame
		if not is_instance_valid(b):
			held = false
			break
		var sp: float = b.linear_velocity.length()
		max_speed = max(max_speed, sp)
		if b.linear_velocity.y < -600.0:
			launched = true
			break
	t.queue_free()
	await physics_frame
	return held and not launched and max_speed < 300.0

func _scenario_inlane() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	var b = t.spawn_ball(Vector2(45, 950), Vector2.ZERO)
	t.rules.on_event("ball_added")
	t.left_flipper.set_pressed(false)
	t.right_flipper.set_pressed(false)
	var touched := false
	for i in 1200:
		await physics_frame
		if not is_instance_valid(b):
			break
		if t.left_flipper.has_ball(b):
			touched = true
			break
	t.queue_free()
	await physics_frame
	return touched

func _scenario_scoop() -> bool:
	var t = await _new_table()
	var got: Array = [0]
	t.rules.message.connect(func(_m, _s): pass)
	t.connect("switch_hit", func(kind): if kind == "scoop": got[0] += 1)
	t.rules.start_game()
	await physics_frame
	var b = t.spawn_ball(Vector2(360, 430), Vector2(0, -520))
	t.rules.on_event("ball_added")
	var kicked := false
	for i in 1830:
		await physics_frame
		if got[0] > 0 and is_instance_valid(b) and not b.freeze and b.linear_velocity.y > 400.0:
			kicked = true
			break
	t.queue_free()
	await physics_frame
	return got[0] == 1 and kicked

func _scenario_targets() -> bool:
	var t = await _new_table()
	var hits: Array = [0, 0, 0, 0]
	t.connect("switch_hit", func(kind): if kind == "target": pass)
	t.target_bank.target_dropped.connect(func(i): hits[i] += 1)
	t.rules.start_game()
	await physics_frame
	for i in 4:
		for other in t.get_tree().get_nodes_in_group("balls"):
			other.queue_free()
		await physics_frame
		var b = t.spawn_ball(Vector2(560, 500.0 + i * 58.0), Vector2(950, 0))
		t.rules.on_event("ball_added")
		for j in 90:
			await physics_frame
			if hits[i] > 0:
				break
		if is_instance_valid(b):
			b.queue_free()
		await physics_frame
	var all := true
	for h in hits:
		if h != 1:
			all = false
	t.queue_free()
	await physics_frame
	return all

func _scenario_lane() -> bool:
	var t = await _new_table()
	var fired: Array = [0]
	t.target_bank.target_dropped.connect(func(_i): pass)
	for s in t.lane_sensors:
		s.lane_entered.connect(func(_i): fired[0] += 1)
	t.rules.start_game()
	await physics_frame
	var b = t.spawn_ball(Vector2(360, 250), Vector2(0, -700))
	t.rules.on_event("ball_added")
	var ok := false
	for i in 240:
		await physics_frame
		if fired[0] > 0:
			ok = true
			break
	t.queue_free()
	await physics_frame
	return ok

func _scenario_orbit() -> bool:
	var t = await _new_table()
	var count: Array = [0]
	t.orbit.orbit_scored.connect(func(): count[0] += 1)
	t.rules.start_game()
	await physics_frame
	t.rules.balls_in_play = 1
	var b = t.spawn_ball(Vector2(57, 800), Vector2(0, -1500))
	t.rules.set("_ball_save_active", false)
	for i in 600:
		await physics_frame
		if count[0] > 0:
			break
	# allow any spurious re-triggers, then confirm exactly one
	for i in 120:
		await physics_frame
	t.queue_free()
	await physics_frame
	return count[0] == 1

func _scenario_multiball() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	t.rules.on_event("ball_added")
	var before: int = t.get_tree().get_nodes_in_group("balls").size()
	t.rules.multiball = true
	t.rules.request_multiball.emit(2)
	var ok := false
	for i in 480:
		await physics_frame
		var n: int = t.get_tree().get_nodes_in_group("balls").size()
		if n >= before + 2:
			ok = true
			break
	t.queue_free()
	await physics_frame
	return ok

func _scenario_restart() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	var overs: Array = [0]
	t.rules.game_over.connect(func(_s, _h): overs[0] += 1)
	t.rules.set("_ball_save_active", false)
	t.rules.balls_in_play = 1
	t.rules.on_event("drain")     # ball 1 -> ball 2
	t.rules.balls_in_play = 1
	t.rules.on_event("drain")     # ball 2 -> ball 3
	t.rules.balls_in_play = 1
	t.rules.on_event("drain")     # ball 3 -> GAME OVER
	var was_over: bool = t.rules.state == RulesScript.State.GAME_OVER
	await physics_frame
	t.rules.start_game()
	await physics_frame
	var restarted: bool = t.rules.state == RulesScript.State.PLAYING and t.rules.ball_number == 1
	var served: bool = t.get_tree().get_nodes_in_group("balls").size() >= 1
	t.queue_free()
	await physics_frame
	return was_over and overs[0] == 1 and restarted and served

func _scenario_slot_cycles() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	var cycles: Array = [0]
	t.slot.cycle_finished.connect(func(_r): cycles[0] += 1)
	var elapsed := 0
	var last := Time.get_ticks_msec()
	while elapsed < 15000:
		await process_frame
		var now := Time.get_ticks_msec()
		elapsed += now - last
		last = now
		if cycles[0] >= 3:
			break
	t.queue_free()
	await physics_frame
	return cycles[0] >= 3

func _scenario_slot_forced_win() -> bool:
	var t = await _new_table()
	t.rules.start_game()
	await physics_frame
	var before: int = t.rules.score
	t.slot.force_grid([
		"eye", "explorer", "ankh",
		"pyramid", "explorer", "feather",
		"emerald", "explorer", "book",
		"eye", "explorer", "ankh",
		"pyramid", "explorer", "feather"])
	var reached := false
	for i in 12000:
		await process_frame
		if t.rules.score - before >= 500000:
			reached = true
			break
	t.queue_free()
	await physics_frame
	return reached

