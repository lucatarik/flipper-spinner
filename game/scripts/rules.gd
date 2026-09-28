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

enum State { ATTRACT, PLAYING, GAME_OVER }

const BALLS_PER_GAME := 3
const BALL_SAVE_SECONDS := 8.0
const MULTIPLIER_MAX := 5
const MODE_SECONDS := 30.0
const MODE_COMPLETE_BONUS := 50000
const MODE_HIT_BONUS := 10000

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

var lanes: Array[bool] = [false, false, false]
var targets_down: int = 0
var bonus: int = 0

var _ball_save_active: bool = false
var _ball_save_timer: float = 0.0
var _mode_index: int = -1
var _mode_active: bool = false
var _mode_timer: float = 0.0
var _mode_progress: int = 0

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
	mode_changed.emit("", 0.0, 0, 0)
	playfield_mult_changed.emit(playfield_mult)
	message.emit("BALL %d" % ball_number, 2.0)
	request_serve_ball.emit()

func tick(delta: float) -> void:
	if state != State.PLAYING:
		return
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
	match name:
		"bumper":
			_award(1000)
			_mode_qualify("bumper")
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

func _award(points: int) -> void:
	score += points * playfield_mult
	score_changed.emit(score)

func set_playfield_mult(m: int) -> void:
	if m == playfield_mult:
		return
	playfield_mult = m
	playfield_mult_changed.emit(playfield_mult)

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
		_ball_save_active = true
		_ball_save_timer = max(_ball_save_timer, 0.0) + save
		message.emit("PHARAOH'S BLESSING", 2.0)
	if bool(bonuses.get("light_lock", false)):
		lock_lit = true
		message.emit("LOCK LIT", 2.0)
	var add_mult := int(bonuses.get("add_multiplier", 0))
	if add_mult > 0:
		multiplier = min(multiplier + add_mult, MULTIPLIER_MAX)
	if bool(bonuses.get("start_multiball", false)) and not multiball:
		multiball = true
		message.emit("ETERNAL LIFE MULTIBALL", 3.0)
		request_multiball.emit(2)
	if bool(bonuses.get("spot_target", false)):
		request_spot_target.emit()

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
	if _ball_save_active and not multiball:
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
	if bonus > 0:
		score += bonus * multiplier
		score_changed.emit(score)
		message.emit("BONUS %d x%d" % [bonus, multiplier], 2.0)
	bonus = 0
	multiplier = 1
	_ball_save_active = false
	_ball_save_timer = 0.0
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

func _mode_qualify(event_name: String) -> void:
	if not _mode_active:
		return
	if MODES[_mode_index]["event"] != event_name:
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
