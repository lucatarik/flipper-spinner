extends Node
## DMDAnimationPlayer: sequences and renders everything the dot-matrix display
## shows, in the spirit of the 1993 adventure-pinball DMD shows — whip-crack
## title reveals, a mine cart racing along its track, a boulder chasing the
## explorer, flickering skulls, slithering snakes, a glinting golden idol,
## plus the generic text effects (marquee scroll, zoom in/out, BLINK).
##
## A "scene" is a plain Dictionary ({"type": ..., "duration": ..., ...}); the
## builder funcs below make them. Scenes play one after another from a queue;
## the optional "idle" scene (the live quest-progress screen) shows whenever
## the queue is empty. Nothing here blocks gameplay: the display just calls
## advance()/render() every frame.
##
## The pixel art is procedural and drawn at native DMD resolution (128x32):
## each animation is a function of time that paints into dmd_canvas — the
## same idea as low-res SpriteFrames, without needing any image assets.

const DmdCanvas = preload("res://scripts/dmd_canvas.gd")

signal scene_finished(scene_type: String)

const W := 128
const H := 32
const FULL := 255
const MID := 140
const DIM := 60
const FLASH_TIME := 0.7
const HURRY_AT := 5.0

const CART := [
	"  +#+##+#+  ",
	"############",
	"#++++++++++#",
	" #++++++++# ",
	" ########## ",
	"  ##    ##  ",
	"  ##    ##  ",
]
const RUNNER_A := [
	"  ###  ",
	"#######",
	"  ###  ",
	"   #   ",
	" ##### ",
	"#  #  #",
	"   #   ",
	"  # #  ",
	" #   # ",
]
const RUNNER_B := [
	"  ###  ",
	"#######",
	"  ###  ",
	"   #   ",
	"  ###  ",
	" # # # ",
	"   #   ",
	"   #   ",
	"  # #  ",
]
const SKULL := [
	"  #######  ",
	" ######### ",
	"###########",
	"##   #   ##",
	"##   #   ##",
	"###########",
	" #### #### ",
	"  #######  ",
	"  # # # #  ",
	"  #######  ",
]
const SKULL_SMALL := [
	" ##### ",
	"#######",
	"#  #  #",
	"#######",
	" ## ## ",
	"  ###  ",
	"  # #  ",
]
const IDOL := [
	"    #####    ",
	"   #######   ",
	"  #########  ",
	"  ##+###+##  ",
	"  #########  ",
	"   ##+++##   ",
	"   #######   ",
	"    #####    ",
	"   #######   ",
	"  #########  ",
	" ########### ",
	" ########### ",
	"#############",
	"#############",
]

var canvas  # dmd_canvas.gd instance, assigned by the display

var _queue: Array = []
var _cur: Dictionary = {}
var _idle: Dictionary = {}
var _flash := 0.0
var _time := 0.0

# --- scene builders ---------------------------------------------------------

static func intro(title: String, anim: String) -> Dictionary:
	return {"type": "intro", "title": title, "anim": anim, "duration": 2.6}

static func marquee(text: String, header := "", speed := 80.0) -> Dictionary:
	var w := DmdCanvas.text_width(text)
	return {"type": "marquee", "text": text, "header": header, "speed": speed,
		"duration": float(W + w) / speed + 0.2}

static func zoom(text: String, duration := 1.6) -> Dictionary:
	return {"type": "zoom", "text": text, "duration": duration}

static func blink(text: String, duration := 1.2) -> Dictionary:
	return {"type": "blink", "text": text, "duration": duration}

static func success(title: String, points: int) -> Dictionary:
	return {"type": "success", "title": title, "points": points, "duration": 4.2}

static func fail(title: String) -> Dictionary:
	return {"type": "fail", "title": title, "duration": 2.6}

## Live screen: reads the quest straight from the QuestManager every frame.
static func progress(quests: Object, anim: String) -> Dictionary:
	return {"type": "progress", "quest": quests, "anim": anim}

# --- playback control -------------------------------------------------------

func queue_scene(scene: Dictionary) -> void:
	_queue.append(scene)

## Drop whatever is queued/playing and start `scene` now (idle is kept).
func play_now(scene: Dictionary) -> void:
	_queue.clear()
	_cur = {}
	_queue.append(scene)

## Show `scene` right now, then carry on with whatever was queued.
func interrupt(scene: Dictionary) -> void:
	if not _cur.is_empty():
		_queue.push_front(_cur)
	_cur = {}
	_queue.push_front(scene)

func set_idle(scene: Dictionary) -> void:
	_idle = scene

func clear() -> void:
	_queue.clear()
	_cur = {}
	_idle = {}
	_flash = 0.0

