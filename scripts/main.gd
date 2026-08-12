extends Control

const RESIZE_MARGIN := 12.0
const WINDOW_ASPECT := 1112.0 / 834.0
const MIN_WINDOW_WIDTH := 445
const MAX_WINDOW_WIDTH := 1779
const WINDOW_SCALE_STEP := 1.08
const VISUAL_CANVAS_SIZE := Vector2(1112.0, 834.0)
const GIRL_HEAD_HIT_CENTER := Vector2(330.0, 175.0)
const GIRL_HEAD_HIT_RADII := Vector2(125.0, 145.0)
const CAT_HIT_RECT := Rect2(525.0, 245.0, 315.0, 175.0)
const TYPING_ANIMATION := "typing"
const STARTLE_ANIMATION := "startled_recover"
const CAT_SLEEP_ANIMATION := "sleep"
const CAT_STARTLE_ANIMATION := "startled"
const IDLE_ANIMATION := "idle"
const NAIL_POLISH_ENTER_ANIMATION := "nail_polish_enter"
const NAIL_POLISH_LOOP_ANIMATION := "nail_polish_loop"
const NAIL_POLISH_EXIT_ANIMATION := "nail_polish_exit"
const DRINK_WATER_ANIMATION := "drink_water"
const PHONE_ANIMATION := "phone"
const STRETCH_ANIMATION := "stretch"
const USE_MOUSE_ANIMATION := "use_mouse"
const LEAVE_ANIMATION := "leave"
const COME_BACK_ANIMATION := "come_back"
const DRINK_WATER_BONUS_ANIMATION := "drink_water_bonus"
const CAT_MISCHIEF_ANIMATION := "mischief"
const ROSE_SWAY_PERIOD_SECONDS := 5.8
const ROSE_SWAY_MAX_DEGREES := 0.7
const RAIN_TARGET_VOLUME_DB := 3.0
const THUNDER_MIN_VOLUME_DB := -13.0
const THUNDER_MAX_VOLUME_DB := -10.5
const THUNDER_STREAMS: Array[AudioStream] = [
	preload("res://assets/audio/weather/user_thunder.mp3"),
]
const LEAVE_STAGE_NONE := ""
const LEAVE_STAGE_LEAVING := "leaving"
const LEAVE_STAGE_WAITING_FOR_CAT_SLEEP_LOOP := "waiting_for_cat_sleep_loop"
const LEAVE_STAGE_MISCHIEF := "mischief"
const LEAVE_STAGE_COME_BACK := "come_back"
const LEAVE_STAGE_TYPING_BEFORE_BONUS := "typing_before_bonus"
const LEAVE_STAGE_DRINK_WATER_BONUS := "drink_water_bonus"

@export_range(1.0, 300.0, 0.5) var random_stretch_min_seconds := 10.0
@export_range(1.0, 300.0, 0.5) var random_stretch_max_seconds := 24.0
@export_range(1.0, 300.0, 0.5) var typing_branch_min_seconds := 12.0
@export_range(1.0, 300.0, 0.5) var typing_branch_max_seconds := 28.0
@export_range(1, 10, 1) var idle_branch_min_loops := 1
@export_range(1, 10, 1) var idle_branch_max_loops := 3
@export_range(0.0, 1.0, 0.01) var typing_branch_probability := 0.6
@export_range(0.0, 10.0, 0.1) var nail_polish_activity_weight := 1.0
@export_range(0.0, 10.0, 0.1) var drink_water_activity_weight := 1.0
@export_range(0.0, 10.0, 0.1) var phone_activity_weight := 1.0
@export_range(0.0, 10.0, 0.1) var use_mouse_activity_weight := 1.0
@export_range(30.0, 1800.0, 1.0) var leave_sequence_min_seconds := 180.0
@export_range(30.0, 1800.0, 1.0) var leave_sequence_max_seconds := 360.0
@export var weather_events_enabled := true
@export_range(5.0, 300.0, 1.0) var first_rain_min_seconds := 20.0
@export_range(5.0, 300.0, 1.0) var first_rain_max_seconds := 40.0
@export_range(20.0, 900.0, 1.0) var clear_weather_min_seconds := 100.0
@export_range(20.0, 900.0, 1.0) var clear_weather_max_seconds := 220.0
@export_range(20.0, 300.0, 1.0) var rain_duration_min_seconds := 70.0
@export_range(20.0, 300.0, 1.0) var rain_duration_max_seconds := 130.0
@export_range(3.0, 60.0, 0.5) var thunder_check_min_seconds := 9.0
@export_range(3.0, 60.0, 0.5) var thunder_check_max_seconds := 17.0
@export_range(0.0, 1.0, 0.01) var thunder_probability_per_check := 0.16

@onready var window_controller: WindowController = $WindowController
@onready var radio_bridge: RadioBridge = $RadioBridge
@onready var visual_viewport: SubViewport = $VisualViewport
@onready var visual_output: TextureRect = $VisualOutput
@onready var night_ambient: CanvasModulate = %NightAmbient
@onready var night_blue_overlay: ColorRect = %NightBlueOverlay
@onready var directional_light_overlay: ColorRect = %DirectionalLightOverlay
@onready var room_key_light: PointLight2D = %RoomKeyLight
@onready var monitor_glow: PointLight2D = %MonitorGlow
@onready var desk_warm_bounce: PointLight2D = %DeskWarmBounce
@onready var window_exterior_background: Sprite2D = %WindowExteriorBackground
@onready var window_exterior_video: VideoStreamPlayer = %WindowExteriorVideo
@onready var window_room_background: Sprite2D = %WindowRoomBackground
@onready var trailing_pothos: Sprite2D = %TrailingPothos
@onready var yellow_cat: Node2D = %YellowCat
@onready var martial_cat_figurine: Sprite2D = %MartialCatFigurine
@onready var cat_food_bag: Sprite2D = %CatFoodBag
@onready var cat_food_bag_shadow: Line2D = %CatFoodBagShadow
@onready var cat_food_bag_rear_shadow: Line2D = %CatFoodBagRearContactShadow
@onready var elevated_cat_bowl: Sprite2D = %ElevatedCatBowl
@onready var cat_bowl_shadow: Polygon2D = %CatBowlShadow
@onready var cat_bowl_left_shadow: Polygon2D = %CatBowlLeftFootShadow
@onready var cat_bowl_right_shadow: Polygon2D = %CatBowlRightFootShadow
@onready var window_room_foreground: Sprite2D = %WindowRoomForeground
@onready var typing_actor: Node2D = %TypingGirl
@onready var rose_pot_shadow: Sprite2D = %RosePotShadow
@onready var rose_pot_base: Sprite2D = %MulticolorRosePotBase
@onready var rose_flowers_pivot: Node2D = %RoseFlowersPivot
@onready var window_rain: ColorRect = %WindowRain
@onready var window_lightning_flash: ColorRect = %WindowLightningFlash
@onready var room_lightning_flash: ColorRect = %RoomLightningFlash
@onready var rain_audio: AudioStreamPlayer = %RainAudio
@onready var thunder_audio: AudioStreamPlayer = %ThunderAudio
@onready var top_bar: Control = $UILayer/MusicPanel
@onready var music_panel: MusicPanel = $UILayer/MusicPanel
@onready var action_preview_window: ActionPreviewWindow = $ActionPreviewWindow

var _typing_cycle_seconds := 0.0
var _typing_scene_scale := 1.0
var _stretch_timer: Timer
var _idle_timer: Timer
var _leave_sequence_timer: Timer
var _weather_timer: Timer
var _thunder_timer: Timer
var _startle_rng := RandomNumberGenerator.new()
var _idle_loop_target := 0
var _startle_playing := false
var _cat_startle_playing := false
var _stretch_playing := false
var _stretch_used_in_typing := false
var _last_idle_activity := ""
var _typing_playing := false
var _idle_playing := false
var _nail_polish_playing := false
var _nail_polish_loop_target := 0
var _nail_polish_loop_completed := 0
var _drink_water_playing := false
var _phone_playing := false
var _use_mouse_playing := false
var _use_mouse_returns_to_typing := false
var _startle_returns_to_typing := false
var _typing_time_remaining_after_startle := 0.0
var _stretch_time_remaining_after_startle := 0.0
var _typing_time_remaining_after_stretch := 0.0
var _typing_time_remaining_after_use_mouse := 0.0
var _leave_sequence_stage := LEAVE_STAGE_NONE
var _pending_parent_branch: Dictionary = {}
var _previous_cat_sleep_frame := -1
var _cat_sleep_loop_completed_before_mischief := false
var _come_back_started_on_first_frame := false
var _yellow_cat_base_z_index := 0
var _martial_cat_figurine_base_z_index := 0
var _qa_typing_loop := false
var _qa_linked_startle := false
var _qa_idle_interleave := false
var _qa_nail_polish := false
var _qa_drink_water := false
var _qa_phone := false
var _qa_stretch := false
var _qa_use_mouse := false
var _qa_leave_sequence := false
var _qa_action_preview := false
var _qa_rain_event := false
var _rose_sway_elapsed_seconds := 0.0
var _rain_active := false
var _thunder_in_progress := false
var _thunder_pending := false
var _rain_fade_tween: Tween


func _ready() -> void:
	visual_output.texture = visual_viewport.get_texture()
	gui_input.connect(_on_window_surface_gui_input)
	top_bar.gui_input.connect(_on_drag_region_gui_input)
	music_panel.manager.set_radio_helper(radio_bridge)
	music_panel.always_on_top_toggle_requested.connect(_on_always_on_top_toggle_requested)
	music_panel.close_confirmed.connect(window_controller.close_window)
	window_controller.always_on_top_changed.connect(music_panel.set_always_on_top_state)
	music_panel.set_always_on_top_state(window_controller.always_on_top_enabled)
	action_preview_window.action_requested.connect(_on_action_preview_requested)
	action_preview_window.toggle_requested.connect(_toggle_action_preview_window)
	typing_actor.connect("animation_finished", _on_frame_animation_finished)
	typing_actor.connect("animation_looped", _on_frame_animation_looped)
	yellow_cat.connect("animation_finished", _on_cat_animation_finished)
	_startle_rng.randomize()
	_stretch_timer = Timer.new()
	_stretch_timer.one_shot = true
	_stretch_timer.timeout.connect(_on_random_stretch_timeout)
	add_child(_stretch_timer)
	_idle_timer = Timer.new()
	_idle_timer.one_shot = true
	_idle_timer.timeout.connect(_on_idle_timeout)
	add_child(_idle_timer)
	_leave_sequence_timer = Timer.new()
	_leave_sequence_timer.one_shot = true
	_leave_sequence_timer.timeout.connect(_on_leave_sequence_timeout)
	add_child(_leave_sequence_timer)
	_weather_timer = Timer.new()
	_weather_timer.one_shot = true
	_weather_timer.timeout.connect(_on_weather_timer_timeout)
	add_child(_weather_timer)
	_thunder_timer = Timer.new()
	_thunder_timer.one_shot = true
	_thunder_timer.timeout.connect(_on_thunder_timer_timeout)
	add_child(_thunder_timer)
	_qa_linked_startle = "--qa-xsxb-linked-startle" in OS.get_cmdline_user_args()
	_qa_typing_loop = "--qa-xsxb-loop" in OS.get_cmdline_user_args()
	_qa_idle_interleave = "--qa-xsxb-idle-interleave" in OS.get_cmdline_user_args()
	_qa_nail_polish = "--qa-xsxb-nail-polish" in OS.get_cmdline_user_args()
	_qa_drink_water = "--qa-xsxb-drink-water" in OS.get_cmdline_user_args()
	_qa_phone = "--qa-xsxb-phone" in OS.get_cmdline_user_args()
	_qa_stretch = "--qa-xsxb-stretch" in OS.get_cmdline_user_args()
	_qa_use_mouse = "--qa-xsxb-use-mouse" in OS.get_cmdline_user_args()
	_qa_leave_sequence = "--qa-xsxb-leave-sequence" in OS.get_cmdline_user_args()
	_qa_action_preview = "--qa-action-preview" in OS.get_cmdline_user_args()
	_qa_rain_event = "--qa-rain-event" in OS.get_cmdline_user_args()
	_initialize_weather()
	_yellow_cat_base_z_index = yellow_cat.z_index
	_martial_cat_figurine_base_z_index = martial_cat_figurine.z_index
	_typing_cycle_seconds = float(typing_actor.call("animation_duration", TYPING_ANIMATION))
	_typing_scene_scale = float(typing_actor.call("scene_scale"))
	typing_actor.call("play_frame_animation", IDLE_ANIMATION, true)
	_idle_playing = true
	if _qa_typing_loop or _qa_stretch:
		_trigger_typing_branch()
	elif not _qa_linked_startle and not _qa_leave_sequence:
		_schedule_idle_branch()
	_schedule_leave_sequence()
	var qa_run := _has_qa_argument()
	if not qa_run or "--qa-ui-screenshot" in OS.get_cmdline_user_args():
		music_panel.manager.set_volume(0.18, false)
		music_panel.manager.play_station(0)
	if "--qa-ui-screenshot" in OS.get_cmdline_user_args():
		music_panel.show()
		_capture_music_ui.call_deferred()
	if "--qa-background-screenshot" in OS.get_cmdline_user_args():
		_capture_background_scene.call_deferred()
	if "--qa-exterior-video" in OS.get_cmdline_user_args():
		_run_exterior_video_smoke.call_deferred()
	if "--qa-ambient-layers" in OS.get_cmdline_user_args():
		_run_ambient_layer_smoke.call_deferred()
	if "--qa-room-enrichment" in OS.get_cmdline_user_args():
		_run_room_enrichment_smoke.call_deferred()
	if "--qa-room-enrichment-half-size" in OS.get_cmdline_user_args():
		_run_room_enrichment_half_size_comparison.call_deferred()
	if "--qa-audio-sliders" in OS.get_cmdline_user_args():
		_run_audio_slider_smoke.call_deferred()
	if "--qa-window-ui" in OS.get_cmdline_user_args():
		_run_window_ui_smoke.call_deferred()
	if "--qa-window-bounds" in OS.get_cmdline_user_args():
		_run_window_bounds_smoke.call_deferred()
	if "--qa-fixed-music-panel" in OS.get_cmdline_user_args():
		_run_fixed_music_panel_smoke.call_deferred()
	if "--qa-source-dialog-layout" in OS.get_cmdline_user_args():
		_run_source_dialog_layout_smoke.call_deferred()
	if OS.is_debug_build() and "--qa-radio" in OS.get_cmdline_user_args():
		_run_audius_smoke.call_deferred()
	if OS.is_debug_build() and "--qa-audius" in OS.get_cmdline_user_args():
		_run_random_chillhop_smoke.call_deferred()
	if "--qa-radio-controls" in OS.get_cmdline_user_args():
		_run_radio_controls_smoke.call_deferred()
	if OS.is_debug_build() and "--qa-xsxb-loop" in OS.get_cmdline_user_args():
		_run_xsxb_loop_smoke.call_deferred()
	if OS.is_debug_build() and _qa_linked_startle:
		_run_linked_startle_smoke.call_deferred()
	if OS.is_debug_build() and _qa_idle_interleave:
		_run_idle_interleave_smoke.call_deferred()
	if OS.is_debug_build() and _qa_nail_polish:
		_run_nail_polish_smoke.call_deferred()
	if OS.is_debug_build() and _qa_drink_water:
		_run_drink_water_smoke.call_deferred()
	if OS.is_debug_build() and _qa_phone:
		_run_phone_smoke.call_deferred()
	if OS.is_debug_build() and _qa_stretch:
		_run_stretch_smoke.call_deferred()
	if OS.is_debug_build() and _qa_use_mouse:
		_run_use_mouse_smoke.call_deferred()
	if OS.is_debug_build() and _qa_leave_sequence:
		_run_leave_sequence_smoke.call_deferred()
	if OS.is_debug_build() and _qa_action_preview:
		_run_action_preview_smoke.call_deferred()
	if OS.is_debug_build() and _qa_rain_event:
		_run_rain_event_smoke.call_deferred()
	if OS.is_debug_build() and "--qa-xsxb-yellow-cat" in OS.get_cmdline_user_args():
		_run_yellow_cat_smoke.call_deferred()
	if OS.is_debug_build() and "--qa-xsxb-lazy-cache" in OS.get_cmdline_user_args():
		_run_xsxb_lazy_cache_smoke.call_deferred()


func _has_qa_argument() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-"):
			return true
	return false


func _process(delta: float) -> void:
	_rose_sway_elapsed_seconds = fmod(
		_rose_sway_elapsed_seconds + delta,
		ROSE_SWAY_PERIOD_SECONDS
	)
	var rose_phase := TAU * _rose_sway_elapsed_seconds / ROSE_SWAY_PERIOD_SECONDS
	var rose_sway := sin(rose_phase) + sin(rose_phase * 0.47 + 0.8) * 0.18
	rose_flowers_pivot.rotation = deg_to_rad(ROSE_SWAY_MAX_DEGREES) * rose_sway / 1.18
	if _leave_sequence_stage != LEAVE_STAGE_WAITING_FOR_CAT_SLEEP_LOOP:
		return
	if str(yellow_cat.get("_current_animation")) != CAT_SLEEP_ANIMATION:
		return
	var current_cat_frame := int(yellow_cat.get("_current_frame"))
	if _previous_cat_sleep_frame < 0:
		_previous_cat_sleep_frame = current_cat_frame
		return
	if current_cat_frame < _previous_cat_sleep_frame:
		_cat_sleep_loop_completed_before_mischief = true
		_begin_mischief_after_sleep_loop()
		return
	_previous_cat_sleep_frame = current_cat_frame


func _initialize_weather() -> void:
	window_rain.visible = true
	window_lightning_flash.color.a = 0.0
	room_lightning_flash.color.a = 0.0
	var rain_mp3 := rain_audio.stream as AudioStreamMP3
	if rain_mp3 != null:
		rain_mp3.loop = true
	if not rain_audio.finished.is_connected(_on_rain_audio_finished):
		rain_audio.finished.connect(_on_rain_audio_finished)
	if not weather_events_enabled or _qa_rain_event:
		return
	var first_delay := _startle_rng.randf_range(
		minf(first_rain_min_seconds, first_rain_max_seconds),
		maxf(first_rain_min_seconds, first_rain_max_seconds)
	)
	_weather_timer.start(first_delay)


func _on_rain_audio_finished() -> void:
	if _rain_active:
		rain_audio.play()


func _on_weather_timer_timeout() -> void:
	if _rain_active:
		_stop_rain_event()
	else:
		_start_rain_event()


