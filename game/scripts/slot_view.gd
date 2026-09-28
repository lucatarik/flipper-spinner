extends Node2D
## "Book of the Temple" slot view. Owns a SlotMachine instance and renders the
## reel window at x 170..490, y 590..782 (5x3 cells of 64 px): clipped reels that
## scroll with a slight vertical stretch, staggered stops with overshoot bounce,
## anticipation, win-line drawing, symbol pulse/glow, count-up credit label,
## BIG WIN zoom, a coin fountain, the book-flip free-spin reveal, expanding
## symbols, the "FREE SPINS n" rainbow marquee and the TEMPLE POWER meter.
##
## Drawing only: no collision of any kind. The demo keeps cycl(ing) while the
## table is not PLAYING (no payout); the table feeds switch energy and applies
## slot results through the public API.

signal cycle_finished(result: Dictionary)
signal free_spins_changed(active: bool)
signal spin_started()

const SlotMachineScript = preload("res://scripts/slot_machine.gd")

const CELL := 64.0
const REELS := 5
const ROWS := 3
const WINDOW := Rect2(170.0, 590.0, 320.0, 192.0)

const IDLE_SECONDS := 0.8
const SPIN_SECONDS := 1.3
const STOP_DELAY := 0.25
const ANTICIPATION_EXTRA := 0.8
const WIN_SECONDS := 2.6
const NO_WIN_SECONDS := 0.6
const BIG_WIN_CREDITS := 50
const ENERGY_MAX := 8

const GOLD := Color("#d4a017")
const GOLD_LIGHT := Color("#ffd24a")
const LAPIS := Color("#151a3a")
const LAPIS_DARK := Color("#0b0e22")
const STONE := Color("#6b6b6b")

const STATE_IDLE := 0
const STATE_SPINNING := 1
const STATE_EVALUATE := 2
const STATE_SHOW_WIN := 3

var slot
var _table: Node = null
var _sfx: Node = null

var _state := STATE_IDLE
var _timer := 0.0
var _stops: Array = []
var _stopped: Array = []
var _stop_times: Array = []
var _anticipation_reels: Array = []

var _win_result: Dictionary = {}
var _display_grid: Array = []
var _win_lines: Array = []
var _win_elapsed := 0.0
var _drawn_line := -1
var _count_current := 0
var _count_target := 0
var _count_tick := 0.0
var _big_win := false

var _active := false
var _free_spins_active := false
var _marquee_time := 0.0
var _frame_glow := 0.0
var _pulse := {}
var _spin_scroll := 0.0
var _book_flip := 0.0
var _book_flip_symbol := ""
var _expanded: Array = []

var _reel_textures: Array = []
var _marquee_lamps: Array = []
var _power_lamps: Array = []
var _win_line_layer: Node2D
var _count_label: Label
var _free_label: Label
var _big_label: Label
var _bonus_label: Label
var _reveal_label: Label
var _idle_label: Label
var _coins: CPUParticles2D
var _book_node: Node2D
var _book_sprite: Sprite2D

func _ready() -> void:
	slot = SlotMachineScript.new()
	_build_frame()
	_build_win_lines()
	_build_reels()
	_build_book_flip()
	_build_lamps()
	_build_labels()
	_build_particles()
	_update_energy_lamps()
	_update_free_label()

func setup(table: Node, sfx: Node) -> void:
	_table = table
	_sfx = sfx
	slot.reset_bet()
	if table:
		var rules = table.get("rules")
		if rules:
			slot.bet = max(1, int(rules.playfield_mult))
	_update_energy_lamps()

# --- public API -------------------------------------------------------------

## Force the next spin() to land on this grid (flat 15 reel-major or grid[reel][row]).
func force_grid(grid: Array) -> void:
	slot.force_grid(grid)

