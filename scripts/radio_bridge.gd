class_name RadioBridge
extends Node

signal playback_changed(is_playing: bool)
signal playback_error(message: String)
signal track_title_changed(title: String)
signal stream_finished

const CATALOG_PATH := "res://data/stations.json"
const HELPER_PATH := "res://helpers/radio_player.ps1"
const HELPER_PATHS := [
	"res://helpers/radio_player.ps1",
	"res://helpers/radio_metadata.ps1",
	"res://helpers/radio_process_monitor.ps1",
	"res://helpers/radio_volume_monitor.ps1",
]
const PID_FILE_NAME := "watercolor_desk_radio.pid"
const METADATA_FILE_NAME := "watercolor_desk_radio_title.txt"
const VOLUME_FILE_NAME := "watercolor_desk_radio_volume.txt"
const PAUSE_FILE_NAME := "watercolor_desk_radio_pause.txt"
const STREAM_LAUNCH_DELAY := 0.05
const VOLUME_APPLY_DELAY := 0.05
const START_GRACE_MSEC := 10000
const WINDOWS_DEV_FFPLAY_PATH := "I:/FF/bin/ffplay.exe"

@export var ffplay_path := ""

var _allowed_urls: Dictionary = {}
var _current_url := ""
var _volume := 0.72
var _is_playing := false
var _is_paused := false
var _pid_file_path := ""
var _metadata_file_path := ""
var _volume_file_path := ""
var _pause_file_path := ""
var _helper_file_path := ""
var _last_track_title := ""
var _metadata_timer: Timer
var _stream_launch_timer: Timer
var _volume_apply_timer: Timer
var _process_id := 0
var _helper_process_id := 0
var _current_uses_icy_metadata := true
var _buffer_delay_seconds := 0
var _start_grace_until_msec := 0


func _ready() -> void:
	ffplay_path = _resolve_ffplay_path()
	_pid_file_path = ProjectSettings.globalize_path("user://%s" % PID_FILE_NAME)
	_metadata_file_path = ProjectSettings.globalize_path("user://%s" % METADATA_FILE_NAME)
	_volume_file_path = ProjectSettings.globalize_path("user://%s" % VOLUME_FILE_NAME)
	_pause_file_path = ProjectSettings.globalize_path("user://%s" % PAUSE_FILE_NAME)
	var helper_directory := _extract_helper_bundle() if OS.get_name() == "Windows" else ""
	_helper_file_path = helper_directory.path_join(HELPER_PATH.get_file()) \
		if not helper_directory.is_empty() else ""
	_load_allowlist()
	_metadata_timer = Timer.new()
	_metadata_timer.wait_time = 0.75
	_metadata_timer.timeout.connect(_poll_track_title)
	_metadata_timer.timeout.connect(_poll_process_state)
	add_child(_metadata_timer)
	_metadata_timer.start()
	_stream_launch_timer = Timer.new()
	_stream_launch_timer.one_shot = true
	_stream_launch_timer.wait_time = STREAM_LAUNCH_DELAY
	_stream_launch_timer.timeout.connect(_launch_current_stream)
	add_child(_stream_launch_timer)
	_volume_apply_timer = Timer.new()
	_volume_apply_timer.one_shot = true
	_volume_apply_timer.wait_time = VOLUME_APPLY_DELAY
	_volume_apply_timer.timeout.connect(_write_volume_request)
	add_child(_volume_apply_timer)


