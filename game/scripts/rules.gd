class_name Rules
extends RefCounted

signal score_changed(score: int)
signal ball_changed(ball_number: int, balls_per_game: int)
signal message(text: String, seconds: float)
signal request_serve_ball()
signal request_multiball(extra_balls: int)
signal targets_reset()
signal lanes_changed(lit: Array)
signal mode_changed(name: String, time_left: float, progress: int, goal: int)
signal state_changed(state: int)
signal game_over(final_score: int, is_high_score: bool)
signal request_spot_target()
signal playfield_mult_changed(mult: int)
signal ramp_count_changed(n: int)
signal extra_balls_changed(n: int)
signal request_add_ball(count: int)
signal tilt_warning(level: int)
signal tilted_changed()
signal bonus_bumpers_changed(lit: Array)

enum State { ATTRACT, PLAYING, GAME_OVER }

const BALLS_PER_GAME := 3
const BALL_SAVE_SECONDS := 8.0
const MULTIPLIER_MAX := 5
const MODE_SECONDS := 30.0
const MODE_COMPLETE_BONUS := 50000
const MODE_HIT_BONUS := 10000
const EXTRA_BALLS_MAX := 3
const TILT_DECAY := 0.5
const RAMP_AWARD := 10000
const RAMP_BONUS := 2500
const RAMP_COMBO_AWARD := 25000
const COMBO_WINDOW := 3.0
const RAMPS_PER_EXTRA_BALL := 4
const BONUS_BUMPER_POINTS := 10000

const MODES := [
	{"name": "WELL OF SOULS", "event": "bumper", "goal": 15},
	{"name": "MINE CART CHASE", "event": "orbit", "goal": 4},
	{"name": "GRAIL QUEST", "event": "target", "goal": 6},
]

var state: int = State.ATTRACT
var score: int = 0
var ball_number: int = 1
var multiplier: int = 1
var balls_in_play: int = 0
var locks: int = 0
var lock_lit: bool = false
var multiball: bool = false
var high_score: int = 0

var playfield_mult: int = 1
var extra_balls: int = 0
var tilted: bool = false
var ramp_count: int = 0

var lanes: Array[bool] = [false, false, false]
var targets_down: int = 0
var bonus: int = 0

## "Bonus bumpers" — the 3 central jungle bumpers double as a light-them-all
## bank, like the top lanes but for bumpers: each one lights on its first hit this
## ball, all 3 lit -> multiplier+1 (cap MULTIPLIER_MAX) + flat bonus points, resets.
var bonus_bumpers: Array[bool] = [false, false, false]

var _free_spins_active: bool = false
var _x2_timer: float = 0.0
var _ball_save_active: bool = false
var _ball_save_timer: float = 0.0
var _mode_index: int = -1
var _mode_active: bool = false
var _mode_timer: float = 0.0
var _mode_progress: int = 0
var _tilt_meter: float = 0.0
var _tilt_level: int = 0
var _combo_timer: float = 0.0

func start_game() -> void:
	state = State.PLAYING
	score = 0
	ball_number = 1
	multiplier = 1
	balls_in_play = 0
	locks = 0
	lock_lit = false
	multiball = false
	bonus = 0
	targets_down = 0
	lanes = [false, false, false]
	bonus_bumpers = [false, false, false]
	extra_balls = 0
	tilted = false
	ramp_count = 0
	_tilt_meter = 0.0
	_tilt_level = 0
	_combo_timer = 0.0
	_free_spins_active = false
	_x2_timer = 0.0
	playfield_mult = 1
	_ball_save_active = false
	_ball_save_timer = 0.0
	_mode_index = -1
	_mode_active = false
	_mode_timer = 0.0
	_mode_progress = 0
	state_changed.emit(state)
	score_changed.emit(score)
	ball_changed.emit(ball_number, BALLS_PER_GAME)
	lanes_changed.emit(lanes.duplicate())
	bonus_bumpers_changed.emit(bonus_bumpers.duplicate())
	mode_changed.emit("", 0.0, 0, 0)
	playfield_mult_changed.emit(playfield_mult)
	extra_balls_changed.emit(extra_balls)
	ramp_count_changed.emit(ramp_count)
	message.emit("BALL %d" % ball_number, 2.0)
	request_serve_ball.emit()