## D3: spin only while a ball is in play. When inactive a running spin finishes
## (and still evaluates), then the reels idle with a "PLUNGE TO SPIN" prompt.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if _idle_label:
		_idle_label.visible = not active
	if not active:
		if _state == STATE_IDLE:
			_timer = IDLE_SECONDS
		return
	if _state == STATE_IDLE and _timer <= 0.0:
		_timer = 0.05

func reset_bet() -> void:
	slot.reset_bet()
	_update_energy_lamps()

func add_energy(n: int = 1) -> void:
	var before: int = slot.bet
	slot.add_energy(n)
	_update_energy_lamps()
	if slot.bet > before:
		_play("bet_up")

func free_spins_active() -> bool:
	return slot.free_spins > 0

func current_bet() -> int:
	return slot.bet

# --- cycle ------------------------------------------------------------------

func _process(delta: float) -> void:
	if slot == null:
		return
	_marquee_time += delta
	if _frame_glow > 0.0:
		_frame_glow = max(_frame_glow - delta * 1.5, 0.0)
	_update_marquee()
	_update_pulses(delta)
	_update_count_up(delta)
	_update_book_flip(delta)
	match _state:
		STATE_IDLE:
			_timer -= delta
			if _timer <= 0.0 and _active:
				_begin_spin()
		STATE_SPINNING:
			_update_spinning(delta)
		STATE_EVALUATE:
			_timer -= delta
			if _timer <= 0.0:
				_begin_show_win()
		STATE_SHOW_WIN:
			_update_show_win(delta)
	_update_reels()

func _clear_win() -> void:
	_win_result = {}
	_win_lines = []

	_big_win = false
	_expanded = []
	_big_label.visible = false
	_bonus_label.visible = false
	_reveal_label.visible = false
	_win_line_layer.visible = false
	_drawn_line = -1
	_book_node.visible = false
	_pulse.clear()
	_count_current = 0
	_count_target = 0
	_count_label.text = ""
	_pulse.clear()
	_update_reels()

func _begin_spin() -> void:
	_clear_win()
	_state = STATE_SPINNING
	_timer = 0.0
	_spin_scroll = 0.0
	_stopped = []
	_stop_times = []
	_anticipation_reels = []
	spin_started.emit()
	_play("reel_spin")
	_loop_start("reel_spin")

	var was_free: bool = slot.free_spins > 0
	var grid: Array = slot.spin()
	_win_result = slot.evaluate(grid)
	_display_grid = grid.duplicate(true)
	_expanded = _win_result.get("expanded_reels", []).duplicate()
	if was_free and slot.free_spins <= 0:
		_update_free_label()
		free_spins_changed.emit(false)

	# Anticipation: if the stopped reels already show 2+ books, the remaining
	# reels spin 0.8 s longer, the frame glows and a rising tension sound plays.
	var anticipation_from := -1
	for r in REELS:
		if _visible_books(grid, r) >= 2:
			anticipation_from = r + 1
			break
	var t := 0.0
	for r in REELS:
		t += SPIN_SECONDS / float(REELS)
		if anticipation_from >= 0 and r >= anticipation_from:
			t += ANTICIPATION_EXTRA
			_anticipation_reels.append(r)
		_stop_times.append(t)
		_stopped.append(false)

func _visible_books(grid: Array, reel: int) -> int:
	var n := 0
	for row in ROWS:
		if String(grid[reel][row]) == "book":
			n += 1
	return n

func _update_spinning(delta: float) -> void:
	_timer += delta
	_spin_scroll += delta * 1400.0
	for r in REELS:
		if not _stopped[r] and _timer >= _stop_times[r]:
			_stopped[r] = true
			_play("reel_stop", 0.92 + r * 0.03)
			if r in _anticipation_reels:
				_play("anticipation")
				_flash_reel_frame()
	if _timer >= _stop_times[REELS - 1]:
		_loop_stop("reel_spin")
		_state = STATE_EVALUATE
		_timer = 0.12