func flash() -> void:
	_flash = FLASH_TIME

func has_content() -> bool:
	return not _cur.is_empty() or not _queue.is_empty() or not _idle.is_empty()

func advance(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta, 0.0)
	if _cur.is_empty() and not _queue.is_empty():
		_start_next()
	if _cur.is_empty():
		return
	_cur["t"] = float(_cur.get("t", 0.0)) + delta
	if float(_cur["t"]) >= float(_cur.get("duration", 2.0)):
		var done := String(_cur["type"])
		_cur = {}
		scene_finished.emit(done)
		if not _queue.is_empty():
			_start_next()

func _start_next() -> void:
	_cur = _queue.pop_front()
	if not _cur.has("t"):
		_cur["t"] = 0.0

## Paint the current frame into `canvas`. With nothing to show the last frame
## is left in place so the display can fade it out instead of blanking.
func render() -> void:
	if canvas == null:
		return
	var s: Dictionary = _cur if not _cur.is_empty() else _idle
	if s.is_empty():
		return
	canvas.clear()
	var t: float = float(s.get("t", _time))
	match String(s["type"]):
		"intro":
			_render_intro(s, t)
		"marquee":
			_render_marquee(s, t)
		"zoom":
			_render_zoom(s, t)
		"blink":
			_render_blink(s, t)
		"success":
			_render_success(s, t)
		"fail":
			_render_fail(s, t)
		"progress":
			_render_progress(s, t)

# --- text effects -------------------------------------------------------------

static func _out(k: float) -> float:
	var c := clampf(k, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)

func _render_marquee(s: Dictionary, t: float) -> void:
	var header := String(s.get("header", ""))
	var y := 12
	if header != "":
		canvas.text_centered(header, 0, MID)
		for x in range(0, W, 2):
			canvas.px(x, 9, DIM)
		y = 16
	var x0 := W - int(t * float(s.get("speed", 80.0)))
	canvas.text(String(s["text"]), x0, y, FULL)
	for x in range(1, W, 2):
		canvas.px(x, 27, DIM)

func _render_zoom(s: Dictionary, t: float) -> void:
	var txt := String(s["text"])
	var dur := float(s["duration"])
	var sc := float(DmdCanvas.fit_scale(txt, 3))
	var scale := sc
	if t < 0.45:
		scale = lerpf(0.2, sc + 0.6, _out(t / 0.45))
	elif t < 0.6:
		scale = lerpf(sc + 0.6, sc, (t - 0.45) / 0.15)
	elif t > dur - 0.3:
		scale = lerpf(sc, 0.0, (t - (dur - 0.3)) / 0.3)
	canvas.text_scaled(txt, W * 0.5, H * 0.5, scale)

func _render_blink(s: Dictionary, t: float) -> void:
	if fmod(t, 0.3) >= 0.19:
		return
	var txt := String(s["text"])
	canvas.text_scaled(txt, W * 0.5, H * 0.5, float(DmdCanvas.fit_scale(txt, 3)))

# --- quest intros -------------------------------------------------------------

func _render_intro(s: Dictionary, t: float) -> void:
	var title := String(s["title"])
	var sc := float(DmdCanvas.fit_scale(title, 2))
	var dur := float(s["duration"])
	match String(s.get("anim", "")):
		"whip":
			_intro_whip(title, sc, t)
		"cart":
			_intro_cart(title, sc, t, dur)
		"boulder":
			_intro_boulder(title, t, dur)
		"skull":
			_intro_skull(title, t)
		"snake":
			_intro_snake(title, sc, t)
		_:
			canvas.text_centered("NEW QUEST", 0, MID)
			canvas.text_scaled(title, W * 0.5, 18, lerpf(0.2, sc, _out(t / 0.5)))

## The whip lashes left to right and its tip "cuts" the title into view, then
## cracks with a starburst and the title flashes.
func _intro_whip(title: String, sc: float, t: float) -> void:
	canvas.text_centered("NEW QUEST", 0, MID)
	var reveal := 1.1
	if t < reveal:
		var tip := int(lerpf(6.0, 130.0, _out(t / reveal)))
		canvas.text_scaled(title, W * 0.5, 17, sc, FULL, tip)
		_whip(tip, t)
	elif t < reveal + 0.35:
		canvas.text_scaled(title, W * 0.5, 17, sc)
		_whip_handle()
		_starburst(122, 26, (t - reveal) / 0.35)
	else:
		var bt := t - reveal - 0.35
		if bt > 0.9 or fmod(bt, 0.3) < 0.18:
			canvas.text_scaled(title, W * 0.5, 17, sc)

func _whip_handle() -> void:
	canvas.line(0, 31, 5, 26, FULL)
	canvas.line(1, 31, 6, 26, FULL)

