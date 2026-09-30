extends RefCounted
## 128x32 dot-matrix frame buffer (one brightness byte per dot, 0..255) plus a
## classic 5x7 bitmap font and a few drawing primitives. Everything the DMD
## shows — text, marquees, zooms, the little pixel-art animations — is drawn
## into this at native resolution, so it always snaps to real "LED" dots;
## dmd.gdshader turns it into round amber dots with glow on screen.

const W := 128
const H := 32
const FULL := 255
const MID := 140
const DIM := 60
const GLYPH_W := 5
const GLYPH_H := 7
const ADVANCE := 6

## 5x7 glyphs, one int per row, bit 4 = leftmost column (HD44780-style).
const FONT := {
	"A": [0x0E, 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11],
	"B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
	"C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
	"D": [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],
	"E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
	"F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
	"G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
	"H": [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
	"I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"J": [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
	"K": [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
	"L": [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
	"M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
	"N": [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
	"O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
	"P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
	"Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
	"R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
	"S": [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
	"T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
	"U": [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
	"V": [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
	"W": [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A],
	"X": [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
	"Y": [0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04],
	"Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
	"0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
	"1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"2": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
	"3": [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
	"4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
	"5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
	"6": [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
	"7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
	"8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
	"9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
	" ": [0, 0, 0, 0, 0, 0, 0],
	"!": [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04],
	"?": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04],
	".": [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
	",": [0x00, 0x00, 0x00, 0x00, 0x0C, 0x04, 0x08],
	":": [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
	"-": [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
	"+": [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],
	"/": [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x00],
	"'": [0x0C, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00],
	"%": [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03],
}

var buf := PackedByteArray()

func _init() -> void:
	buf.resize(W * H)
	clear()

func clear() -> void:
	buf.fill(0)

func px(x: int, y: int, level: int = FULL) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	var i := y * W + x
	if level > buf[i]:
		buf[i] = level

func rect(x: int, y: int, w: int, h: int, level: int = FULL, filled := true) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if filled or yy == y or yy == y + h - 1 or xx == x or xx == x + w - 1:
				px(xx, yy, level)

func line(x0: int, y0: int, x1: int, y1: int, level: int = FULL) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var guard := 0
	while guard < 512:
		guard += 1
		px(x0, y0, level)
		if x0 == x1 and y0 == y1:
			return
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

func circle(cx: int, cy: int, r: int, level: int = FULL, filled := true) -> void:
	for yy in range(-r, r + 1):
		for xx in range(-r, r + 1):
			var d := xx * xx + yy * yy
			if d <= r * r and (filled or d >= (r - 1) * (r - 1)):
				px(cx + xx, cy + yy, level)

## Pixel art from strings: "#" = FULL, "+" = MID, "." = DIM, anything else off.
func sprite(rows: Array, x: int, y: int, flip := false) -> void:
	for ry in rows.size():
		var row: String = rows[ry]
		for rx in row.length():
			var c := row[row.length() - 1 - rx] if flip else row[rx]
			if c == "#":
				px(x + rx, y + ry, FULL)
			elif c == "+":
				px(x + rx, y + ry, MID)
			elif c == ".":
				px(x + rx, y + ry, DIM)

static func text_width(s: String, scale := 1.0) -> int:
	if s.is_empty():
		return 0
	return int(round((s.length() * ADVANCE - 1) * scale))

func _glyph(c: String) -> Array:
	return FONT.get(c.to_upper(), FONT["?"])

## 1:1 text, top-left at (x, y). `clip_x` > 0 hides columns at/after it
## (used by the whip reveal).
func text(s: String, x: int, y: int, level: int = FULL, clip_x := -1) -> void:
	var cx := x
	for ch in s:
		if cx > W:
			return
		if cx + GLYPH_W >= 0:
			var g: Array = _glyph(ch)
			for row in GLYPH_H:
				var bits: int = g[row]
				for col in GLYPH_W:
					if bits & (0x10 >> col):
						var xx := cx + col
						if clip_x < 0 or xx < clip_x:
							px(xx, y + row, level)
		cx += ADVANCE

func text_centered(s: String, y: int, level: int = FULL) -> void:
	text(s, (W - text_width(s)) / 2, y, level)

## Any (fractional) scale, centred on (cx, cy): nearest-neighbour inverse
## mapping, so a zoom tween from 0.5x to 3x stays crisp on the dot grid.
func text_scaled(s: String, cx: float, cy: float, scale: float, level: int = FULL, clip_x := -1) -> void:
	if scale <= 0.05 or s.is_empty():
		return
	var tw := float(s.length() * ADVANCE - 1) * scale
	var th := float(GLYPH_H) * scale
	var x0 := cx - tw * 0.5
	var y0 := cy - th * 0.5
	var xa := maxi(0, int(floor(x0)))
	var xb := mini(W - 1, int(ceil(x0 + tw)))
	var ya := maxi(0, int(floor(y0)))
	var yb := mini(H - 1, int(ceil(y0 + th)))
	for yy in range(ya, yb + 1):
		var gy := int(floor((float(yy) + 0.5 - y0) / scale))
		if gy < 0 or gy >= GLYPH_H:
			continue
		for xx in range(xa, xb + 1):
			if clip_x >= 0 and xx >= clip_x:
				break
			var gx := int(floor((float(xx) + 0.5 - x0) / scale))
			if gx < 0:
				continue
			var ci := gx / ADVANCE
			var col := gx % ADVANCE
			if ci >= s.length() or col >= GLYPH_W:
				continue
			var bits: int = _glyph(s[ci])[gy]
			if bits & (0x10 >> col):
				px(xx, yy, level)

## Largest whole-number scale (1..max_scale) at which `s` fits the width —
## whole numbers keep every glyph pixel the same size on the dot grid.
static func fit_scale(s: String, max_scale := 3, margin := 2) -> int:
	var w1 := text_width(s)
	var sc := max_scale
	while sc > 1 and w1 * sc > W - margin * 2:
		sc -= 1
	return sc

## Knock out a pseudo-random `amount` (0..1) of the lit dots — a stable
## per-dot hash, so the dissolve eats away steadily instead of flickering.
func dissolve(amount: float) -> void:
	if amount <= 0.0:
		return
	for i in buf.size():
		if buf[i] == 0:
			continue
		var h := float((i * 7919 + 104729) % 1009) / 1009.0
		if h < amount:
			buf[i] = 0