func _start_rain_event(immediate: bool = false) -> void:
	if _rain_active:
		return
	_rain_active = true
	if _rain_fade_tween != null and _rain_fade_tween.is_valid():
		_rain_fade_tween.kill()
	var rain_material := window_rain.material as ShaderMaterial
	if rain_material != null:
		rain_material.set_shader_parameter("intensity", 1.0 if immediate else 0.0)
	rain_audio.volume_db = RAIN_TARGET_VOLUME_DB if immediate else -80.0
	rain_audio.play()
	if not immediate:
		_rain_fade_tween = create_tween().set_parallel(true)
		if rain_material != null:
			_rain_fade_tween.tween_method(
				_set_rain_shader_intensity.bind(rain_material), 0.0, 1.0, 2.4
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_rain_fade_tween.tween_property(rain_audio, "volume_db", RAIN_TARGET_VOLUME_DB, 2.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if not _qa_rain_event:
		_weather_timer.start(_startle_rng.randf_range(
			minf(rain_duration_min_seconds, rain_duration_max_seconds),
			maxf(rain_duration_min_seconds, rain_duration_max_seconds)
		))
	_schedule_thunder_check()


func _stop_rain_event(immediate: bool = false) -> void:
	if not _rain_active:
		return
	_rain_active = false
	_thunder_pending = false
	_thunder_timer.stop()
	if _rain_fade_tween != null and _rain_fade_tween.is_valid():
		_rain_fade_tween.kill()
	var rain_material := window_rain.material as ShaderMaterial
	if immediate:
		if rain_material != null:
			rain_material.set_shader_parameter("intensity", 0.0)
		rain_audio.stop()
		rain_audio.volume_db = -80.0
	else:
		_rain_fade_tween = create_tween().set_parallel(true)
		if rain_material != null:
			var current_intensity := float(rain_material.get_shader_parameter("intensity"))
			_rain_fade_tween.tween_method(
				_set_rain_shader_intensity.bind(rain_material), current_intensity, 0.0, 3.2
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_rain_fade_tween.tween_property(rain_audio, "volume_db", -80.0, 3.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_rain_fade_tween.chain().tween_callback(rain_audio.stop)
	if weather_events_enabled and not _qa_rain_event:
		_weather_timer.start(_startle_rng.randf_range(
			minf(clear_weather_min_seconds, clear_weather_max_seconds),
			maxf(clear_weather_min_seconds, clear_weather_max_seconds)
		))


func _set_rain_shader_intensity(value: float, material: ShaderMaterial) -> void:
	material.set_shader_parameter("intensity", value)


func _schedule_thunder_check(delay_override: float = -1.0) -> void:
	if not _rain_active or _thunder_in_progress:
		return
	var delay := delay_override if delay_override >= 0.0 else _startle_rng.randf_range(
		minf(thunder_check_min_seconds, thunder_check_max_seconds),
		maxf(thunder_check_min_seconds, thunder_check_max_seconds)
	)
	_thunder_timer.start(delay)


func _on_thunder_timer_timeout() -> void:
	if not _rain_active:
		return
	if not _thunder_pending and _startle_rng.randf() >= thunder_probability_per_check:
		_schedule_thunder_check()
		return
	_thunder_pending = true
	if not _can_weather_startle_now():
		# A selected strike waits for idle/typing so its thunder always causes the promised reaction.
		_schedule_thunder_check(0.6)
		return
	_thunder_pending = false
	_trigger_thunder()


func _can_weather_startle_now() -> bool:
	var current_animation := str(typing_actor.get("_current_animation"))
	return not _startle_playing and not _cat_startle_playing \
		and ((_typing_playing and current_animation == TYPING_ANIMATION) \
		or (_idle_playing and current_animation == IDLE_ANIMATION))


func _trigger_thunder(force: bool = false) -> bool:
	if _thunder_in_progress or not _rain_active:
		return false
	if not force and not _can_weather_startle_now():
		return false
	_thunder_pending = false
	_thunder_in_progress = true
	_play_lightning_flash()
	_finish_thunder_strike.call_deferred(_startle_rng.randf_range(0.16, 0.32), force)
	return true


func _play_lightning_flash() -> void:
	window_lightning_flash.color.a = 0.0
	room_lightning_flash.color.a = 0.0
	var window_tween := create_tween()
	window_tween.tween_property(window_lightning_flash, "color:a", 0.72, 0.045) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	window_tween.tween_property(window_lightning_flash, "color:a", 0.09, 0.075)
	window_tween.tween_interval(0.045)
	window_tween.tween_property(window_lightning_flash, "color:a", 0.38, 0.035)
	window_tween.tween_property(window_lightning_flash, "color:a", 0.0, 0.38) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var room_tween := create_tween()
	room_tween.tween_property(room_lightning_flash, "color:a", 0.16, 0.055) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	room_tween.tween_property(room_lightning_flash, "color:a", 0.025, 0.08)
	room_tween.tween_interval(0.05)
	room_tween.tween_property(room_lightning_flash, "color:a", 0.075, 0.04)
	room_tween.tween_property(room_lightning_flash, "color:a", 0.0, 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _finish_thunder_strike(sound_delay: float, force: bool) -> void:
	await get_tree().create_timer(sound_delay).timeout
	if force and not _can_weather_startle_now():
		_enter_idle_base(false)
	var thunder_index := _startle_rng.randi_range(0, THUNDER_STREAMS.size() - 1)
	thunder_audio.stream = THUNDER_STREAMS[thunder_index]
	thunder_audio.pitch_scale = _startle_rng.randf_range(0.94, 1.04)
	thunder_audio.volume_db = _startle_rng.randf_range(
		THUNDER_MIN_VOLUME_DB, THUNDER_MAX_VOLUME_DB
	)
	thunder_audio.play()
	var startled := trigger_startle()
	await get_tree().create_timer(0.75).timeout
	_thunder_in_progress = false
	if _rain_active and not _qa_rain_event:
		_schedule_thunder_check()
	if force and not startled:
		push_error("Forced thunder could not trigger the linked person/cat startle")


func _on_always_on_top_toggle_requested() -> void:
	music_panel.set_always_on_top_state(window_controller.toggle_always_on_top())


func _toggle_action_preview_window() -> void:
	action_preview_window.toggle_from_main(
		DisplayServer.window_get_position(),
		DisplayServer.window_get_size()
	)


func _on_action_preview_requested(route_id: String) -> void:
	action_preview_window.set_route_status(route_id, _play_preview_route(route_id))


func _play_preview_route(route_id: String) -> bool:
	match route_id:
		"idle":
			_reset_for_preview_route()
			return _enter_idle_base(true)
		"typing":
			return _queue_preview_route(TYPING_ANIMATION, IDLE_ANIMATION)
		"cat_sleep":
			_reset_for_preview_route()
			return _enter_idle_base(true)
		"startle_idle":
			return _queue_preview_route(STARTLE_ANIMATION, IDLE_ANIMATION, {
				"returns_to_typing": false,
			})
		"startle_typing":
			return _queue_preview_route(STARTLE_ANIMATION, TYPING_ANIMATION, {
				"returns_to_typing": true,
				"typing_time_remaining": maxf(_typing_cycle_seconds, 0.1),
				"stretch_time_remaining": 0.0,
			})
		"stretch":
			return _queue_preview_route(STRETCH_ANIMATION, TYPING_ANIMATION, {
				"typing_time_remaining": maxf(_typing_cycle_seconds, 0.1),
			})
		"nail_polish":
			return _queue_preview_route(NAIL_POLISH_ENTER_ANIMATION, IDLE_ANIMATION, {
				"loop_target": 5,
			})
		"drink_water":
			return _queue_preview_route(DRINK_WATER_ANIMATION, IDLE_ANIMATION)
		"phone":
			return _queue_preview_route(PHONE_ANIMATION, IDLE_ANIMATION)
		"use_mouse_idle":
			return _queue_preview_route(USE_MOUSE_ANIMATION, IDLE_ANIMATION, {
				"returns_to_typing": false,
			})
		"use_mouse_typing":
			return _queue_preview_route(USE_MOUSE_ANIMATION, TYPING_ANIMATION, {
				"returns_to_typing": true,
				"typing_time_remaining": maxf(_typing_cycle_seconds, 0.1),
			})
		"leave_idle":
			return _queue_preview_route(LEAVE_ANIMATION, IDLE_ANIMATION)
		"leave_typing":
			return _queue_preview_route(LEAVE_ANIMATION, TYPING_ANIMATION)
		"cat_mischief":
			_reset_for_preview_route()
			_idle_playing = true
			typing_actor.call("restart_frame_animation", IDLE_ANIMATION, true)
			_leave_sequence_stage = LEAVE_STAGE_WAITING_FOR_CAT_SLEEP_LOOP
			_previous_cat_sleep_frame = int(yellow_cat.get("_current_frame"))
			return true
		"come_back":
			_reset_for_preview_route()
			_leave_sequence_stage = LEAVE_STAGE_MISCHIEF
			typing_actor.visible = false
			yellow_cat.z_index = typing_actor.z_index + 1
			martial_cat_figurine.z_index = yellow_cat.z_index + 1
			yellow_cat.call("restart_frame_animation", CAT_MISCHIEF_ANIMATION, false)
			return true
		"drink_water_bonus":
			_reset_for_preview_route()
			_leave_sequence_stage = LEAVE_STAGE_COME_BACK
			typing_actor.call("restart_frame_animation", COME_BACK_ANIMATION, false)
			return true
	return false


func _queue_preview_route(branch_id: String, parent_animation: String, context: Dictionary = {}) -> bool:
	if not bool(typing_actor.call("has_frame_animation", parent_animation)) \
			or not bool(typing_actor.call("has_frame_animation", branch_id)):
		return false
	if branch_id == STARTLE_ANIMATION \
			and not bool(yellow_cat.call("has_frame_animation", CAT_STARTLE_ANIMATION)):
		return false
	if branch_id == NAIL_POLISH_ENTER_ANIMATION \
			and (not bool(typing_actor.call("has_frame_animation", NAIL_POLISH_LOOP_ANIMATION)) \
			or not bool(typing_actor.call("has_frame_animation", NAIL_POLISH_EXIT_ANIMATION))):
		return false
	if branch_id == LEAVE_ANIMATION \
			and (not bool(yellow_cat.call("has_frame_animation", CAT_MISCHIEF_ANIMATION)) \
			or not bool(typing_actor.call("has_frame_animation", COME_BACK_ANIMATION)) \
			or not bool(typing_actor.call("has_frame_animation", DRINK_WATER_BONUS_ANIMATION))):
		return false
	_reset_for_preview_route()
	_typing_playing = parent_animation == TYPING_ANIMATION
	_idle_playing = parent_animation == IDLE_ANIMATION
	typing_actor.call("restart_frame_animation", parent_animation, true)
	if branch_id == STARTLE_ANIMATION:
		_start_linked_startle_branch(context)
		return true
	return _queue_parent_branch(branch_id, parent_animation, context)


func _reset_for_preview_route() -> void:
	for timer in [_idle_timer, _stretch_timer, _leave_sequence_timer]:
		if timer != null:
			timer.stop()
	_pending_parent_branch.clear()
	_typing_playing = false
	_idle_playing = false
	_idle_loop_target = 0
	_startle_playing = false
	_cat_startle_playing = false
	_stretch_playing = false
	_stretch_used_in_typing = false
	_nail_polish_playing = false
	_nail_polish_loop_target = 0
	_nail_polish_loop_completed = 0
	_drink_water_playing = false
	_phone_playing = false
	_use_mouse_playing = false
	_use_mouse_returns_to_typing = false
	_startle_returns_to_typing = false
	_typing_time_remaining_after_startle = 0.0
	_stretch_time_remaining_after_startle = 0.0
	_typing_time_remaining_after_stretch = 0.0
	_typing_time_remaining_after_use_mouse = 0.0
	_leave_sequence_stage = LEAVE_STAGE_NONE
	_previous_cat_sleep_frame = -1
	_cat_sleep_loop_completed_before_mischief = false
	_come_back_started_on_first_frame = false
	_last_idle_activity = ""
	typing_actor.visible = true
	yellow_cat.visible = true
	yellow_cat.z_index = _yellow_cat_base_z_index
	martial_cat_figurine.z_index = _martial_cat_figurine_base_z_index
	yellow_cat.call("restart_frame_animation", CAT_SLEEP_ANIMATION, true)


func _has_pending_parent_branch() -> bool:
	return not _pending_parent_branch.is_empty()


func _queue_parent_branch(branch_id: String, parent_animation: String, context: Dictionary = {}) -> bool:
	if _has_pending_parent_branch():
		return false
	if str(typing_actor.get("_current_animation")) != parent_animation:
		return false
	_pending_parent_branch = {
		"id": branch_id,
		"parent": parent_animation,
		"context": context.duplicate(true),
	}
	return true


func _on_frame_animation_looped(animation_name: String) -> void:
	if animation_name == TYPING_ANIMATION \
			and _leave_sequence_stage == LEAVE_STAGE_TYPING_BEFORE_BONUS:
		_leave_sequence_stage = LEAVE_STAGE_DRINK_WATER_BONUS
		_typing_playing = false
		typing_actor.call("restart_frame_animation", DRINK_WATER_BONUS_ANIMATION, false)
		return
	if not _has_pending_parent_branch():
		return
	if animation_name != str(_pending_parent_branch.get("parent", "")):
		return
	var request := _pending_parent_branch.duplicate(true)
	_pending_parent_branch.clear()
	_start_pending_parent_branch(request)


func _start_pending_parent_branch(request: Dictionary) -> void:
	var branch_id := str(request.get("id", ""))
	var context: Dictionary = request.get("context", {}) as Dictionary
	match branch_id:
		STARTLE_ANIMATION:
			_start_linked_startle_branch(context)
		STRETCH_ANIMATION:
			_start_stretch_branch(context)
		TYPING_ANIMATION:
			_start_typing_branch()
		NAIL_POLISH_ENTER_ANIMATION:
			_start_nail_polish_branch(context)
		DRINK_WATER_ANIMATION:
			_start_drink_water_branch()
		PHONE_ANIMATION:
			_start_phone_branch()
		USE_MOUSE_ANIMATION:
			_start_use_mouse_branch(context)
		LEAVE_ANIMATION:
			_start_leave_sequence_branch()


func _start_linked_startle_branch(context: Dictionary) -> void:
	_startle_returns_to_typing = bool(context.get("returns_to_typing", false))
	_typing_time_remaining_after_startle = float(context.get("typing_time_remaining", 0.0))
	_stretch_time_remaining_after_startle = float(context.get("stretch_time_remaining", 0.0))
	_typing_playing = false
	_idle_playing = false
	_idle_loop_target = 0
	_nail_polish_playing = false
	_nail_polish_loop_target = 0
	_nail_polish_loop_completed = 0
	_drink_water_playing = false
	_phone_playing = false
	_use_mouse_playing = false
	_use_mouse_returns_to_typing = false
	_typing_time_remaining_after_use_mouse = 0.0
	_startle_playing = true
	_cat_startle_playing = true
	_stretch_playing = false
	typing_actor.call("restart_frame_animation", STARTLE_ANIMATION, false)
	yellow_cat.call("restart_frame_animation", CAT_STARTLE_ANIMATION, false)


func _start_stretch_branch(context: Dictionary) -> void:
	_typing_time_remaining_after_stretch = float(context.get("typing_time_remaining", 0.0))
	_typing_playing = false
	_stretch_playing = true
	_stretch_used_in_typing = true
	typing_actor.call("restart_frame_animation", STRETCH_ANIMATION, false)


func _start_typing_branch() -> void:
	_idle_playing = false
	_idle_loop_target = 0
	_typing_playing = true
	_stretch_used_in_typing = false
	_last_idle_activity = ""
	typing_actor.call("restart_frame_animation", TYPING_ANIMATION, true)
	var delay := 10.0 if (_qa_linked_startle or _qa_typing_loop or _qa_stretch or _qa_use_mouse) else _startle_rng.randf_range(
		minf(typing_branch_min_seconds, typing_branch_max_seconds),
		maxf(typing_branch_min_seconds, typing_branch_max_seconds)
	)
	_idle_timer.start(delay)
	_schedule_next_stretch()


func _start_nail_polish_branch(context: Dictionary) -> void:
	_idle_playing = false
	_idle_loop_target = 0
	_nail_polish_playing = true
	_nail_polish_loop_target = int(context.get("loop_target", 5))
	_nail_polish_loop_completed = 0
	_last_idle_activity = NAIL_POLISH_ENTER_ANIMATION
	typing_actor.call("restart_frame_animation", NAIL_POLISH_ENTER_ANIMATION, false)


func _start_drink_water_branch() -> void:
	_idle_playing = false
	_idle_loop_target = 0
	_drink_water_playing = true
	_last_idle_activity = DRINK_WATER_ANIMATION
	typing_actor.call("restart_frame_animation", DRINK_WATER_ANIMATION, false)


func _start_phone_branch() -> void:
	_idle_playing = false
	_idle_loop_target = 0
	_phone_playing = true
	_last_idle_activity = PHONE_ANIMATION
	typing_actor.call("restart_frame_animation", PHONE_ANIMATION, false)


func _start_use_mouse_branch(context: Dictionary) -> void:
	var returns_to_typing := bool(context.get("returns_to_typing", false))
	_typing_time_remaining_after_use_mouse = float(context.get("typing_time_remaining", 0.0))
	_typing_playing = false
	_idle_playing = false
	_idle_loop_target = 0
	_use_mouse_playing = true
	_use_mouse_returns_to_typing = returns_to_typing
	if returns_to_typing:
		_stretch_used_in_typing = true
	else:
		_last_idle_activity = USE_MOUSE_ANIMATION
	typing_actor.call("restart_frame_animation", USE_MOUSE_ANIMATION, false)


func _start_leave_sequence_branch() -> void:
	_typing_playing = false
	_idle_playing = false
	_idle_loop_target = 0
	_stretch_playing = false
	_stretch_used_in_typing = false
	_nail_polish_playing = false
	_nail_polish_loop_target = 0
	_nail_polish_loop_completed = 0
	_drink_water_playing = false
	_phone_playing = false
	_use_mouse_playing = false
	_use_mouse_returns_to_typing = false
	_typing_time_remaining_after_use_mouse = 0.0
	_last_idle_activity = ""
	_leave_sequence_stage = LEAVE_STAGE_LEAVING
	_previous_cat_sleep_frame = -1
	_cat_sleep_loop_completed_before_mischief = false
	_come_back_started_on_first_frame = false
	typing_actor.visible = true
	yellow_cat.visible = true
	typing_actor.call("restart_frame_animation", LEAVE_ANIMATION, false)


## Clicks on the girl's head or the cat call this only from the idle/typing base states.
func trigger_startle() -> bool:
	if _startle_playing or _cat_startle_playing:
		return false
	if not bool(typing_actor.call("has_frame_animation", STARTLE_ANIMATION)) \
		or not bool(yellow_cat.call("has_frame_animation", CAT_STARTLE_ANIMATION)):
		return false
	var current_animation := str(typing_actor.get("_current_animation"))
	var from_typing := _typing_playing and current_animation == TYPING_ANIMATION
	var from_idle := _idle_playing and current_animation == IDLE_ANIMATION
	if not from_typing and not from_idle:
		return false
	var typing_time_remaining := _idle_timer.time_left \
		if from_typing and _idle_timer != null and not _idle_timer.is_stopped() else 0.0
	var stretch_time_remaining := _stretch_timer.time_left \
		if from_typing and _stretch_timer != null and not _stretch_timer.is_stopped() \
		else 0.0
	if _stretch_timer != null:
		_stretch_timer.stop()
	if _idle_timer != null:
		_idle_timer.stop()
	_pending_parent_branch.clear()
	_start_linked_startle_branch({
		"returns_to_typing": from_typing,
		"typing_time_remaining": typing_time_remaining,
		"stretch_time_remaining": stretch_time_remaining,
	})
	return true


func _schedule_next_stretch() -> void:
	if _stretch_timer == null or not _typing_playing or _stretch_used_in_typing \
		or _qa_typing_loop or _qa_linked_startle or _qa_idle_interleave \
		or _qa_nail_polish or _qa_drink_water or _qa_phone or _qa_use_mouse \
		or _qa_leave_sequence:
		return
	var delay := 0.2 if _qa_stretch else _startle_rng.randf_range(
		minf(random_stretch_min_seconds, random_stretch_max_seconds),
		maxf(random_stretch_min_seconds, random_stretch_max_seconds)
	)
	_stretch_timer.start(delay)


func _on_random_stretch_timeout() -> void:
	if not _typing_playing or str(typing_actor.get("_current_animation")) != TYPING_ANIMATION:
		return
	var has_stretch := bool(typing_actor.call("has_frame_animation", STRETCH_ANIMATION))
	var has_mouse := use_mouse_activity_weight > 0.0 \
		and bool(typing_actor.call("has_frame_animation", USE_MOUSE_ANIMATION))
	var triggered := false
	if _qa_stretch:
		triggered = _trigger_stretch()
	elif has_stretch and has_mouse:
		var mouse_probability := use_mouse_activity_weight / (1.0 + use_mouse_activity_weight)
		triggered = _trigger_use_mouse() if _startle_rng.randf() < mouse_probability \
			else _trigger_stretch()
	elif has_mouse:
		triggered = _trigger_use_mouse()
	elif has_stretch:
		triggered = _trigger_stretch()
	if not triggered:
		_schedule_next_stretch()


func _trigger_stretch() -> bool:
	if _stretch_playing or _startle_playing or not _typing_playing \
		or _stretch_used_in_typing or _use_mouse_playing or _has_pending_parent_branch():
		return false
	if str(typing_actor.get("_current_animation")) != TYPING_ANIMATION:
		return false
	if not bool(typing_actor.call("has_frame_animation", STRETCH_ANIMATION)):
		return false
	var typing_time_remaining := _idle_timer.time_left \
		if _idle_timer != null and not _idle_timer.is_stopped() else 0.0
	if _idle_timer != null:
		_idle_timer.stop()
	if _stretch_timer != null:
		_stretch_timer.stop()
	return _queue_parent_branch(STRETCH_ANIMATION, TYPING_ANIMATION, {
		"typing_time_remaining": typing_time_remaining,
	})


func _enter_idle_base(schedule_branch: bool = true) -> bool:
	if not bool(typing_actor.call("has_frame_animation", IDLE_ANIMATION)):
		return false
	if _stretch_timer != null:
		_stretch_timer.stop()
	if _idle_timer != null:
		_idle_timer.stop()
	_typing_playing = false
	_stretch_playing = false
	_stretch_used_in_typing = false
	_use_mouse_playing = false
	_use_mouse_returns_to_typing = false
	_stretch_time_remaining_after_startle = 0.0
	_typing_time_remaining_after_stretch = 0.0
	_typing_time_remaining_after_use_mouse = 0.0
	_idle_playing = true
	_idle_loop_target = 0
	typing_actor.call("restart_frame_animation", IDLE_ANIMATION, true)
	if schedule_branch:
		_schedule_idle_branch()
	return true


func _trigger_typing_branch() -> bool:
	if _typing_playing or not _idle_playing or _startle_playing \
		or _stretch_playing or _nail_polish_playing or _drink_water_playing \
		or _phone_playing or _use_mouse_playing or _has_pending_parent_branch():
		return false
	if str(typing_actor.get("_current_animation")) != IDLE_ANIMATION:
		return false
	if not bool(typing_actor.call("has_frame_animation", TYPING_ANIMATION)):
		return false
	if _idle_timer != null:
		_idle_timer.stop()
	return _queue_parent_branch(TYPING_ANIMATION, IDLE_ANIMATION)


func _trigger_nail_polish() -> bool:
	if _nail_polish_playing or not _idle_playing or _startle_playing \
		or _drink_water_playing or _phone_playing or _use_mouse_playing \
		or _last_idle_activity == NAIL_POLISH_ENTER_ANIMATION or _has_pending_parent_branch():
		return false
	if str(typing_actor.get("_current_animation")) != IDLE_ANIMATION:
		return false
	for animation_name in [NAIL_POLISH_ENTER_ANIMATION, NAIL_POLISH_LOOP_ANIMATION, NAIL_POLISH_EXIT_ANIMATION]:
		if not bool(typing_actor.call("has_frame_animation", animation_name)):
			return false
	if _idle_timer != null:
		_idle_timer.stop()
	var loop_target := 5 if _qa_nail_polish else _startle_rng.randi_range(5, 10)
	return _queue_parent_branch(NAIL_POLISH_ENTER_ANIMATION, IDLE_ANIMATION, {
		"loop_target": loop_target,
	})


func _trigger_drink_water() -> bool:
	if _drink_water_playing or not _idle_playing or _startle_playing \
		or _nail_polish_playing or _phone_playing or _use_mouse_playing \
		or _last_idle_activity == DRINK_WATER_ANIMATION or _has_pending_parent_branch():
		return false
	if str(typing_actor.get("_current_animation")) != IDLE_ANIMATION:
		return false
	if not bool(typing_actor.call("has_frame_animation", DRINK_WATER_ANIMATION)):
		return false
	if _idle_timer != null:
		_idle_timer.stop()
	return _queue_parent_branch(DRINK_WATER_ANIMATION, IDLE_ANIMATION)


func _trigger_phone() -> bool:
	if _phone_playing or not _idle_playing or _startle_playing \
		or _nail_polish_playing or _drink_water_playing or _use_mouse_playing \
		or _last_idle_activity == PHONE_ANIMATION or _has_pending_parent_branch():
		return false
	if str(typing_actor.get("_current_animation")) != IDLE_ANIMATION:
		return false
	if not bool(typing_actor.call("has_frame_animation", PHONE_ANIMATION)):
		return false
	if _idle_timer != null:
		_idle_timer.stop()
	return _queue_parent_branch(PHONE_ANIMATION, IDLE_ANIMATION)


func _trigger_use_mouse() -> bool:
	if _use_mouse_playing or _startle_playing or _stretch_playing \
		or _nail_polish_playing or _drink_water_playing or _phone_playing \
		or _has_pending_parent_branch():
		return false
	if not bool(typing_actor.call("has_frame_animation", USE_MOUSE_ANIMATION)):
		return false
	var current_animation := str(typing_actor.get("_current_animation"))
	var from_typing := _typing_playing and current_animation == TYPING_ANIMATION
	var from_idle := _idle_playing and current_animation == IDLE_ANIMATION \
		and _last_idle_activity != USE_MOUSE_ANIMATION
	if not from_typing and not from_idle:
		return false
	var typing_time_remaining := _idle_timer.time_left \
		if from_typing and _idle_timer != null and not _idle_timer.is_stopped() else 0.0
	if _idle_timer != null:
		_idle_timer.stop()
	if _stretch_timer != null:
		_stretch_timer.stop()
	return _queue_parent_branch(USE_MOUSE_ANIMATION, current_animation, {
		"returns_to_typing": from_typing,
		"typing_time_remaining": typing_time_remaining,
	})


func _schedule_leave_sequence() -> void:
	if _leave_sequence_timer == null or _leave_sequence_stage != LEAVE_STAGE_NONE \
			or _has_qa_argument() or not _leave_sequence_timer.is_stopped():
		return
	var delay := _startle_rng.randf_range(
		minf(leave_sequence_min_seconds, leave_sequence_max_seconds),
		maxf(leave_sequence_min_seconds, leave_sequence_max_seconds)
	)
	_leave_sequence_timer.start(delay)


func _on_leave_sequence_timeout() -> void:
	if not _trigger_leave_sequence():
		_schedule_leave_sequence()


func _trigger_leave_sequence() -> bool:
	if _leave_sequence_stage != LEAVE_STAGE_NONE or _has_pending_parent_branch():
		return false
	var current_animation := str(typing_actor.get("_current_animation"))
	var from_typing := _typing_playing and current_animation == TYPING_ANIMATION
	var from_idle := _idle_playing and current_animation == IDLE_ANIMATION
	if not from_typing and not from_idle:
		return false
	if str(yellow_cat.get("_current_animation")) != CAT_SLEEP_ANIMATION:
		return false
	for animation_name in [LEAVE_ANIMATION, COME_BACK_ANIMATION, DRINK_WATER_BONUS_ANIMATION]:
		if not bool(typing_actor.call("has_frame_animation", animation_name)):
			return false
	if not bool(yellow_cat.call("has_frame_animation", CAT_MISCHIEF_ANIMATION)):
		return false
	if _idle_timer != null:
		_idle_timer.stop()
	if _stretch_timer != null:
		_stretch_timer.stop()
	if _leave_sequence_timer != null:
		_leave_sequence_timer.stop()
	return _queue_parent_branch(LEAVE_ANIMATION, current_animation)


func _begin_mischief_after_sleep_loop() -> void:
	if _leave_sequence_stage != LEAVE_STAGE_WAITING_FOR_CAT_SLEEP_LOOP:
		return
	_leave_sequence_stage = LEAVE_STAGE_MISCHIEF
	_previous_cat_sleep_frame = -1
	typing_actor.visible = false
	yellow_cat.visible = true
	yellow_cat.z_index = typing_actor.z_index + 1
	martial_cat_figurine.z_index = yellow_cat.z_index + 1
	yellow_cat.call("restart_frame_animation", CAT_MISCHIEF_ANIMATION, false)


func _begin_come_back_after_mischief() -> void:
	if _leave_sequence_stage != LEAVE_STAGE_MISCHIEF:
		return
	_leave_sequence_stage = LEAVE_STAGE_COME_BACK
	yellow_cat.z_index = _yellow_cat_base_z_index
	martial_cat_figurine.z_index = _martial_cat_figurine_base_z_index
	yellow_cat.call("restart_frame_animation", CAT_SLEEP_ANIMATION, true)
	typing_actor.visible = true
	typing_actor.call("restart_frame_animation", COME_BACK_ANIMATION, false)
	_come_back_started_on_first_frame = int(typing_actor.get("_current_frame")) == 0 \
		and int(yellow_cat.get("_current_frame")) == 0


func _finish_leave_sequence_to_typing() -> void:
	_leave_sequence_stage = LEAVE_STAGE_NONE
	_previous_cat_sleep_frame = -1
	typing_actor.visible = true
	yellow_cat.visible = true
	yellow_cat.z_index = _yellow_cat_base_z_index
	martial_cat_figurine.z_index = _martial_cat_figurine_base_z_index
	_typing_playing = true
	_idle_playing = false
	_idle_loop_target = 0
	_stretch_playing = false
	_stretch_used_in_typing = false
	_last_idle_activity = ""
	typing_actor.call("restart_frame_animation", TYPING_ANIMATION, true)
	var delay := _startle_rng.randf_range(
		minf(typing_branch_min_seconds, typing_branch_max_seconds),
		maxf(typing_branch_min_seconds, typing_branch_max_seconds)
	)
	_idle_timer.start(delay)
	_schedule_next_stretch()
	_schedule_leave_sequence()


func _schedule_idle_branch() -> void:
	if _idle_timer == null or not _idle_playing or _qa_linked_startle \
		or _qa_typing_loop or _qa_idle_interleave:
		return
	var idle_duration := float(typing_actor.call("animation_duration", IDLE_ANIMATION))
	if idle_duration <= 0.0:
		return
	var min_loops := mini(idle_branch_min_loops, idle_branch_max_loops)
	var max_loops := maxi(idle_branch_min_loops, idle_branch_max_loops)
	_idle_loop_target = 1 if (_qa_nail_polish or _qa_drink_water or _qa_phone or _qa_use_mouse) \
		else _startle_rng.randi_range(min_loops, max_loops)
	var final_loop_last_frame_start := float(typing_actor.call(
		"animation_last_playable_frame_start", IDLE_ANIMATION
	))
	var delay := idle_duration * float(_idle_loop_target - 1) \
		+ maxf(0.001, final_loop_last_frame_start + 0.001)
	_idle_timer.start(delay)


func _trigger_idle_branch() -> bool:
	var triggered := false
	if _qa_nail_polish:
		triggered = _trigger_nail_polish()
	elif _qa_drink_water:
		triggered = _trigger_drink_water()
	elif _qa_phone:
		triggered = _trigger_phone()
	elif _qa_use_mouse:
		triggered = _trigger_use_mouse()
	else:
		if _startle_rng.randf() < clampf(typing_branch_probability, 0.0, 1.0):
			triggered = _trigger_typing_branch()
		else:
			var candidates: Array[Dictionary] = []
			if _last_idle_activity != NAIL_POLISH_ENTER_ANIMATION and nail_polish_activity_weight > 0.0:
				candidates.append({"id": NAIL_POLISH_ENTER_ANIMATION, "weight": nail_polish_activity_weight})
			if _last_idle_activity != DRINK_WATER_ANIMATION and drink_water_activity_weight > 0.0:
				candidates.append({"id": DRINK_WATER_ANIMATION, "weight": drink_water_activity_weight})
			if _last_idle_activity != PHONE_ANIMATION and phone_activity_weight > 0.0:
				candidates.append({"id": PHONE_ANIMATION, "weight": phone_activity_weight})
			if _last_idle_activity != USE_MOUSE_ANIMATION and use_mouse_activity_weight > 0.0:
				candidates.append({"id": USE_MOUSE_ANIMATION, "weight": use_mouse_activity_weight})
			var total_weight := 0.0
			for candidate in candidates:
				total_weight += float(candidate.weight)
			if total_weight <= 0.0:
				triggered = _trigger_typing_branch()
			else:
				var roll := _startle_rng.randf_range(0.0, total_weight)
				for candidate in candidates:
					roll -= float(candidate.weight)
					if roll <= 0.0:
						var activity_id := str(candidate.id)
						if activity_id == NAIL_POLISH_ENTER_ANIMATION:
							triggered = _trigger_nail_polish()
						elif activity_id == DRINK_WATER_ANIMATION:
							triggered = _trigger_drink_water()
						elif activity_id == PHONE_ANIMATION:
							triggered = _trigger_phone()
						else:
							triggered = _trigger_use_mouse()
						break
	return triggered


func _on_idle_timeout() -> void:
	var current_animation := str(typing_actor.get("_current_animation"))
	if current_animation == TYPING_ANIMATION and _typing_playing:
		if _stretch_timer != null:
			_stretch_timer.stop()
		_enter_idle_base()
	elif current_animation == IDLE_ANIMATION and _idle_playing:
		if not _trigger_idle_branch():
			_schedule_idle_branch()


func _on_frame_animation_finished(animation_name: String) -> void:
	if animation_name == LEAVE_ANIMATION and _leave_sequence_stage == LEAVE_STAGE_LEAVING:
		_leave_sequence_stage = LEAVE_STAGE_WAITING_FOR_CAT_SLEEP_LOOP
		_previous_cat_sleep_frame = int(yellow_cat.get("_current_frame"))
	elif animation_name == COME_BACK_ANIMATION and _leave_sequence_stage == LEAVE_STAGE_COME_BACK:
		_leave_sequence_stage = LEAVE_STAGE_TYPING_BEFORE_BONUS
		_typing_playing = true
		_idle_playing = false
		_idle_loop_target = 0
		typing_actor.call("restart_frame_animation", TYPING_ANIMATION, true)
	elif animation_name == DRINK_WATER_BONUS_ANIMATION \
			and _leave_sequence_stage == LEAVE_STAGE_DRINK_WATER_BONUS:
		_finish_leave_sequence_to_typing()
	elif animation_name == STARTLE_ANIMATION:
		_startle_playing = false
		if _startle_returns_to_typing and _typing_time_remaining_after_startle > 0.0:
			_typing_playing = true
			typing_actor.call("play_frame_animation", TYPING_ANIMATION, true)
			_idle_timer.start(_typing_time_remaining_after_startle)
			if _stretch_time_remaining_after_startle > 0.0 and not _stretch_used_in_typing:
				_stretch_timer.start(_stretch_time_remaining_after_startle)
			else:
				_schedule_next_stretch()
		else:
			_enter_idle_base(not _qa_linked_startle)
		_startle_returns_to_typing = false
		_typing_time_remaining_after_startle = 0.0
		_stretch_time_remaining_after_startle = 0.0
	elif animation_name == STRETCH_ANIMATION and _stretch_playing:
		_stretch_playing = false
		if _typing_time_remaining_after_stretch > 0.0:
			_typing_playing = true
			typing_actor.call("play_frame_animation", TYPING_ANIMATION, true)
			_idle_timer.start(_typing_time_remaining_after_stretch)
		else:
			_enter_idle_base(not _qa_stretch)
		_typing_time_remaining_after_stretch = 0.0
	elif animation_name == NAIL_POLISH_ENTER_ANIMATION and _nail_polish_playing:
		typing_actor.call("restart_frame_animation", NAIL_POLISH_LOOP_ANIMATION, false)
	elif animation_name == NAIL_POLISH_LOOP_ANIMATION and _nail_polish_playing:
		_nail_polish_loop_completed += 1
		if _nail_polish_loop_completed < _nail_polish_loop_target:
			typing_actor.call("restart_frame_animation", NAIL_POLISH_LOOP_ANIMATION, false)
		else:
			typing_actor.call("restart_frame_animation", NAIL_POLISH_EXIT_ANIMATION, false)
	elif animation_name == NAIL_POLISH_EXIT_ANIMATION and _nail_polish_playing:
		_nail_polish_playing = false
		_enter_idle_base(not _qa_nail_polish)
	elif animation_name == DRINK_WATER_ANIMATION and _drink_water_playing:
		_drink_water_playing = false
		_enter_idle_base(not _qa_drink_water)
	elif animation_name == PHONE_ANIMATION and _phone_playing:
		_phone_playing = false
		_enter_idle_base(not _qa_phone)
	elif animation_name == USE_MOUSE_ANIMATION and _use_mouse_playing:
		_use_mouse_playing = false
		if _use_mouse_returns_to_typing and _typing_time_remaining_after_use_mouse > 0.0:
			_typing_playing = true
			typing_actor.call("play_frame_animation", TYPING_ANIMATION, true)
			_idle_timer.start(_typing_time_remaining_after_use_mouse)
		else:
			_enter_idle_base(not _qa_use_mouse)
		_use_mouse_returns_to_typing = false
		_typing_time_remaining_after_use_mouse = 0.0


func _on_cat_animation_finished(animation_name: String) -> void:
	if animation_name == CAT_MISCHIEF_ANIMATION \
			and _leave_sequence_stage == LEAVE_STAGE_MISCHIEF:
		_begin_come_back_after_mischief()
		return
	if animation_name != CAT_STARTLE_ANIMATION or not _cat_startle_playing:
		return
	_cat_startle_playing = false
	yellow_cat.call("restart_frame_animation", CAT_SLEEP_ANIMATION, true)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_T or event.physical_keycode == KEY_T):
		_toggle_action_preview_window()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if Input.is_key_pressed(KEY_Z) and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_scale_window(event.button_index == MOUSE_BUTTON_WHEEL_UP)
			get_viewport().set_input_as_handled()
			return
		if event.button_index != MOUSE_BUTTON_RIGHT:
			return
		top_bar.visible = not top_bar.visible
		get_viewport().set_input_as_handled()


func _scale_window(grow: bool) -> void:
	var old_size := DisplayServer.window_get_size()
	var factor := WINDOW_SCALE_STEP if grow else 1.0 / WINDOW_SCALE_STEP
	var next_width := clampi(roundi(float(old_size.x) * factor), MIN_WINDOW_WIDTH, MAX_WINDOW_WIDTH)
	var next_size := Vector2i(next_width, roundi(float(next_width) / WINDOW_ASPECT))
	if next_size == old_size:
		return
	var old_position := DisplayServer.window_get_position()
	var centered_position := old_position + (old_size - next_size) / 2
	DisplayServer.window_set_size(next_size)
	window_controller.set_window_position_constrained(centered_position)


func _on_drag_region_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		window_controller.begin_window_drag()


func _on_window_surface_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var logical_position := _surface_to_visual_position(event.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND \
			if _can_trigger_startle_from_base() and _is_startle_click_target(logical_position) \
			else Control.CURSOR_ARROW
		return
	if event is not InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var resize_edge := _resize_edge_for_position(event.position)
	if resize_edge >= 0:
		window_controller.begin_window_resize(resize_edge)
	elif _is_startle_click_target(_surface_to_visual_position(event.position)) \
		and trigger_startle():
		get_viewport().set_input_as_handled()
	else:
		window_controller.begin_window_drag()


func _surface_to_visual_position(surface_position: Vector2) -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(-1.0, -1.0)
	return Vector2(
		surface_position.x * VISUAL_CANVAS_SIZE.x / size.x,
		surface_position.y * VISUAL_CANVAS_SIZE.y / size.y
	)


func _visual_to_surface_position(visual_position: Vector2) -> Vector2:
	return Vector2(
		visual_position.x * size.x / VISUAL_CANVAS_SIZE.x,
		visual_position.y * size.y / VISUAL_CANVAS_SIZE.y
	)


func _can_trigger_startle_from_base() -> bool:
	var current_animation := str(typing_actor.get("_current_animation"))
	return (_idle_playing and current_animation == IDLE_ANIMATION) \
		or (_typing_playing and current_animation == TYPING_ANIMATION)


func _is_startle_click_target(visual_position: Vector2) -> bool:
	var head_delta := visual_position - GIRL_HEAD_HIT_CENTER
	var head_value := (head_delta.x * head_delta.x) / (GIRL_HEAD_HIT_RADII.x * GIRL_HEAD_HIT_RADII.x) \
		+ (head_delta.y * head_delta.y) / (GIRL_HEAD_HIT_RADII.y * GIRL_HEAD_HIT_RADII.y)
	return head_value <= 1.0 or CAT_HIT_RECT.has_point(visual_position)


func _resize_edge_for_position(position: Vector2) -> int:
	var near_left := position.x <= RESIZE_MARGIN
	var near_right := position.x >= size.x - RESIZE_MARGIN
	var near_top := position.y <= RESIZE_MARGIN
	var near_bottom := position.y >= size.y - RESIZE_MARGIN
	if near_top and near_left:
		return DisplayServer.WINDOW_EDGE_TOP_LEFT
	if near_top and near_right:
		return DisplayServer.WINDOW_EDGE_TOP_RIGHT
	if near_bottom and near_left:
		return DisplayServer.WINDOW_EDGE_BOTTOM_LEFT
	if near_bottom and near_right:
		return DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT
	if near_top:
		return DisplayServer.WINDOW_EDGE_TOP
	if near_bottom:
		return DisplayServer.WINDOW_EDGE_BOTTOM
	if near_left:
		return DisplayServer.WINDOW_EDGE_LEFT
	if near_right:
		return DisplayServer.WINDOW_EDGE_RIGHT
	return -1


func _wait_for_actor_animation(actor: Node2D, animation_name: String, timeout_seconds: float) -> bool:
	var deadline_msec := Time.get_ticks_msec() + int(maxf(0.05, timeout_seconds) * 1000.0)
	while str(actor.get("_current_animation")) != animation_name \
			and Time.get_ticks_msec() < deadline_msec:
		await get_tree().create_timer(0.01).timeout
	return str(actor.get("_current_animation")) == animation_name


func _run_action_preview_smoke() -> void:
	await get_tree().create_timer(0.4).timeout
	var window_configured := action_preview_window.force_native \
		and not action_preview_window.transient \
		and action_preview_window.action_button_count() == 16
	var toggle_key := InputEventKey.new()
	toggle_key.pressed = true
	toggle_key.keycode = KEY_T
	toggle_key.physical_keycode = KEY_T
	_input(toggle_key)
	await get_tree().process_frame
	await get_tree().process_frame
	var opened_with_t := action_preview_window.visible
	var preview_rendered := DisplayServer.get_name() == "headless"
	if not preview_rendered:
		var preview_image := action_preview_window.get_texture().get_image()
		preview_rendered = preview_image != null \
			and preview_image.get_size() == action_preview_window.size \
			and preview_image.save_png(ProjectSettings.globalize_path(
				"res://qa/action_preview_window.png"
			)) == OK
	_input(toggle_key)
	await get_tree().process_frame
	var hidden_with_t := not action_preview_window.visible
	var routes_bound := _preview_routes_are_bound()
	var queued := _play_preview_route("stretch")
	var parent_started_first := queued \
		and str(typing_actor.get("_current_animation")) == TYPING_ANIMATION \
		and str(_pending_parent_branch.get("id", "")) == STRETCH_ANIMATION
	var child_started := await _wait_for_actor_animation(
		typing_actor,
		STRETCH_ANIMATION,
		float(typing_actor.call("animation_duration", TYPING_ANIMATION)) + 0.6
	)
	await get_tree().create_timer(
		float(typing_actor.call("animation_duration", STRETCH_ANIMATION)) + 0.15
	).timeout
	var natural_return := str(typing_actor.get("_current_animation")) == TYPING_ANIMATION \
		and _typing_playing and not _stretch_playing
	var ok := window_configured and opened_with_t and preview_rendered and hidden_with_t \
		and routes_bound and parent_started_first and child_started and natural_return
	print("ACTION_PREVIEW_SMOKE native=%s buttons=%d t_open=%s rendered=%s t_hide=%s routes=%s parent_first=%s child=%s natural_return=%s ok=%s" % [
		action_preview_window.force_native,
		action_preview_window.action_button_count(),
		opened_with_t,
		preview_rendered,
		hidden_with_t,
		routes_bound,
		parent_started_first,
		child_started,
		natural_return,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _preview_routes_are_bound() -> bool:
	var queued_routes: Array[Dictionary] = [
		{"id": "typing", "parent": IDLE_ANIMATION, "branch": TYPING_ANIMATION},
		{"id": "startle_idle", "parent": IDLE_ANIMATION, "branch": STARTLE_ANIMATION},
		{"id": "startle_typing", "parent": TYPING_ANIMATION, "branch": STARTLE_ANIMATION},
		{"id": "stretch", "parent": TYPING_ANIMATION, "branch": STRETCH_ANIMATION},
		{"id": "nail_polish", "parent": IDLE_ANIMATION, "branch": NAIL_POLISH_ENTER_ANIMATION},
		{"id": "drink_water", "parent": IDLE_ANIMATION, "branch": DRINK_WATER_ANIMATION},
		{"id": "phone", "parent": IDLE_ANIMATION, "branch": PHONE_ANIMATION},
		{"id": "use_mouse_idle", "parent": IDLE_ANIMATION, "branch": USE_MOUSE_ANIMATION},
		{"id": "use_mouse_typing", "parent": TYPING_ANIMATION, "branch": USE_MOUSE_ANIMATION},
		{"id": "leave_idle", "parent": IDLE_ANIMATION, "branch": LEAVE_ANIMATION},
		{"id": "leave_typing", "parent": TYPING_ANIMATION, "branch": LEAVE_ANIMATION},
	]
	for route in queued_routes:
		if not _play_preview_route(str(route.id)):
			return false
		if str(route.branch) == STARTLE_ANIMATION:
			if str(typing_actor.get("_current_animation")) != STARTLE_ANIMATION \
					or str(yellow_cat.get("_current_animation")) != CAT_STARTLE_ANIMATION \
					or _has_pending_parent_branch():
				return false
		elif str(typing_actor.get("_current_animation")) != str(route.parent) \
				or str(_pending_parent_branch.get("id", "")) != str(route.branch):
			return false
	if not _play_preview_route("idle") \
			or str(typing_actor.get("_current_animation")) != IDLE_ANIMATION:
		return false
	if not _play_preview_route("cat_sleep") \
			or str(yellow_cat.get("_current_animation")) != CAT_SLEEP_ANIMATION:
		return false
	if not _play_preview_route("cat_mischief") \
			or _leave_sequence_stage != LEAVE_STAGE_WAITING_FOR_CAT_SLEEP_LOOP:
		return false
	if not _play_preview_route("come_back") \
			or _leave_sequence_stage != LEAVE_STAGE_MISCHIEF \
			or str(yellow_cat.get("_current_animation")) != CAT_MISCHIEF_ANIMATION:
		return false
	if not _play_preview_route("drink_water_bonus") \
			or _leave_sequence_stage != LEAVE_STAGE_COME_BACK \
			or str(typing_actor.get("_current_animation")) != COME_BACK_ANIMATION:
		return false
	return true


func _run_xsxb_loop_smoke() -> void:
	var parent_gate_entered := await _wait_for_actor_animation(
		typing_actor,
		TYPING_ANIMATION,
		float(typing_actor.call("animation_duration", IDLE_ANIMATION)) + 0.5
	)
	var frame_count := int(typing_actor.call("animation_frame_count", "typing"))
	var duration := float(typing_actor.call("animation_duration", "typing"))
	var first_index := int(typing_actor.get("_current_frame"))
	await get_tree().create_timer(0.44).timeout
	var advanced_index := int(typing_actor.get("_current_frame"))
	await get_tree().create_timer(2.4).timeout
	var wrapped_index := int(typing_actor.get("_current_frame"))
	var advanced := advanced_index > first_index
	var wrapped := wrapped_index < advanced_index
	var metadata_ok := frame_count == 15 and is_equal_approx(duration, 2.64)
	var ok := parent_gate_entered and advanced and wrapped and metadata_ok
	print("XSXB_LOOP_SMOKE frames=%d duration=%.3f first=%d advanced=%d wrapped=%d scale=%.3f ok=%s" % [
		frame_count,
		duration,
		first_index,
		advanced_index,
		wrapped_index,
		_typing_scene_scale,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_xsxb_lazy_cache_smoke() -> void:
	await get_tree().process_frame
	var startup_texture_bytes: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	var startup_girl_groups: int = int(typing_actor.call("loaded_animation_group_count"))
	var startup_cat_groups: int = int(yellow_cat.call("loaded_animation_group_count"))
	typing_actor.call("play_frame_animation", IDLE_ANIMATION, true, true)
	typing_actor.call("play_frame_animation", TYPING_ANIMATION, true, true)
	typing_actor.call("play_frame_animation", STRETCH_ANIMATION, false, true)
	yellow_cat.call("play_frame_animation", CAT_SLEEP_ANIMATION, true, true)
	yellow_cat.call("play_frame_animation", CAT_STARTLE_ANIMATION, false, true)
	yellow_cat.call("play_frame_animation", CAT_MISCHIEF_ANIMATION, true, true)
	await get_tree().process_frame
	var switched_texture_bytes: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	var girl_groups: int = int(typing_actor.call("loaded_animation_group_count"))
	var cat_groups: int = int(yellow_cat.call("loaded_animation_group_count"))
	var girl_ids: Array = typing_actor.call("loaded_animation_group_ids") as Array
	var cat_ids: Array = yellow_cat.call("loaded_animation_group_ids") as Array
	var girl_sprite: Sprite2D = typing_actor.get_node("VisualOwner/FrameSprite") as Sprite2D
	var cat_sprite: Sprite2D = yellow_cat.get_node("VisualOwner/FrameSprite") as Sprite2D
	var metadata_ok := int(typing_actor.call("animation_frame_count", IDLE_ANIMATION)) == 7 \
		and int(typing_actor.call("animation_frame_count", TYPING_ANIMATION)) == 15 \
		and int(yellow_cat.call("animation_frame_count", CAT_SLEEP_ANIMATION)) == 13
	var girl_cache_ok := girl_groups == 2 \
		and bool(typing_actor.call("is_animation_group_loaded", TYPING_ANIMATION)) \
		and bool(typing_actor.call("is_animation_group_loaded", STRETCH_ANIMATION)) \
		and not bool(typing_actor.call("is_animation_group_loaded", IDLE_ANIMATION))
	var cat_cache_ok := cat_groups == 2 \
		and bool(yellow_cat.call("is_animation_group_loaded", CAT_STARTLE_ANIMATION)) \
		and bool(yellow_cat.call("is_animation_group_loaded", CAT_MISCHIEF_ANIMATION)) \
		and not bool(yellow_cat.call("is_animation_group_loaded", CAT_SLEEP_ANIMATION))
	var visuals_ok := girl_sprite.texture != null and cat_sprite.texture != null \
		and girl_sprite.visible and cat_sprite.visible
	var ok := startup_girl_groups <= 2 and startup_cat_groups <= 2 \
		and metadata_ok and girl_cache_ok and cat_cache_ok and visuals_ok
	print("XSXB_LAZY_CACHE_SMOKE startup_girl=%d startup_cat=%d girl=%s cat=%s loaded_frames=%d/%d texture_mib=%.1f->%.1f ok=%s" % [
		startup_girl_groups,
		startup_cat_groups,
		girl_ids,
		cat_ids,
		int(typing_actor.call("loaded_animation_frame_count")),
		int(yellow_cat.call("loaded_animation_frame_count")),
		float(startup_texture_bytes) / 1048576.0,
		float(switched_texture_bytes) / 1048576.0,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_linked_startle_smoke() -> void:
	await get_tree().process_frame
	var girl_frames := int(typing_actor.call("animation_frame_count", STARTLE_ANIMATION))
	var girl_duration := float(typing_actor.call("animation_duration", STARTLE_ANIMATION))
	var cat_frames := int(yellow_cat.call("animation_frame_count", CAT_STARTLE_ANIMATION))
	var cat_duration := float(yellow_cat.call("animation_duration", CAT_STARTLE_ANIMATION))
	var sleep_frames := int(yellow_cat.call("animation_frame_count", CAT_SLEEP_ANIMATION))
	var idle_duration := float(typing_actor.call("animation_duration", IDLE_ANIMATION))
	var hit_regions_ok := _is_startle_click_target(GIRL_HEAD_HIT_CENTER) \
		and _is_startle_click_target(CAT_HIT_RECT.get_center()) \
		and not _is_startle_click_target(Vector2(1000.0, 700.0))
	var idle_branch_was_pending := _queue_parent_branch(
		TYPING_ANIMATION,
		IDLE_ANIMATION
	)
	var cat_click := InputEventMouseButton.new()
	cat_click.button_index = MOUSE_BUTTON_LEFT
	cat_click.pressed = true
	cat_click.position = _visual_to_surface_position(CAT_HIT_RECT.get_center())
	_on_window_surface_gui_input(cat_click)
	var idle_interrupted_immediately := str(typing_actor.get("_current_animation")) == STARTLE_ANIMATION \
		and str(yellow_cat.get("_current_animation")) == CAT_STARTLE_ANIMATION \
		and int(typing_actor.get("_current_frame")) == 0 \
		and int(yellow_cat.get("_current_frame")) == 0 \
		and not _has_pending_parent_branch()
	var repeat_blocked := not trigger_startle()
	await get_tree().create_timer(cat_duration + 0.12).timeout
	var cat_slept_after_own_finish := str(yellow_cat.get("_current_animation")) == CAT_SLEEP_ANIMATION \
		and str(typing_actor.get("_current_animation")) == STARTLE_ANIMATION
	await get_tree().create_timer(maxf(0.1, girl_duration - cat_duration) + 0.2).timeout
	var idle_restored := str(typing_actor.get("_current_animation")) == IDLE_ANIMATION \
		and str(yellow_cat.get("_current_animation")) == CAT_SLEEP_ANIMATION and _idle_playing
	var typing_queued := _trigger_typing_branch()
	var typing_gate_released := await _wait_for_actor_animation(
		typing_actor, TYPING_ANIMATION, idle_duration + 0.5
	)
	var typing_branch_was_pending := _queue_parent_branch(
		STRETCH_ANIMATION,
		TYPING_ANIMATION
	)
	var head_click := InputEventMouseButton.new()
	head_click.button_index = MOUSE_BUTTON_LEFT
	head_click.pressed = true
	head_click.position = _visual_to_surface_position(GIRL_HEAD_HIT_CENTER)
	_on_window_surface_gui_input(head_click)
	var typing_interrupted_immediately := str(typing_actor.get("_current_animation")) == STARTLE_ANIMATION \
		and str(yellow_cat.get("_current_animation")) == CAT_STARTLE_ANIMATION \
		and int(typing_actor.get("_current_frame")) == 0 \
		and int(yellow_cat.get("_current_frame")) == 0 \
		and not _has_pending_parent_branch()
	await get_tree().create_timer(girl_duration + 0.25).timeout
	var typing_restored := str(typing_actor.get("_current_animation")) == TYPING_ANIMATION \
		and str(yellow_cat.get("_current_animation")) == CAT_SLEEP_ANIMATION \
		and _typing_playing and _idle_timer.time_left > 0.0
	var metadata_ok := girl_frames == 21 and is_equal_approx(girl_duration, 3.41) \
		and cat_frames == 21 and is_equal_approx(cat_duration, 2.86) and sleep_frames == 13
	var ok := hit_regions_ok and idle_branch_was_pending and idle_interrupted_immediately \
		and repeat_blocked and cat_slept_after_own_finish \
		and idle_restored and typing_queued and typing_gate_released \
		and typing_branch_was_pending and typing_interrupted_immediately \
		and typing_restored and metadata_ok \
		and not _startle_playing and not _cat_startle_playing
	print("XSXB_LINKED_STARTLE_SMOKE girl=%d/%.3f cat=%d/%.3f hits=%s idle_pending=%s idle_interrupt=%s cat_sleep=%s idle_return=%s typing_pending=%s typing_interrupt=%s typing_return=%s remaining=%.3f ok=%s" % [
		girl_frames,
		girl_duration,
		cat_frames,
		cat_duration,
		hit_regions_ok,
		idle_branch_was_pending,
		idle_interrupted_immediately,
		cat_slept_after_own_finish,
		idle_restored,
		typing_branch_was_pending,
		typing_interrupted_immediately,
		typing_restored,
		_idle_timer.time_left,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_leave_sequence_smoke() -> void:
	await get_tree().create_timer(0.7).timeout
	var leave_frames := int(typing_actor.call("animation_frame_count", LEAVE_ANIMATION))
	var leave_duration := float(typing_actor.call("animation_duration", LEAVE_ANIMATION))
	var sleep_frames := int(yellow_cat.call("animation_frame_count", CAT_SLEEP_ANIMATION))
	var sleep_duration := float(yellow_cat.call("animation_duration", CAT_SLEEP_ANIMATION))
	var mischief_frames := int(yellow_cat.call("animation_frame_count", CAT_MISCHIEF_ANIMATION))
	var mischief_duration := float(yellow_cat.call("animation_duration", CAT_MISCHIEF_ANIMATION))
	var come_back_frames := int(typing_actor.call("animation_frame_count", COME_BACK_ANIMATION))
	var come_back_duration := float(typing_actor.call("animation_duration", COME_BACK_ANIMATION))
	var bonus_frames := int(typing_actor.call("animation_frame_count", DRINK_WATER_BONUS_ANIMATION))
	var bonus_duration := float(typing_actor.call("animation_duration", DRINK_WATER_BONUS_ANIMATION))
	var idle_duration := float(typing_actor.call("animation_duration", IDLE_ANIMATION))
	var typing_duration := float(typing_actor.call("animation_duration", TYPING_ANIMATION))
	var started_from_idle := _trigger_leave_sequence()
	var idle_held_until_parent_end := str(typing_actor.get("_current_animation")) == IDLE_ANIMATION \
		and str(_pending_parent_branch.get("id", "")) == LEAVE_ANIMATION
	var idle_gate_released := await _wait_for_actor_animation(
		typing_actor, LEAVE_ANIMATION, idle_duration + 0.5
	)
	var entered_leave := _leave_sequence_stage == LEAVE_STAGE_LEAVING \
		and str(typing_actor.get("_current_animation")) == LEAVE_ANIMATION \
		and str(yellow_cat.get("_current_animation")) == CAT_SLEEP_ANIMATION
	var repeat_blocked := not _trigger_leave_sequence()
	await get_tree().create_timer(leave_duration + 0.12).timeout
	var held_leave_last_frame := _leave_sequence_stage == LEAVE_STAGE_WAITING_FOR_CAT_SLEEP_LOOP \
		and int(typing_actor.get("_current_frame")) == leave_frames - 1 \
		and str(yellow_cat.get("_current_animation")) == CAT_SLEEP_ANIMATION
	var wait_deadline_msec := Time.get_ticks_msec() + int((sleep_duration + 0.5) * 1000.0)
	while _leave_sequence_stage == LEAVE_STAGE_WAITING_FOR_CAT_SLEEP_LOOP \
			and Time.get_ticks_msec() < wait_deadline_msec:
		await get_tree().create_timer(0.02).timeout
	var whole_scene_replaced := _leave_sequence_stage == LEAVE_STAGE_MISCHIEF \
		and str(yellow_cat.get("_current_animation")) == CAT_MISCHIEF_ANIMATION \
		and not typing_actor.visible and yellow_cat.visible \
		and yellow_cat.z_index > window_room_foreground.z_index \
		and martial_cat_figurine.z_index > yellow_cat.z_index \
		and _cat_sleep_loop_completed_before_mischief
	var waited_for_cat_sleep_loop := _cat_sleep_loop_completed_before_mischief
	var mischief_rendered := DisplayServer.get_name() == "headless"
	if not mischief_rendered:
		await get_tree().process_frame
		await get_tree().process_frame
		var screenshot_path := ProjectSettings.globalize_path("res://qa/leave_sequence_mischief_runtime.png")
		var screenshot_image := visual_viewport.get_texture().get_image()
		var screenshot_result := screenshot_image.save_png(screenshot_path) \
			if screenshot_image != null else ERR_CANT_CREATE
		mischief_rendered = screenshot_result == OK
	await get_tree().create_timer(mischief_duration + 0.15).timeout
	var sleep_and_come_back_started := _leave_sequence_stage == LEAVE_STAGE_COME_BACK \
		and str(yellow_cat.get("_current_animation")) == CAT_SLEEP_ANIMATION \
		and str(typing_actor.get("_current_animation")) == COME_BACK_ANIMATION \
		and yellow_cat.visible and typing_actor.visible and _come_back_started_on_first_frame \
		and martial_cat_figurine.z_index == _martial_cat_figurine_base_z_index
	await get_tree().create_timer(come_back_duration + 0.15).timeout
	var typing_bridged_after_come_back := _leave_sequence_stage == LEAVE_STAGE_TYPING_BEFORE_BONUS \
		and str(typing_actor.get("_current_animation")) == TYPING_ANIMATION \
		and _typing_playing and not _idle_playing \
		and str(yellow_cat.get("_current_animation")) == CAT_SLEEP_ANIMATION
	var bonus_delayed_until_typing_loop := \
		str(typing_actor.get("_current_animation")) != DRINK_WATER_BONUS_ANIMATION
	await get_tree().create_timer(typing_duration + 0.15).timeout
	var bonus_followed_typing_loop := _leave_sequence_stage == LEAVE_STAGE_DRINK_WATER_BONUS \
		and str(typing_actor.get("_current_animation")) == DRINK_WATER_BONUS_ANIMATION \
		and str(yellow_cat.get("_current_animation")) == CAT_SLEEP_ANIMATION
	await get_tree().create_timer(bonus_duration + 0.2).timeout
	var returned_to_typing := _leave_sequence_stage == LEAVE_STAGE_NONE \
		and str(typing_actor.get("_current_animation")) == TYPING_ANIMATION \
		and str(yellow_cat.get("_current_animation")) == CAT_SLEEP_ANIMATION \
		and _typing_playing and not _idle_playing \
		and martial_cat_figurine.z_index == _martial_cat_figurine_base_z_index
	var queued_from_typing := _trigger_leave_sequence()
	var typing_held_until_parent_end := str(typing_actor.get("_current_animation")) == TYPING_ANIMATION \
		and str(_pending_parent_branch.get("id", "")) == LEAVE_ANIMATION
	var typing_gate_released := await _wait_for_actor_animation(
		typing_actor, LEAVE_ANIMATION, typing_duration + 0.5
	)
	var triggered_from_typing := queued_from_typing and typing_gate_released \
		and _leave_sequence_stage == LEAVE_STAGE_LEAVING \
		and str(typing_actor.get("_current_animation")) == LEAVE_ANIMATION
	var metadata_ok := leave_frames == 28 and leave_duration > 0.0 \
		and sleep_frames == 13 and sleep_duration > 0.0 \
		and mischief_frames == 91 and mischief_duration > 0.0 \
		and come_back_frames == 59 and come_back_duration > 0.0 \
		and bonus_frames == 26 and bonus_duration > 0.0
	var ok := started_from_idle and idle_held_until_parent_end and idle_gate_released \
		and entered_leave and repeat_blocked and held_leave_last_frame \
		and whole_scene_replaced and mischief_rendered and sleep_and_come_back_started \
		and typing_bridged_after_come_back and bonus_delayed_until_typing_loop \
		and bonus_followed_typing_loop and returned_to_typing and queued_from_typing \
		and typing_held_until_parent_end and triggered_from_typing \
		and metadata_ok
	print("XSXB_LEAVE_SEQUENCE_SMOKE leave=%d/%.3f sleep=%d/%.3f mischief=%d/%.3f comeback=%d/%.3f bonus=%d/%.3f idle_held=%s idle_start=%s hold=%s waited_loop=%s replaced=%s rendered=%s comeback_sync=%s typing_bridge=%s bonus_delayed=%s bonus_chain=%s typing_return=%s typing_held=%s typing_start=%s ok=%s" % [
		leave_frames,
		leave_duration,
		sleep_frames,
		sleep_duration,
		mischief_frames,
		mischief_duration,
		come_back_frames,
		come_back_duration,
		bonus_frames,
		bonus_duration,
		idle_held_until_parent_end,
		started_from_idle,
		held_leave_last_frame,
		waited_for_cat_sleep_loop,
		whole_scene_replaced,
		mischief_rendered,
		sleep_and_come_back_started,
		typing_bridged_after_come_back,
		bonus_delayed_until_typing_loop,
		bonus_followed_typing_loop,
		returned_to_typing,
		typing_held_until_parent_end,
		triggered_from_typing,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_stretch_smoke() -> void:
	var typing_entered := await _wait_for_actor_animation(
		typing_actor,
		TYPING_ANIMATION,
		float(typing_actor.call("animation_duration", IDLE_ANIMATION)) + 0.5
	)
	await get_tree().create_timer(0.35).timeout
	var typing_held_until_parent_end := str(typing_actor.get("_current_animation")) == TYPING_ANIMATION \
		and str(_pending_parent_branch.get("id", "")) == STRETCH_ANIMATION
	var stretch_gate_released := await _wait_for_actor_animation(
		typing_actor,
		STRETCH_ANIMATION,
		float(typing_actor.call("animation_duration", TYPING_ANIMATION)) + 0.5
	)
	var frame_count := int(typing_actor.call("animation_frame_count", STRETCH_ANIMATION))
	var duration := float(typing_actor.call("animation_duration", STRETCH_ANIMATION))
	var interrupted_typing := str(typing_actor.get("_current_animation")) == STRETCH_ANIMATION
	await get_tree().create_timer(duration + 0.25).timeout
	var returned_to_typing := str(typing_actor.get("_current_animation")) == TYPING_ANIMATION
	var typing_continues := _typing_playing and _idle_timer.time_left > 0.0
	var metadata_ok := frame_count == 15 and is_equal_approx(duration, 2.34)
	var ok := typing_entered and typing_held_until_parent_end and stretch_gate_released \
		and interrupted_typing and returned_to_typing and typing_continues \
		and metadata_ok and _stretch_used_in_typing and not _stretch_playing
	print("XSXB_STRETCH_SMOKE frames=%d duration=%.3f parent_held=%s interrupted=%s returned=%s remaining=%.3f ok=%s" % [
		frame_count,
		duration,
		typing_held_until_parent_end,
		interrupted_typing,
		returned_to_typing,
		_idle_timer.time_left,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_use_mouse_smoke() -> void:
	var completed_idle_cycle := await _wait_for_qa_idle_cycle()
	var frame_count := int(typing_actor.call("animation_frame_count", USE_MOUSE_ANIMATION))
	var duration := float(typing_actor.call("animation_duration", USE_MOUSE_ANIMATION))
	var entered_from_idle := str(typing_actor.get("_current_animation")) == USE_MOUSE_ANIMATION \
		and _use_mouse_playing and not _use_mouse_returns_to_typing
	await get_tree().create_timer(duration + 0.25).timeout
	var returned_to_idle := str(typing_actor.get("_current_animation")) == IDLE_ANIMATION \
		and _idle_playing and not _use_mouse_playing
	var typing_started := _trigger_typing_branch()
	var typing_gate_released := await _wait_for_actor_animation(
		typing_actor,
		TYPING_ANIMATION,
		float(typing_actor.call("animation_duration", IDLE_ANIMATION)) + 0.5
	)
	var mouse_started_from_typing := _trigger_use_mouse()
	var typing_held_until_parent_end := str(typing_actor.get("_current_animation")) == TYPING_ANIMATION \
		and str(_pending_parent_branch.get("id", "")) == USE_MOUSE_ANIMATION
	var mouse_gate_released := await _wait_for_actor_animation(
		typing_actor,
		USE_MOUSE_ANIMATION,
		float(typing_actor.call("animation_duration", TYPING_ANIMATION)) + 0.5
	)
	var entered_from_typing := str(typing_actor.get("_current_animation")) == USE_MOUSE_ANIMATION \
		and _use_mouse_playing and _use_mouse_returns_to_typing
	await get_tree().create_timer(duration + 0.25).timeout
	var returned_to_typing := str(typing_actor.get("_current_animation")) == TYPING_ANIMATION \
		and _typing_playing and _idle_timer.time_left > 0.0 and not _use_mouse_playing
	var metadata_ok := frame_count == 17 and is_equal_approx(duration, 2.42)
	var policy_ok := use_mouse_activity_weight > 0.0
	var ok := completed_idle_cycle and entered_from_idle and returned_to_idle \
		and typing_started and typing_gate_released and mouse_started_from_typing \
		and typing_held_until_parent_end and mouse_gate_released and entered_from_typing \
		and returned_to_typing and metadata_ok and policy_ok
	print("XSXB_USE_MOUSE_SMOKE idle_complete=%s frames=%d duration=%.3f idle_enter=%s idle_return=%s typing_start=%s typing_held=%s typing_enter=%s typing_return=%s remaining=%.3f ok=%s" % [
		completed_idle_cycle,
		frame_count,
		duration,
		entered_from_idle,
		returned_to_idle,
		typing_started,
		typing_held_until_parent_end,
		entered_from_typing,
		returned_to_typing,
		_idle_timer.time_left,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_idle_interleave_smoke() -> void:
	await get_tree().create_timer(0.4).timeout
	var frame_count := int(typing_actor.call("animation_frame_count", IDLE_ANIMATION))
	var duration := float(typing_actor.call("animation_duration", IDLE_ANIMATION))
	var entered_idle := str(typing_actor.get("_current_animation")) == IDLE_ANIMATION
	var first_frame := int(typing_actor.get("_current_frame"))
	await get_tree().create_timer(duration + 0.25).timeout
	var still_idle := str(typing_actor.get("_current_animation")) == IDLE_ANIMATION
	var later_frame := int(typing_actor.get("_current_frame"))
	var metadata_ok := frame_count == 7 and is_equal_approx(duration, 1.21)
	var policy_ok := idle_branch_min_loops == 1 and idle_branch_max_loops == 3 \
		and is_equal_approx(typing_branch_probability, 0.6) \
		and nail_polish_activity_weight > 0.0 and drink_water_activity_weight > 0.0 \
		and phone_activity_weight > 0.0
	var looped_as_base := still_idle and later_frame != first_frame
	var ok := entered_idle and looped_as_base and metadata_ok and policy_ok and _idle_playing
	print("XSXB_IDLE_BASE_SMOKE frames=%d duration=%.3f loops=%d-%d typing_probability=%.0f%% entered=%s persisted=%s first=%d later=%d ok=%s" % [
		frame_count,
		duration,
		idle_branch_min_loops,
		idle_branch_max_loops,
		typing_branch_probability * 100.0,
		entered_idle,
		still_idle,
		first_frame,
		later_frame,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _wait_for_qa_idle_cycle() -> bool:
	var idle_duration := float(typing_actor.call("animation_duration", IDLE_ANIMATION))
	var targeted_one_loop := _idle_loop_target == 1
	await get_tree().create_timer(maxf(0.05, idle_duration - 0.08)).timeout
	var stayed_until_cycle_end := str(typing_actor.get("_current_animation")) == IDLE_ANIMATION \
		and _idle_playing
	await get_tree().create_timer(0.25).timeout
	return targeted_one_loop and stayed_until_cycle_end


func _run_nail_polish_smoke() -> void:
	var completed_idle_cycle := await _wait_for_qa_idle_cycle()
	var enter_frames := int(typing_actor.call("animation_frame_count", NAIL_POLISH_ENTER_ANIMATION))
	var loop_frames := int(typing_actor.call("animation_frame_count", NAIL_POLISH_LOOP_ANIMATION))
	var exit_frames := int(typing_actor.call("animation_frame_count", NAIL_POLISH_EXIT_ANIMATION))
	var enter_duration := float(typing_actor.call("animation_duration", NAIL_POLISH_ENTER_ANIMATION))
	var loop_duration := float(typing_actor.call("animation_duration", NAIL_POLISH_LOOP_ANIMATION))
	var exit_duration := float(typing_actor.call("animation_duration", NAIL_POLISH_EXIT_ANIMATION))
	var entered_sequence := str(typing_actor.get("_current_animation")) == NAIL_POLISH_ENTER_ANIMATION
	var expected_total := enter_duration + loop_duration * 5.0 + exit_duration
	await get_tree().create_timer(expected_total + 0.35).timeout
	var returned_to_idle := str(typing_actor.get("_current_animation")) == IDLE_ANIMATION
	var repeat_blocked := not _trigger_nail_polish()
	var metadata_ok := enter_frames == 23 and loop_frames == 5 and exit_frames == 22 \
		and is_equal_approx(enter_duration, 2.64) and is_equal_approx(loop_duration, 1.44) \
		and is_equal_approx(exit_duration, 2.86)
	var loop_count_ok := _nail_polish_loop_target == 5 and _nail_polish_loop_completed == 5
	var ok := completed_idle_cycle and entered_sequence and returned_to_idle \
		and repeat_blocked and metadata_ok and loop_count_ok and not _nail_polish_playing
	print("XSXB_NAIL_POLISH_SMOKE idle_complete=%s repeat_blocked=%s enter=%d loop=%d exit=%d loops=%d total=%.3f returned=%s ok=%s" % [
		completed_idle_cycle,
		repeat_blocked,
		enter_frames,
		loop_frames,
		exit_frames,
		_nail_polish_loop_completed,
		expected_total,
		returned_to_idle,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_drink_water_smoke() -> void:
	var completed_idle_cycle := await _wait_for_qa_idle_cycle()
	var frame_count := int(typing_actor.call("animation_frame_count", DRINK_WATER_ANIMATION))
	var duration := float(typing_actor.call("animation_duration", DRINK_WATER_ANIMATION))
	var entered_sequence := str(typing_actor.get("_current_animation")) == DRINK_WATER_ANIMATION
	await get_tree().create_timer(duration + 0.25).timeout
	var returned_to_idle := str(typing_actor.get("_current_animation")) == IDLE_ANIMATION
	var repeat_blocked := not _trigger_drink_water()
	var metadata_ok := frame_count == 23 and duration > 0.0
	var ok := completed_idle_cycle and entered_sequence and returned_to_idle \
		and repeat_blocked and metadata_ok and not _drink_water_playing
	print("XSXB_DRINK_WATER_SMOKE idle_complete=%s repeat_blocked=%s frames=%d duration=%.3f entered=%s returned_idle=%s ok=%s" % [
		completed_idle_cycle,
		repeat_blocked,
		frame_count,
		duration,
		entered_sequence,
		returned_to_idle,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_phone_smoke() -> void:
	var completed_idle_cycle := await _wait_for_qa_idle_cycle()
	var frame_count := int(typing_actor.call("animation_frame_count", PHONE_ANIMATION))
	var duration := float(typing_actor.call("animation_duration", PHONE_ANIMATION))
	var entered_sequence := str(typing_actor.get("_current_animation")) == PHONE_ANIMATION
	await get_tree().create_timer(duration + 0.25).timeout
	var returned_to_idle := str(typing_actor.get("_current_animation")) == IDLE_ANIMATION
	var repeat_blocked := not _trigger_phone()
	var cross_activity_allowed := _trigger_drink_water()
	var metadata_ok := frame_count == 24 and duration > 0.0
	var ok := completed_idle_cycle and entered_sequence and returned_to_idle \
		and repeat_blocked and cross_activity_allowed and metadata_ok and not _phone_playing
	print("XSXB_PHONE_SMOKE idle_complete=%s repeat_blocked=%s cross_allowed=%s frames=%d duration=%.3f entered=%s returned_idle=%s ok=%s" % [
		completed_idle_cycle,
		repeat_blocked,
		cross_activity_allowed,
		frame_count,
		duration,
		entered_sequence,
		returned_to_idle,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_yellow_cat_smoke() -> void:
	await get_tree().process_frame
	var frame_count := int(yellow_cat.call("animation_frame_count", "sleep"))
	var duration := float(yellow_cat.call("animation_duration", "sleep"))
	var started_sleeping := str(yellow_cat.get("_current_animation")) == "sleep"
	var first_frame := int(yellow_cat.get("_current_frame"))
	await get_tree().create_timer(0.55).timeout
	var advanced_frame := int(yellow_cat.get("_current_frame"))
	await get_tree().create_timer(2.75).timeout
	var wrapped_frame := int(yellow_cat.get("_current_frame"))
	var layered_behind := yellow_cat.get_parent() == typing_actor.get_parent() \
		and yellow_cat.z_index < typing_actor.z_index
	var room_layering_ok := window_exterior_background.texture != null \
		and window_exterior_video.stream != null \
		and window_exterior_video.autoplay and window_exterior_video.loop \
		and window_room_background.texture != null \
		and window_room_foreground.texture != null \
		and window_exterior_background.texture.get_size() == Vector2(1112, 834) \
		and window_room_background.texture.get_size() == Vector2(1112, 834) \
		and window_room_foreground.texture.get_size() == Vector2(1112, 834) \
		and window_exterior_background.z_index < window_exterior_video.z_index \
		and window_exterior_video.z_index < window_room_background.z_index \
		and window_room_background.z_index < yellow_cat.z_index \
		and yellow_cat.z_index < window_room_foreground.z_index \
		and window_room_foreground.get_index() < typing_actor.get_index()
	var metadata_ok := frame_count == 13 and is_equal_approx(duration, 2.981)
	var looped := advanced_frame > first_frame and wrapped_frame < advanced_frame
	var ok := started_sleeping and looped and layered_behind and room_layering_ok and metadata_ok \
		and bool(yellow_cat.get("loop_animation")) and not bool(yellow_cat.get("use_frame_boxes"))
	print("XSXB_YELLOW_CAT_SMOKE frames=%d duration=%.3f first=%d advanced=%d wrapped=%d behind=%s room_layers=%s ok=%s" % [
		frame_count,
		duration,
		first_frame,
		advanced_frame,
		wrapped_frame,
		layered_behind,
		room_layering_ok,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _capture_music_ui() -> void:
	await get_tree().create_timer(1.0).timeout
	var output_path := ProjectSettings.globalize_path("res://qa/music_ui_simplified.png")
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		print("MUSIC_UI_SMOKE render_texture=false")
		get_tree().quit(1)
		return
	var image := viewport_texture.get_image()
	if image == null:
		print("MUSIC_UI_SMOKE render_image=false")
		get_tree().quit(1)
		return
	var save_result := image.save_png(output_path)
	var playlist_names_ok := music_panel.playlist_buttons.size() == 3 \
		and music_panel.playlist_buttons[0].text == "雨夜伏案" \
		and music_panel.playlist_buttons[1].text == "午后咖啡" \
		and music_panel.playlist_buttons[2].text == "深夜黄猫"
	var single_pool_ok: bool = music_panel.manager.stations.size() == 1 \
		and music_panel.playlist_buttons.is_empty() \
		and not music_panel.get_node("Margin/Layout/PlaylistOne").visible \
		and not music_panel.get_node("Margin/Layout/PlaylistTwo").visible \
		and not music_panel.get_node("Margin/Layout/PlaylistThree").visible
	var controls_ok := music_panel.music_volume_slider.visible \
		and music_panel.sfx_volume_slider.visible \
		and music_panel.now_playing_label.visible \
		and music_panel.artist_label.visible \
		and music_panel.source_button.visible \
		and music_panel.play_button.visible
	var utility_row := music_panel.get_node("Margin/Layout/UtilityRow")
	var source_layout_ok := music_panel.source_button.get_parent() == utility_row \
		and music_panel.play_button.get_parent() == utility_row \
		and music_panel.source_button.get_index() < music_panel.play_button.get_index()
	music_panel.source_button.pressed.emit()
	await get_tree().process_frame
	var source_dialog_ok: bool = music_panel.source_dialog.visible \
		and music_panel.source_text.text.contains("Rain Music Radio") \
		and music_panel.get_node("SourceDialog/SourceMargin/SourceContent/SourceNotice").text.contains("游戏不内置")
	var source_content := music_panel.get_node("SourceDialog/SourceMargin/SourceContent") as Control
	var source_padding_ok: bool = source_content.position.x >= 24.0 \
		and source_content.position.y >= 20.0 \
		and source_content.size.x <= music_panel.source_dialog.size.x - 48.0 \
		and _source_dialog_has_safe_spacing()
	var source_dialog_image := get_viewport().get_texture().get_image()
	var source_dialog_capture := source_dialog_image.save_png(
		ProjectSettings.globalize_path("res://qa/source_dialog_styled.png")
	) if source_dialog_image != null else ERR_CANT_CREATE
	music_panel.source_dialog.hide()
	music_panel.get_node("Margin/Layout/UtilityRow/PowerButton").pressed.emit()
	await get_tree().process_frame
	var close_dialog_ok: bool = music_panel.close_confirmation.visible \
		and music_panel.get_node("CloseConfirmation/CloseMargin/CloseContent/CloseQuestion").text == "你要走了吗？" \
		and music_panel.get_node("CloseConfirmation/CloseMargin/CloseContent/CloseButtons/CloseYesButton").text == "是" \
		and music_panel.get_node("CloseConfirmation/CloseMargin/CloseContent/CloseButtons/CloseNoButton").text == "否"
	var close_content := music_panel.get_node("CloseConfirmation/CloseMargin/CloseContent") as Control
	var close_padding_ok: bool = close_content.position.x >= 24.0 \
		and close_content.position.y >= 22.0 \
		and close_content.size.x <= music_panel.close_confirmation.size.x - 48.0
	var close_dialog_image := get_viewport().get_texture().get_image()
	var close_dialog_capture := close_dialog_image.save_png(
		ProjectSettings.globalize_path("res://qa/close_dialog_styled.png")
	) if close_dialog_image != null else ERR_CANT_CREATE
	music_panel.close_confirmation.hide()
	music_panel.now_playing_label.text = "Running Through the Quiet City After Midnight — Extended Jazzhop Session"
	music_panel.call("_configure_title_marquee")
	await get_tree().create_timer(1.4).timeout
	var marquee_ok := music_panel.now_playing_clip.clip_contents \
		and music_panel.now_playing_label.size.x > music_panel.now_playing_clip.size.x \
		and music_panel.now_playing_label.position.x < 0.0
	print("MUSIC_UI_SMOKE playlists=%s controls=%s source_layout=%s source_dialog=%s source_padding=%s close_dialog=%s close_padding=%s marquee=%s screenshot=%s result=%d source_capture=%d close_capture=%d" % [
		playlist_names_ok,
		controls_ok,
		source_layout_ok,
		source_dialog_ok,
		source_padding_ok,
		close_dialog_ok,
		close_padding_ok,
		marquee_ok,
		output_path,
		save_result,
		source_dialog_capture,
		close_dialog_capture,
	])
	music_panel.manager.stop()
	print("MUSIC_UI_SINGLE_POOL pool=%s artist=%s" % [single_pool_ok, music_panel.artist_label.text])
	get_tree().quit(0 if single_pool_ok and controls_ok and source_layout_ok \
		and source_dialog_ok and source_padding_ok and close_dialog_ok and close_padding_ok \
		and marquee_ok and save_result == OK \
		and source_dialog_capture == OK and close_dialog_capture == OK else 1)


func _capture_background_scene() -> void:
	await get_tree().create_timer(1.0).timeout
	var output_path := ProjectSettings.globalize_path("res://qa/window_room_runtime.png")
	var image := get_viewport().get_texture().get_image()
	var save_result := image.save_png(output_path) if image != null else ERR_CANT_CREATE
	var layering_ok := window_exterior_background.texture != null \
		and window_exterior_video.stream != null \
		and window_exterior_video.autoplay and window_exterior_video.loop \
		and window_exterior_video.is_playing() \
		and window_room_background.texture != null \
		and window_room_foreground.texture != null \
		and window_exterior_background.z_index < window_exterior_video.z_index \
		and window_exterior_video.z_index < window_room_background.z_index \
		and window_room_background.z_index < yellow_cat.z_index \
		and yellow_cat.z_index < window_room_foreground.z_index \
		and window_room_foreground.get_index() < typing_actor.get_index()
	print("WINDOW_ROOM_SMOKE layering=%s screenshot=%s result=%d" % [
		layering_ok,
		output_path,
		save_result,
	])
	get_tree().quit(0 if layering_ok and save_result == OK else 1)


func _run_exterior_video_smoke() -> void:
	await get_tree().create_timer(0.6).timeout
	var first_image := visual_viewport.get_texture().get_image()
	var first_path := ProjectSettings.globalize_path("res://qa/window_exterior_video_frame_a.png")
	var first_result := first_image.save_png(first_path) if first_image != null else ERR_CANT_CREATE
	var first_data := first_image.get_region(Rect2i(244, 0, 686, 240)).get_data() \
		if first_image != null else PackedByteArray()
	var first_tree_data := first_image.get_region(Rect2i(244, 150, 686, 180)).get_data() \
		if first_image != null else PackedByteArray()
	await get_tree().create_timer(0.8).timeout
	var second_image := visual_viewport.get_texture().get_image()
	var second_path := ProjectSettings.globalize_path("res://qa/window_exterior_video_frame_b.png")
	var second_result := second_image.save_png(second_path) if second_image != null else ERR_CANT_CREATE
	var second_data := second_image.get_region(Rect2i(244, 0, 686, 240)).get_data() \
		if second_image != null else PackedByteArray()
	var second_tree_data := second_image.get_region(Rect2i(244, 150, 686, 180)).get_data() \
		if second_image != null else PackedByteArray()
	var frames_changed := not first_data.is_empty() and first_data != second_data
	var tree_region_changed := not first_tree_data.is_empty() \
		and first_tree_data != second_tree_data
	var ok := window_exterior_video.stream != null \
		and window_exterior_video.autoplay and window_exterior_video.loop \
		and window_exterior_video.is_playing() and frames_changed and tree_region_changed \
		and first_result == OK and second_result == OK
	print("WINDOW_EXTERIOR_VIDEO_SMOKE playing=%s loop=%s changed=%s tree_changed=%s first=%s second=%s ok=%s" % [
		window_exterior_video.is_playing(),
		window_exterior_video.loop,
		frames_changed,
		tree_region_changed,
		first_path,
		second_path,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_rain_event_smoke() -> void:
	var output_directory := ProjectSettings.globalize_path("res://qa/rain_event")
	DirAccess.make_dir_recursive_absolute(output_directory)
	_start_rain_event(true)
	await get_tree().create_timer(0.45).timeout
	var rain_material := window_rain.material as ShaderMaterial
	var rain_intensity := float(rain_material.get_shader_parameter("intensity")) \
		if rain_material != null else 0.0
	var rain_image := visual_viewport.get_texture().get_image()
	var rain_path := output_directory.path_join("rain_runtime.png")
	var rain_result := rain_image.save_png(rain_path) if rain_image != null else ERR_CANT_CREATE
	var rain_ok := _rain_active and rain_intensity >= 0.99 and rain_audio.is_playing() \
		and rain_audio.stream is AudioStreamMP3 \
		and (rain_audio.stream as AudioStreamMP3).loop \
		and window_rain.z_index == window_exterior_video.z_index \
		and window_rain.get_index() > window_exterior_video.get_index() \
		and window_rain.z_index < window_room_background.z_index

	_enter_idle_base(false)
	var thunder_started := _trigger_thunder(true)
	await get_tree().create_timer(0.07).timeout
	var flash_visible := window_lightning_flash.color.a > 0.02 \
		and room_lightning_flash.color.a > 0.005
	var flash_image := visual_viewport.get_texture().get_image()
	var flash_path := output_directory.path_join("thunder_flash_runtime.png")
	var flash_result := flash_image.save_png(flash_path) \
		if flash_image != null else ERR_CANT_CREATE
	await get_tree().create_timer(0.38).timeout
	var audio_ok := thunder_audio.is_playing() and thunder_audio.stream in THUNDER_STREAMS \
		and thunder_audio.stream is AudioStreamMP3
	await get_tree().create_timer(0.32).timeout
	var girl_startled := str(typing_actor.get("_current_animation")) == STARTLE_ANIMATION
	var cat_startled := str(yellow_cat.get("_current_animation")) == CAT_STARTLE_ANIMATION
	var startled_image := visual_viewport.get_texture().get_image()
	var startled_path := output_directory.path_join("thunder_startle_runtime.png")
	var startled_result := startled_image.save_png(startled_path) \
		if startled_image != null else ERR_CANT_CREATE
	var ok := rain_ok and thunder_started and flash_visible and girl_startled and cat_startled \
		and audio_ok and rain_result == OK and flash_result == OK and startled_result == OK
	print("RAIN_EVENT_SMOKE rain=%s intensity=%.2f rain_audio=%s thunder=%s flash=%s girl=%s cat=%s thunder_audio=%s rain_shot=%s flash_shot=%s startle_shot=%s ok=%s" % [
		_rain_active,
		rain_intensity,
		rain_audio.is_playing(),
		thunder_started,
		flash_visible,
		girl_startled,
		cat_startled,
		audio_ok,
		rain_path,
		flash_path,
		startled_path,
		ok,
	])
	_stop_rain_event(true)
	thunder_audio.stop()
	get_tree().quit(0 if ok else 1)


func _run_room_enrichment_smoke() -> void:
	await get_tree().create_timer(0.45).timeout
	var texture_size := trailing_pothos.texture.get_size() if trailing_pothos.texture != null \
		else Vector2.ZERO
	var prop_rect := Rect2(trailing_pothos.position - texture_size * 0.5, texture_size)
	var safe_corner := prop_rect.position.x >= 40.0 and prop_rect.end.x <= 170.0 \
		and prop_rect.position.y <= 0.0 and prop_rect.end.y <= 160.0
	var layering_ok := trailing_pothos.z_index < typing_actor.z_index \
		and trailing_pothos.get_index() < yellow_cat.get_index() \
		and prop_rect.end.x < window_exterior_video.offset_left
	var bag_texture_size := cat_food_bag.texture.get_size() if cat_food_bag.texture != null \
		else Vector2.ZERO
	var bag_image := cat_food_bag.texture.get_image() if cat_food_bag.texture != null else null
	var bag_used_rect := bag_image.get_used_rect() if bag_image != null else Rect2i()
	var bag_rect := Rect2(
		cat_food_bag.position + (Vector2(bag_used_rect.position) - bag_texture_size * 0.5) \
			* cat_food_bag.scale,
		Vector2(bag_used_rect.size) * cat_food_bag.scale.abs()
	)
	var bag_floor_safe := bag_rect.position.x >= 820.0 and bag_rect.end.x <= 1045.0 \
		and bag_rect.position.y >= 580.0 and bag_rect.end.y >= 778.0 \
		and bag_rect.end.y <= 790.0
	var bag_layering_ok := cat_food_bag.z_index < window_room_foreground.z_index \
		and cat_food_bag.get_index() < window_room_foreground.get_index()
	var bag_asset_ok := cat_food_bag.texture != null \
		and cat_food_bag.texture.resource_path.ends_with("黄猫猫粮袋_透明.png")
	var bowl_texture_size := elevated_cat_bowl.texture.get_size() \
		if elevated_cat_bowl.texture != null else Vector2.ZERO
	var bowl_image := elevated_cat_bowl.texture.get_image() \
		if elevated_cat_bowl.texture != null else null
	var bowl_used_rect := bowl_image.get_used_rect() if bowl_image != null else Rect2i()
	var bowl_rect := Rect2(
		elevated_cat_bowl.position \
			+ (Vector2(bowl_used_rect.position) - bowl_texture_size * 0.5) \
			* elevated_cat_bowl.scale,
		Vector2(bowl_used_rect.size) * elevated_cat_bowl.scale.abs()
	)
	var bowl_floor_safe := bowl_rect.position.x >= 700.0 and bowl_rect.end.x < bag_rect.position.x \
		and bowl_rect.position.y >= 670.0 and bowl_rect.end.y >= 780.0 \
		and bowl_rect.end.y <= 795.0
	var bowl_asset_ok := elevated_cat_bowl.texture != null \
		and elevated_cat_bowl.texture.resource_path.ends_with("垫高猫粮碗_透明.png")
	var floor_prop_material := cat_food_bag.material as ShaderMaterial
	var prop_grade_ok := floor_prop_material != null \
		and elevated_cat_bowl.material == cat_food_bag.material \
		and float(floor_prop_material.get_shader_parameter("saturation")) < 0.8 \
		and float(floor_prop_material.get_shader_parameter("exposure")) < 0.9
	var shadows_ok := cat_food_bag_shadow.points.size() == 2 \
		and cat_food_bag_rear_shadow.points.size() == 2 \
		and cat_food_bag_shadow.width <= 3.0 \
		and cat_food_bag_rear_shadow.width <= 3.0 \
		and cat_food_bag_shadow.default_color.a > 0.0 \
		and cat_food_bag_shadow.default_color.a < 0.4 \
		and cat_food_bag_rear_shadow.default_color.a > 0.0 \
		and cat_food_bag_rear_shadow.default_color.a < 0.4 \
		and cat_bowl_shadow.polygon.size() == 4 \
		and cat_bowl_left_shadow.polygon.size() == 4 \
		and cat_bowl_right_shadow.polygon.size() == 4 \
		and cat_bowl_shadow.color.a > 0.0 and cat_bowl_shadow.color.a < 0.4 \
		and cat_bowl_left_shadow.color.a > 0.0 and cat_bowl_left_shadow.color.a < 0.4 \
		and cat_bowl_right_shadow.color.a > 0.0 and cat_bowl_right_shadow.color.a < 0.4 \
		and rose_pot_shadow.texture != null \
		and cat_food_bag_shadow.z_index <= cat_food_bag.z_index \
		and cat_bowl_shadow.z_index <= elevated_cat_bowl.z_index \
		and rose_pot_shadow.z_index < rose_pot_base.z_index \
		and cat_bowl_shadow.position.y >= 784.0 \
		and cat_bowl_left_shadow.position.y >= 768.0 \
		and cat_bowl_right_shadow.position.y >= 768.0 \
		and rose_pot_shadow.self_modulate.a > 0.0
	var output_path := ProjectSettings.globalize_path("res://qa/room_enrichment_runtime.png")
	var grounding_path := ProjectSettings.globalize_path(
		"res://qa/room_enrichment_grounding_runtime.png"
	)
	var image := visual_viewport.get_texture().get_image()
	var save_result := image.save_png(output_path) if image != null else ERR_CANT_CREATE
	var grounding_image := image.get_region(Rect2i(690, 590, 390, 244)) \
		if image != null else null
	var grounding_result := grounding_image.save_png(grounding_path) \
		if grounding_image != null else ERR_CANT_CREATE
	var ok := trailing_pothos.texture != null and safe_corner and layering_ok \
		and bag_floor_safe and bag_layering_ok and bag_asset_ok \
		and bowl_floor_safe and bowl_asset_ok and prop_grade_ok and shadows_ok \
		and save_result == OK and grounding_result == OK
	print("ROOM_ENRICHMENT_SMOKE plant=%s plant_safe=%s behind_actors=%s bag=%s bag_safe=%s bag_layer=%s bowl=%s bowl_safe=%s grade=%s shadows=%s screenshot=%s grounding=%s ok=%s" % [
		prop_rect,
		safe_corner,
		layering_ok,
		bag_rect,
		bag_floor_safe,
		bag_layering_ok,
		bowl_rect,
		bowl_floor_safe,
		prop_grade_ok,
		shadows_ok,
		output_path,
		grounding_path,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_room_enrichment_half_size_comparison() -> void:
	await get_tree().create_timer(0.45).timeout
	var output_directory := ProjectSettings.globalize_path("res://qa")
	DirAccess.make_dir_recursive_absolute(output_directory)
	var original_path := output_directory.path_join(
		"room_enrichment_original_size_runtime.png"
	)
	var half_path := output_directory.path_join(
		"room_enrichment_half_size_runtime.png"
	)
	var comparison_path := output_directory.path_join(
		"room_enrichment_size_comparison_runtime.png"
	)

	var original_image := visual_viewport.get_texture().get_image()
	var original_result := original_image.save_png(original_path) \
		if original_image != null else ERR_CANT_CREATE
	if original_image == null or original_result != OK:
		push_error("Could not capture original enrichment scale")
		get_tree().quit(1)
		return

	var bag_rect := _opaque_sprite_rect(cat_food_bag)
	var bowl_rect := _opaque_sprite_rect(elevated_cat_bowl)
	var bag_pivot := Vector2(cat_food_bag.position.x, bag_rect.end.y)
	var bowl_pivot := Vector2(elevated_cat_bowl.position.x, bowl_rect.end.y)

	var original_bag_position := cat_food_bag.position
	var original_bag_scale := cat_food_bag.scale
	var original_bag_shadow_points := cat_food_bag_shadow.points.duplicate()
	var original_bag_shadow_width := cat_food_bag_shadow.width
	var original_bag_rear_points := cat_food_bag_rear_shadow.points.duplicate()
	var original_bag_rear_width := cat_food_bag_rear_shadow.width
	var original_bowl_position := elevated_cat_bowl.position
	var original_bowl_scale := elevated_cat_bowl.scale
	var original_bowl_shadow_position := cat_bowl_shadow.position
	var original_bowl_shadow_scale := cat_bowl_shadow.scale
	var original_bowl_left_position := cat_bowl_left_shadow.position
	var original_bowl_left_scale := cat_bowl_left_shadow.scale
	var original_bowl_right_position := cat_bowl_right_shadow.position
	var original_bowl_right_scale := cat_bowl_right_shadow.scale

	cat_food_bag.position = bag_pivot + (cat_food_bag.position - bag_pivot) * 0.5
	cat_food_bag.scale *= 0.5
	cat_food_bag_shadow.points = _scaled_points_around(
		cat_food_bag_shadow.points, bag_pivot, 0.5
	)
	cat_food_bag_shadow.width *= 0.5
	cat_food_bag_rear_shadow.points = _scaled_points_around(
		cat_food_bag_rear_shadow.points, bag_pivot, 0.5
	)
	cat_food_bag_rear_shadow.width *= 0.5

	elevated_cat_bowl.position = bowl_pivot \
		+ (elevated_cat_bowl.position - bowl_pivot) * 0.5
	elevated_cat_bowl.scale *= 0.5
	cat_bowl_shadow.position = bowl_pivot \
		+ (cat_bowl_shadow.position - bowl_pivot) * 0.5
	cat_bowl_shadow.scale *= 0.5
	cat_bowl_left_shadow.position = bowl_pivot \
		+ (cat_bowl_left_shadow.position - bowl_pivot) * 0.5
	cat_bowl_left_shadow.scale *= 0.5
	cat_bowl_right_shadow.position = bowl_pivot \
		+ (cat_bowl_right_shadow.position - bowl_pivot) * 0.5
	cat_bowl_right_shadow.scale *= 0.5

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var half_image := visual_viewport.get_texture().get_image()
	var half_result := half_image.save_png(half_path) \
		if half_image != null else ERR_CANT_CREATE

	cat_food_bag.position = original_bag_position
	cat_food_bag.scale = original_bag_scale
	cat_food_bag_shadow.points = original_bag_shadow_points
	cat_food_bag_shadow.width = original_bag_shadow_width
	cat_food_bag_rear_shadow.points = original_bag_rear_points
	cat_food_bag_rear_shadow.width = original_bag_rear_width
	elevated_cat_bowl.position = original_bowl_position
	elevated_cat_bowl.scale = original_bowl_scale
	cat_bowl_shadow.position = original_bowl_shadow_position
	cat_bowl_shadow.scale = original_bowl_shadow_scale
	cat_bowl_left_shadow.position = original_bowl_left_position
	cat_bowl_left_shadow.scale = original_bowl_left_scale
	cat_bowl_right_shadow.position = original_bowl_right_position
	cat_bowl_right_shadow.scale = original_bowl_right_scale

	var comparison_result := ERR_CANT_CREATE
	if half_image != null:
		var comparison := Image.create(
			original_image.get_width() * 2,
			original_image.get_height(),
			false,
			Image.FORMAT_RGBA8
		)
		comparison.blit_rect(
			original_image,
			Rect2i(Vector2i.ZERO, original_image.get_size()),
			Vector2i.ZERO
		)
		comparison.blit_rect(
			half_image,
			Rect2i(Vector2i.ZERO, half_image.get_size()),
			Vector2i(original_image.get_width(), 0)
		)
		comparison_result = comparison.save_png(comparison_path)

	var ok := original_result == OK and half_result == OK and comparison_result == OK \
		and cat_food_bag.scale.is_equal_approx(original_bag_scale) \
		and elevated_cat_bowl.scale.is_equal_approx(original_bowl_scale)
	print("ROOM_ENRICHMENT_SIZE_COMPARISON original=%s half=%s comparison=%s restored=%s ok=%s" % [
		original_path,
		half_path,
		comparison_path,
		cat_food_bag.scale.is_equal_approx(original_bag_scale) \
			and elevated_cat_bowl.scale.is_equal_approx(original_bowl_scale),
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _opaque_sprite_rect(sprite: Sprite2D) -> Rect2:
	if sprite.texture == null:
		return Rect2()
	var image := sprite.texture.get_image()
	if image == null:
		return Rect2()
	var texture_size := sprite.texture.get_size()
	var used_rect := image.get_used_rect()
	return Rect2(
		sprite.position + (Vector2(used_rect.position) - texture_size * 0.5) * sprite.scale,
		Vector2(used_rect.size) * sprite.scale.abs()
	)


func _scaled_points_around(
	points: PackedVector2Array,
	pivot: Vector2,
	factor: float
) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	for point in points:
		scaled.append(pivot + (point - pivot) * factor)
	return scaled


func _run_ambient_layer_smoke() -> void:
	await get_tree().create_timer(0.2).timeout
	var pot_position := rose_pot_base.position
	var pot_rotation := rose_pot_base.rotation
	var first_flower_rotation := rose_flowers_pivot.rotation
	await get_tree().create_timer(1.2).timeout
	var second_flower_rotation := rose_flowers_pivot.rotation
	var flower_moved := absf(second_flower_rotation - first_flower_rotation) > 0.0005
	var flower_motion_subtle := absf(second_flower_rotation) <= deg_to_rad(0.8)
	var pot_static := rose_pot_base.position == pot_position \
		and is_equal_approx(rose_pot_base.rotation, pot_rotation)

	var wall_material: ShaderMaterial = window_room_background.material as ShaderMaterial
	var exterior_material: ShaderMaterial = window_exterior_video.material as ShaderMaterial
	var output_material: ShaderMaterial = visual_output.material as ShaderMaterial
	var overlay_material: ShaderMaterial = night_blue_overlay.material as ShaderMaterial
	var directional_material: ShaderMaterial = directional_light_overlay.material as ShaderMaterial
	var wall_darkening := float(wall_material.get_shader_parameter("wall_darkening")) \
		if wall_material != null else 0.0
	var exterior_saturation := float(exterior_material.get_shader_parameter("saturation")) \
		if exterior_material != null else 0.0
	var exterior_building_darkening := float(exterior_material.get_shader_parameter("building_darkening")) \
		if exterior_material != null else 0.0
	var exterior_window_gain := float(exterior_material.get_shader_parameter("window_gain")) \
		if exterior_material != null else 0.0
	var exterior_tree_visibility := float(exterior_material.get_shader_parameter("tree_visibility")) \
		if exterior_material != null else 0.0
	var night_tint_strength := float(output_material.get_shader_parameter("night_tint_strength")) \
		if output_material != null else 0.0
	var blue_amount := float(overlay_material.get_shader_parameter("blue_amount")) \
		if overlay_material != null else 0.0
	var blue_tint: Vector3 = overlay_material.get_shader_parameter("blue_tint") \
		if overlay_material != null else Vector3.ZERO
	var main_source: Vector2 = directional_material.get_shader_parameter("main_source") \
		if directional_material != null else Vector2.ZERO
	var main_occlusion_strength := float(directional_material.get_shader_parameter("main_occlusion_strength")) \
		if directional_material != null else 0.0
	var monitor_screen_x := float(directional_material.get_shader_parameter("monitor_screen_x")) \
		if directional_material != null else 0.0
	var monitor_far_x := float(directional_material.get_shader_parameter("monitor_far_x")) \
		if directional_material != null else 0.0
	var window_min: Vector2 = overlay_material.get_shader_parameter("window_min") \
		if overlay_material != null else Vector2.ZERO
	var window_max: Vector2 = overlay_material.get_shader_parameter("window_max") \
		if overlay_material != null else Vector2.ZERO
	var directional_window_max: Vector2 = directional_material.get_shader_parameter("window_max") \
		if directional_material != null else Vector2.ZERO
	var upper_background_reveal := float(overlay_material.get_shader_parameter("upper_background_reveal")) \
		if overlay_material != null else 0.0
	var lower_shadow_strength := float(directional_material.get_shader_parameter("lower_shadow_strength")) \
		if directional_material != null else 0.0
	var lower_shadow_start_left := float(directional_material.get_shader_parameter("lower_shadow_start_left")) \
		if directional_material != null else 0.0
	var lower_shadow_start_right := float(directional_material.get_shader_parameter("lower_shadow_start_right")) \
		if directional_material != null else 0.0
	var lower_shadow_end := float(directional_material.get_shader_parameter("lower_shadow_end")) \
		if directional_material != null else 0.0
	var ambient_neutral := night_ambient.color.r >= 0.99 \
		and night_ambient.color.g >= 0.99 and night_ambient.color.b >= 0.99
	var blue_overlay_ok := blue_amount >= 0.7 and blue_tint.z > blue_tint.x * 4.0 \
		and night_blue_overlay.z_index < typing_actor.z_index
	var directional_geometry_ok := main_source.y < 0.0 \
		and main_occlusion_strength > 0.0 and main_occlusion_strength < 0.3 \
		and monitor_far_x < monitor_screen_x
	var window_exclusion_ok := window_min.x > 0.0 and window_max.x > window_min.x \
		and window_max.y >= 0.4 and directional_window_max.is_equal_approx(window_max)
	var vertical_light_layers_ok := upper_background_reveal >= 0.8 \
		and lower_shadow_strength >= 0.4 \
		and lower_shadow_start_left < lower_shadow_start_right \
		and lower_shadow_start_right < lower_shadow_end
	var circular_lights_disabled := room_key_light.energy <= 0.001 \
		and monitor_glow.energy <= 0.001 and desk_warm_bounce.energy <= 0.001
	var grading_ok := wall_darkening > 0.0 and wall_darkening < 0.1 \
		and exterior_saturation > 1.0 and exterior_building_darkening >= 0.2 \
		and exterior_window_gain > 1.1 and exterior_tree_visibility >= 0.2 \
		and night_tint_strength <= 0.001 \
		and ambient_neutral and blue_overlay_ok and directional_geometry_ok \
		and window_exclusion_ok and vertical_light_layers_ok and circular_lights_disabled

	var output_path := ProjectSettings.globalize_path("res://qa/ambient_layers_runtime.png")
	var image := get_viewport().get_texture().get_image()
	var save_result := image.save_png(output_path) if image != null else ERR_CANT_CREATE
	var ok := flower_moved and flower_motion_subtle and pot_static and grading_ok \
		and save_result == OK
	print("AMBIENT_LAYER_SMOKE wall=%.3f saturation=%.3f output_tint=%.3f blue_amount=%.3f blue=%s main_source=%s occlusion=%.3f monitor_trapezoid=%.3f->%.3f ambient_neutral=%s circles_disabled=%s flower_a=%.4f flower_b=%.4f moved=%s subtle=%s pot_static=%s screenshot=%s ok=%s" % [
		wall_darkening,
		exterior_saturation,
		night_tint_strength,
		blue_amount,
		blue_tint,
		main_source,
		main_occlusion_strength,
		monitor_screen_x,
		monitor_far_x,
		ambient_neutral,
		circular_lights_disabled,
		first_flower_rotation,
		second_flower_rotation,
		flower_moved,
		flower_motion_subtle,
		pot_static,
		output_path,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_audio_slider_smoke() -> void:
	await get_tree().process_frame
	var original_music := music_panel.manager.volume
	var original_sfx := music_panel.sfx_volume
	var bus_index := AudioServer.get_bus_index("Master")
	music_panel.manager.set_volume(0.31, false)
	music_panel.set_sfx_volume(0.47, false)
	var music_ok := is_equal_approx(music_panel.manager.volume, 0.31) \
		and is_equal_approx(music_panel.music_volume_slider.value, 0.31)
	var sfx_linear := db_to_linear(AudioServer.get_bus_volume_db(bus_index)) if bus_index >= 0 else -1.0
	var sfx_ok := is_equal_approx(music_panel.sfx_volume_slider.value, 0.47) \
		and is_equal_approx(sfx_linear, 0.47) \
		and not AudioServer.is_bus_mute(bus_index)
	music_panel.set_sfx_volume(0.0, false)
	var mute_ok := AudioServer.is_bus_mute(bus_index)
	music_panel.manager.set_volume(original_music, false)
	music_panel.set_sfx_volume(original_sfx, false)
	for candidate in get_tree().current_scene.find_children("FrameAudioPlayer*", "AudioStreamPlayer", true, false):
		var frame_audio_player := candidate as AudioStreamPlayer
		if frame_audio_player != null:
			frame_audio_player.stop()
			frame_audio_player.stream = null
	await get_tree().process_frame
	print("AUDIO_SLIDER_SMOKE music=%s sfx=%s mute=%s" % [music_ok, sfx_ok, mute_ok])
	get_tree().quit(0 if music_ok and sfx_ok and mute_ok else 1)


func _run_window_ui_smoke() -> void:
	await get_tree().process_frame
	var hidden_by_default := not music_panel.visible
	var edge_motion := InputEventMouseMotion.new()
	edge_motion.position = Vector2(1.0, size.y * 0.5)
	_on_window_surface_gui_input(edge_motion)
	var ordinary_cursor := mouse_default_cursor_shape == Control.CURSOR_ARROW
	var original_top_state := window_controller.always_on_top_enabled
	_on_always_on_top_toggle_requested()
	var lock_toggled := window_controller.always_on_top_enabled != original_top_state \
		and music_panel.is_lock_icon_visible() == window_controller.always_on_top_enabled
	_on_always_on_top_toggle_requested()
	var lock_restored := window_controller.always_on_top_enabled == original_top_state \
		and music_panel.is_lock_icon_visible() == original_top_state
	music_panel.show()
	music_panel.get_node("Margin/Layout/UtilityRow/PowerButton").emit_signal("pressed")
	await get_tree().process_frame
	var confirmation_visible: bool = music_panel.close_confirmation.visible \
		and music_panel.get_node("CloseConfirmation/CloseMargin/CloseContent/CloseQuestion").text == "你要走了吗？" \
		and music_panel.get_node("CloseConfirmation/CloseMargin/CloseContent/CloseButtons/CloseYesButton").text == "是" \
		and music_panel.get_node("CloseConfirmation/CloseMargin/CloseContent/CloseButtons/CloseNoButton").text == "否"
	var close_wired := music_panel.close_confirmed.is_connected(window_controller.close_window)
	music_panel.close_confirmation.hide()
	for candidate in get_tree().current_scene.find_children("FrameAudioPlayer*", "AudioStreamPlayer", true, false):
		var frame_audio_player := candidate as AudioStreamPlayer
		if frame_audio_player != null:
			frame_audio_player.stop()
			frame_audio_player.stream = null
	await get_tree().process_frame
	print("WINDOW_UI_SMOKE hidden=%s cursor_arrow=%s lock_toggle=%s lock_restore=%s confirm=%s close_wired=%s" % [
		hidden_by_default,
		ordinary_cursor,
		lock_toggled,
		lock_restored,
		confirmation_visible,
		close_wired,
	])
	var ok: bool = hidden_by_default and ordinary_cursor and lock_toggled and lock_restored \
		and confirmation_visible and close_wired
	get_tree().quit(0 if ok else 1)


func _run_window_bounds_smoke() -> void:
	var window_size := Vector2i(500, 400)
	var single_screen: Array[Rect2i] = [Rect2i(0, 0, 1920, 1080)]
	var adjacent_screens: Array[Rect2i] = [
		Rect2i(-1920, 0, 1920, 1080),
		Rect2i(0, 0, 1920, 1080),
	]
	var stepped_screens: Array[Rect2i] = [
		Rect2i(0, 0, 1920, 1080),
		Rect2i(1920, 200, 1920, 1080),
	]
	var separated_left_right: Array[Rect2i] = [
		Rect2i(-2048, 0, 1707, 960),
		Rect2i(0, 0, 2048, 1152),
	]
	var top_left := window_controller._constrain_position_to_screens(
		Vector2i(-100, -50), window_size, single_screen
	)
	var bottom_right := window_controller._constrain_position_to_screens(
		Vector2i(1700, 800), window_size, single_screen
	)
	var across_seam := window_controller._constrain_position_to_screens(
		Vector2i(-250, 100), window_size, adjacent_screens
	)
	var left_outer := window_controller._constrain_position_to_screens(
		Vector2i(-2100, 100), window_size, adjacent_screens
	)
	var right_outer := window_controller._constrain_position_to_screens(
		Vector2i(1800, 100), window_size, adjacent_screens
	)
	var stepped_gap := window_controller._constrain_position_to_screens(
		Vector2i(1800, 0), window_size, stepped_screens
	)
	var across_internal_gap := window_controller._constrain_position_to_screens(
		Vector2i(-500, 100), window_size, separated_left_right
	)
	var actual_screens := window_controller._get_screen_rects()
	var outer_right := actual_screens[0].end.x
	var upper_edge := actual_screens[0].position.y
	for screen in actual_screens:
		outer_right = maxi(outer_right, screen.end.x)
		upper_edge = mini(upper_edge, screen.position.y)
	DisplayServer.window_set_position(Vector2i(outer_right + 200, upper_edge))
	await get_tree().process_frame
	await get_tree().process_frame
	var live_position := DisplayServer.window_get_position()
	var live_coverage := window_controller._with_internal_screen_bridges(actual_screens)
	var live_clamped := window_controller._rect_is_covered_by_screens(
		Rect2i(live_position, DisplayServer.window_get_size()),
		live_coverage
	)
	var ok := top_left == Vector2i.ZERO \
		and bottom_right == Vector2i(1420, 680) \
		and across_seam == Vector2i(-250, 100) \
		and left_outer == Vector2i(-1920, 100) \
		and right_outer == Vector2i(1420, 100) \
		and stepped_gap == Vector2i(1800, 200) \
		and across_internal_gap == Vector2i(-500, 100) \
		and live_clamped
	print("WINDOW_BOUNDS_SMOKE top_left=%s bottom_right=%s seam=%s left=%s right=%s stepped=%s internal_gap=%s live=%s live_clamped=%s ok=%s" % [
		top_left,
		bottom_right,
		across_seam,
		left_outer,
		right_outer,
		stepped_gap,
		across_internal_gap,
		live_position,
		live_clamped,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_fixed_music_panel_smoke() -> void:
	music_panel.show()
	var configured_minimum := DisplayServer.window_get_min_size()
	var configured_maximum := DisplayServer.window_get_max_size()
	DisplayServer.window_set_size(WindowController.MIN_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	var minimum_window := DisplayServer.window_get_size()
	var minimum_panel_size := music_panel.size
	var minimum_right_gap := size.x - music_panel.position.x - music_panel.size.x
	var minimum_top_gap := music_panel.position.y
	var minimum_image := get_viewport().get_texture().get_image()
	var minimum_result := minimum_image.save_png(
		ProjectSettings.globalize_path("res://qa/music_panel_fixed_min.png")
	) if minimum_image != null else ERR_CANT_CREATE

	DisplayServer.window_set_size(WindowController.MAX_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	var maximum_window := DisplayServer.window_get_size()
	var maximum_panel_size := music_panel.size
	var maximum_right_gap := size.x - music_panel.position.x - music_panel.size.x
	var maximum_top_gap := music_panel.position.y
	var maximum_image := get_viewport().get_texture().get_image()
	var maximum_result := maximum_image.save_png(
		ProjectSettings.globalize_path("res://qa/music_panel_fixed_max.png")
	) if maximum_image != null else ERR_CANT_CREATE

	var limits_ok := configured_minimum == WindowController.MIN_WINDOW_SIZE \
		and configured_maximum == WindowController.MAX_WINDOW_SIZE \
		and minimum_window == WindowController.MIN_WINDOW_SIZE \
		and maximum_window == WindowController.MAX_WINDOW_SIZE
	var panel_size_ok := minimum_panel_size == Vector2(222.0, 178.0) \
		and maximum_panel_size == minimum_panel_size
	var anchor_ok := is_equal_approx(minimum_right_gap, 18.0) \
		and is_equal_approx(maximum_right_gap, 18.0) \
		and is_equal_approx(minimum_top_gap, 18.0) \
		and is_equal_approx(maximum_top_gap, 18.0)
	var captures_ok := minimum_result == OK and maximum_result == OK
	var ok := limits_ok and panel_size_ok and anchor_ok and captures_ok
	print("FIXED_MUSIC_PANEL_SMOKE min_window=%s max_window=%s min_panel=%s max_panel=%s right_gap=%.1f/%.1f top_gap=%.1f/%.1f captures=%s ok=%s" % [
		minimum_window,
		maximum_window,
		minimum_panel_size,
		maximum_panel_size,
		minimum_right_gap,
		maximum_right_gap,
		minimum_top_gap,
		maximum_top_gap,
		captures_ok,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _run_source_dialog_layout_smoke() -> void:
	music_panel.show()
	var all_layouts_ok := true
	var all_captures_ok := true
	var capture_directory := "res://qa" if OS.is_debug_build() else "user://qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
	var test_sizes: Array[Vector2i] = [
		Vector2i(626, 409),
		Vector2i(575, 419),
		WindowController.MIN_WINDOW_SIZE,
	]
	var capture_names := [
		"source_dialog_regular.png",
		"source_dialog_reported_size.png",
		"source_dialog_minimum.png",
	]
	for index in test_sizes.size():
		DisplayServer.window_set_size(test_sizes[index])
		await get_tree().process_frame
		await get_tree().process_frame
		music_panel.source_dialog.hide()
		music_panel.source_button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var layout_ok := _source_dialog_has_safe_spacing()
		var image := get_viewport().get_texture().get_image()
		var capture_result := image.save_png(
			ProjectSettings.globalize_path("%s/%s" % [capture_directory, capture_names[index]])
		) if image != null else ERR_CANT_CREATE
		all_layouts_ok = all_layouts_ok and layout_ok
		all_captures_ok = all_captures_ok and capture_result == OK
		print("SOURCE_DIALOG_LAYOUT size=%s dialog=%s layout=%s capture=%d" % [
			DisplayServer.window_get_size(),
			music_panel.source_dialog.size,
			layout_ok,
			capture_result,
		])
		music_panel.source_dialog.hide()
	var ok := all_layouts_ok and all_captures_ok
	print("SOURCE_DIALOG_LAYOUT_SMOKE layouts=%s captures=%s ok=%s" % [
		all_layouts_ok,
		all_captures_ok,
		ok,
	])
	get_tree().quit(0 if ok else 1)


func _source_dialog_has_safe_spacing() -> bool:
	var source_content := music_panel.get_node("SourceDialog/SourceMargin/SourceContent") as Control
	var source_text := music_panel.get_node("SourceDialog/SourceMargin/SourceContent/SourceText") as Label
	var source_divider := music_panel.get_node("SourceDialog/SourceMargin/SourceContent/SourceDivider") as Control
	var source_notice := music_panel.get_node("SourceDialog/SourceMargin/SourceContent/SourceNotice") as Label
	var source_buttons := music_panel.get_node("SourceDialog/SourceMargin/SourceContent/SourceButtons") as Control
	var details_gap := source_divider.position.y - (source_text.position.y + source_text.size.y)
	var notice_gap := source_notice.position.y - (source_divider.position.y + source_divider.size.y)
	var buttons_gap := source_buttons.position.y - (source_notice.position.y + source_notice.size.y)
	var content_bottom_gap := source_content.size.y - (source_buttons.position.y + source_buttons.size.y)
	var dialog_bottom_gap := music_panel.source_dialog.size.y \
		- (source_content.position.y + source_content.size.y)
	var details_text_fits: bool = source_text.get_line_count() <= source_text.get_visible_line_count()
	var notice_text_fits: bool = source_notice.get_line_count() <= source_notice.get_visible_line_count()
	var content_fits_horizontally: bool = source_content.position.x >= 0.0 \
		and source_content.position.x + source_content.size.x <= music_panel.source_dialog.size.x
	var dialog_inside_window := music_panel.source_dialog.position.x >= 0 \
		and music_panel.source_dialog.position.y >= 0 \
		and music_panel.source_dialog.position.x + music_panel.source_dialog.size.x <= size.x \
		and music_panel.source_dialog.position.y + music_panel.source_dialog.size.y <= size.y
	print("SOURCE_DIALOG_SPACING details=%.1f notice=%.1f buttons=%.1f content_bottom=%.1f dialog_bottom=%.1f details_fit=%s notice_fit=%s horizontal_fit=%s inside=%s" % [
		details_gap,
		notice_gap,
		buttons_gap,
		content_bottom_gap,
		dialog_bottom_gap,
		details_text_fits,
		notice_text_fits,
		content_fits_horizontally,
		dialog_inside_window,
	])
	return music_panel.source_dialog.visible \
		and music_panel.source_dialog.size.x >= 390 \
		and music_panel.source_dialog.size.y >= 274 \
		and music_panel.source_dialog.size.y <= 300 \
		and source_notice.text.contains("游戏不提供音乐文件下载") \
		and details_gap >= 8.0 \
		and notice_gap >= 8.0 \
		and buttons_gap >= 8.0 \
		and content_bottom_gap >= 0.0 \
		and content_bottom_gap <= 4.0 \
		and dialog_bottom_gap >= 18.0 \
		and details_text_fits \
		and notice_text_fits \
		and content_fits_horizontally \
		and dialog_inside_window


func _run_audius_smoke() -> void:
	var original_volume := music_panel.manager.volume
	music_panel.manager.set_volume(0.0)
	var all_ok := true
	var first_theme_advanced := false
	var pid_path := "user://watercolor_desk_radio.pid"
	for index in music_panel.manager.stations.size():
		var started := music_panel.manager.play_station(index)
		await get_tree().create_timer(2.0).timeout
		var pid := FileAccess.get_file_as_string(pid_path).strip_edges().to_int() if FileAccess.file_exists(pid_path) else 0
		var process_alive := pid > 0
		var station: Dictionary = music_panel.manager.stations[index]
		var first_track: Dictionary = station.get("tracks", [])[0]
		var title_visible := music_panel.now_playing_label.text == str(first_track.get("title", ""))
		var playlist_selected := music_panel.playlist_buttons[index].button_pressed
		var pause_symbol_visible := music_panel.is_pause_icon_visible()
		var theme_ok := started and process_alive and title_visible and playlist_selected and pause_symbol_visible
		all_ok = all_ok and theme_ok
		print("AUDIUS_SMOKE theme=%d started=%s alive=%s title=%s selected=%s pause=%s" % [
			index,
			started,
			process_alive,
			title_visible,
			playlist_selected,
			pause_symbol_visible,
		])
		if index == 0 and process_alive:
			var first_title := music_panel.now_playing_label.text
			OS.kill(pid)
			await get_tree().create_timer(2.0).timeout
			first_theme_advanced = music_panel.now_playing_label.text != first_title \
				and music_panel.now_playing_label.text == str(station.get("tracks", [])[1].get("title", ""))
			all_ok = all_ok and first_theme_advanced
			print("AUDIUS_SMOKE auto_next=%s title='%s'" % [first_theme_advanced, music_panel.now_playing_label.text])
		music_panel.manager.stop()
		for attempt in range(20):
			await get_tree().create_timer(0.1).timeout
			if not FileAccess.file_exists(pid_path) \
					or FileAccess.get_file_as_string(pid_path).strip_edges().is_empty():
				break
	music_panel.manager.set_volume(original_volume)
	var pid_text := FileAccess.get_file_as_string(pid_path).strip_edges() if FileAccess.file_exists(pid_path) else "<missing>"
	print("AUDIUS_SMOKE stopped=true auto_next=%s pid_file='%s'" % [first_theme_advanced, pid_text])
	get_tree().quit(0 if all_ok and first_theme_advanced and pid_text.is_empty() else 1)


func _run_random_chillhop_smoke() -> void:
	var manager := music_panel.manager
	var original_volume := manager.volume
	var pid_path := "user://watercolor_desk_radio.pid"
	manager.set_volume(0.0, false)
	var pool: Array = manager.stations[0].get("tracks", []) as Array \
		if manager.stations.size() == 1 else []
	var single_pool_ok: bool = manager.stations.size() == 1 and pool.size() > 1 \
		and music_panel.playlist_buttons.is_empty()
	var started := manager.play_station(0)
	await get_tree().create_timer(2.0).timeout
	var first_index := int(manager.get("_current_theme_track_index"))
	var first_track: Dictionary = pool[first_index] if first_index >= 0 and first_index < pool.size() else {}
	var metadata_ok := music_panel.now_playing_label.text == str(first_track.get("title", "")) \
		and music_panel.artist_label.text == str(first_track.get("artist", "")) \
		and not music_panel.artist_label.text.is_empty()

	var next_started := manager.play_next()
	var second_index := int(manager.get("_current_theme_track_index"))
	var next_excluded_current := second_index >= 0 and second_index != first_index
	await get_tree().create_timer(2.0).timeout
	var previous_started := manager.play_previous()
	var previous_index := int(manager.get("_current_theme_track_index"))
	var previous_exact := previous_started and previous_index == first_index \
		and music_panel.now_playing_label.text == str(first_track.get("title", "")) \
		and music_panel.artist_label.text == str(first_track.get("artist", ""))

	await get_tree().create_timer(2.0).timeout
	var random_after_previous_started := manager.play_next()
	var random_after_previous_index := int(manager.get("_current_theme_track_index"))
	var next_after_previous_excluded_current := random_after_previous_index != first_index
	await get_tree().create_timer(2.0).timeout
	var playing_pid := FileAccess.get_file_as_string(pid_path).strip_edges().to_int() \
		if FileAccess.file_exists(pid_path) else 0
	var before_auto_index := int(manager.get("_current_theme_track_index"))
	if playing_pid > 0:
		OS.kill(playing_pid)
	await get_tree().create_timer(2.0).timeout
	var after_auto_index := int(manager.get("_current_theme_track_index"))
	var auto_next_random := playing_pid > 0 and after_auto_index >= 0 \
		and after_auto_index != before_auto_index

	var ok := single_pool_ok and started and metadata_ok and next_started \
		and next_excluded_current and previous_exact and random_after_previous_started \
		and next_after_previous_excluded_current and auto_next_random
	print("RANDOM_CHILLHOP_SMOKE pool=%d first=%d next=%d previous=%d next_after_previous=%d auto=%d title=%s artist=%s ok=%s" % [
		pool.size(),
		first_index,
		second_index,
		previous_index,
		random_after_previous_index,
		after_auto_index,
		music_panel.now_playing_label.text,
		music_panel.artist_label.text,
		ok,
	])
	manager.stop()
	for attempt in range(20):
		await get_tree().create_timer(0.1).timeout
		if not FileAccess.file_exists(pid_path) \
				or FileAccess.get_file_as_string(pid_path).strip_edges().is_empty():
			break
	manager.set_volume(original_volume, false)
	get_tree().quit(0 if ok else 1)


func _radio_control_ack_matches(path: String, process_id: int, volume: float, paused: bool) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parts := FileAccess.get_file_as_string(path).strip_edges().split("|")
	return parts.size() == 3 \
		and parts[0].to_int() == process_id \
		and is_equal_approx(parts[1].to_float(), volume) \
		and parts[2].to_int() == int(paused)


func _run_radio_controls_smoke() -> void:
	var pid_path := "user://watercolor_desk_radio.pid"
	var volume_path := "user://watercolor_desk_radio_volume.txt"
	var pause_path := "user://watercolor_desk_radio_pause.txt"
	var ack_path := "user://watercolor_desk_radio_control_ack.txt"
	music_panel.manager.set_volume(0.0, false)
	var start_usec := Time.get_ticks_usec()
	var started := music_panel.manager.play_station(0)
	await get_tree().process_frame
	var start_frame_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	var original_pid := 0
	for attempt in range(100):
		await get_tree().create_timer(0.1).timeout
		original_pid = FileAccess.get_file_as_string(pid_path).strip_edges().to_int() \
			if FileAccess.file_exists(pid_path) else 0
		if original_pid > 0:
			break

	var volume_usec := Time.get_ticks_usec()
	for index in range(60):
		music_panel.music_volume_slider.value = float(index) / 100.0
	music_panel.music_volume_slider.value = 0.0
	await get_tree().process_frame
	var volume_frame_ms := float(Time.get_ticks_usec() - volume_usec) / 1000.0
	var volume_acknowledged := false
	for attempt in range(100):
		await get_tree().create_timer(0.1).timeout
		if _radio_control_ack_matches(ack_path, original_pid, 0.0, false):
			volume_acknowledged = true
			break
	var volume_pid := FileAccess.get_file_as_string(pid_path).strip_edges().to_int()
	var applied_volume := FileAccess.get_file_as_string(volume_path).strip_edges().to_float()

	music_panel.play_button.pressed.emit()
	var pause_acknowledged := false
	for attempt in range(50):
		await get_tree().create_timer(0.1).timeout
		if _radio_control_ack_matches(ack_path, original_pid, 0.0, true):
			pause_acknowledged = true
			break
	var paused_pid := FileAccess.get_file_as_string(pid_path).strip_edges().to_int()
	var pause_requested := FileAccess.get_file_as_string(pause_path).strip_edges() == "1"
	music_panel.play_button.pressed.emit()
	var resume_acknowledged := false
	for attempt in range(50):
		await get_tree().create_timer(0.1).timeout
		if _radio_control_ack_matches(ack_path, original_pid, 0.0, false):
			resume_acknowledged = true
			break
	var resumed_pid := FileAccess.get_file_as_string(pid_path).strip_edges().to_int()
	var resume_requested := FileAccess.get_file_as_string(pause_path).strip_edges() == "0"

	var switch_usec := Time.get_ticks_usec()
	var switched := music_panel.manager.play_next()
	await get_tree().process_frame
	var switch_frame_ms := float(Time.get_ticks_usec() - switch_usec) / 1000.0
	var switched_pid := 0
	for attempt in range(100):
		await get_tree().create_timer(0.1).timeout
		switched_pid = FileAccess.get_file_as_string(pid_path).strip_edges().to_int() \
			if FileAccess.file_exists(pid_path) else 0
		if switched_pid > 0 and switched_pid != original_pid:
			break

	var controls_same_process := original_pid > 0 and volume_pid == original_pid \
		and paused_pid == original_pid and resumed_pid == original_pid
	var responsive := start_frame_ms < 100.0 and volume_frame_ms < 100.0 and switch_frame_ms < 100.0
	var switch_connected_new_track := switched and switched_pid > 0 and switched_pid != original_pid
	var ok := started and controls_same_process and is_zero_approx(applied_volume) \
		and volume_acknowledged and pause_requested and pause_acknowledged \
		and resume_requested and resume_acknowledged and responsive and switch_connected_new_track
	print("RADIO_CONTROLS_SMOKE original_pid=%d volume_pid=%d paused_pid=%d resumed_pid=%d switched_pid=%d start_ms=%.3f volume_ms=%.3f switch_ms=%.3f same_process=%s volume_ack=%s pause=%s pause_ack=%s resume=%s resume_ack=%s ok=%s" % [
		original_pid,
		volume_pid,
		paused_pid,
		resumed_pid,
		switched_pid,
		start_frame_ms,
		volume_frame_ms,
		switch_frame_ms,
		controls_same_process,
		volume_acknowledged,
		pause_requested,
		pause_acknowledged,
		resume_requested,
		resume_acknowledged,
		ok,
	])
	music_panel.manager.stop()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if ok else 1)