func start(
		url: String,
		volume_linear: float = 0.72,
		enable_icy_metadata := true,
		buffer_delay_seconds := 0
) -> bool:
	if OS.get_name() not in ["Windows", "macOS"]:
		return _fail("The online radio currently supports Windows and macOS only.")
	if OS.get_name() == "Windows" and _helper_file_path.is_empty():
		return _fail("The radio helper could not be prepared.")
	if ffplay_path.is_empty() or not FileAccess.file_exists(ffplay_path):
		return _fail("The configured ffplay executable is missing: %s" % ffplay_path)
	if not _allowed_urls.has(url):
		return _fail("The requested stream is not in the fixed prototype station list.")

	_volume = clampf(volume_linear, 0.0, 1.0)
	_current_uses_icy_metadata = enable_icy_metadata
	_buffer_delay_seconds = clampi(buffer_delay_seconds, 0, 120)
	_last_track_title = ""
	_current_url = url
	_process_id = 0
	_helper_process_id = 0
	_start_grace_until_msec = 0
	_is_playing = true
	_is_paused = false
	_volume_apply_timer.stop()
	_write_volume_request()
	_write_pause_request(false)
	_stream_launch_timer.start()
	playback_changed.emit(true)
	return true


func stop() -> void:
	_stop_process(true)


func switch_station(url: String, volume_linear: float = -1.0) -> bool:
	var requested_volume := _volume if volume_linear < 0.0 else volume_linear
	return start(url, requested_volume, true)


func play_stream(url: String, station: Dictionary = {}) -> bool:
	var uses_icy_metadata := str(station.get("source", "")) != "audius"
	var buffer_delay_seconds := int(station.get("buffer_delay_seconds", 0))
	return start(url, _volume, uses_icy_metadata, buffer_delay_seconds)


func stop_stream() -> void:
	stop()


func pause_stream(paused: bool) -> void:
	if paused == _is_paused:
		return
	if paused:
		if _is_playing:
			if OS.get_name() == "macOS":
				_stop_macos_process()
			else:
				_write_pause_request(true)
		_is_paused = true
		playback_changed.emit(false)
		return
	if _is_playing and not _current_url.is_empty():
		if OS.get_name() == "macOS":
			_launch_macos_stream()
		else:
			_write_pause_request(false)
		_is_paused = false
		playback_changed.emit(true)


func set_volume(linear: float) -> void:
	var next_volume := clampf(linear, 0.0, 1.0)
	if is_equal_approx(next_volume, _volume):
		return
	_volume = next_volume
	if _is_playing and not _is_paused and not _current_url.is_empty():
		_volume_apply_timer.start()


func is_playing() -> bool:
	return _is_playing and not _is_paused


func _stop_process(clear_current: bool) -> void:
	_stream_launch_timer.stop()
	_volume_apply_timer.stop()
	_write_pause_request(false)
	if OS.get_name() == "macOS":
		_stop_macos_process()
	elif OS.get_name() == "Windows" and not _pid_file_path.is_empty() \
			and not _helper_file_path.is_empty():
		# Wait for cleanup before the Godot process exits. A detached stop helper can
		# otherwise lose a race with a new start and leave ffplay running on its own.
		_run_helper_sync("stop")
	_is_playing = false
	_process_id = 0
	_helper_process_id = 0
	_start_grace_until_msec = 0
	_last_track_title = ""
	if clear_current:
		_current_url = ""
		_is_paused = false
	playback_changed.emit(false)


func _poll_track_title() -> void:
	if not _is_playing or _metadata_file_path.is_empty() or not FileAccess.file_exists(_metadata_file_path):
		return
	var title := FileAccess.get_file_as_string(_metadata_file_path).strip_edges()
	if title.is_empty() or title == _last_track_title:
		return
	_last_track_title = title
	track_title_changed.emit(title)


func _poll_process_state() -> void:
	if not _is_playing or _is_paused or not _stream_launch_timer.is_stopped():
		return
	if OS.get_name() == "macOS":
		if _process_id > 0 and OS.is_process_running(_process_id):
			return
		if _start_grace_until_msec > Time.get_ticks_msec():
			return
		_process_id = 0
		_is_playing = false
		playback_changed.emit(false)
		stream_finished.emit()
		return
	if _helper_process_id > 0:
		if OS.is_process_running(_helper_process_id):
			return
		_helper_process_id = 0
	if _start_grace_until_msec > Time.get_ticks_msec():
		var pending_process_id := _read_process_id()
		if pending_process_id <= 0:
			return
	var reported_process_id := _read_process_id()
	if _process_id <= 0 and reported_process_id > 0:
		_process_id = reported_process_id
		return
	if _process_id > 0 and reported_process_id == _process_id:
		return
	_is_playing = false
	_process_id = 0
	playback_changed.emit(false)
	stream_finished.emit()


