class_name QuestManager
extends Node
## Timed "quests" in the spirit of the classic 1993 adventure-pinball video
## modes: every so often, right after the player scores, a quest starts on the
## DMD with a goal ("hit the bumpers 8 times"), a time limit and a points
## reward. Hit the goal in time -> big bonus; run out of time -> it just goes
## away with nothing awarded.
##
## Pure state + signals, no drawing: dmd_display.gd renders it, table.gd feeds
## it switch events and pays out the reward. `tick()` is public so the headless
## tests can drive it without a scene tree.

signal quest_started(quest_data: Dictionary)
signal quest_progress_updated(current: int, target: int)
signal quest_completed(quest_data: Dictionary)
signal quest_failed(quest_data: Dictionary)
signal quest_aborted()
signal dmd_message_requested(text: String, duration: float, anim_type: String)

const FIRST_DELAY_MIN := 12.0
const FIRST_DELAY_MAX := 25.0
const COOLDOWN_MIN := 25.0
const COOLDOWN_MAX := 50.0
## Chance that a scoring event starts a quest once the cooldown is over, so the
## start lands "a random while after you've scored" rather than on a fixed beat.
const START_CHANCE := 0.35
## The clock does not run while the intro (~2.6 s) and the scrolling
## description (~5 s) play on the DMD; hits still count during it.
const INTRO_GRACE := 7.0
const HURRY_AT := 5.0

## `animations` = [intro, progress, success] DMD animation names
## (see dmd_animation_player.gd). `events` = switch kinds that count.
const QUESTS: Array = [
	{
		"id": "sacred_stones", "title": "STEAL THE STONES",
		"description": "HIT THE BUMPERS 8 TIMES TO PRY THE SACRED STONES LOOSE",
		"events": ["bumper", "bumper_explode"], "target_count": 8, "time_limit": 30.0,
		"reward_points": 150000, "animations": ["whip", "skull", "idol"],
	},
	{
		"id": "mine_cart", "title": "RUNAWAY MINE CART",
		"description": "MAKE 2 RAMPS BEFORE THE CART RUNS OUT OF TRACK",
		"events": ["ramp"], "target_count": 2, "time_limit": 40.0,
		"reward_points": 250000, "animations": ["whip", "cart", "idol"],
	},
	{
		"id": "skull_bank", "title": "TEMPLE OF SKULLS",
		"description": "KNOCK DOWN 4 DROP TARGETS TO SILENCE THE SKULLS",
		"events": ["target"], "target_count": 4, "time_limit": 35.0,
		"reward_points": 200000, "animations": ["skull", "skull", "idol"],
	},
	{
		"id": "boulder_run", "title": "OUTRUN THE BOULDER",
		"description": "SHOOT 3 ORBITS OR TOP LANES BEFORE THE BOULDER CATCHES YOU",
		"events": ["orbit", "lane"], "target_count": 3, "time_limit": 30.0,
		"reward_points": 175000, "animations": ["boulder", "boulder", "idol"],
	},
	{
		"id": "snake_well", "title": "WELL OF SNAKES",
		"description": "HIT THE SLINGSHOTS 6 TIMES TO SCARE THE SNAKES AWAY",
		"events": ["sling"], "target_count": 6, "time_limit": 25.0,
		"reward_points": 120000, "animations": ["snake", "snake", "idol"],
	},
	{
		"id": "idol_eye", "title": "EYE OF THE IDOL",
		"description": "SHOOT THE IDOL SCOOP, A VORTEX PIT, OR GET TAKEN BY THE IDOL",
		"events": ["scoop", "vortex", "idol"], "target_count": 1, "time_limit": 25.0,
		"reward_points": 200000, "animations": ["whip", "idol", "idol"],
	},
]

## Only true while a ball is actually in play (table sets it every frame);
## timers and triggers freeze otherwise.
var enabled := false
var active_quest: Dictionary = {}
var time_left := 0.0
var completed_count := 0
var rng := RandomNumberGenerator.new()

var _cooldown := 0.0
var _grace := 0.0
var _last_id := ""

func _init() -> void:
	rng.randomize()
	_cooldown = rng.randf_range(FIRST_DELAY_MIN, FIRST_DELAY_MAX)

func _process(delta: float) -> void:
	tick(delta)

func is_active() -> bool:
	return not active_quest.is_empty()

## New game: no quest, fresh first delay.
func reset() -> void:
	abort()
	completed_count = 0
	_cooldown = rng.randf_range(FIRST_DELAY_MIN, FIRST_DELAY_MAX)

## Silently drop the running quest (game over etc.) — no fail message.
func abort() -> void:
	if is_active():
		active_quest = {}
		quest_aborted.emit()

## Called by the table whenever points are scored.
func notify_points_scored(points: int) -> void:
	if points <= 0 or not enabled or is_active() or _cooldown > 0.0:
		return
	if rng.randf() < START_CHANCE:
		start_random_quest()

func start_random_quest() -> Dictionary:
	var pool: Array = []
	for q in QUESTS:
		if String(q["id"]) != _last_id:
			pool.append(q)
	var pick: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	return start_quest(String(pick["id"]))

func start_quest(id: String) -> Dictionary:
	for q in QUESTS:
		if String(q["id"]) != id:
			continue
		active_quest = (q as Dictionary).duplicate(true)
		active_quest["current_count"] = 0
		time_left = float(active_quest["time_limit"])
		_grace = INTRO_GRACE
		_last_id = id
		quest_started.emit(active_quest.duplicate(true))
		return active_quest
	push_warning("QuestManager: unknown quest '%s'" % id)
	return {}

## A switch/feature event from the table ("bumper", "ramp", "target", ...).
func on_event(kind: String) -> void:
	if not is_active() or not enabled:
		return
	if not (kind in active_quest["events"]):
		return
	var cur := int(active_quest["current_count"]) + 1
	var target := int(active_quest["target_count"])
	active_quest["current_count"] = cur
	quest_progress_updated.emit(cur, target)
	if cur >= target:
		_complete()

func tick(delta: float) -> void:
	if not enabled:
		return
	if not is_active():
		if _cooldown > 0.0:
			_cooldown -= delta
		return
	if _grace > 0.0:
		_grace -= delta
		return
	var before := time_left
	time_left -= delta
	if before > HURRY_AT and time_left <= HURRY_AT:
		dmd_message_requested.emit("HURRY UP!", 1.2, "blink")
	if time_left <= 0.0:
		_fail()

func _complete() -> void:
	var data := active_quest.duplicate(true)
	active_quest = {}
	completed_count += 1
	_cooldown = rng.randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	quest_completed.emit(data)

func _fail() -> void:
	var data := active_quest.duplicate(true)
	active_quest = {}
	time_left = 0.0
	_cooldown = rng.randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	quest_failed.emit(data)
