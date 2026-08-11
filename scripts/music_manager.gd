class_name MusicManager
extends Node

signal library_changed
signal current_item_changed(item: Dictionary)
signal playback_state_changed(is_playing: bool)
signal playback_error(message: String)
signal volume_changed(value: float)

const STATIONS_PATH := "res://data/stations.json"
const SETTINGS_PATH := "user://music_settings.cfg"
const DEFAULT_VOLUME := 0.18
const SETTINGS_SAVE_DELAY := 0.35
const AUDIUS_STREAM_TEMPLATE := "https://api.audius.co/v1/tracks/%s/stream?app_name=WatercolorDeskCompanion"

var stations: Array[Dictionary] = []
var current_kind := ""
var current_index := -1
var volume := DEFAULT_VOLUME

var _radio_helper: Object = null
var _radio_is_playing := false
var _current_station_title := ""
var _current_theme_track_index := -1
var _settings_save_timer: Timer
var _play_history: Array[int] = []
var _history_cursor := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if "--qa-audius" in OS.get_cmdline_user_args():
		_rng.seed = 20260808
	_settings_save_timer = Timer.new()
	_settings_save_timer.one_shot = true
	_settings_save_timer.wait_time = SETTINGS_SAVE_DELAY
	_settings_save_timer.timeout.connect(_save_settings)
	add_child(_settings_save_timer)
	stations = _load_stations()
	_load_settings()
	set_volume(volume, false)
	library_changed.emit()


func set_radio_helper(helper: Object) -> void:
	_radio_helper = helper
	if _radio_helper != null and _radio_helper.has_method("set_volume"):
		_radio_helper.call("set_volume", volume)
	if _radio_helper != null and _radio_helper.has_signal("track_title_changed"):
		var title_callback := Callable(self, "_on_radio_track_title_changed")
		if not _radio_helper.is_connected("track_title_changed", title_callback):
			_radio_helper.connect("track_title_changed", title_callback)
	if _radio_helper != null and _radio_helper.has_signal("stream_finished"):
		var finished_callback := Callable(self, "_on_radio_stream_finished")
		if not _radio_helper.is_connected("stream_finished", finished_callback):
			_radio_helper.connect("stream_finished", finished_callback)


func play_station(index: int) -> bool:
	if index < 0 or index >= stations.size():
		return _fail("这个歌单不存在。")
	var station := stations[index]
	if not bool(station.get("enabled", false)):
		return _fail("“%s”暂时不可用。" % station.get("title", "歌单"))
	var tracks: Variant = station.get("tracks", [])
	if tracks is Array and not tracks.is_empty():
		_play_history.clear()
		_history_cursor = -1
		_current_theme_track_index = -1
		return _play_random_track()
	if not str(station.get("stream_url", "")).strip_edges().is_empty():
		_play_history.clear()
		_history_cursor = -1
		_current_theme_track_index = -1
		return _play_live_station(index)
	return _fail("“%s”中没有可播放的曲目。" % station.get("title", "歌单"))


func toggle_pause() -> void:
	if current_kind != "station" or _radio_helper == null or not _radio_helper.has_method("pause_stream"):
		return
	_radio_is_playing = not _radio_is_playing
	_radio_helper.call("pause_stream", not _radio_is_playing)
	playback_state_changed.emit(_radio_is_playing)


func play_previous() -> bool:
	if current_index >= 0 and current_index < stations.size() \
			and not str(stations[current_index].get("stream_url", "")).strip_edges().is_empty():
		return false
	if _history_cursor <= 0:
		return false
	var target_cursor := _history_cursor - 1
	var target_track_index := _play_history[target_cursor]
	if not _play_audius_theme_track(0, target_track_index, false):
		return false
	_history_cursor = target_cursor
	return true


func play_next() -> bool:
	if current_index >= 0 and current_index < stations.size() \
			and not str(stations[current_index].get("stream_url", "")).strip_edges().is_empty():
		return _play_live_station(current_index)
	return _play_random_track()


func stop() -> void:
	_stop_radio()
	current_kind = ""
	current_index = -1
	_current_theme_track_index = -1
	_play_history.clear()
	_history_cursor = -1
	playback_state_changed.emit(false)


func set_volume(value: float, persist := true) -> void:
	volume = clampf(value, 0.0, 1.0)
	if _radio_helper != null and _radio_helper.has_method("set_volume"):
		_radio_helper.call("set_volume", volume)
	if persist:
		_settings_save_timer.start()
	volume_changed.emit(volume)


func is_playing() -> bool:
	return current_kind == "station" and _radio_is_playing


func _play_random_track() -> bool:
	if stations.is_empty():
		return _fail("当前没有可用歌单。")
	var tracks: Array = stations[0].get("tracks", []) as Array
	if tracks.is_empty():
		return _fail("当前没有可用的 Chillhop 曲目。")
	var candidates: Array[int] = []
	for track_index in tracks.size():
		if track_index != _current_theme_track_index or tracks.size() == 1:
			candidates.append(track_index)
	var next_index := candidates[_rng.randi_range(0, candidates.size() - 1)]
	return _play_audius_theme_track(0, next_index)


func _play_live_station(station_index: int) -> bool:
	if _radio_helper == null or not _radio_helper.has_method("play_stream"):
		return _fail("在线电台播放器没有启动。")
	if station_index < 0 or station_index >= stations.size():
		return _fail("这个电台不存在。")
	var station := stations[station_index]
	var stream_url := str(station.get("stream_url", "")).strip_edges()
	if stream_url.is_empty():
		return _fail("电台缺少直播流地址。")
	var accepted: Variant = _radio_helper.call("play_stream", stream_url, station)
	if accepted != true:
		return _fail("无法连接：%s" % station.get("title", "在线电台"))

	_radio_is_playing = true
	_current_station_title = str(station.get("title", "在线电台"))
	current_kind = "station"
	current_index = station_index
	var current_item := station.duplicate(true)
	current_item["kind"] = "station"
	current_item["station_title"] = _current_station_title
	current_item["display_title"] = str(station.get("description", _current_station_title))
	current_item_changed.emit(current_item)
	playback_state_changed.emit(true)
	return true