func _whip(tip: int, t: float) -> void:
	_whip_handle()
	var px := 6
	var py := 26
	for x in range(7, tip):
		var k := float(x - 6) / maxf(1.0, float(tip - 6))
		var y := 26 + int(round(sin(float(x) * 0.22 - t * 28.0) * 3.0 * k))
		canvas.line(px, py, x, y, FULL if k < 0.8 else MID)
		px = x
		py = y

func _starburst(cx: int, cy: int, k: float) -> void:
	var r := int(2.0 + 6.0 * clampf(k, 0.0, 1.0))
	var level := FULL if k < 0.6 else MID
	for i in 8:
		var a := TAU * float(i) / 8.0
		canvas.line(cx, cy, cx + int(round(cos(a) * r)), cy + int(round(sin(a) * r * 0.7)), level)

func _intro_cart(title: String, sc: float, t: float, dur: float) -> void:
	canvas.text_scaled(title, W * 0.5, 10, lerpf(0.2, sc, _out(t / 0.6)))
	for x in range(0, W, 2):
		canvas.px(x, 31, DIM)
	var cx := int(lerpf(-14.0, 132.0, t / dur))
	canvas.sprite(CART, cx, 24)
	# sparks off the wheels
	if fmod(t, 0.12) < 0.06:
		canvas.px(cx - 2, 29, FULL)
		canvas.px(cx - 4, 28, MID)

func _intro_boulder(title: String, t: float, dur: float) -> void:
	if t < 1.0 or fmod(t, 0.3) < 0.2:
		canvas.text_centered(title, 1, FULL)
	var bx := int(lerpf(-12.0, 150.0, t / dur))
	_runner(bx + 16, 23, t)
	_boulder(bx, 25, 6, t)
	for x in range(0, W, 3):
		canvas.px(x, 31, DIM)

func _intro_skull(title: String, t: float) -> void:
	canvas.text_centered("NEW QUEST", 0, MID)
	var glow := fmod(t, 0.25) < 0.12
	for sx in [2, 115]:
		canvas.sprite(SKULL, sx, 11)
		if glow:
			canvas.rect(sx + 2, 14, 3, 2, FULL)
			canvas.rect(sx + 6, 14, 3, 2, FULL)
	if t > 0.4:
		canvas.text_scaled(title, W * 0.5, 16, lerpf(0.2, 1.0, _out((t - 0.4) / 0.4)))

func _intro_snake(title: String, sc: float, t: float) -> void:
	canvas.text_scaled(title, W * 0.5, 9, lerpf(0.2, sc, _out(t / 0.6)))
	_snake(int(t * 50.0) - 10, 25, t, 0.0)
	_snake(int(t * 42.0) - 60, 28, t, 1.7)

func _runner(x: int, y: int, t: float) -> void:
	canvas.sprite(RUNNER_A if fmod(t, 0.2) < 0.1 else RUNNER_B, x, y)

func _boulder(cx: int, cy: int, r: int, t: float) -> void:
	canvas.circle(cx, cy, r, MID, true)
	canvas.circle(cx, cy, r, FULL, false)
	var a0 := t * 10.0
	for i in 3:
		var a := a0 + float(i) * 2.1
		canvas.line(cx, cy, cx + int(round(cos(a) * (r - 1))), cy + int(round(sin(a) * (r - 1))), FULL)

func _snake(head_x: int, base_y: int, t: float, phase: float) -> void:
	var hy := base_y
	for i in 26:
		var x := head_x - i
		var y := base_y + int(round(sin(float(x) * 0.35 - t * 9.0 + phase) * 2.0))
		canvas.px(x, y, FULL)
		canvas.px(x, y + 1, MID)
		if i == 0:
			hy = y
	canvas.rect(head_x, hy - 1, 3, 3, FULL)
	if fmod(t, 0.4) < 0.2:
		canvas.px(head_x + 3, hy, FULL)
		canvas.px(head_x + 4, hy - 1, MID)
		canvas.px(head_x + 4, hy + 1, MID)

func _sparkle(x: int, y: int, phase: float) -> void:
	var k := 0.5 + 0.5 * sin(_time * 7.0 + phase)
	if k < 0.35:
		return
	canvas.px(x, y, FULL)
	if k > 0.75:
		canvas.px(x - 1, y, MID)
		canvas.px(x + 1, y, MID)
		canvas.px(x, y - 1, MID)
		canvas.px(x, y + 1, MID)

# --- outcome screens ------------------------------------------------------------