func _begin_show_win() -> void:
	_state = STATE_SHOW_WIN
	_win_elapsed = 0.0
	var awarded := int(_win_result.get("free_spins_awarded", 0))
	var was_active: bool = slot.free_spins > 0
	if awarded > 0:
		if was_active:
			slot.free_spins += SlotMachineScript.FREE_SPINS_RETRIGGER
		else:
			slot.grant_free_spins(awarded)
			_play("free_spins")
			_begin_book_flip()
		_update_free_label()
		free_spins_changed.emit(true)
	# collect winning lines (line index + the symbols on them) for drawing
	_win_lines = []
	var grid: Array = _win_result.get("grid", [])
	for line in _win_result.get("lines", []):
		var idx := int(line["line"])
		var payline: Array = SlotMachineScript.PAYLINES[idx]
		var pts: Array = []
		var cells: Array = []
		for r in REELS:
			var pos := _cell_centre(grid, r, int(payline[r]))
			pts.append(pos)
			cells.append(Vector2i(r, int(payline[r])))
		_win_lines.append({"line": idx, "points": pts, "cells": cells, "symbol": line["symbol"]})
		for c in cells:
			_pulse[c] = 0.0

	var credits := int(_win_result.get("credits", 0))
	_count_target = credits
	_big_win = credits >= BIG_WIN_CREDITS
	if credits > 0:
		_count_label.text = str(_count_current)
		if _big_win:
			_big_label.visible = true
			_big_label.scale = Vector2.ONE
			var t := create_tween()
			t.tween_property(_big_label, "scale", Vector2(1.6, 1.6), 0.25).set_trans(Tween.TRANS_BACK)
			t.tween_property(_big_label, "scale", Vector2(1.0, 1.0), 0.35)
			_play("win_big")
			_coins.emitting = true
		else:
			_play("win_small")
	_show_bonus_banner()

## C2: show the pinball bonus names won by this spin as the slot's win banner
## with a distinct sound and a frame flash.
func _show_bonus_banner() -> void:
	var bonuses: Dictionary = _win_result.get("bonuses", {})
	var names: Array = bonuses.get("names", [])
	if names.is_empty():
		return
	var parts: Array = []
	for n in names:
		parts.append("%s!" % String(n))
	_bonus_label.text = "  ".join(parts)
	_bonus_label.visible = true
	_flash_reel_frame()
	_play("win_big")

func _update_show_win(delta: float) -> void:
	_win_elapsed += delta
	# reveal winning lines one after another
	if not _win_lines.is_empty():
		var per := 0.45
		var shown := int(_win_elapsed / per)
		var line_index := mini(shown, _win_lines.size() - 1)
		_win_line_layer.visible = true
		if line_index != _drawn_line:
			_drawn_line = line_index
			_draw_win_line(_win_lines[line_index])
	var duration := WIN_SECONDS if not _win_lines.is_empty() else NO_WIN_SECONDS
	if _win_elapsed >= duration:
		_count_current = _count_target
		_count_label.text = str(_count_current)
		var result := _win_result.duplicate(true)
		result["counted"] = _count_current
		_win_line_layer.visible = false
		_coins.emitting = false
		cycle_finished.emit(result)
		_state = STATE_IDLE
		_timer = IDLE_SECONDS

## Points come straight from _cell_centre (exact cell-centre coordinates), so
## the line was already mathematically correct — what read as "imprecise"
## (user report) was the soft, non-antialiased 5px stroke and loose diagonal
## corner-to-corner "X" markers not actually centred-looking on the symbol.
## Thinner antialiased line + a small centred filled dot per cell instead.
func _draw_win_line(line: Dictionary) -> void:
	for child in _win_line_layer.get_children():
		child.queue_free()
	var pts: Array = line["points"]
	var shape := Line2D.new()
	shape.points = PackedVector2Array(pts)
	shape.width = 3.0
	shape.antialiased = true
	shape.default_color = _line_colour(int(line["line"]))
	_win_line_layer.add_child(shape)
	for p in pts:
		var dot := Polygon2D.new()
		var dot_pts := PackedVector2Array()
		var n := 12
		for i in n:
			var a := TAU * float(i) / float(n)
			dot_pts.append(Vector2(cos(a), sin(a)) * 4.0)
		dot.polygon = dot_pts
		dot.position = p
		dot.color = Color(1, 1, 1, 0.85)
		_win_line_layer.add_child(dot)

