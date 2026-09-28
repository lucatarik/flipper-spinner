extends SceneTree

const RulesScript = preload("res://scripts/rules.gd")
const SlotMachineScript = preload("res://scripts/slot_machine.gd")

var passed := 0
var failed := 0
var failures: Array[String] = []
var _cur_name := ""
var _cur_failed := false

func _initialize() -> void:
	run("start_game resets everything", test_start_game_resets)
	run("award values", test_award_values)
	run("lanes all lit -> multiplier cap 5", test_lanes_multiplier_cap)
	run("INDY completion -> lock_lit + targets_reset", test_indy_completion)
	run("scoop priority chain", test_scoop_priority)
	run("mode progress, completion, timeout, cycle", test_modes)
	run("ball save 7.9s vs 8.1s", test_ball_save)
	run("saved drain does not leak balls_in_play", test_ball_save_reserve)
	run("multiball drain handling", test_multiball_drain)
	run("bonus x multiplier at end of ball", test_bonus_multiplier)
	run("game over after ball 3 + high score flag", test_game_over)
	run("events ignored when not PLAYING", test_events_ignored)
	run("balls_in_play never negative", test_balls_in_play_never_negative)
	run("high score round-trip + corrupt file", test_high_score_roundtrip)
	run("slot paytable + wild substitution", test_slot_paytable)
	run("slot scatter + free spins trigger/retrigger", test_slot_scatter_free_spins)
	run("slot expanding symbol", test_slot_expanding)
	run("slot bonuses mapping", test_slot_bonuses)
	run("slot bet energy + reset", test_slot_bet_energy)
	run("rules playfield_mult + apply_slot_result", test_rules_playfield_mult)
	run("slot 20000-spin target math", test_slot_target_math)
	print("----------------------------------------")
	print("SUMMARY: %d passed, %d failed" % [passed, failed])
	for f in failures:
		print("  - %s" % f)
	quit(0 if failed == 0 else 1)

func run(name: String, fn: Callable) -> void:
	_cur_name = name
	_cur_failed = false
	fn.call()
	if _cur_failed:
		failed += 1
		print("FAIL: %s" % name)
	else:
		passed += 1
		print("PASS: %s" % name)

func expect(cond: bool, msg: String) -> void:
	if not cond:
		_cur_failed = true
		failures.append("%s: %s" % [_cur_name, msg])

func _new_started() -> Rules:
	var r = RulesScript.new()
	r.start_game()
	return r

func test_start_game_resets() -> void:
	var r = RulesScript.new()
	r.score = 999
	r.ball_number = 3
	r.multiplier = 5
	r.balls_in_play = 7
	r.locks = 2
	r.lock_lit = true
	r.multiball = true
	r.bonus = 1234
	r.on_event("bumper")
	r.start_game()
	expect(r.state == RulesScript.State.PLAYING, "state PLAYING")
	expect(r.score == 0, "score reset")
	expect(r.ball_number == 1, "ball 1")
	expect(r.multiplier == 1, "multiplier 1")
	expect(r.balls_in_play == 0, "balls 0")
	expect(r.locks == 0, "locks 0")
	expect(not r.lock_lit, "lock_lit false")
	expect(not r.multiball, "multiball false")
	expect(r.bonus == 0, "bonus 0")
	expect(r.lanes == [false, false, false], "lanes clear")

func test_award_values() -> void:
	var r = _new_started()
	var base: int = r.score
	r.on_event("bumper")
	expect(r.score - base == 1000, "bumper 1000")
	base = r.score
	r.on_event("sling")
	expect(r.score - base == 100, "sling 100")
	base = r.score
	r.on_event("lane", {"index": 0})
	expect(r.score - base == 500, "lane 500")
	base = r.score
	r.on_event("target", {"index": 0})
	expect(r.score - base == 2500, "target 2500")
	base = r.score
	r.on_event("orbit", {"side": "left"})
	expect(r.score - base == 5000, "orbit 5000")
	base = r.score
	r.on_event("scoop")
	expect(r.score - base == 0, "scoop starts mode, no points")
	base = r.score
	r.on_event("scoop")
	expect(r.score - base == 5000, "scoop base 5000 while mode running")

func test_lanes_multiplier_cap() -> void:
	var r = _new_started()
	r.on_event("lane", {"index": 0})
	r.on_event("lane", {"index": 1})
	r.on_event("lane", {"index": 2})
	expect(r.multiplier == 2, "multiplier 2 after first set")
	for i in 10:
		r.on_event("lane", {"index": 0})
		r.on_event("lane", {"index": 1})
		r.on_event("lane", {"index": 2})
	expect(r.multiplier == 5, "multiplier capped at 5")
	expect(not r.lanes[0] and not r.lanes[1] and not r.lanes[2], "lanes cleared after bump")