func _render_success(s: Dictionary, t: float) -> void:
	if t < 0.35 and fmod(t, 0.1) < 0.05:
		canvas.rect(0, 0, W, H, MID)
	if t < 1.5:
		var sc := lerpf(0.3, 2.0, _out(t / 0.5))
		canvas.text_scaled("QUEST", W * 0.5, 8, sc)
		canvas.text_scaled("COMPLETE", W * 0.5, 24, sc)
		return
	var bt := t - 1.5
	var iy := 16 + int(round(sin(bt * 6.0)))
	canvas.sprite(IDOL, 2, iy - 7)
	_sparkle(1, iy - 9, 0.0)
	_sparkle(15, iy - 4, 1.3)
	_sparkle(4, iy + 7, 2.6)
	_sparkle(16, iy + 5, 3.9)
	var title := String(s["title"])
	var tw := DmdCanvas.text_width(title)
	canvas.text(title, 18 + maxi(0, (110 - tw) / 2), 0, MID)
	var pts := int(s["points"])
	var shown := int(float(pts) * clampf(bt / 1.0, 0.0, 1.0))
	if bt < 1.0 or fmod(bt, 0.3) < 0.2:
		var ps := "+" + _commas(shown)
		var sc2 := 2.0 if DmdCanvas.text_width(ps) * 2 <= 108 else 1.0
		canvas.text_scaled(ps, 73, 20, sc2)

func _render_fail(s: Dictionary, t: float) -> void:
	if t > 1.2 or fmod(t, 0.26) < 0.16:
		canvas.text_scaled("QUEST", W * 0.5, 8, 2.0)
		canvas.text_scaled("FAILED", W * 0.5, 24, 2.0)
	if t > 1.2:
		canvas.dissolve((t - 1.2) / maxf(0.1, float(s["duration"]) - 1.3))

static func _commas(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

# --- live progress ------------------------------------------------------------

func _render_progress(s: Dictionary, t: float) -> void:
	var qm = s.get("quest")
	if qm == null or not is_instance_valid(qm) or not qm.is_active():
		return
	var q: Dictionary = qm.active_quest
	var cur := int(q.get("current_count", 0))
	var target := maxi(1, int(q.get("target_count", 1)))
	var time_left: float = maxf(0.0, float(qm.time_left))
	if _flash > 0.0:
		# progress "pop": the new count zooms out big for a moment
		var k := 1.0 - _flash / FLASH_TIME
		canvas.text_scaled("%d/%d" % [cur, target], W * 0.5, H * 0.5, lerpf(3.6, 3.0, _out(k)))
		canvas.rect(0, 0, W, H, DIM, false)
		return
	var title := String(q.get("title", ""))
	var tw := DmdCanvas.text_width(title)
	if tw <= W:
		canvas.text_centered(title, 0, FULL)
	else:
		canvas.text(title, W - int(fmod(t * 40.0, float(tw + W))), 0, FULL)
	canvas.text("%d/%d" % [cur, target], 0, 9, FULL)
	var more := "%d MORE" % (target - cur)
	canvas.text(more, (W - DmdCanvas.text_width(more)) / 2, 9, MID)
	var secs := "%dS" % int(ceil(time_left))
	if time_left > HURRY_AT or fmod(t, 0.3) < 0.18:
		canvas.text(secs, W - DmdCanvas.text_width(secs), 9, FULL)
	canvas.rect(0, 18, W, 4, MID, false)
	var fill := int(round(float(W - 2) * clampf(float(cur) / float(target), 0.0, 1.0)))
	if fill > 0:
		canvas.rect(1, 19, fill, 2, FULL)
	var time_ratio := clampf(time_left / maxf(1.0, float(q.get("time_limit", 30.0))), 0.0, 1.0)
	_strip(String(s.get("anim", "")), t, time_ratio)

## Bottom band (rows 23-31): a small looping animation for the quest theme.
func _strip(anim: String, t: float, time_ratio: float) -> void:
	match anim:
		"cart":
			for x in range(0, W, 2):
				canvas.px(x, 31, DIM)
			canvas.sprite(CART, int(fmod(t * 28.0, 150.0)) - 14, 24)
		"boulder":
			# the boulder closes in as the clock runs down
			var rx := int(fmod(t * 30.0, 170.0)) - 10
			_runner(rx, 23, t)
			_boulder(rx - 8 - int(22.0 * time_ratio), 27, 4, t)
		"skull":
			for i in 5:
				canvas.sprite(SKULL_SMALL, int(fmod(t * 20.0 + float(i) * 30.0, 150.0)) - 10, 24)
		"snake":
			_snake(int(fmod(t * 40.0, 170.0)) - 10, 27, t, 0.0)
		_:
			for i in 7:
				var x := int(fmod(float(i) * 23.0 + t * 12.0, float(W)))
				_sparkle(x, 25 + (i * 3) % 6, float(i) * 1.7)
