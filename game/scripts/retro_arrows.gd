extends Node2D
## Small decorative "shoot here" chevron chase near a flipper — pure retro
## pinball flavour (no collision at all), a light chasing down toward the
## flipper to draw the eye, like classic GI arrow inserts on 70s/80s tables.
## User request: something in the freed space after lowering the flippers
## "that feels very [of those] years pinball".

const GOLD := Color("#ffcf5a")
const OFF := Color("#3a2c0c")
const COUNT := 3
const SPACING := 20.0
const SIZE := 12.0
const CYCLE := 1.6

@export var pointing_down := true

var _chevrons: Array = []
var _time := 0.0

func _ready() -> void:
	var dir := 1.0 if pointing_down else -1.0
	for i in COUNT:
		var c := Polygon2D.new()
		c.polygon = _chevron(float(i) * SPACING * dir, dir)
		c.color = OFF
		add_child(c)
		_chevrons.append(c)

func _chevron(y: float, dir: float) -> PackedVector2Array:
	var h := SIZE * 0.5
	return PackedVector2Array([
		Vector2(-h, y - h * dir), Vector2(0.0, y), Vector2(h, y - h * dir),
		Vector2(h, y - h * 0.4 * dir), Vector2(0.0, y + h * 0.6 * dir), Vector2(-h, y - h * 0.4 * dir),
	])

func _process(delta: float) -> void:
	_time += delta
	for i in _chevrons.size():
		var phase := fmod(_time - float(i) * 0.22, CYCLE) / CYCLE
		var lit: float = maxf(0.0, 1.0 - phase * 2.2)
		_chevrons[i].color = OFF.lerp(GOLD, lit)
