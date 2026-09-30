extends CanvasLayer
## HUD bound to Rules signals: score, ball, multiplier, locks, current mode with
## a timed progress bar, transient messages, attract and game-over screens.

signal music_toggle_pressed
signal slot_only_requested

## Every command in the game, shown by the INFO screen (start menu + pause
## menu, or I). Keep in sync with README.md "Controls". "" key = header.
const INFO_ROWS := [
	["", "PINBALL"],
	["LEFT / Z / A / SHIFT+L", "left flipper + left wings"],
	["RIGHT / D / /", "right flipper + right wings"],
	["DOWN / SPACE (hold)", "plunger: hold to charge, release"],
	["ENTER / SPACE", "start game"],
	["X / C / T / UP", "nudge left / right / up"],
	["P / ESC", "pause menu"],
	["I", "this info screen"],
	["S", "SLOT ONLY mode on / off"],
	["SPEAKER ICON", "music + sound on / off"],
	["", "CHEATS"],
	["M", "Eternal Life multiball"],
	["B", "free extra ball right now"],
	["N", "extra ball in reserve"],
	["R", "reset a stuck ball"],
	["V", "gravity 100% / 50%"],
	["TAB", "zoom camera following the ball"],
	["", "SLOT ONLY"],
	["SPACE / ENTER", "spin"],
	["1 - 5", "hold a reel (after a losing spin)"],
	["UP / DOWN  or  + / -", "bet 1-5 per line (10 lines)"],
	["C", "insert coin: +100 credits"],
	["S / ESC", "back to the pinball"],
	["", "QUESTS"],
	["DOT-MATRIX (TOP)", "random timed quests after you score:"],
	["", "reach the goal in time = big bonus"],
	["", "DEV + TOUCH"],
	["E", "layout editor (drag, S = save)"],
	["LEFT / RIGHT HALF", "touch: flippers"],
	["BOTTOM-RIGHT / 2 FINGERS", "touch: plunger / nudge up"],
]

var rules = null

var _score_label: Label
var _ball_label: Label
var _mult_label: Label
var _locks_label: Label
var _extra_label: Label
var _tilt_label: Label
var _pf_label: Label
var _mode_label: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _message_label: Label
var _attract: Control
var _attract_high: Label
var _gameover: Control
var _gameover_score: Label
var _new_high: Label
var _music_btn: Button
var _music_shapes: Array = []
var _pause_menu: Control
var _info: Control
var _paused_by_me := false

var _message_timer := 0.0
var _message_total := 0.0

const GOLD := Color("#d4a017")
const STONE := Color("#e8e2d0")
const DARK := Color(0.05, 0.04, 0.02, 0.82)
const BAR_W := 300.0

