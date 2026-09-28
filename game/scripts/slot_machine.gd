class_name SlotMachine
extends RefCounted
## Pure "Book of the Temple" slot logic. 5 reels x 3 rows, 10 fixed paylines,
## book = wild + scatter, free spins with an expanding symbol.
## No nodes: the view/animation layer lives in slot_view.gd.

const REELS := 5
const ROWS := 3
const LINE_COUNT := 10
const CREDITS_PER_POINT := 100

const SYMBOLS: Array[String] = [
	"book", "explorer", "pharaoh", "anubis", "scarab",
	"eye", "ankh", "pyramid", "feather", "emerald",
]

const PAYLINES: Array = [
	[1, 1, 1, 1, 1],
	[0, 0, 0, 0, 0],
	[2, 2, 2, 2, 2],
	[0, 1, 2, 1, 0],
	[2, 1, 0, 1, 2],
	[1, 2, 2, 2, 1],
	[1, 0, 0, 0, 1],
	[2, 2, 1, 0, 0],
	[0, 0, 1, 2, 2],
	[2, 1, 1, 1, 0],
]

## credits for 2/3/4/5 of a kind, left to right.
const PAYTABLE: Dictionary = {
	"explorer": [10, 100, 1000, 5000],
	"pharaoh": [5, 40, 400, 2000],
	"anubis": [5, 40, 400, 2000],
	"scarab": [5, 30, 100, 750],
	"eye": [0, 5, 40, 150],
	"ankh": [0, 5, 40, 150],
	"pyramid": [0, 5, 25, 100],
	"feather": [0, 5, 25, 100],
	"emerald": [0, 5, 25, 100],
}

## scatter payout (credits) by number of books on screen.
const SCATTER_CREDITS: Dictionary = {3: 20, 4: 200, 5: 2000}
const FREE_SPINS_AWARD := 10
const FREE_SPINS_RETRIGGER := 10
## Order the C2 trio bonuses are reported in (matches the spec table).
const BONUS_ORDER: Array[String] = [
	"explorer", "pharaoh", "anubis", "scarab", "eye",
	"ankh", "pyramid", "feather", "emerald",
]

## minimum number of reels containing the special symbol for it to expand.
const EXPAND_MIN: Dictionary = {
	"explorer": 2, "pharaoh": 2, "anubis": 2, "scarab": 2,
	"eye": 3, "ankh": 3, "pyramid": 3, "feather": 3, "emerald": 3,
}

## Per-cell symbol weights (identical for every reel). Each of the 15 cells is an
## independent weighted draw; originally tuned by simulation to the spec target
## math (hit 25-45 %, free spins 1/60-1/150, avg 6-14 credits per spin).
## "book" bumped 3 -> 3.45 (+15%, user request: "aumenta la possibilità di
## bonus di un 15%") — book is the wild/scatter that substitutes on every
## line, so more of it raises the odds of completing a 3+ run (any bonus-
## paying symbol) across the board rather than favouring one symbol over
## another. NOT re-verified against the 20000-spin `test_slot_target_math`
## bounds (no engine here) — run it before trusting this is still in range.
const WEIGHTS: Dictionary = {
	"book": 3.45, "explorer": 3, "pharaoh": 3, "anubis": 3, "scarab": 5,
	"eye": 12, "ankh": 12, "pyramid": 20, "feather": 20, "emerald": 20,
}

## Visual strip only: what slot_view scrolls past while a reel spins.
const REEL_STRIP: Array[String] = [
	"book", "explorer", "pharaoh", "anubis", "scarab",
	"eye", "ankh", "pyramid", "feather", "emerald",
	"book", "explorer", "pharaoh", "anubis", "scarab",
	"eye", "ankh", "pyramid", "feather", "emerald",
	"explorer", "pharaoh", "anubis", "scarab",
	"eye", "ankh", "feather", "emerald",
	"pyramid", "pyramid", "pyramid",
]

var bet: int = 1
var energy: int = 0
var free_spins: int = 0
var special_symbol: String = ""

var rng: RandomNumberGenerator
var _force_grid: Array = []

func _init(rng_arg: RandomNumberGenerator = null) -> void:
	if rng_arg == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	else:
		rng = rng_arg

func spin() -> Array:
	if free_spins > 0:
		free_spins -= 1
	var grid: Array
	if _force_grid.size() == REELS:
		grid = _grid_from_forced()
		_force_grid = []
	else:
		grid = _random_grid()
	return grid

func _random_grid() -> Array:
	var grid: Array = []
	var names: Array = WEIGHTS.keys()
	var weights := PackedFloat32Array(WEIGHTS.values())
	for r in REELS:
		var col: Array = []
		for row in ROWS:
			col.append(String(names[rng.rand_weighted(weights)]))
		grid.append(col)
	return grid

func _grid_from_forced() -> Array:
	var grid: Array = []
	for r in REELS:
		var col: Array = []
		for row in ROWS:
			col.append(String(_force_grid[r][row]))
		grid.append(col)
	return grid

## Deterministic grid for tests/debug. Accepts either grid[reel][row] (5x3) or a
## flat 15-symbol array read reel-major. The next spin() returns exactly this.
func force_grid(grid: Array) -> void:
	if grid.size() == REELS and typeof(grid[0]) == TYPE_ARRAY:
		_force_grid = grid.duplicate(true)
	elif grid.size() == REELS * ROWS:
		var out: Array = []
		for r in REELS:
			out.append([grid[r * ROWS], grid[r * ROWS + 1], grid[r * ROWS + 2]])
		_force_grid = out
	else:
		push_warning("SlotMachine.force_grid: expected 5x3 or 15 symbols")