func tick(delta: float) -> void:
	if state != State.PLAYING:
		return
	if _tilt_meter > 0.0:
		_tilt_meter = maxf(_tilt_meter - TILT_DECAY * delta, 0.0)
	if _combo_timer > 0.0:
		_combo_timer = maxf(_combo_timer - delta, 0.0)
	if _x2_timer > 0.0:
		_x2_timer -= delta
		if _x2_timer <= 0.0:
			_x2_timer = 0.0
			_recompute_playfield_mult()
	if _ball_save_active:
		_ball_save_timer -= delta
		if _ball_save_timer <= 0.0:
			_ball_save_active = false
			_ball_save_timer = 0.0
	if _mode_active:
		_mode_timer -= delta
		if _mode_timer <= 0.0:
			_mode_timer = 0.0
			_mode_active = false
			message.emit("%s FAILED" % _mode_name(), 2.0)
			mode_changed.emit("", 0.0, 0, 0)
		else:
			mode_changed.emit(_mode_name(), _mode_timer, _mode_progress, _mode_goal())

func on_event(name: String, data: Dictionary = {}) -> void:
	if state != State.PLAYING:
		return
	if tilted and name != "drain" and name != "ball_added":
		return
	match name:
		"bumper":
			_award(1000)
			_mode_qualify("bumper")
			var bonus_index := int(data.get("bonus_index", -1))
			if bonus_index >= 0:
				_on_bonus_bumper(bonus_index)
		"sling":
			_award(100)
		"lane":
			_on_lane(int(data.get("index", 0)))
		"target":
			_on_target(int(data.get("index", 0)))
		"scoop":
			_on_scoop()
		"orbit":
			_award(5000)
			bonus += 2000
			_mode_qualify("orbit")
			_flow_event()
		"ramp":
			_award(RAMP_AWARD)
			bonus += RAMP_BONUS
			ramp_count += 1
			ramp_count_changed.emit(ramp_count)
			_mode_qualify("ramp")
			_flow_event()
			if ramp_count % RAMPS_PER_EXTRA_BALL == 0:
				extra_balls = mini(extra_balls + 1, EXTRA_BALLS_MAX)
				extra_balls_changed.emit(extra_balls)
				message.emit("EXTRA BALL", 2.0)
		"plunger_exit":
			_on_plunger_exit()
		"drain":
			_on_drain()
		"ball_added":
			balls_in_play += 1

func flip_lanes(direction: int) -> void:
	if state != State.PLAYING:
		return
	var n := lanes.size()
	var copy := lanes.duplicate()
	for i in n:
		var j := (i + direction) % n
		if j < 0:
			j += n
		lanes[j] = copy[i]
	lanes_changed.emit(lanes.duplicate())

func nudge() -> void:
	if state != State.PLAYING or tilted:
		return
	_tilt_meter += 1.0
	_update_tilt()

func _update_tilt() -> void:
	if _tilt_meter >= 2.0 and _tilt_level < 1:
		_tilt_level = 1
		tilt_warning.emit(1)
		message.emit("WARNING", 2.0)
	if _tilt_meter >= 3.0 and _tilt_level < 2:
		_tilt_level = 2
		tilt_warning.emit(2)
		message.emit("DANGER", 2.0)
	if _tilt_meter > 3.5 and not tilted:
		_tilt_level = 3
		tilted = true
		tilted_changed.emit()
		message.emit("TILT", 2.0)

func _award(points: int) -> void:
	score += points * playfield_mult
	score_changed.emit(score)

func set_playfield_mult(m: int) -> void:
	if m == playfield_mult:
		return
	playfield_mult = m
	playfield_mult_changed.emit(playfield_mult)

## Table tells Rules whether the slot's free spins are running; Rules folds it
## (together with the playfield x2 timer) into playfield_mult.
func set_free_spins_active(active: bool) -> void:
	if active == _free_spins_active:
		return
	_free_spins_active = active
	_recompute_playfield_mult()

func _recompute_playfield_mult() -> void:
	var m := 1
	if _free_spins_active:
		m += 1
	if _x2_timer > 0.0:
		m += 1
	set_playfield_mult(m)

## C3: put `n` balls into play at the idol scoop (table spawns them). Also lights
## multiball so a drain does not end the ball while a ball remains.
func add_ball(n: int = 1) -> void:
	if state != State.PLAYING or n <= 0:
		return
	request_add_ball.emit(n)
	if not multiball:
		multiball = true
		message.emit("ADD-A-BALL", 2.0)