func _line_colour(i: int) -> Color:
	var palette := [
		Color("#ff4d4d"), Color("#4dff88"), Color("#4da6ff"), Color("#ffd24a"),
		Color("#ff4dff"), Color("#4dffff"), Color("#ffa64d"), Color("#b366ff"),
		Color("#66ff66"), Color("#ff6666"),
	]
	return palette[i % palette.size()]

func _cell_centre(grid: Array, reel: int, row: int) -> Vector2:
	return WINDOW.position + Vector2((reel + 0.5) * CELL, (row + 0.5) * CELL)

func _update_reels() -> void:
	var grid: Array = _display_grid
	var spin_phase := _state == STATE_SPINNING
	for r in REELS:
		if spin_phase and not _stopped[r]:
			_draw_reel_scroll(r)
		else:
			_draw_reel_static(r, grid)

func _draw_reel_scroll(reel: int) -> void:
	var holders: Array = _reel_textures[reel]
	var strip: Array = SlotMachineScript.REEL_STRIP
	var stride := CELL
	var start_index := int(_spin_scroll / stride) % strip.size()
	for i in holders.size():
		var sym := String(strip[(start_index + i) % strip.size()])
		var holder: Node2D = holders[i]
		var y := (float(i) + 0.5) * stride + fmod(_spin_scroll, stride) - stride
		holder.position = Vector2(CELL * 0.5, y)
		# slight vertical stretch for a motion-blur feel while scrolling fast
		holder.scale = Vector2(0.94, 1.12)
		_set_holder_symbol(holder, sym)
		holder.visible = true

func _draw_reel_static(reel: int, grid: Array) -> void:
	var holders: Array = _reel_textures[reel]
	var is_expanded: bool = reel in _expanded
	# holders.size() is ROWS+1 (one spare for smooth scrolling) — the spare one
	# was being left visible wherever the scroll last placed it, showing as a
	## overlapping "ghost" symbol once the reel stopped (user report: symbols
	## sometimes overlap). Hide anything past ROWS explicitly here.
	for row in holders.size():
		var holder: Node2D = holders[row]
		if row >= ROWS:
			holder.visible = false
			continue
		var sym := "book"
		if is_expanded:
			sym = slot.special_symbol
		elif grid.size() == REELS and grid[reel].size() > row:
			sym = String(grid[reel][row])
		holder.position = Vector2(CELL * 0.5, (float(row) + 0.5) * CELL)
		var pulse := 1.0 + 0.15 * _pulse_at(Vector2i(reel, row))
		holder.scale = Vector2(pulse, pulse)
		_set_holder_symbol(holder, sym)
		holder.visible = true
func _pulse_at(cell: Vector2i) -> float:
	return float(_pulse.get(cell, 0.0))

func _update_pulses(delta: float) -> void:
	if _pulse.is_empty():
		return
	for key in _pulse.keys():
		_pulse[key] = min(float(_pulse[key]) + delta * 3.0, 1.0)

func _update_count_up(delta: float) -> void:
	if _count_current == _count_target:
		return
	_count_tick += delta
	if _count_tick >= 0.02:
		_count_tick = 0.0
		var step: int = max(1, int(abs(_count_target - _count_current) / 30))
		_count_current = mini(_count_current + step, _count_target)
		if _count_current > _count_target:
			_count_current = _count_target
		_count_label.text = str(_count_current)
		_play("coin", randf_range(0.95, 1.1))