func test_indy_completion() -> void:
	var r = _new_started()
	var reset_count: Array = [0]
	r.targets_reset.connect(func(): reset_count[0] += 1)
	for i in 4:
		r.on_event("target", {"index": i})
	expect(r.lock_lit, "lock_lit after 4 targets")
	expect(reset_count[0] == 1, "targets_reset emitted once")
	expect(r.targets_down == 0, "target bank reset")
	expect(r.score >= 25000 + 4 * 2500, "completion award 25000")

func test_scoop_priority() -> void:
	# 1. multiball -> jackpot
	var r = _new_started()
	r.multiball = true
	var base: int = r.score
	r.on_event("scoop")
	expect(r.score - base == 100000, "multiball scoop jackpot 100000")

	# 2. lock_lit -> lock increments
	r = _new_started()
	r.lock_lit = true
	r.on_event("scoop")
	expect(r.locks == 1, "lock_lit scoop locks a ball")
	expect(not r.lock_lit, "lock_lit consumed")
	r.lock_lit = true
	r.on_event("scoop")
	r.lock_lit = true
	var mb_requests: Array = []
	r.request_multiball.connect(func(n): mb_requests.append(n))
	r.on_event("scoop")
	expect(r.locks == 0, "locks reset at 3")
	expect(r.multiball, "multiball started at 3 locks")
	expect(mb_requests == [2], "request_multiball(2)")

	# 3. no mode -> start mode
	r = _new_started()
	var names: Array = []
	r.mode_changed.connect(func(n, t, p, g): names.append(n))
	base = r.score
	r.on_event("scoop")
	expect(names.size() > 0 and names[-1] == "WELL OF SOULS", "starts first mode")
	expect(r.score - base == 0, "no points for starting mode")

	# 4. mode running -> 5000
	base = r.score
	r.on_event("scoop")
	expect(r.score - base == 5000, "scoop 5000 with mode running")

func test_modes() -> void:
	var r = _new_started()
	r.on_event("scoop")
	expect(r._mode_index == 0, "mode 0")
	# complete WELL OF SOULS with 15 bumpers
	for i in 15:
		r.on_event("bumper")
	expect(not r._mode_active, "mode completes at goal")
	# next mode
	r.on_event("scoop")
	expect(r._mode_index == 1, "mode 1 next")
	for i in 4:
		r.on_event("orbit", {"side": "left"})
	expect(not r._mode_active, "mode 1 completes")
	r.on_event("scoop")
	expect(r._mode_index == 2, "mode 2 next")
	for i in 6:
		r.on_event("target", {"index": i % 4})
	expect(not r._mode_active, "mode 2 completes")
	r.lock_lit = false
	r.on_event("scoop")
	expect(r._mode_index == 0, "cycles back to mode 0")
	# timeout
	r.tick(31.0)
	expect(not r._mode_active, "mode times out")
	expect(r._mode_timer == 0.0, "mode timer cleared")

func test_ball_save() -> void:
	var r = _new_started()
	r.on_event("ball_added")
	r.on_event("plunger_exit")
	var saved: Array = []
	r.message.connect(func(t, s): saved.append(t))
	var serves: Array = [0]
	r.request_serve_ball.connect(func(): serves[0] += 1)
	r.tick(7.9)
	r.on_event("drain")
	expect("BALL SAVED" in saved, "save within 8s")
	expect(r.balls_in_play == 0, "saved drain removes the ball")
	expect(serves[0] == 1, "re-serve requested after save")
	expect(r.ball_number == 1, "still ball 1")

	var r2 = _new_started()
	r2.on_event("ball_added")
	r2.on_event("plunger_exit")
	r2.tick(8.1)
	r2.on_event("drain")
	expect(r2.balls_in_play == 0, "ball lost after save window")
	expect(r2.ball_number == 2, "advance to ball 2")

