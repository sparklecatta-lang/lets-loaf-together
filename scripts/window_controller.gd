class_name WindowController
extends Node

signal always_on_top_changed(enabled: bool)

const SETTINGS_PATH := "user://window_settings.cfg"
const WINDOWS_BORDER_HELPER_PATH := "res://helpers/window_border_helper.exe"
const MIN_WINDOW_SIZE := Vector2i(445, 334)
const MAX_WINDOW_SIZE := Vector2i(1779, 1334)

var always_on_top_enabled := true
var _dragging := false
var _drag_mouse_offset := Vector2i.ZERO


func _ready() -> void:
	DisplayServer.window_set_min_size(MIN_WINDOW_SIZE)
	DisplayServer.window_set_max_size(MAX_WINDOW_SIZE)
	_load_window_geometry()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, always_on_top_enabled)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	get_tree().root.set_transparent_background(true)
	_disable_windows_dwm_border.call_deferred()
	_constrain_current_window.call_deferred()


func _process(_delta: float) -> void:
	if _dragging:
		if (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) == 0:
			_dragging = false
			_save_window_geometry()
			return
		var desired_position := DisplayServer.mouse_get_position() - _drag_mouse_offset
		set_window_position_constrained(desired_position)
		return
	_constrain_current_window()


func begin_window_drag() -> void:
	_dragging = true
	_drag_mouse_offset = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()


func begin_window_resize(edge: int) -> void:
	_dragging = false
	DisplayServer.window_start_resize(edge)


func set_window_position_constrained(position: Vector2i) -> void:
	var constrained := _constrain_position_to_screens(
		position,
		DisplayServer.window_get_size(),
		_get_screen_rects()
	)
	if constrained != DisplayServer.window_get_position():
		DisplayServer.window_set_position(constrained)


func toggle_always_on_top() -> bool:
	always_on_top_enabled = not always_on_top_enabled
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, always_on_top_enabled)
	_save_window_geometry()
	always_on_top_changed.emit(always_on_top_enabled)
	return always_on_top_enabled


func minimize_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func close_window() -> void:
	_save_window_geometry()
	get_tree().quit()


func _disable_windows_dwm_border() -> void:
	if OS.get_name() != "Windows":
		return
	var helper_path := _extract_windows_border_helper()
	if helper_path.is_empty():
		push_warning("Windows DWM border helper could not be prepared.")
		return
	var window_handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	if window_handle == 0:
		return
	var helper_pid := OS.create_process(helper_path, [str(window_handle)], false)
	if helper_pid <= 0:
		push_warning("Could not start the Windows DWM border helper.")