func _read_process_id() -> int:
	if not FileAccess.file_exists(_pid_file_path):
		return 0
	return FileAccess.get_file_as_string(_pid_file_path).strip_edges().to_int()


func _launch_current_stream() -> void:
	if not _is_playing or _is_paused or _current_url.is_empty():
		return
	if OS.get_name() == "macOS":
		_launch_macos_stream()
		return
	_helper_process_id = _run_helper_async("start", _current_url, _current_uses_icy_metadata)
	if _helper_process_id <= 0:
		_is_playing = false
		_fail("The radio helper process could not be launched.")
		playback_changed.emit(false)
		return
	_process_id = 0
	_start_grace_until_msec = Time.get_ticks_msec() + START_GRACE_MSEC


func _write_volume_request() -> void:
	if OS.get_name() == "macOS":
		if _process_id > 0 and _is_playing and not _is_paused and not _current_url.is_empty():
			_stop_macos_process()
			_launch_macos_stream()
		return
	if _volume_file_path.is_empty():
		return
	var file := FileAccess.open(_volume_file_path, FileAccess.WRITE)
	if file != null:
		file.store_string(str(_volume))


func _write_pause_request(paused: bool) -> void:
	if _pause_file_path.is_empty():
		return
	var file := FileAccess.open(_pause_file_path, FileAccess.WRITE)
	if file != null:
		file.store_string("1" if paused else "0")


func _launch_macos_stream() -> void:
	if ffplay_path.is_empty() or not FileAccess.file_exists(ffplay_path):
		_fail("The bundled macOS ffplay executable is missing: %s" % ffplay_path)
		return
	var arguments := PackedStringArray([
		"-hide_banner",
		"-loglevel", "error",
		"-nostats",
		"-nodisp",
		"-volume", str(roundi(_volume * 100.0)),
		"-rtbufsize", "33554432",
		"-reconnect", "1",
		"-reconnect_streamed", "1",
		"-reconnect_at_eof", "1",
		"-reconnect_on_network_error", "1",
		"-reconnect_on_http_error", "4xx,5xx",
		"-reconnect_delay_max", "2",
	])
	if _buffer_delay_seconds > 0:
		arguments.append_array(PackedStringArray([
			"-af", "adelay=%d:all=1" % (_buffer_delay_seconds * 1000),
		]))
	arguments.append(_current_url)
	_process_id = OS.create_process(ffplay_path, arguments, false)
	_start_grace_until_msec = Time.get_ticks_msec() + START_GRACE_MSEC
	if _process_id <= 0:
		_is_playing = false
		_fail("The bundled macOS ffplay process could not be launched.")
		playback_changed.emit(false)


func _stop_macos_process() -> void:
	if _process_id > 0 and OS.is_process_running(_process_id):
		OS.kill(_process_id)
	_process_id = 0
	_start_grace_until_msec = 0


func _resolve_ffplay_path() -> String:
	if not ffplay_path.is_empty() and FileAccess.file_exists(ffplay_path):
		return ffplay_path
	var executable_directory := OS.get_executable_path().get_base_dir()
	if OS.get_name() == "Windows":
		var bundled_windows := executable_directory.path_join("ffplay.exe")
		if FileAccess.file_exists(bundled_windows):
			return bundled_windows
		if FileAccess.file_exists(WINDOWS_DEV_FFPLAY_PATH):
			return WINDOWS_DEV_FFPLAY_PATH
	elif OS.get_name() == "macOS":
		var architecture := Engine.get_architecture_name()
		var preferred_name := "ffplay-arm64" if architecture.begins_with("arm") else "ffplay-x86_64"
		var bundled_macos := executable_directory.path_join(preferred_name)
		if FileAccess.file_exists(bundled_macos):
			return bundled_macos
	return ""


