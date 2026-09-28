class_name Settings
## Tiny persisted settings helper (user://settings.cfg, [audio] music=true/false).
## Missing or corrupt file -> the supplied default, never crashes.

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "audio"
const KEY_MUSIC := "music"

static func get_music_enabled(path := DEFAULT_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return true
	return bool(cfg.get_value(SECTION, KEY_MUSIC, true))

static func set_music_enabled(on: bool, path := DEFAULT_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # ignore a missing/corrupt file; we overwrite it below
	cfg.set_value(SECTION, KEY_MUSIC, on)
	cfg.save(path)