func _update_book_flip(delta: float) -> void:
	if not _book_node.visible:
		return
	_book_flip += delta
	var t := clampf(_book_flip / 1.6, 0.0, 1.0)
	if t < 0.65:
		# flip the book
		var angle := t / 0.65
		_book_sprite.rotation = angle * TAU
		_book_sprite.scale = Vector2(abs(cos(angle * PI)), 1.0) * 0.8
		_reveal_label.visible = false
	else:
		_book_sprite.rotation = 0.0
		_book_sprite.scale = Vector2(0.8, 0.8)
		_reveal_label.visible = true
	if t >= 1.0:
		_book_node.visible = false

func _update_marquee() -> void:
	var rainbow := _free_spins_active
	for i in _marquee_lamps.size():
		var lamp: Polygon2D = _marquee_lamps[i]
		if not _active and not rainbow:
			lamp.color = LAPIS_DARK.lerp(GOLD, 0.12)
			continue
		var phase := _marquee_time * 6.0 - float(i) * 0.7
		var on := 0.5 + 0.5 * sin(phase)
		if rainbow:
			lamp.color = Color.from_hsv(fmod(_marquee_time * 0.35 + float(i) / _marquee_lamps.size(), 1.0), 0.75, 0.95)
		else:
			lamp.color = GOLD_LIGHT.lerp(LAPIS_DARK, 1.0 - on * 0.85)
		if _frame_glow > 0.0:
			lamp.color = lamp.color.lerp(Color(1.0, 1.0, 1.0), _frame_glow * 0.8)

func _flash_reel_frame() -> void:
	_frame_glow = 1.0

func _update_energy_lamps() -> void:
	for i in _power_lamps.size():
		var on: bool = i < slot.energy
		_power_lamps[i].color = GOLD_LIGHT if on else Color(0.16, 0.13, 0.08)

func _update_free_label() -> void:
	_free_spins_active = slot.free_spins > 0
	if _free_spins_active:
		_free_label.text = "FREE SPINS %d" % slot.free_spins
		_free_label.visible = true
	else:
		_free_label.visible = false

# --- construction -----------------------------------------------------------

func _build_frame() -> void:
	var outer := Polygon2D.new()
	outer.polygon = PackedVector2Array([
		WINDOW.position + Vector2(-14, -14), WINDOW.position + Vector2(WINDOW.size.x + 14, -14),
		WINDOW.position + Vector2(WINDOW.size.x + 14, WINDOW.size.y + 14),
		WINDOW.position + Vector2(-14, WINDOW.size.y + 14)])
	outer.color = GOLD
	outer.z_index = 1
	add_child(outer)

	var inner := Polygon2D.new()
	inner.polygon = PackedVector2Array([
		WINDOW.position, WINDOW.position + Vector2(WINDOW.size.x, 0),
		WINDOW.position + WINDOW.size, WINDOW.position + Vector2(0, WINDOW.size.y)])
	inner.color = LAPIS
	inner.z_index = 2
	add_child(inner)

	var dark := Polygon2D.new()
	dark.polygon = PackedVector2Array([
		WINDOW.position + Vector2(6, 6), WINDOW.position + Vector2(WINDOW.size.x - 6, 6),
		WINDOW.position + Vector2(WINDOW.size.x - 6, WINDOW.size.y - 6),
		WINDOW.position + Vector2(6, WINDOW.size.y - 6)])
	dark.color = LAPIS_DARK
	dark.z_index = 3
	add_child(dark)

	# reel separators
	for r in range(1, REELS):
		var sep := Line2D.new()
		var x := WINDOW.position.x + r * CELL
		sep.points = PackedVector2Array([Vector2(x, WINDOW.position.y), Vector2(x, WINDOW.position.y + WINDOW.size.y)])
		sep.width = 2.0
		sep.default_color = Color(1, 1, 1, 0.08)
		sep.z_index = 7
		add_child(sep)