func _extract_windows_border_helper() -> String:
	if not FileAccess.file_exists(WINDOWS_BORDER_HELPER_PATH):
		return ""
	var source_hash := FileAccess.get_md5(WINDOWS_BORDER_HELPER_PATH)
	var runtime_directory := ProjectSettings.globalize_path("user://runtime_helpers")
	var directory_error := DirAccess.make_dir_recursive_absolute(runtime_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return ""
	var helper_path := runtime_directory.path_join(
		"window_border_helper-%s.exe" % source_hash.left(12)
	)
	if FileAccess.file_exists(helper_path) and FileAccess.get_md5(helper_path) == source_hash:
		return helper_path
	var target_file := FileAccess.open(helper_path, FileAccess.WRITE)
	if target_file == null:
		return ""
	target_file.store_buffer(FileAccess.get_file_as_bytes(WINDOWS_BORDER_HELPER_PATH))
	target_file.close()
	return helper_path if FileAccess.get_md5(helper_path) == source_hash else ""


func _load_window_geometry() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	always_on_top_enabled = bool(config.get_value("window", "always_on_top", true))
	var saved_size: Vector2i = config.get_value("window", "size", Vector2i(-1, -1))
	if saved_size.x > 0 and saved_size.y > 0:
		DisplayServer.window_set_size(saved_size)
	if config.has_section_key("window", "position"):
		var saved_position: Vector2i = config.get_value("window", "position", Vector2i.ZERO)
		DisplayServer.window_set_position(_constrain_position_to_screens(
			saved_position,
			DisplayServer.window_get_size(),
			_get_screen_rects()
		))


func _save_window_geometry() -> void:
	var config := ConfigFile.new()
	config.set_value("window", "always_on_top", always_on_top_enabled)
	config.set_value("window", "position", DisplayServer.window_get_position())
	config.set_value("window", "size", DisplayServer.window_get_size())
	config.save(SETTINGS_PATH)


func _constrain_current_window() -> void:
	set_window_position_constrained(DisplayServer.window_get_position())


func _get_screen_rects() -> Array[Rect2i]:
	var screens: Array[Rect2i] = []
	for screen_index in DisplayServer.get_screen_count():
		screens.append(Rect2i(
			DisplayServer.screen_get_position(screen_index),
			DisplayServer.screen_get_size(screen_index)
		))
	return screens


func _constrain_position_to_screens(
	desired_position: Vector2i,
	window_size: Vector2i,
	screens: Array[Rect2i]
) -> Vector2i:
	if screens.is_empty() or window_size.x <= 0 or window_size.y <= 0:
		return desired_position
	var coverage_screens := _with_internal_screen_bridges(screens)
	var desired_rect := Rect2i(desired_position, window_size)
	if _rect_is_covered_by_screens(desired_rect, coverage_screens):
		return desired_position

	var x_candidates: Array[int] = [desired_position.x]
	var y_candidates: Array[int] = [desired_position.y]
	for screen in coverage_screens:
		var maximum_x := screen.end.x - window_size.x
		var maximum_y := screen.end.y - window_size.y
		x_candidates.append(screen.position.x)
		x_candidates.append(maximum_x)
		y_candidates.append(screen.position.y)
		y_candidates.append(maximum_y)
		if maximum_x >= screen.position.x:
			x_candidates.append(clampi(desired_position.x, screen.position.x, maximum_x))
		if maximum_y >= screen.position.y:
			y_candidates.append(clampi(desired_position.y, screen.position.y, maximum_y))

	var best_position := desired_position
	var best_distance_squared := 9223372036854775807
	var found_valid_position := false
	for candidate_x in x_candidates:
		for candidate_y in y_candidates:
			var candidate := Vector2i(candidate_x, candidate_y)
			if not _rect_is_covered_by_screens(Rect2i(candidate, window_size), coverage_screens):
				continue
			var offset := candidate - desired_position
			var distance_squared := offset.x * offset.x + offset.y * offset.y
			if not found_valid_position or distance_squared < best_distance_squared:
				found_valid_position = true
				best_distance_squared = distance_squared
				best_position = candidate
	if found_valid_position:
		return best_position
	return screens[0].position


func _with_internal_screen_bridges(screens: Array[Rect2i]) -> Array[Rect2i]:
	var coverage := screens.duplicate()
	for first_index in screens.size():
		for second_index in range(first_index + 1, screens.size()):
			var first := screens[first_index]
			var second := screens[second_index]
			var vertical_start := maxi(first.position.y, second.position.y)
			var vertical_end := mini(first.end.y, second.end.y)
			if vertical_end > vertical_start:
				var left := first if first.position.x <= second.position.x else second
				var right := second if left == first else first
				if left.end.x < right.position.x:
					coverage.append(Rect2i(
						Vector2i(left.end.x, vertical_start),
						Vector2i(right.position.x - left.end.x, vertical_end - vertical_start)
					))
			var horizontal_start := maxi(first.position.x, second.position.x)
			var horizontal_end := mini(first.end.x, second.end.x)
			if horizontal_end > horizontal_start:
				var upper := first if first.position.y <= second.position.y else second
				var lower := second if upper == first else first
				if upper.end.y < lower.position.y:
					coverage.append(Rect2i(
						Vector2i(horizontal_start, upper.end.y),
						Vector2i(horizontal_end - horizontal_start, lower.position.y - upper.end.y)
					))
	return coverage


func _rect_is_covered_by_screens(rect: Rect2i, screens: Array[Rect2i]) -> bool:
	var uncovered: Array[Rect2i] = [rect]
	for screen in screens:
		var next_uncovered: Array[Rect2i] = []
		for part in uncovered:
			var overlap := part.intersection(screen)
			if overlap.size.x <= 0 or overlap.size.y <= 0:
				next_uncovered.append(part)
				continue
			if overlap.position.y > part.position.y:
				next_uncovered.append(Rect2i(
					part.position,
					Vector2i(part.size.x, overlap.position.y - part.position.y)
				))
			if overlap.end.y < part.end.y:
				next_uncovered.append(Rect2i(
					Vector2i(part.position.x, overlap.end.y),
					Vector2i(part.size.x, part.end.y - overlap.end.y)
				))
			if overlap.position.x > part.position.x:
				next_uncovered.append(Rect2i(
					Vector2i(part.position.x, overlap.position.y),
					Vector2i(overlap.position.x - part.position.x, overlap.size.y)
				))
			if overlap.end.x < part.end.x:
				next_uncovered.append(Rect2i(
					Vector2i(overlap.end.x, overlap.position.y),
					Vector2i(part.end.x - overlap.end.x, overlap.size.y)
				))
		uncovered = next_uncovered
		if uncovered.is_empty():
			return true
	return uncovered.is_empty()