func _lock_balls(n: int) -> void:
	locks += n
	if locks >= 3:
		locks = 0
		if not multiball:
			multiball = true
			message.emit("ETERNAL LIFE MULTIBALL", 3.0)
			request_multiball.emit(2)
	else:
		message.emit("BALL LOCKED %d" % locks, 2.0)

## Additive slot extension: award slot points (already bet-scaled, NOT multiplied
## again by playfield_mult) and apply the slot line bonuses. Ignored unless PLAYING.
func apply_slot_result(res: Dictionary) -> void:
	if state != State.PLAYING:
		return
	var points := int(res.get("points", 0))
	if points > 0:
		score += points
		score_changed.emit(score)
	var bonuses: Dictionary = res.get("bonuses", {})
	var save := float(bonuses.get("ball_save", 0.0))
	if save > 0.0:
		if not tilted:
			_ball_save_active = true
			_ball_save_timer = max(_ball_save_timer, 0.0) + save
		message.emit("PHARAOH'S BLESSING", 2.0)
	if bool(bonuses.get("light_lock", false)):
		lock_lit = true
		message.emit("LOCK LIT", 2.0)
	var add_mult := int(bonuses.get("add_multiplier", 0))
	if add_mult > 0:
		multiplier = min(multiplier + add_mult, MULTIPLIER_MAX)
	var lock_add := int(bonuses.get("lock_balls", 0))
	if lock_add > 0:
		_lock_balls(lock_add)
	var spots := int(bonuses.get("spot_targets", 0))
	for _i in spots:
		request_spot_target.emit()
	if bool(bonuses.get("start_multiball", false)) and not multiball:
		multiball = true
		message.emit("ETERNAL LIFE MULTIBALL", 3.0)
		request_multiball.emit(2)
	var gain_extra := int(bonuses.get("extra_balls", 0))
	if gain_extra > 0:
		extra_balls = mini(extra_balls + gain_extra, EXTRA_BALLS_MAX)
		extra_balls_changed.emit(extra_balls)
		message.emit("EXTRA BALL", 2.0)
	var add_n := int(bonuses.get("add_balls", 0))
	if add_n > 0:
		add_ball(add_n)
	var mode_time := float(bonuses.get("mode_time", 0.0))
	if mode_time > 0.0 and _mode_active:
		_mode_timer += mode_time
		mode_changed.emit(_mode_name(), _mode_timer, _mode_progress, _mode_goal())
	if bool(bonuses.get("start_mode", false)) and not _mode_active:
		_start_next_mode()
	var x2 := float(bonuses.get("playfield_x2_seconds", 0.0))
	if x2 > 0.0:
		_x2_timer = maxf(_x2_timer, 0.0) + x2
		_recompute_playfield_mult()
	var bonus_points := int(bonuses.get("bonus_points", 0))
	if bonus_points > 0:
		score += bonus_points
		score_changed.emit(score)

func _on_lane(index: int) -> void:
	if index < 0 or index >= lanes.size():
		return
	_award(500)
	bonus += 500
	lanes[index] = true
	if lanes[0] and lanes[1] and lanes[2]:
		multiplier = min(multiplier + 1, MULTIPLIER_MAX)
		lanes = [false, false, false]
		message.emit("MULTIPLIER x%d" % multiplier, 2.0)
	lanes_changed.emit(lanes.duplicate())

## Lights one of the 3 bonus bumpers; all 3 lit -> multiplier+1 (cap), flat bonus
## points, and the bank resets so it can be lit again later in the same ball.
func _on_bonus_bumper(index: int) -> void:
	if index < 0 or index >= bonus_bumpers.size():
		return
	bonus_bumpers[index] = true
	if bonus_bumpers[0] and bonus_bumpers[1] and bonus_bumpers[2]:
		multiplier = min(multiplier + 1, MULTIPLIER_MAX)
		bonus_bumpers = [false, false, false]
		_award(BONUS_BUMPER_POINTS)
		message.emit("BUMPER BONUS x%d" % multiplier, 2.0)
	bonus_bumpers_changed.emit(bonus_bumpers.duplicate())