func evaluate(grid: Array) -> Dictionary:
	var working: Array = []
	for r in REELS:
		working.append((grid[r] as Array).duplicate())
	var books := _count_books(grid)
	var expanded: Array = _expanded_reels(grid)
	for r in expanded:
		working[r] = [special_symbol, special_symbol, special_symbol]

	var lines: Array = []
	var credits := 0
	for i in LINE_COUNT:
		var payline: Array = PAYLINES[i]
		var syms: Array = []
		for r in REELS:
			syms.append(working[r][int(payline[r])])
		var win := _best_line(syms)
		if win.is_empty():
			continue
		credits += int(win["credits"])
		lines.append({
			"line": i,
			"symbol": win["symbol"],
			"count": win["count"],
			"credits": win["credits"],
		})

	if books >= 3:
		credits += int(SCATTER_CREDITS[min(books, 5)])

	var best_counts := {}
	for line in lines:
		var sym: String = line["symbol"]
		var count: int = line["count"]
		if count >= 3:
			best_counts[sym] = max(int(best_counts.get(sym, 0)), count)

	var bonuses := {
		"ball_save": 0.0,
		"light_lock": false,
		"lock_balls": 0,
		"spot_targets": 0,
		"add_multiplier": 0,
		"start_multiball": false,
		"extra_balls": 0,
		"add_balls": 0,
		"mode_time": 0.0,
		"start_mode": false,
		"playfield_x2_seconds": 0.0,
		"bonus_points": 0,
		"names": [],
	}
	var names: Array = []
	for sym in BONUS_ORDER:
		if best_counts.has(sym):
			_apply_bonus(bonuses, names, sym, int(best_counts[sym]))
	bonuses["names"] = names

	var awarded := 0
	if books >= 3:
		awarded = FREE_SPINS_AWARD
		if free_spins > 0:
			free_spins += FREE_SPINS_RETRIGGER

	return {
		"grid": grid.duplicate(true),
		"credits": credits,
		"points": credits * bet * CREDITS_PER_POINT,
		"lines": lines,
		"books": books,
		"free_spins_awarded": awarded,
		"expanded_reels": expanded,
		"bonuses": bonuses,
	}

## C2: one pinball bonus per group of 3+ identical symbols on a payline
## (book substitutes; a line of pure books is an explorer line). `count` is the
## best run length for `sym` in this spin.
func _apply_bonus(bonuses: Dictionary, names: Array, sym: String, count: int) -> void:
	var four := count >= 4
	match sym:
		"explorer":
			if four:
				bonuses["start_multiball"] = true
				names.append("ETERNAL LIFE MULTIBALL")
			else:
				bonuses["extra_balls"] += 1
				names.append("EXTRA BALL")
		"pharaoh":
			bonuses["ball_save"] = maxf(float(bonuses["ball_save"]), 20.0 if four else 10.0)
			names.append("PHARAOH'S BLESSING")
		"anubis":
			if four:
				bonuses["lock_balls"] += 1
				names.append("BALL LOCKED")
			else:
				bonuses["light_lock"] = true
				names.append("LOCK LIT")
		"scarab":
			bonuses["spot_targets"] += 2 if four else 1
			names.append("SPOT 2 TARGETS" if four else "SPOT TARGET")
		"eye":
			bonuses["add_multiplier"] += 2 if four else 1
			names.append("MULTIPLIER +2" if four else "MULTIPLIER +1")
		"ankh":
			bonuses["add_balls"] += 2 if four else 1
			names.append("ADD 2 BALLS" if four else "ADD-A-BALL")
		"pyramid":
			bonuses["mode_time"] += 10.0
			bonuses["start_mode"] = true
			if four:
				bonuses["bonus_points"] += 25000
				names.append("MODE +10s +25000")
			else:
				names.append("MODE +10s")
		"feather":
			bonuses["playfield_x2_seconds"] += 40.0 if four else 20.0
			names.append("PLAYFIELD x2 40s" if four else "PLAYFIELD x2")
		"emerald":
			var base := 100000 if four else 25000
			bonuses["bonus_points"] += base * bet
			names.append(str(base * bet))

## Applies a free-spin trigger. Called by the view/table after evaluate().
func grant_free_spins(count: int) -> void:
	free_spins += count
	special_symbol = _pick_special()

func _pick_special() -> String:
	var options: Array[String] = []
	for s in SYMBOLS:
		if s != "book":
			options.append(s)
	return options[rng.randi_range(0, options.size() - 1)]

func add_energy(n: int = 1) -> void:
	energy += n
	while energy >= 8:
		energy -= 8
		if bet < 5:
			bet += 1

func reset_bet() -> void:
	bet = 1
	energy = 0

func _count_books(grid: Array) -> int:
	var n := 0
	for r in REELS:
		for c in ROWS:
			if String(grid[r][c]) == "book":
				n += 1
	return n

func _expanded_reels(grid: Array) -> Array:
	var out: Array = []
	if special_symbol == "" or free_spins <= 0:
		return out
	var count := 0
	for r in REELS:
		for c in ROWS:
			if String(grid[r][c]) == special_symbol:
				count += 1
				break
	var need := int(EXPAND_MIN.get(special_symbol, 3))
	if count < need:
		return out
	for r in REELS:
		if special_symbol in grid[r]:
			out.append(r)
	return out

## Best paying run on a 5-symbol line, book substituting any symbol.
func _best_line(syms: Array) -> Dictionary:
	var best: Dictionary = {}
	for sym in SYMBOLS:
		if sym == "book":
			continue
		var k := 0
		while k < syms.size() and (syms[k] == sym or syms[k] == "book"):
			k += 1
		if k < 2:
			continue
		var credits := int((PAYTABLE[sym] as Array)[k - 2])
		if credits > int(best.get("credits", 0)):
			best = {"symbol": sym, "count": k, "credits": credits}
	return best