func test_ball_save_reserve() -> void:
	var r = _new_started()
	r.on_event("ball_added")          # serve -> 1 ball
	expect(r.balls_in_play == 1, "1 ball after serve")
	r.on_event("plunger_exit")        # ball save armed
	r.on_event("drain")               # saved drain: ball removed, re-serve requested
	expect(r.balls_in_play == 0, "saved drain removes the ball")
	expect(r.ball_number == 1, "no ball loss on save")
	r.on_event("ball_added")          # table re-serves -> back to 1
	expect(r.balls_in_play == 1, "re-serve puts exactly 1 ball back")
	r.tick(9.0)                       # save window expired
	r.on_event("drain")               # ordinary drain -> end of ball
	expect(r.balls_in_play == 0, "drain after save window empties play")
	expect(r.ball_number == 2, "advance to ball 2")

func test_multiball_drain() -> void:
	var r = _new_started()
	r.on_event("ball_added")
	r.multiball = true
	r.balls_in_play = 3
	r.on_event("drain")
	expect(r.balls_in_play == 2, "mb drain 3->2")
	expect(r.multiball, "multiball continues at 2")
	r.on_event("drain")
	expect(r.balls_in_play == 1, "mb drain 2->1")
	expect(not r.multiball, "multiball ends at <=1")
	r.on_event("drain")
	expect(r.balls_in_play == 0, "last ball drains")
	expect(r.ball_number == 2, "end of ball after multiball")

func test_bonus_multiplier() -> void:
	var r = _new_started()
	r.on_event("ball_added")
	r.on_event("target", {"index": 0})  # 2500 + bonus 1000
	r.on_event("target", {"index": 1})  # 2500 + bonus 1000
	var pre: int = r.score
	r.multiplier = 2
	r.on_event("drain")
	expect(r.score == pre + 2000 * 2, "bonus x multiplier added")
	expect(r.bonus == 0, "bonus cleared")
	expect(r.multiplier == 1, "multiplier reset")

func test_game_over() -> void:
	var r = _new_started()
	r.high_score = 999999
	r.on_event("bumper")
	var over: Array = []
	r.game_over.connect(func(s, h): over.append([s, h]))
	for i in 3:
		r.on_event("ball_added")
		r.on_event("drain")
	expect(r.state == RulesScript.State.GAME_OVER, "GAME_OVER after ball 3")
	expect(over.size() == 1, "game_over emitted once")
	expect(over.size() > 0 and over[0][1] == false, "not high score vs 100")
	# high score flag
	var r2 = _new_started()
	r2.high_score = 0
	var over2: Array = []
	r2.game_over.connect(func(s, h): over2.append([s, h]))
	r2.on_event("orbit", {"side": "left"})
	for i in 3:
		r2.on_event("ball_added")
		r2.on_event("drain")
	expect(over2.size() > 0 and over2[0][1] == true, "high score flag set")
	expect(r2.high_score == over2[0][0], "high_score updated")

func test_events_ignored() -> void:
	var r = RulesScript.new()
	# ATTRACT
	r.on_event("bumper")
	r.on_event("scoop")
	r.on_event("lane", {"index": 0})
	r.on_event("drain")
	expect(r.score == 0, "no scoring in ATTRACT")
	expect(r.balls_in_play == 0, "no balls in ATTRACT")
	expect(r.state == RulesScript.State.ATTRACT, "still ATTRACT")
	# GAME_OVER
	r.state = RulesScript.State.GAME_OVER
	r.on_event("bumper")
	expect(r.score == 0, "no scoring in GAME_OVER")

func test_balls_in_play_never_negative() -> void:
	var r = _new_started()
	r.on_event("drain")
	expect(r.balls_in_play >= 0, "drain with 0 balls stays >=0")
	for i in 5:
		r.on_event("drain")
	expect(r.balls_in_play >= 0, "repeated drains stay >=0")