func _on_target(_index: int) -> void:
	_award(2500)
	bonus += 1000
	targets_down += 1
	_mode_qualify("target")
	if targets_down >= 4:
		targets_down = 0
		_award(25000)
		lock_lit = true
		message.emit("LOCK LIT", 2.0)
		targets_reset.emit()

func _on_scoop() -> void:
	if multiball:
		_award(100000)
		message.emit("JACKPOT 100000", 2.0)
		return
	if lock_lit:
		locks += 1
		lock_lit = false
		if locks >= 3:
			locks = 0
			multiball = true
			message.emit("ETERNAL LIFE MULTIBALL", 3.0)
			request_multiball.emit(2)
		else:
			message.emit("BALL LOCKED %d" % locks, 2.0)
		return
	if not _mode_active:
		_start_next_mode()
		return
	_award(5000)

func _on_plunger_exit() -> void:
	if multiball:
		return
	_ball_save_active = true
	_ball_save_timer = BALL_SAVE_SECONDS

func _on_drain() -> void:
	if _ball_save_active and not multiball and not tilted:
		_ball_save_active = false
		_ball_save_timer = 0.0
		balls_in_play -= 1
		if balls_in_play < 0:
			balls_in_play = 0
		message.emit("BALL SAVED", 2.0)
		request_serve_ball.emit()
		return
	balls_in_play -= 1
	if balls_in_play < 0:
		balls_in_play = 0
	if multiball and balls_in_play <= 1:
		multiball = false
	if balls_in_play == 0:
		_end_of_ball()

func _end_of_ball() -> void:
	var was_tilted := tilted
	if not was_tilted and bonus > 0:
		score += bonus * multiplier
		score_changed.emit(score)
		message.emit("BONUS %d x%d" % [bonus, multiplier], 2.0)
	bonus = 0
	multiplier = 1
	_ball_save_active = false
	_ball_save_timer = 0.0
	if was_tilted:
		tilted = false
		_tilt_meter = 0.0
		_tilt_level = 0
	if not was_tilted and extra_balls > 0:
		extra_balls -= 1
		extra_balls_changed.emit(extra_balls)
		message.emit("SHOOT AGAIN", 2.0)
		request_serve_ball.emit()
		return
	ball_number += 1
	if ball_number > BALLS_PER_GAME:
		_game_over()
	else:
		ball_changed.emit(ball_number, BALLS_PER_GAME)
		message.emit("BALL %d" % ball_number, 2.0)
		request_serve_ball.emit()

func _game_over() -> void:
	state = State.GAME_OVER
	var is_high := score > high_score
	if is_high:
		high_score = score
	state_changed.emit(state)
	game_over.emit(score, is_high)

func _start_next_mode() -> void:
	_mode_index = (_mode_index + 1) % MODES.size()
	_mode_active = true
	_mode_timer = MODE_SECONDS
	_mode_progress = 0
	message.emit("%s START" % _mode_name(), 2.0)
	mode_changed.emit(_mode_name(), _mode_timer, _mode_progress, _mode_goal())

## D2 combo: a ramp within COMBO_WINDOW of another ramp or an orbit pays a bonus.
func _flow_event() -> void:
	if _combo_timer > 0.0:
		_award(RAMP_COMBO_AWARD)
		message.emit("COMBO", 2.0)
	_combo_timer = COMBO_WINDOW

func _mode_qualify(event_name: String) -> void:
	if not _mode_active:
		return
	var required: String = MODES[_mode_index]["event"]
	# D2: mode 1 "MINE CART CHASE" qualifies on orbit OR ramp.
	if required != event_name and not (required == "orbit" and event_name == "ramp"):
		return
	_award(MODE_HIT_BONUS)
	_mode_progress += 1
	if _mode_progress >= _mode_goal():
		_award(MODE_COMPLETE_BONUS)
		message.emit("%s COMPLETE" % _mode_name(), 3.0)
		_mode_active = false
		_mode_timer = 0.0
		mode_changed.emit("", 0.0, 0, 0)
	else:
		mode_changed.emit(_mode_name(), _mode_timer, _mode_progress, _mode_goal())

func _mode_name() -> String:
	if _mode_index < 0:
		return ""
	return MODES[_mode_index]["name"]

func _mode_goal() -> int:
	if _mode_index < 0:
		return 0
	return int(MODES[_mode_index]["goal"])