func _build_reels() -> void:
	for r in REELS:
		var clip := Control.new()
		clip.position = WINDOW.position + Vector2(r * CELL, 0.0)
		clip.size = Vector2(CELL, WINDOW.size.y)
		clip.clip_contents = true
		clip.z_index = 4
		add_child(clip)
		var holder_col: Array = []
		for row in ROWS + 1:
			var holder := Node2D.new()
			holder.position = Vector2(CELL * 0.5, (float(row) + 0.5) * CELL)
			var spr := Sprite2D.new()
			spr.centered = true
			holder.add_child(spr)
			clip.add_child(holder)
			holder_col.append(holder)
		_reel_textures.append(holder_col)
	# initial demo grid
	var demo: Array = []
	var syms: Array = SlotMachineScript.SYMBOLS
	for r in REELS:
		var col: Array = []
		for row in ROWS:
			col.append(syms[(r + row) % syms.size()])
		demo.append(col)
	_win_result = {"grid": demo}
	_display_grid = demo.duplicate(true)
	_draw_reel_static_all(demo)

func _draw_reel_static_all(grid: Array) -> void:
	for r in REELS:
		_draw_reel_static(r, grid)

func _set_holder_symbol(holder: Node2D, sym: String) -> void:
	if not SlotMachineScript.PAYTABLE.has(sym) and sym != "book":
		return
	var spr := holder.get_child(0) as Sprite2D
	if spr == null:
		return
	var path := "res://assets/slot/%s.png" % sym
	if ResourceLoader.exists(path):
		spr.texture = load(path)
	var tex := spr.texture
	if tex == null:
		return
	var target := CELL - 6.0
	var tw := maxf(1.0, float(tex.get_width()))
	var th := maxf(1.0, float(tex.get_height()))
	var scale := target / maxf(tw, th)
	spr.scale = Vector2(scale, scale)

func _build_book_flip() -> void:
	_book_node = Node2D.new()
	_book_node.visible = false
	_book_node.z_index = 9
	_book_node.position = Vector2(WINDOW.position.x + WINDOW.size.x * 0.5, WINDOW.position.y + WINDOW.size.y * 0.5)
	add_child(_book_node)
	_book_sprite = Sprite2D.new()
	var path := "res://assets/slot/book.png"
	if ResourceLoader.exists(path):
		_book_sprite.texture = load(path)
		_book_sprite.scale = Vector2(0.8, 0.8)
	_book_node.add_child(_book_sprite)
	_reveal_label = _make_label("", 28, GOLD_LIGHT)
	_reveal_label.position = _book_node.position + Vector2(-160, -70)
	_reveal_label.size.x = 320
	_reveal_label.visible = false
	_reveal_label.z_index = 10
	add_child(_reveal_label)

func _build_lamps() -> void:
	# marquee bulbs around the frame
	var perimeter: Array = []
	var step := CELL * 0.5
	var x := WINDOW.position.x - 22.0
	while x <= WINDOW.position.x + WINDOW.size.x + 22.0:
		perimeter.append(Vector2(x, WINDOW.position.y - 22.0))
		perimeter.append(Vector2(x, WINDOW.position.y + WINDOW.size.y + 22.0))
		x += step
	var y := WINDOW.position.y - 22.0 + step
	while y < WINDOW.position.y + WINDOW.size.y + 22.0:
		perimeter.append(Vector2(WINDOW.position.x - 22.0, y))
		perimeter.append(Vector2(WINDOW.position.x + WINDOW.size.x + 22.0, y))
		y += step
	for p in perimeter:
		_marquee_lamps.append(_make_circle(p, 4.5, 5))

	# TEMPLE POWER lamps under the slot
	var lamp_y := WINDOW.position.y + WINDOW.size.y + 30.0
	for i in range(ENERGY_MAX):
		var lx := WINDOW.position.x + 24.0 + i * 34.0
		_power_lamps.append(_make_circle(Vector2(lx, lamp_y), 7.0, 6))

