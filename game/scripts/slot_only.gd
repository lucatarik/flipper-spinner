extends CanvasLayer
## SLOT ONLY mode (S): the pinball is paused and the "Book of the Temple"
## cabinet fills the screen as a standalone slot machine — credits, a bet
## selector, a SPIN button and a HOLD button under every reel.
##
## Pure slot game: it uses its own SlotMachine (a second slot.tscn instance in
## manual mode), its own credits, and never touches the pinball score.
##
## Rules for holds (classic fruit-machine style, so it can't be farmed):
## available only on the spin right after a losing spin, never during free
## spins, at most 4 reels, and they clear after every spin.
##
## Runs with PROCESS_MODE_ALWAYS because the rest of the tree is paused.

signal closed

const SlotScene = preload("res://scenes/slot.tscn")

const START_CREDITS := 100
const COIN_CREDITS := 100
const LINES := 10
const BET_MIN := 1
const BET_MAX := 5
const MAX_HOLDS := 4

## The cabinet (local slot_view coords, window centre ~(330,686)) scaled up to
## fill the portrait screen; reel r centre on screen = REEL_X0 + (r+0.5)*CELL_PX.
const CAB_SCALE := 1.8
const CAB_POS := Vector2(-234.0, -664.0)
const REEL_X0 := 72.0
const CELL_PX := 115.2
const WINDOW_TOP := 398.0
const WINDOW_H := 345.6

const GOLD := Color("#d4a017")
const GOLD_LIGHT := Color("#ffd24a")
const STONE := Color("#e8e2d0")
const RUBY := Color("#c0203a")

var is_open := false
var credits := START_CREDITS
var bet := 1

var _root: Control
var _slot
var _sfx: Node = null
var _held: Array[bool] = [false, false, false, false, false]
var _holds_allowed := false
var _spinning := false
var _last_win := 0
var _hold_buttons: Array = []
var _hold_frames: Array = []
var _spin_btn: Button
var _credits_label: Label
var _bet_label: Label
var _win_label: Label
var _status_label: Label

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()

func setup(sfx: Node) -> void:
	_sfx = sfx
	if _slot:
		_slot.setup(null, sfx)
		_slot.slot.bet = bet

func open() -> void:
	is_open = true
	visible = true
	_slot.process_mode = Node.PROCESS_MODE_INHERIT
	_slot.set_active(true)
	_refresh()

func close() -> void:
	if _spinning:
		return  # let the reels land first, so a spin is never lost/half-paid
	is_open = false
	visible = false
	_slot.set_active(false)
	_slot.process_mode = Node.PROCESS_MODE_DISABLED
	closed.emit()

# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var handled := true
	match event.keycode:
		KEY_S, KEY_ESCAPE:
			close()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_spin()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_toggle_hold(int(event.keycode - KEY_1))
		KEY_UP, KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_change_bet(1)
		KEY_DOWN, KEY_MINUS, KEY_KP_SUBTRACT:
			_change_bet(-1)
		KEY_C:
			_insert_coin()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()

# --- game -------------------------------------------------------------------

func spin_cost() -> int:
	return 0 if _slot.free_spins_active() else LINES * bet

func _spin() -> void:
	if _spinning or not _slot.is_idle():
		return
	var cost := spin_cost()
	if cost > credits:
		_status("NOT ENOUGH CREDITS - INSERT COIN (C)", RUBY)
		_play("tilt")
		return
	var held: Array = []
	if _holds_allowed:
		for r in 5:
			if _held[r]:
				held.append(r)
	credits -= cost
	_slot.slot.bet = bet
	if not _slot.request_spin(held):
		credits += cost
		return
	_spinning = true
	_last_win = 0
	for r in 5:
		_held[r] = false
	_holds_allowed = false
	_status("GOOD LUCK!" if cost > 0 else "FREE SPIN!", GOLD_LIGHT)
	_refresh()