func test_high_score_roundtrip() -> void:
	var path := "user://test_highscore.save"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	expect(HighScore.load_score(path) == 0, "missing file -> 0")
	HighScore.save_score(123456, path)
	expect(FileAccess.file_exists(path), "file written")
	expect(HighScore.load_score(path) == 123456, "value round-trips")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not-a-number!!")
	f = null
	expect(HighScore.load_score(path) == 0, "corrupt file -> 0")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("")
	f = null
	expect(HighScore.load_score(path) == 0, "empty file -> 0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _slot(seed_val := 1):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return SlotMachineScript.new(rng)

func _g(symbols: Array) -> Array:
	var grid: Array = []
	for r in SlotMachineScript.REELS:
		grid.append([symbols[r * 3], symbols[r * 3 + 1], symbols[r * 3 + 2]])
	return grid

func test_slot_paytable() -> void:
	var slot = _slot()
	# five explorers on the middle line
	var res: Dictionary = slot.evaluate(_g([
		"eye", "explorer", "ankh",
		"pyramid", "explorer", "feather",
		"emerald", "explorer", "book",
		"eye", "explorer", "ankh",
		"pyramid", "explorer", "feather"]))
	var line0: Dictionary = {}
	for l in res["lines"]:
		if int(l["line"]) == 0:
			line0 = l
	expect(line0.get("symbol", "") == "explorer", "explorer line detected")
	expect(int(line0.get("count", 0)) == 5, "book counts as wild for 5 of a kind")
	expect(int(line0.get("credits", 0)) == 5000, "5 explorer = 5000 credits")
	expect(int(res["credits"]) >= 5000, "credits include the line")
	# two-of-a-kind awards its 2-credit value
	var res2: Dictionary = slot.evaluate(_g([
		"eye", "pharaoh", "eye",
		"eye", "pharaoh", "eye",
		"eye", "eye", "eye",
		"eye", "eye", "eye",
		"eye", "eye", "eye"]))
	var has2 := false
	for l in res2["lines"]:
		if int(l["count"]) == 2 and int(l["credits"]) == 5:
			has2 = true
	expect(has2, "2 pharaoh = 5 credits")

func test_slot_scatter_free_spins() -> void:
	var slot = _slot()
	# 3 books (scatter) -> 20 credits and 10 free spins
	var res: Dictionary = slot.evaluate(_g([
		"book", "eye", "ankh",
		"pyramid", "book", "feather",
		"emerald", "eye", "book",
		"eye", "eye", "eye",
		"eye", "eye", "eye"]))
	expect(int(res["books"]) == 3, "3 books counted")
	expect(int(res["free_spins_awarded"]) == 10, "3 books -> 10 free spins")
	# credits include the scatter award of 20
	expect(int(res["credits"]) >= 20, "3-book scatter credits")
	# book wild does not make a scatter-line win for the book itself
	# retrigger: with free spins running, a new 3-book grid adds 10
	slot.free_spins = 4
	var res2: Dictionary = slot.evaluate(_g([
		"book", "eye", "ankh",
		"pyramid", "book", "feather",
		"emerald", "eye", "book",
		"eye", "eye", "eye",
		"eye", "eye", "eye"]))
	expect(int(res2["free_spins_awarded"]) == 10, "retrigger reports 10")

func test_slot_expanding() -> void:
	var slot = _slot()
	slot.special_symbol = "explorer"
	slot.free_spins = 5
	# explorer on 2 reels -> expands those reels; books on the others complete a
	# 5-of-a-kind on the middle line
	var grid := _g([
		"explorer", "eye", "ankh",
		"pyramid", "book", "feather",
		"explorer", "eye", "book",
		"eye", "book", "eye",
		"eye", "book", "eye"])
	var res: Dictionary = slot.evaluate(grid)
	var expanded: Array = res["expanded_reels"]
	expect(0 in expanded and 2 in expanded, "reels 0 and 2 expand")
	expect(int(res["credits"]) > 0, "expanding pays on lines")
	# below the minimum count -> no expansion
	slot.special_symbol = "emerald"
	slot.free_spins = 5
	var res2: Dictionary = slot.evaluate(_g([
		"emerald", "eye", "ankh",
		"eye", "eye", "eye",
		"eye", "eye", "eye",
		"eye", "eye", "eye",
		"eye", "eye", "eye"]))
	expect(res2["expanded_reels"].is_empty(), "single emerald does not expand")
	# not during the base game
	slot.special_symbol = "explorer"
	slot.free_spins = 0
	var res3: Dictionary = slot.evaluate(grid)
	expect(res3["expanded_reels"].is_empty(), "no expansion outside free spins")

func test_slot_bonuses() -> void:
	var slot = _slot()
	var res: Dictionary = slot.evaluate(_g([
		"eye", "pharaoh", "ankh",
		"pyramid", "pharaoh", "feather",
		"emerald", "pharaoh", "book",
		"eye", "eye", "ankh",
		"pyramid", "eye", "feather"]))
	var b: Dictionary = res["bonuses"]
	expect(float(b["ball_save"]) == 10.0, "3 pharaoh -> ball save 10s")
	# anubis locks
	var res2: Dictionary = slot.evaluate(_g([
		"eye", "anubis", "ankh",
		"pyramid", "anubis", "feather",
		"emerald", "anubis", "book",
		"eye", "eye", "ankh",
		"pyramid", "eye", "feather"]))
	expect(bool(res2["bonuses"]["light_lock"]), "3 anubis -> light lock")
	# scarab spots a target
	var res3: Dictionary = slot.evaluate(_g([
		"eye", "scarab", "ankh",
		"pyramid", "scarab", "feather",
		"emerald", "scarab", "book",
		"eye", "eye", "ankh",
		"pyramid", "eye", "feather"]))
	expect(bool(res3["bonuses"]["spot_target"]), "3 scarab -> spot target")
	# explorer 3 -> +1 multiplier, 4 -> multiball
	var res4: Dictionary = slot.evaluate(_g([
		"eye", "explorer", "ankh",
		"pyramid", "explorer", "feather",
		"emerald", "explorer", "book",
		"eye", "explorer", "ankh",
		"pyramid", "eye", "feather"]))
	expect(int(res4["bonuses"]["add_multiplier"]) == 1, "explorer line -> +1 multiplier")
	expect(bool(res4["bonuses"]["start_multiball"]), "4 explorers -> multiball")

func test_slot_bet_energy() -> void:
	var slot = _slot()
	expect(slot.bet == 1, "bet starts at 1")
	for i in 8:
		slot.add_energy()
	expect(slot.bet == 2, "8 energy -> bet 2")
	expect(slot.energy == 0, "energy wraps to 0")
	for i in 40:
		slot.add_energy()
	expect(slot.bet == 5, "bet capped at 5")
	slot.reset_bet()
	expect(slot.bet == 1 and slot.energy == 0, "reset_bet restores 1")

func test_rules_playfield_mult() -> void:
	var r = _new_started()
	var base: int = r.score
	r.on_event("bumper")
	expect(r.score - base == 1000, "x1 bumper 1000")
	r.set_playfield_mult(2)
	base = r.score
	r.on_event("bumper")
	expect(r.score - base == 2000, "x2 bumper 2000")
	r.on_event("sling")
	expect(r.score - base == 2000 + 200, "x2 sling 200")
	# events ignored when not PLAYING
	var attract = RulesScript.new()
	attract.apply_slot_result({"points": 5000, "bonuses": {"light_lock": true}})
	expect(attract.score == 0, "slot result ignored in ATTRACT")
	expect(not attract.lock_lit, "bonus ignored in ATTRACT")

	# each bonus applied through apply_slot_result
	var r2 = _new_started()
	r2.on_event("ball_added")
	var base2: int = r2.score
	r2.apply_slot_result({"points": 12345, "bonuses": {
		"ball_save": 10.0, "light_lock": true, "spot_target": true,
		"add_multiplier": 1, "start_multiball": false}})
	expect(r2.score - base2 == 12345, "slot points not multiplied by playfield_mult")
	expect(r2.lock_lit, "light_lock applied")
	expect(r2.multiplier == 2, "add_multiplier applied")
	var spotted: Array = [0]
	r2.request_spot_target.connect(func(): spotted[0] += 1)
	r2.apply_slot_result({"points": 0, "bonuses": {"spot_target": true}})
	expect(spotted[0] == 1, "spot_target emits request_spot_target")
	var mbs: Array = [0]
	r2.request_multiball.connect(func(_n): mbs[0] += 1)
	r2.apply_slot_result({"points": 0, "bonuses": {"start_multiball": true}})
	expect(r2.multiball, "start_multiball sets multiball")
	expect(mbs[0] == 1, "start_multiball requests 2 balls")
	expect(r2.playfield_mult == 1, "slot points did not change playfield_mult")

func test_slot_target_math() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var slot = SlotMachineScript.new(rng)
	var n := 20000
	var wins := 0
	var fs := 0
	var total := 0
	for i in n:
		var res: Dictionary = slot.evaluate(slot.spin())
		if int(res["credits"]) > 0:
			wins += 1
		if int(res["free_spins_awarded"]) > 0:
			fs += 1
		total += int(res["credits"])
	var hit := float(wins) / n
	var fs_rate := float(fs) / n
	var avg := float(total) / n
	print("  slot sim: hit=%.1f%% fs=1/%.0f avg=%.2f credits/spin" % [
		hit * 100.0, (1.0 / fs_rate) if fs_rate > 0.0 else INF, avg])
	# Target math per spec.md Part B.
	expect(hit >= 0.25 and hit <= 0.45, "hit frequency 25-45 %")
	expect(fs_rate >= 1.0 / 150.0 and fs_rate <= 1.0 / 60.0, "free spins 1 in 60-150")
	expect(avg >= 6.0 and avg <= 14.0, "average 6-14 credits per spin")