func _play_audius_theme_track(theme_index: int, track_index: int, record_history := true) -> bool:
	if _radio_helper == null or not _radio_helper.has_method("play_stream"):
		return _fail("在线音乐播放器没有启动。")
	var theme := stations[theme_index]
	var tracks: Array = theme.get("tracks", []) as Array
	if track_index < 0 or track_index >= tracks.size():
		return _fail("这个歌单中没有可播放的曲目。")
	var track: Dictionary = tracks[track_index]
	var track_id := str(track.get("id", "")).strip_edges()
	if track_id.is_empty():
		return _fail("在线曲目缺少 Track ID。")

	var stream_url := AUDIUS_STREAM_TEMPLATE % track_id.uri_encode()
	var playback_context := theme.duplicate(true)
	playback_context["source"] = "audius"
	var accepted: Variant = _radio_helper.call("play_stream", stream_url, playback_context)
	if accepted != true:
		return _fail("无法播放：%s" % track.get("title", "未命名曲目"))

	_radio_is_playing = true
	_current_station_title = str(theme.get("title", "Chillhop"))
	_current_theme_track_index = track_index
	if record_history:
		if _history_cursor < _play_history.size() - 1:
			_play_history.resize(_history_cursor + 1)
		_play_history.append(track_index)
		_history_cursor = _play_history.size() - 1
	current_kind = "station"
	current_index = theme_index
	var current_item := track.duplicate(true)
	current_item["kind"] = "station"
	current_item["source"] = "audius"
	current_item["station_title"] = _current_station_title
	current_item["display_title"] = "%s — %s" % [
		track.get("title", "未命名曲目"),
		track.get("artist", "未知艺术家"),
	]
	current_item["license_name"] = "Audius Open Music License"
	current_item["license_url"] = "https://audius.org/open-music-license.pdf"
	current_item_changed.emit(current_item)
	playback_state_changed.emit(true)
	return true


func _load_stations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(STATIONS_PATH):
		push_warning("没有找到在线歌单：%s" % STATIONS_PATH)
		return result
	var file := FileAccess.open(STATIONS_PATH, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("在线歌单不是有效 JSON。")
		return result
	var raw_stations: Variant = parsed.get("stations", [])
	if not raw_stations is Array:
		return result
	var chillhop_tracks: Array[Dictionary] = []
	var seen_track_ids: Dictionary = {}
	for item: Variant in raw_stations:
		if not item is Dictionary or not bool(item.get("enabled", false)):
			continue
		if not str(item.get("stream_url", "")).strip_edges().is_empty():
			result.append(item.duplicate(true))
			continue
		var tracks: Variant = item.get("tracks", [])
		if not tracks is Array:
			continue
		for track: Variant in tracks:
			if not track is Dictionary:
				continue
			var track_id := str(track.get("id", "")).strip_edges()
			if track_id.is_empty() or seen_track_ids.has(track_id):
				continue
			seen_track_ids[track_id] = true
			chillhop_tracks.append(track.duplicate(true))
	if not chillhop_tracks.is_empty():
		result.append({
			"id": "chillhop",
			"title": "Chillhop",
			"description": "随机播放的 Chillhop 曲目池",
			"source": "audius",
			"enabled": true,
			"release_enabled": true,
			"tracks": chillhop_tracks,
		})
	return result


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		volume = clampf(float(config.get_value("music", "volume", DEFAULT_VOLUME)), 0.0, 1.0)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("music", "volume", volume)
	config.save(SETTINGS_PATH)


func _stop_radio() -> void:
	if _radio_helper != null and _radio_helper.has_method("stop_stream"):
		_radio_helper.call("stop_stream")
	_radio_is_playing = false
	_current_station_title = ""
	_current_theme_track_index = -1


func _fail(message: String) -> bool:
	playback_error.emit(message)
	playback_state_changed.emit(false)
	return false


func _on_radio_track_title_changed(title: String) -> void:
	if current_kind != "station" or current_index < 0 or title.strip_edges().is_empty():
		return
	var current_item := stations[current_index].duplicate(true)
	var clean_title := title.strip_edges()
	var separator_index := clean_title.find(" - ")
	if separator_index > 0:
		current_item["artist"] = clean_title.left(separator_index).strip_edges()
		current_item["title"] = clean_title.substr(separator_index + 3).strip_edges()
	else:
		current_item["title"] = clean_title
	current_item["station_title"] = _current_station_title
	current_item["display_title"] = "%s — %s" % [
		current_item.get("title", clean_title),
		current_item.get("artist", current_item.get("provider", "")),
	]
	current_item["live_metadata"] = true
	current_item_changed.emit(current_item)


func _on_radio_stream_finished() -> void:
	_radio_is_playing = false
	if current_kind == "station" and current_index >= 0:
		if not str(stations[current_index].get("stream_url", "")).strip_edges().is_empty():
			call_deferred("_play_live_station", current_index)
			return
		var tracks: Variant = stations[current_index].get("tracks", [])
		if tracks is Array and not tracks.is_empty():
			call_deferred("play_next")
			return
	playback_state_changed.emit(false)
func _exit_tree() -> void:
	if _settings_save_timer != null and not _settings_save_timer.is_stopped():
		_save_settings()
