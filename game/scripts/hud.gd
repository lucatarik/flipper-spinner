extends CanvasLayer
## HUD bound to Rules signals: score, ball, multiplier, locks, current mode with
## a timed progress bar, transient messages, attract and game-over screens.

var rules = null

var _score_label: Label
var _ball_label: Label
var _mult_label: Label
var _locks_label: Label
var _mode_label: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _message_label: Label
var _attract: Control
var _attract_high: Label
var _gameover: Control
var _gameover_score: Label
var _new_high: Label

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
	_mode_label = _make_label(Vector2(24, 108), 24, STONE, HORIZONTAL_ALIGNMENT_LEFT)
	_bar_bg = _make_rect(Vector2(24, 140), Vector2(BAR_W, 14), Color(0.1, 0.09, 0.05, 0.7))
	_bar_fill = _make_rect(Vector2(24, 140), Vector2(0, 14), GOLD)
	_message_label = _make_label(Vector2(0, 330), 52, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_message_label.size.x = 720
	_message_label.visible = false

	_build_attract()
	_build_gameover()

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
	_attract_high.text = "HIGH SCORE  %d" % r.high_score
	_on_score(r.score)
	_on_ball(r.ball_number, 3)
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
	_attract.visible = state == 0
	_gameover.visible = state == 2
	if state == 1:
		_attract_high.text = "HIGH SCORE  %d" % rules.high_score

func _on_game_over(final_score: int, is_high: bool) -> void:
	_gameover_score.text = str(final_score)
	_new_high.visible = is_high

func _on_mode(mode_name: String, time_left: float, progress: int, goal: int) -> void:
	if mode_name == "":
		_mode_label.text = ""
		_bar_fill.size.x = 0.0
	else:
		_mode_label.text = "%s   %.0fs   %d/%d" % [mode_name, ceilf(time_left), progress, goal]
		var ratio := 0.0 if goal <= 0 else clampf(float(progress) / float(goal), 0.0, 1.0)
		_bar_fill.size.x = BAR_W * ratio
