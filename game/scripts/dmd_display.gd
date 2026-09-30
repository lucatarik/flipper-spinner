extends CanvasLayer
## Quest DMD overlay (scenes/dmd_display.tscn): a 128x32 amber dot-matrix
## display floating over the top of the table on a fully transparent
## background. It only appears while there is something to show (a quest
## intro, the live progress screen, the success/fail outro or a one-off
## message) and fades away otherwise. Purely visual: it never blocks input
## or the game (mouse_filter IGNORE, no pausing).
##
## Signal wiring: bind_quests() connects a QuestManager's quest_started /
## quest_progress_updated / quest_completed / quest_failed / quest_aborted /
## dmd_message_requested to the matching DMD sequences.

const DmdCanvas = preload("res://scripts/dmd_canvas.gd")
const DmdAnim = preload("res://scripts/dmd_animation_player.gd")

const DOT := 5.0
const ORIGIN := Vector2(40.0, 196.0)
const RENDER_FPS := 30.0
const FADE_SECONDS := 0.35

@onready var _matrix: ColorRect = $Matrix
@onready var _anim: Node = $DMDAnimationPlayer

var _canvas
var _img: Image
var _tex: ImageTexture
var _quests = null
var _alpha := 0.0
var _render_acc := 0.0

func _ready() -> void:
	_canvas = DmdCanvas.new()
	_anim.canvas = _canvas
	_img = Image.create_from_data(DmdCanvas.W, DmdCanvas.H, false, Image.FORMAT_L8, _canvas.buf)
	_tex = ImageTexture.create_from_image(_img)
	_matrix.position = ORIGIN
	_matrix.size = Vector2(DmdCanvas.W, DmdCanvas.H) * DOT
	_matrix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := _matrix.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("dmd_tex", _tex)
	_set_alpha(0.0)

func bind_quests(qm) -> void:
	_quests = qm
	qm.quest_started.connect(_on_quest_started)
	qm.quest_progress_updated.connect(_on_quest_progress)
	qm.quest_completed.connect(_on_quest_completed)
	qm.quest_failed.connect(_on_quest_failed)
	qm.quest_aborted.connect(clear)
	qm.dmd_message_requested.connect(show_message)

## Generic one-off DMD message. anim_type: "blink", "zoom" or "marquee".
func show_message(text: String, duration: float, anim_type: String) -> void:
	var scene: Dictionary
	match anim_type:
		"zoom":
			scene = DmdAnim.zoom(text, duration)
		"marquee":
			scene = DmdAnim.marquee(text)
		_:
			scene = DmdAnim.blink(text, duration)
	_anim.interrupt(scene)

func clear() -> void:
	_anim.clear()

func is_showing() -> bool:
	return _alpha > 0.0

func _on_quest_started(q: Dictionary) -> void:
	var anims: Array = q.get("animations", ["whip", "idol", "idol"])
	var title := String(q["title"])
	_anim.play_now(DmdAnim.intro(title, String(anims[0])))
	_anim.queue_scene(DmdAnim.marquee(String(q["description"]), title, 100.0))
	_anim.set_idle(DmdAnim.progress(_quests, String(anims[1]) if anims.size() > 1 else ""))

func _on_quest_progress(_current: int, _target: int) -> void:
	_anim.flash()

func _on_quest_completed(q: Dictionary) -> void:
	_anim.set_idle({})
	_anim.play_now(DmdAnim.success(String(q["title"]), int(q["reward_points"])))

func _on_quest_failed(q: Dictionary) -> void:
	_anim.set_idle({})
	_anim.play_now(DmdAnim.fail(String(q["title"])))

func _process(delta: float) -> void:
	_anim.advance(delta)
	var want := 1.0 if _anim.has_content() else 0.0
	_set_alpha(move_toward(_alpha, want, delta / FADE_SECONDS))
	if not _matrix.visible:
		_render_acc = 1.0  # render straight away on the next visible frame
		return
	_render_acc += delta
	if _render_acc < 1.0 / RENDER_FPS:
		return
	_render_acc = 0.0
	_anim.render()
	_img.set_data(DmdCanvas.W, DmdCanvas.H, false, Image.FORMAT_L8, _canvas.buf)
	_tex.update(_img)

func _set_alpha(a: float) -> void:
	_alpha = a
	_matrix.visible = a > 0.0
	var mat := _matrix.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("master_alpha", a)