func _make_circle(pos: Vector2, radius: float, z: int) -> Polygon2D:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	var p := Polygon2D.new()
	p.polygon = pts
	p.position = pos
	p.color = GOLD_LIGHT
	p.z_index = z
	add_child(p)
	return p

func _build_labels() -> void:
	_count_label = _make_label("", 30, GOLD_LIGHT)
	_count_label.position = Vector2(WINDOW.position.x, WINDOW.position.y + WINDOW.size.y + 46.0)
	_count_label.size.x = WINDOW.size.x
	add_child(_count_label)

	_free_label = _make_label("FREE SPINS 0", 26, GOLD_LIGHT)
	_free_label.position = Vector2(WINDOW.position.x, WINDOW.position.y - 54.0)
	_free_label.size.x = WINDOW.size.x
	_free_label.visible = false
	add_child(_free_label)

	_idle_label = _make_label("PLUNGE TO SPIN", 26, Color("#c9b78a"))
	_idle_label.position = Vector2(WINDOW.position.x, WINDOW.position.y - 54.0)
	_idle_label.size.x = WINDOW.size.x
	_idle_label.visible = true
	add_child(_idle_label)

	_bonus_label = _make_label("", 30, Color("#ffe066"))
	_bonus_label.position = Vector2(WINDOW.position.x - 40.0, WINDOW.position.y + WINDOW.size.y + 78.0)
	_bonus_label.size.x = WINDOW.size.x + 80.0
	_bonus_label.visible = false
	_bonus_label.z_index = 12
	add_child(_bonus_label)

	_big_label = _make_label("BIG WIN!", 54, Color("#ffe066"))
	_big_label.position = Vector2(WINDOW.position.x, WINDOW.position.y + 40.0)
	_big_label.size.x = WINDOW.size.x
	_big_label.visible = false
	_big_label.z_index = 20
	_big_label.pivot_offset = Vector2(WINDOW.size.x * 0.5, 30.0)
	add_child(_big_label)

func _make_label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 8
	return l

func _build_win_lines() -> void:
	_win_line_layer = Node2D.new()
	_win_line_layer.z_index = 21
	_win_line_layer.visible = false
	add_child(_win_line_layer)

func _build_particles() -> void:
	_coins = CPUParticles2D.new()
	var path := "res://assets/slot/coins.png"
	if ResourceLoader.exists(path):
		_coins.texture = load(path)
	_coins.amount = 40
	_coins.lifetime = 1.4
	_coins.one_shot = false
	_coins.emitting = false
	_coins.explosiveness = 0.9
	_coins.direction = Vector2(0, -1)
	_coins.spread = 60.0
	_coins.gravity = Vector2(0, 700)
	_coins.initial_velocity_min = 250.0
	_coins.initial_velocity_max = 520.0
	_coins.scale_amount_min = 0.12
	_coins.scale_amount_max = 0.22
	_coins.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_coins.emission_rect_extents = Vector2(WINDOW.size.x * 0.4, 10.0)
	_coins.position = Vector2(WINDOW.position.x + WINDOW.size.x * 0.5, WINDOW.position.y + 40.0)
	_coins.z_index = 19
	add_child(_coins)

func _begin_book_flip() -> void:
	_book_flip_symbol = slot.special_symbol
	_book_flip = 0.0
	_book_node.visible = true
	_reveal_label.text = "%s EXPANDS" % _book_flip_symbol.to_upper()
	_reveal_label.visible = false
	_play("book_reveal")

func _play(sound: String, pitch := 1.0) -> void:
	if _sfx:
		_sfx.play(sound, pitch)

func _loop_start(sound: String) -> void:
	if _sfx:
		_sfx.loop_start(sound)

func _loop_stop(sound: String) -> void:
	if _sfx:
		_sfx.loop_stop(sound)