func _on_cycle_finished(result: Dictionary) -> void:
	_spinning = false
	var win := int(result.get("credits", 0)) * bet
	_last_win = win
	credits += win
	var free_now: bool = _slot.free_spins_active()
	if win > 0:
		_status("WIN %d CREDITS!" % win, GOLD_LIGHT)
		_play("coin")
	elif int(result.get("free_spins_awarded", 0)) > 0:
		_status("FREE SPINS!", GOLD_LIGHT)
	else:
		_status("NO WIN - HOLD REELS (1-5) AND SPIN AGAIN", STONE)
	_holds_allowed = win == 0 and not free_now
	_refresh()

func _toggle_hold(r: int) -> void:
	if r < 0 or r >= 5 or _spinning or not _holds_allowed:
		return
	if not _held[r] and _held.count(true) >= MAX_HOLDS:
		_status("MAX %d HOLDS" % MAX_HOLDS, RUBY)
		return
	_held[r] = not _held[r]
	_play("lane")
	_refresh()

func _change_bet(d: int) -> void:
	if _spinning:
		return
	var nb := clampi(bet + d, BET_MIN, BET_MAX)
	if nb == bet:
		return
	bet = nb
	_slot.slot.bet = bet
	_play("bet_up", 0.9 + 0.05 * bet)
	_refresh()

func _insert_coin() -> void:
	credits += COIN_CREDITS
	_play("coin")
	_status("+%d CREDITS" % COIN_CREDITS, GOLD_LIGHT)
	_refresh()

func _refresh() -> void:
	_credits_label.text = "CREDITS\n%d" % credits
	_bet_label.text = "BET %d x %d LINES" % [bet, LINES]
	_win_label.text = "WIN\n%d" % _last_win
	var cost := spin_cost()
	_spin_btn.text = "FREE SPIN" if _slot.free_spins_active() else "SPIN  (%d)" % cost
	_spin_btn.disabled = _spinning
	for r in 5:
		var b: Button = _hold_buttons[r]
		b.disabled = _spinning or not _holds_allowed
		b.text = "HELD" if _held[r] else "HOLD %d" % (r + 1)
		b.modulate = Color(1.0, 0.85, 0.3) if _held[r] else Color.WHITE
		(_hold_frames[r] as Control).visible = _held[r]

