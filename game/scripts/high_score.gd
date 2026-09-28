class_name HighScore
## High-score persistence helper. Missing or corrupt file -> 0, never crashes.

const DEFAULT_PATH := "user://highscore.save"

static func load_score(path := DEFAULT_PATH) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var txt := f.get_as_text().strip_edges()
	if txt.is_valid_int():
		return int(txt)
	return 0

static func save_score(value: int, path := DEFAULT_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(str(value))