func _ready() -> void:
	_score_label = _make_label(Vector2(24, 16), 48, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_ball_label = _make_label(Vector2(440, 20), 36, STONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_mult_label = _make_label(Vector2(24, 72), 30, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_locks_label = _make_label(Vector2(440, 72), 30, STONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_extra_label = _make_label(Vector2(24, 108), 26, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_extra_label.visible = false
	_pf_label = _make_label(Vector2(440, 108), 26, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_pf_label.visible = false
	_mode_label = _make_label(Vector2(24, 140), 24, STONE, HORIZONTAL_ALIGNMENT_LEFT)
	_tilt_label = _make_label(Vector2(440, 140), 26, Color("#ff4040"), HORIZONTAL_ALIGNMENT_RIGHT)
	_tilt_label.visible = false
	_bar_bg = _make_rect(Vector2(24, 172), Vector2(BAR_W, 14), Color(0.1, 0.09, 0.05, 0.7))
	_bar_fill = _make_rect(Vector2(24, 172), Vector2(0, 14), GOLD)
	_bar_bg.visible = false  # only while a mode runs (read as a stray wall)
	_message_label = _make_label(Vector2(0, 330), 52, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_message_label.size.x = 720
	_message_label.visible = false

	# Above the quest DMD (layer 2); keeps working while the tree is paused so
	# the pause menu / info screen can be driven.
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_attract()
	_build_gameover()
	_build_music_button()
	_build_pause_menu()
	_build_info()

# --- pause menu + info ------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action_pressed("pause"):
		if _info.visible:
			_close_info()
		elif _paused_by_me:
			_resume()
		elif _can_pause():
			_pause()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("info"):
		if _info.visible:
			_close_info()
		elif _paused_by_me or not _is_playing():
			_open_info()
		elif _can_pause():
			_pause()
			_open_info()
		else:
			return
		get_viewport().set_input_as_handled()

func _is_playing() -> bool:
	return rules != null and rules.state == 1

## Only mid-game, and never while something else (SLOT ONLY, the layout
## editor) already owns the pause.
func _can_pause() -> bool:
	if not _is_playing() or get_tree().paused:
		return false
	var table := get_parent()
	if table and table.has_method("pause_blocked") and table.pause_blocked():
		return false
	return true

func _pause() -> void:
	_paused_by_me = true
	get_tree().paused = true
	_pause_menu.visible = true

func _resume() -> void:
	_info.visible = false
	_pause_menu.visible = false
	if _paused_by_me:
		_paused_by_me = false
		get_tree().paused = false

func _open_info() -> void:
	_info.visible = true

func _close_info() -> void:
	_info.visible = false

func _request_slot_only() -> void:
	_resume()
	slot_only_requested.emit()

func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.size = Vector2(720, 1280)
	_pause_menu.visible = false
	add_child(_pause_menu)
	var bg := ColorRect.new()
	bg.size = Vector2(720, 1280)
	bg.color = DARK
	_pause_menu.add_child(bg)
	_pause_menu.add_child(_child_label("PAUSED", Vector2(0, 380), 64, GOLD))
	_pause_menu.add_child(_child_label("P / ESC TO RESUME", Vector2(0, 470), 22, STONE))
	_menu_button(_pause_menu, "RESUME", 560, _resume)
	_menu_button(_pause_menu, "INFO  (I)", 660, _open_info)
	_menu_button(_pause_menu, "SLOT ONLY  (S)", 760, _request_slot_only)

func _build_info() -> void:
	_info = Control.new()
	_info.size = Vector2(720, 1280)
	_info.visible = false
	add_child(_info)
	var bg := ColorRect.new()
	bg.size = Vector2(720, 1280)
	bg.color = Color(0.04, 0.03, 0.015, 1.0)
	_info.add_child(bg)
	_info.add_child(_child_label("HOW TO PLAY", Vector2(0, 28), 44, GOLD))
	var y := 104.0
	for row in INFO_ROWS:
		var key := String(row[0])
		var desc := String(row[1])
		if key == "" and desc == desc.to_upper():
			y += 8.0
			var h := _child_label(desc, Vector2(0, y), 24, GOLD)
			_info.add_child(h)
			y += 34.0
			continue
		var k := Label.new()
		k.text = key
		k.position = Vector2(16, y)
		k.size.x = 290
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		k.add_theme_font_size_override("font_size", 19)
		k.add_theme_color_override("font_color", Color("#ffd24a"))
		_info.add_child(k)
		var d := Label.new()
		d.text = desc
		d.position = Vector2(322, y)
		d.size.x = 390
		d.add_theme_font_size_override("font_size", 19)
		d.add_theme_color_override("font_color", STONE)
		_info.add_child(d)
		y += 29.0
	_menu_button(_info, "CLOSE  (I / ESC)", 1180, _close_info)

## Big touch-friendly menu button, horizontally centred at row `y`.
func _menu_button(parent: Control, text: String, y: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(200, y)
	b.size = Vector2(320, 72)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color("#ffd24a"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#2a1608") if state == "normal" else (Color("#4a2a10") if state == "hover" else Color("#c0203a"))
		sb.border_color = GOLD
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

## D4: clickable/tappable speaker icon (top-right, under the ball counter).
func _build_music_button() -> void:
	_music_btn = Button.new()
	_music_btn.flat = true
	_music_btn.position = Vector2(622, 12)
	_music_btn.size = Vector2(78, 50)
	_music_btn.tooltip_text = "Music (N)"
	add_child(_music_btn)

	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(10, 20), Vector2(22, 20), Vector2(22, 30), Vector2(10, 30)])
	_music_btn.add_child(body)
	_music_shapes.append(body)

	var cone := Polygon2D.new()
	cone.polygon = PackedVector2Array([
		Vector2(22, 20), Vector2(36, 8), Vector2(36, 42), Vector2(22, 30)])
	_music_btn.add_child(cone)
	_music_shapes.append(cone)

	for radius in [8.0, 14.0]:
		var wave := Line2D.new()
		var pts := PackedVector2Array()
		for i in 7:
			var a := deg_to_rad(-55.0 + 110.0 * float(i) / 6.0)
			pts.append(Vector2(36, 25) + Vector2(cos(a), sin(a)) * radius)
		wave.points = pts
		wave.width = 2.5
		_music_btn.add_child(wave)
		_music_shapes.append(wave)

	_music_btn.pressed.connect(func(): music_toggle_pressed.emit())
	set_music_enabled(true)

func set_music_enabled(on: bool) -> void:
	var col := Color("#ffd24a") if on else Color("#6a6355")
	for s in _music_shapes:
		if s is Line2D:
			s.default_color = col
		else:
			s.color = col
	if _music_btn:
		_music_btn.modulate = Color(1, 1, 1, 1.0 if on else 0.6)

func _make_label(pos: Vector2, size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align as HorizontalAlignment
	add_child(l)
	return l

func _make_rect(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = color
	add_child(r)
	return r

func _build_attract() -> void:
	_attract = Control.new()
	_attract.position = Vector2.ZERO
	add_child(_attract)
	var bg := ColorRect.new()
	bg.size = Vector2(720, 1280)
	bg.color = DARK
	_attract.add_child(bg)
	_attract.add_child(_child_label("TEMPLE OF THE IDOL", Vector2(0, 430), 60, GOLD))
	_attract.add_child(_child_label("THE PATH OF ADVENTURE AWAITS", Vector2(0, 510), 22, STONE))
	_attract_high = _child_label("HIGH SCORE  0", Vector2(0, 660), 32, STONE)
	_attract.add_child(_attract_high)
	_attract.add_child(_child_label("PRESS ENTER / TAP", Vector2(0, 980), 40, GOLD))
	_menu_button(_attract, "INFO  (I)", 1070, _open_info)
	_menu_button(_attract, "SLOT ONLY  (S)", 1160, func(): slot_only_requested.emit())

func _build_gameover() -> void:
	_gameover = Control.new()
	_gameover.position = Vector2.ZERO
	_gameover.visible = false
	add_child(_gameover)
	var bg := ColorRect.new()
	bg.size = Vector2(720, 1280)
	bg.color = DARK
	_gameover.add_child(bg)
	_gameover.add_child(_child_label("GAME OVER", Vector2(0, 400), 56, GOLD))
	_gameover_score = _child_label("0", Vector2(0, 480), 60, STONE)
	_gameover.add_child(_gameover_score)
	_new_high = _child_label("NEW HIGH SCORE", Vector2(0, 570), 40, GOLD)
	_new_high.visible = false
	_gameover.add_child(_new_high)
	_gameover.add_child(_child_label("PRESS ENTER / TAP", Vector2(0, 980), 40, GOLD))

func _child_label(text: String, pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size.x = 720
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func setup(r) -> void:
	rules = r
	r.score_changed.connect(_on_score)
	r.ball_changed.connect(_on_ball)
	r.message.connect(_on_message)
	r.state_changed.connect(_on_state)
	r.mode_changed.connect(_on_mode)
	r.game_over.connect(_on_game_over)
	r.extra_balls_changed.connect(_on_extra_balls)
	r.tilt_warning.connect(_on_tilt_warning)
	r.playfield_mult_changed.connect(_on_playfield_mult)
	r.request_serve_ball.connect(_on_serve)
	_attract_high.text = "HIGH SCORE  %d" % r.high_score
	_on_score(r.score)
	_on_ball(r.ball_number, 3)
	_on_extra_balls(r.extra_balls)
	_on_state(r.state)

func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message_label.visible = false
		else:
			var a := 1.0
			if _message_timer < 0.5:
				a = _message_timer / 0.5
			_message_label.modulate.a = a

func _on_score(score: int) -> void:
	_score_label.text = str(score)

func _on_ball(ball_number: int, balls_per_game: int) -> void:
	_ball_label.text = "BALL %d/%d" % [ball_number, balls_per_game]

func _on_message(text: String, seconds: float) -> void:
	_message_label.text = text
	_message_label.modulate.a = 1.0
	_message_label.visible = true
	_message_timer = seconds
	_message_total = max(seconds, 0.001)

func _on_state(state: int) -> void:
	if _info:
		_info.visible = false
	_attract.visible = state == 0
	_gameover.visible = state == 2
	if state == 1:
		_attract_high.text = "HIGH SCORE  %d" % rules.high_score
	if state != 1:
		_tilt_label.visible = false
		_extra_label.visible = false
		_pf_label.visible = false

func _on_extra_balls(n: int) -> void:
	_extra_label.text = "EXTRA BALL x%d" % n
	_extra_label.visible = n > 0

func _on_tilt_warning(level: int) -> void:
	if level >= 2:
		_tilt_label.text = "DANGER"
	else:
		_tilt_label.text = "WARNING"
	_tilt_label.visible = true
	var t := create_tween()
	t.tween_property(_tilt_label, "modulate:a", 0.2, 0.15)
	t.tween_property(_tilt_label, "modulate:a", 1.0, 0.15)

func _on_playfield_mult(mult: int) -> void:
	_pf_label.text = "PLAYFIELD x%d" % mult
	_pf_label.visible = mult > 1

func _on_serve() -> void:
	_tilt_label.visible = false
	_tilt_label.modulate.a = 1.0

func _on_game_over(final_score: int, is_high: bool) -> void:
	_gameover_score.text = str(final_score)
	_new_high.visible = is_high

func _on_mode(mode_name: String, time_left: float, progress: int, goal: int) -> void:
	if mode_name == "":
		_mode_label.text = ""
		_bar_fill.size.x = 0.0
		_bar_bg.visible = false
	else:
		_mode_label.text = "%s   %.0fs   %d/%d" % [mode_name, ceilf(time_left), progress, goal]
		var ratio := 0.0 if goal <= 0 else clampf(float(progress) / float(goal), 0.0, 1.0)
		_bar_fill.size.x = BAR_W * ratio
		_bar_bg.visible = true
