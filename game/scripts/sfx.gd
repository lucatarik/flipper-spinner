extends Node
## Audio autoload. `play` uses a pool of 16 players; `loop_start`/`loop_stop`
## manage a named looping SFX; `music(track)` crossfades the CC0 OGG tracks.
## A drop-in override in res://assets/sfx/override/<name>.ogg|.wav wins over the
## synthesized WAV. Must work under the headless dummy audio driver.

const SettingsScript = preload("res://scripts/settings.gd")

const POOL_SIZE := 16
const SFX_DIR := "res://assets/sfx/"
const OVERRIDE_DIR := "res://assets/sfx/override/"
const MUSIC_DIR := "res://assets/music/"
const MUSIC_DB := -14.0
const FADE_TIME := 0.5

var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}
var _streams: Dictionary = {}
var _music: Array[AudioStreamPlayer] = []
var _music_index := 0
var _current_track := ""
var _audio_enabled := true
var _music_enabled := true

func _ready() -> void:
	# The headless dummy audio driver leaks active Ogg playbacks at exit; skip
	# real playback there so the engine shuts down without "resources in use".
	_audio_enabled = DisplayServer.get_name() != "headless"
	_music_enabled = SettingsScript.get_music_enabled()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.name = "Music%d" % i
		m.bus = "Master"
		add_child(m)
		_music.append(m)

func _exit_tree() -> void:
	for name in _loops.keys():
		loop_stop(String(name))
	for p in _pool:
		p.stop()
		p.stream = null
	for m in _music:
		m.stop()
		m.stream = null
	_streams.clear()

func _get_stream(sfx_name: String) -> AudioStream:
	var s: AudioStream = _streams.get(sfx_name, null)
	if s != null:
		return s
	for ext in [".ogg", ".wav"]:
		var ov: String = OVERRIDE_DIR + sfx_name + ext
		if ResourceLoader.exists(ov):
			s = load(ov)
			break
	if s == null:
		var path := SFX_DIR + sfx_name + ".wav"
		if ResourceLoader.exists(path):
			s = load(path)
	if s != null:
		_streams[sfx_name] = s
	return s

func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[0]

func play(sfx_name: String, pitch := 1.0, db := 0.0) -> void:
	if not _audio_enabled or not _music_enabled:
		return
	var s := _get_stream(sfx_name)
	if s == null:
		push_warning("Sfx: unknown sound '%s'" % sfx_name)
		return
	var p := _free_player()
	p.stream = s
	p.pitch_scale = maxf(0.01, pitch)
	p.volume_db = db
	p.play()

func loop_start(sfx_name: String) -> void:
	if not _audio_enabled or not _music_enabled or _loops.has(sfx_name):
		return
	var s := _get_stream(sfx_name)
	if s == null:
		push_warning("Sfx: unknown loop '%s'" % sfx_name)
		return
	if s is AudioStreamWAV:
		s = (s as AudioStreamWAV).duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2
	elif s is AudioStreamOggVorbis:
		s = (s as AudioStreamOggVorbis).duplicate()
		s.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = s
	add_child(p)
	p.play()
	_loops[sfx_name] = p

func loop_stop(sfx_name: String) -> void:
	var p: AudioStreamPlayer = _loops.get(sfx_name, null)
	if p == null:
		return
	_loops.erase(sfx_name)
	p.stop()
	p.queue_free()

func is_music_enabled() -> bool:
	return _music_enabled

## Mute/unmute ALL audio, music and SFX together (user request — originally
## music-only, D4). Persisted in user://settings.cfg under the same "music"
## key as before, name kept for API/save-file compatibility.
func set_music_enabled(on: bool) -> void:
	if on == _music_enabled:
		return
	_music_enabled = on
	SettingsScript.set_music_enabled(on)
	if not _audio_enabled:
		return
	if not on:
		for p in _music:
			_fade_out(p)
		for p in _pool:
			p.stop()
		for loop_name in _loops.keys().duplicate():
			loop_stop(String(loop_name))
	elif _current_track != "":
		_start_track(_current_track)

func music(track: String) -> void:
	if track == _current_track:
		return
	_current_track = track
	if not _audio_enabled or not _music_enabled:
		return
	_start_track(track)

func _start_track(track: String) -> void:
	if not _audio_enabled:
		return
	var old := _music[_music_index]
	_music_index = (_music_index + 1) % _music.size()
	var new_p := _music[_music_index]
	if track == "":
		_fade_out(old)
		return
	var path := ""
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(MUSIC_DIR + track + ext):
			path = MUSIC_DIR + track + ext
			break
	if path == "":
		push_warning("Sfx: missing music track '%s'" % track)
		_fade_out(old)
		return
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2
	new_p.stream = s
	new_p.volume_db = -80.0
	new_p.play()
	_tween_db(new_p, MUSIC_DB)
	_fade_out(old)

func _fade_out(p: AudioStreamPlayer) -> void:
	if not p.playing:
		return
	_tween_db(p, -80.0)
	var t := create_tween()
	t.tween_interval(FADE_TIME)
	t.tween_callback(p.stop)

func _tween_db(p: AudioStreamPlayer, target: float) -> void:
	var t := create_tween()
	t.tween_property(p, "volume_db", target, FADE_TIME)