func _run_helper_async(action: String, url: String = "", enable_icy_metadata := false) -> int:
	return OS.create_process("powershell.exe", _build_helper_arguments(
		action,
		url,
		enable_icy_metadata
	), false)


func _run_helper_sync(action: String, url: String = "", enable_icy_metadata := false) -> int:
	var output: Array = []
	return OS.execute(
		"powershell.exe",
		_build_helper_arguments(action, url, enable_icy_metadata),
		output,
		true
	)


func _build_helper_arguments(
	action: String,
	url: String = "",
	enable_icy_metadata := false
) -> PackedStringArray:
	var arguments := PackedStringArray([
		"-NoLogo",
		"-NoProfile",
		"-NonInteractive",
		"-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden",
		"-File", _helper_file_path,
		"-Action", action,
		"-FfplayPath", ffplay_path,
		"-PidFile", _pid_file_path,
		"-VolumeFile", _volume_file_path,
		"-PauseFile", _pause_file_path,
		"-OwnerProcessId", str(OS.get_process_id()),
	])
	if action == "start":
		arguments.append_array(PackedStringArray([
			"-Url", url,
			"-Volume", str(roundi(_volume * 100.0)),
			"-BufferDelaySeconds", str(_buffer_delay_seconds),
		]))
		if enable_icy_metadata:
			arguments.append("-EnableIcyMetadata")

	return arguments


func _extract_helper_bundle() -> String:
	var combined_hash := ""
	for source_path: String in HELPER_PATHS:
		if not FileAccess.file_exists(source_path):
			push_warning("Radio helper is missing: %s" % source_path)
			return ""
		combined_hash += FileAccess.get_md5(source_path)
	var runtime_directory := ProjectSettings.globalize_path("user://runtime_helpers")
	var directory_error := DirAccess.make_dir_recursive_absolute(runtime_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_warning("Could not create runtime helper directory: %s" % runtime_directory)
		return ""
	var helper_directory := runtime_directory.path_join(
		"radio-%s" % combined_hash.sha256_text().left(12)
	)
	directory_error = DirAccess.make_dir_recursive_absolute(helper_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_warning("Could not create radio helper directory: %s" % helper_directory)
		return ""
	for source_path: String in HELPER_PATHS:
		var target_path := helper_directory.path_join(source_path.get_file())
		var source_hash := FileAccess.get_md5(source_path)
		if FileAccess.file_exists(target_path) and FileAccess.get_md5(target_path) == source_hash:
			continue
		var target_file := FileAccess.open(target_path, FileAccess.WRITE)
		if target_file == null:
			push_warning("Could not extract radio helper: %s" % target_path)
			return ""
		target_file.store_buffer(FileAccess.get_file_as_bytes(source_path))
		target_file.close()
		if FileAccess.get_md5(target_path) != source_hash:
			push_warning("Extracted radio helper failed verification: %s" % target_path)
			return ""
	return helper_directory


func _load_allowlist() -> void:
	_allowed_urls.clear()
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("Fixed radio catalog is missing: %s" % CATALOG_PATH)
		return

	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Fixed radio catalog is not valid JSON.")
		return
	var stations: Variant = parsed.get("stations", [])
	if not stations is Array:
		return
	for station: Variant in stations:
		if not station is Dictionary or not bool(station.get("enabled", false)):
			continue
		var url := str(station.get("stream_url", "")).strip_edges()
		if not url.is_empty():
			_allowed_urls[url] = true
		var tracks: Variant = station.get("tracks", [])
		if tracks is Array:
			for track: Variant in tracks:
				if track is Dictionary:
					var track_id := str(track.get("id", "")).strip_edges()
					if not track_id.is_empty():
						_allowed_urls[_audius_stream_url(track_id)] = true


func _audius_stream_url(track_id: String) -> String:
	return "https://api.audius.co/v1/tracks/%s/stream?app_name=WatercolorDeskCompanion" % track_id.uri_encode()


func _fail(message: String) -> bool:
	playback_error.emit(message)
	push_warning(message)
	return false


func _exit_tree() -> void:
	_stop_process(true)