func _status(text: String, col: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", col)

func _play(sound: String, pitch := 1.0) -> void:
	if _sfx:
		_sfx.play(sound, pitch)

# --- construction -----------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.size = Vector2(720, 1280)
	add_child(_root)

	var bg := ColorRect.new()
	bg.size = Vector2(720, 1280)
	bg.color = Color("#0d0604")
	_root.add_child(bg)
	var spot := TextureRect.new()
	spot.texture = _radial_tex(Color(0.85, 0.55, 0.12, 0.35))
	spot.stretch_mode = TextureRect.STRETCH_SCALE
	spot.position = Vector2(-140, 60)
	spot.size = Vector2(1000, 1000)
	spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(spot)
	# red velvet side curtains + gold rails, casino-floor framing
	for x in [0.0, 700.0]:
		var rail := ColorRect.new()
		rail.position = Vector2(x, 0)
		rail.size = Vector2(20, 1280)
		rail.color = Color("#5a0f18")
		rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(rail)
		var trim := ColorRect.new()
		trim.position = Vector2(x + (16.0 if x == 0.0 else 0.0), 0)
		trim.size = Vector2(4, 1280)
		trim.color = GOLD
		trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(trim)

	_root.add_child(_label("SLOT ONLY", Vector2(0, 30), 44, GOLD_LIGHT, 720))
	_root.add_child(_label("1-5 HOLD   SPACE SPIN   UP/DOWN BET   C COIN   S EXIT",
		Vector2(0, 92), 18, STONE, 720))

	var cab := Node2D.new()
	cab.scale = Vector2(CAB_SCALE, CAB_SCALE)
	cab.position = CAB_POS
	_root.add_child(cab)
	_slot = SlotScene.instantiate()
	_slot.manual_mode = true
	cab.add_child(_slot)
	_slot.process_mode = Node.PROCESS_MODE_DISABLED
	_slot.cycle_finished.connect(_on_cycle_finished)
	_slot.free_spins_changed.connect(func(_a): _refresh())

	# gold "HELD" frames drawn over held reels
	for r in 5:
		var f := Panel.new()
		f.position = Vector2(REEL_X0 + r * CELL_PX + 3.0, WINDOW_TOP + 3.0)
		f.size = Vector2(CELL_PX - 6.0, WINDOW_H - 6.0)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.82, 0.3, 0.12)
		sb.border_color = GOLD_LIGHT
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(6)
		f.add_theme_stylebox_override("panel", sb)
		f.visible = false
		f.z_index = 30  # above the cabinet's reels (z 4) and win lines (z 21)
		var tag := _label("HELD", Vector2(0, WINDOW_H - 46.0), 24, GOLD_LIGHT, CELL_PX - 6.0)
		f.add_child(tag)
		_root.add_child(f)
		_hold_frames.append(f)

	for r in 5:
		var cx := REEL_X0 + (float(r) + 0.5) * CELL_PX
		var b := _button("HOLD %d" % (r + 1), Vector2(cx - 52.0, 952.0), Vector2(104, 58), 20)
		var idx := r
		b.pressed.connect(func(): _toggle_hold(idx))
		_hold_buttons.append(b)

	_credits_label = _label("CREDITS\n0", Vector2(30, 1024), 26, GOLD_LIGHT, 200)
	_root.add_child(_credits_label)
	_win_label = _label("WIN\n0", Vector2(490, 1024), 26, GOLD_LIGHT, 200)
	_root.add_child(_win_label)
	_bet_label = _label("BET 1", Vector2(230, 1020), 20, STONE, 260)
	_root.add_child(_bet_label)
	var minus := _button("-", Vector2(262, 1052), Vector2(90, 48), 30)
	minus.pressed.connect(func(): _change_bet(-1))
	var plus := _button("+", Vector2(368, 1052), Vector2(90, 48), 30)
	plus.pressed.connect(func(): _change_bet(1))

	_spin_btn = _button("SPIN", Vector2(210, 1120), Vector2(300, 92), 36, true)
	_spin_btn.pressed.connect(_spin)
	var coin := _button("INSERT\nCOIN", Vector2(34, 1128), Vector2(150, 76), 20)
	coin.pressed.connect(_insert_coin)
	var exit := _button("EXIT (S)", Vector2(536, 1128), Vector2(150, 76), 20)
	exit.pressed.connect(close)

	_status_label = _label("", Vector2(0, 1228), 20, STONE, 720)
	_root.add_child(_status_label)
	_status("PRESS SPIN - GOOD LUCK!", STONE)

func _label(text: String, pos: Vector2, size: int, col: Color, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size.x = width
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	l.add_theme_constant_override("outline_size", maxi(2, int(size * 0.12)))
	return l

func _button(text: String, pos: Vector2, size: Vector2, font_size: int, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color("#1a0d02") if big else GOLD_LIGHT)
	b.add_theme_color_override("font_hover_color", Color("#1a0d02") if big else Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.45, 0.35))
	var base := GOLD if big else Color("#2a1608")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = base
		if state == "hover":
			sb.bg_color = base.lightened(0.15)
		elif state == "pressed":
			sb.bg_color = RUBY
		elif state == "disabled":
			sb.bg_color = base.darkened(0.45)
		sb.border_color = GOLD_LIGHT if state != "disabled" else Color(0.4, 0.33, 0.15)
		sb.set_border_width_all(4 if big else 3)
		sb.set_corner_radius_all(18 if big else 10)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 6
		b.add_theme_stylebox_override(state, sb)
	_root.add_child(b)
	return b

func _radial_tex(col: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex
