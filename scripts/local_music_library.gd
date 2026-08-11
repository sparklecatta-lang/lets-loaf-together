class_name LocalMusicLibrary
extends RefCounted

const SAVE_PATH := "user://local_music_playlist.json"
const SUPPORTED_EXTENSIONS := ["mp3", "ogg", "wav"]

var tracks: Array[Dictionary] = []


func load_from_disk() -> Array[Dictionary]:
	tracks.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return tracks.duplicate(true)

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("无法读取本地音乐列表：%s" % FileAccess.get_open_error())
		return tracks.duplicate(true)

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("本地音乐列表格式无效，已忽略。")
		return tracks.duplicate(true)

	var saved_tracks: Variant = parsed.get("tracks", [])
	if not saved_tracks is Array:
		return tracks.duplicate(true)

	for item: Variant in saved_tracks:
		if not item is Dictionary:
			continue
		var path := str(item.get("path", ""))
		if is_supported(path):
			tracks.append(_make_track(path))

	return tracks.duplicate(true)


func add_paths(paths: PackedStringArray) -> Array[Dictionary]:
	var known_paths := {}
	for track in tracks:
		known_paths[str(track.get("path", "")).to_lower()] = true

	var added: Array[Dictionary] = []
	for raw_path in paths:
		var path := str(raw_path).strip_edges()
		var key := path.to_lower()
		if path.is_empty() or known_paths.has(key) or not is_supported(path):
			continue
		var track := _make_track(path)
		tracks.append(track)
		added.append(track.duplicate(true))
		known_paths[key] = true

	if not added.is_empty():
		save_to_disk()
	return added


func remove_at(index: int) -> bool:
	if index < 0 or index >= tracks.size():
		return false
	tracks.remove_at(index)
	save_to_disk()
	return true


func save_to_disk() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("无法保存本地音乐列表：%s" % FileAccess.get_open_error())
		return false

	var stored_tracks: Array[Dictionary] = []
	for track in tracks:
		stored_tracks.append({"path": str(track.get("path", ""))})
	file.store_string(JSON.stringify({"version": 1, "tracks": stored_tracks}, "\t"))
	return true


func is_supported(path: String) -> bool:
	return path.get_extension().to_lower() in SUPPORTED_EXTENSIONS


func _make_track(path: String) -> Dictionary:
	return {
		"kind": "local",
		"path": path,
		"title": path.get_file().get_basename(),
		"filename": path.get_file(),
		"available": FileAccess.file_exists(path),
	}
