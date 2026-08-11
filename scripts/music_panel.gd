class_name MusicPanel
extends PanelContainer

signal always_on_top_toggle_requested
signal close_confirmed

const SFX_SETTINGS_PATH := "user://sound_effect_settings.cfg"
const DEFAULT_SFX_VOLUME := 0.72
const PLAY_ICON := preload("res://assets/ui/play.svg")
const PAUSE_ICON := preload("res://assets/ui/pause.svg")
const LOCK_ICON := preload("res://assets/ui/lock.svg")
const UNLOCK_ICON := preload("res://assets/ui/unlock.svg")
const TITLE_MARQUEE_SPEED := 30.0
const TITLE_MARQUEE_START_DELAY := 1.2
const TITLE_MARQUEE_END_DELAY := 0.9

@onready var manager: MusicManager = %MusicManager
@onready var now_playing_clip: Control = %NowPlayingClip
@onready var now_playing_label: Label = %NowPlayingLabel
@onready var artist_label: Label = %ArtistLabel
@onready var play_button: Button = %PlayButton
@onready var source_button: Button = %SourceButton
@onready var music_volume_slider: HSlider = %MusicVolumeSlider
@onready var sfx_volume_slider: HSlider = %SfxVolumeSlider
@onready var lock_button: Button = %LockButton
@onready var close_confirmation: PopupPanel = %CloseConfirmation
@onready var source_dialog: PopupPanel = %SourceDialog
@onready var source_text: Label = %SourceText

var playlist_buttons: Array[Button] = []
var sfx_volume := DEFAULT_SFX_VOLUME
var _title_marquee: Tween
var _source_homepage_url := ""


func _ready() -> void:
	manager.current_item_changed.connect(_on_current_item_changed)
	manager.playback_state_changed.connect(_on_playback_state_changed)
	manager.playback_error.connect(_on_playback_error)
	manager.volume_changed.connect(_on_music_volume_changed)
	%PreviousButton.pressed.connect(_on_previous_pressed)
	play_button.pressed.connect(_on_play_pressed)
	%NextButton.pressed.connect(_on_next_pressed)
	source_button.pressed.connect(_on_source_pressed)
	lock_button.pressed.connect(_on_lock_pressed)
	%PowerButton.pressed.connect(_on_power_pressed)
	%CloseYesButton.pressed.connect(_on_close_confirmed)
	%CloseNoButton.pressed.connect(close_confirmation.hide)
	%SourceHomepageButton.pressed.connect(_on_source_homepage_pressed)
	%SourceCloseButton.pressed.connect(source_dialog.hide)
	now_playing_clip.resized.connect(_configure_title_marquee)
	music_volume_slider.value_changed.connect(manager.set_volume)
	sfx_volume_slider.value_changed.connect(set_sfx_volume)
	music_volume_slider.set_value_no_signal(manager.volume)
	sfx_volume = _load_sfx_volume()
	sfx_volume_slider.set_value_no_signal(sfx_volume)
	_apply_sfx_volume(sfx_volume)
	var is_live_radio := manager.stations.size() == 1 \
		and not str(manager.stations[0].get("stream_url", "")).strip_edges().is_empty()
	%PreviousButton.visible = not is_live_radio
	%NextButton.visible = not is_live_radio
	$Margin/Layout/PlaybackRow.visible = not is_live_radio
	_on_playback_state_changed(manager.is_playing())
	call_deferred("_configure_title_marquee")


func set_always_on_top_state(enabled: bool) -> void:
	lock_button.icon = LOCK_ICON if enabled else UNLOCK_ICON
	lock_button.text = ""
	lock_button.tooltip_text = "取消置顶" if enabled else "保持置顶"


func is_pause_icon_visible() -> bool:
	return play_button.icon == PAUSE_ICON


func is_lock_icon_visible() -> bool:
	return lock_button.icon == LOCK_ICON


func set_sfx_volume(value: float, persist := true) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	if not is_equal_approx(sfx_volume_slider.value, sfx_volume):
		sfx_volume_slider.set_value_no_signal(sfx_volume)
	_apply_sfx_volume(sfx_volume)
	if persist:
		_save_sfx_volume()


func _refresh_playlist_buttons() -> void:
	for index in playlist_buttons.size():
		var button := playlist_buttons[index]
		if index >= manager.stations.size():
			button.hide()
			continue
		var station := manager.stations[index]
		button.show()
		button.text = str(station.get("title", "歌单 %d" % (index + 1)))
		button.tooltip_text = str(station.get("description", ""))
		button.disabled = not bool(station.get("enabled", false))
		button.set_pressed_no_signal(index == manager.current_index)


func _on_playlist_pressed(index: int) -> void:
	if manager.play_station(index):
		_refresh_playlist_buttons()


func _on_play_pressed() -> void:
	if manager.current_index >= 0:
		manager.toggle_pause()
	elif not manager.stations.is_empty():
		manager.play_station(0)


func _on_previous_pressed() -> void:
	manager.play_previous()


func _on_next_pressed() -> void:
	manager.play_next()


func _on_lock_pressed() -> void:
	always_on_top_toggle_requested.emit()


func _on_power_pressed() -> void:
	close_confirmation.popup_centered(Vector2i(300, 170))


func _on_source_pressed() -> void:
	if manager.stations.is_empty():
		_source_homepage_url = ""
		source_text.text = "当前没有可用的在线电台来源。"
		%SourceDivider.visible = false
		%SourceNotice.visible = false
		%SourceHomepageButton.disabled = true
		source_dialog.popup_centered(Vector2i(390, 220))
		return
	var station_index := manager.current_index if manager.current_index >= 0 else 0
	var station := manager.stations[station_index]
	_source_homepage_url = str(station.get("homepage", station.get("source_url", ""))).strip_edges()
	var source_name := str(station.get("title", "在线电台"))
	var provider := str(station.get("provider", source_name))
	var genres := str(station.get("artist", station.get("description", "")))
	var license_name := str(station.get("license_name", "请查看来源页面"))
	%SourceDivider.visible = true
	%SourceNotice.visible = true
	%SourceHomepageButton.disabled = _source_homepage_url.is_empty()
	source_text.text = "电台：%s\n提供方：%s\n风格：%s\n授权：%s" % [
		source_name,
		provider,
		genres,
		license_name,
	]
	source_dialog.popup_centered(Vector2i(390, 300))


func _on_source_homepage_pressed() -> void:
	if not _source_homepage_url.is_empty():
		OS.shell_open(_source_homepage_url)


func _on_close_confirmed() -> void:
	close_confirmation.hide()
	close_confirmed.emit()


func _on_current_item_changed(item: Dictionary) -> void:
	now_playing_label.text = str(item.get("title", "未命名曲目"))
	artist_label.text = str(item.get("artist", ""))
	now_playing_label.tooltip_text = str(item.get("display_title", now_playing_label.text))
	now_playing_clip.tooltip_text = now_playing_label.tooltip_text
	artist_label.tooltip_text = now_playing_label.tooltip_text
	call_deferred("_configure_title_marquee")


func _on_playback_state_changed(is_playing: bool) -> void:
	play_button.icon = PAUSE_ICON if is_playing else PLAY_ICON
	play_button.text = ""
	play_button.tooltip_text = "暂停" if is_playing else "播放"


func _on_playback_error(message: String) -> void:
	artist_label.text = ""
	now_playing_label.text = "无法播放"
	now_playing_label.tooltip_text = message
	now_playing_clip.tooltip_text = message
	call_deferred("_configure_title_marquee")


func _configure_title_marquee() -> void:
	if _title_marquee != null and _title_marquee.is_valid():
		_title_marquee.kill()
	_title_marquee = null
	if not is_instance_valid(now_playing_clip) or not is_instance_valid(now_playing_label):
		return
	var viewport_width := now_playing_clip.size.x
	var viewport_height := now_playing_clip.size.y
	if viewport_width <= 0.0 or viewport_height <= 0.0:
		return
	var font := now_playing_label.get_theme_font("font")
	var font_size := now_playing_label.get_theme_font_size("font_size")
	var text_width := ceilf(font.get_string_size(now_playing_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	now_playing_label.position = Vector2.ZERO
	now_playing_label.size = Vector2(maxf(viewport_width, text_width), viewport_height)
	if text_width <= viewport_width:
		now_playing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	now_playing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var travel_distance := text_width - viewport_width
	var travel_time := travel_distance / TITLE_MARQUEE_SPEED
	_title_marquee = create_tween().set_loops()
	_title_marquee.tween_interval(TITLE_MARQUEE_START_DELAY)
	_title_marquee.tween_property(
		now_playing_label,
		"position:x",
		-travel_distance,
		travel_time
	).set_trans(Tween.TRANS_LINEAR)
	_title_marquee.tween_interval(TITLE_MARQUEE_END_DELAY)
	_title_marquee.tween_callback(_reset_title_marquee_position)


func _reset_title_marquee_position() -> void:
	now_playing_label.position.x = 0.0


func _on_music_volume_changed(value: float) -> void:
	if not is_equal_approx(music_volume_slider.value, value):
		music_volume_slider.set_value_no_signal(value)


func _apply_sfx_volume(value: float) -> void:
	# Online music is played by the external radio bridge. The Godot Master bus
	# therefore contains only the character frame SFX in this desktop-pet build.
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return
	AudioServer.set_bus_mute(bus_index, value <= 0.0001)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value, 0.0001)))


func _load_sfx_volume() -> float:
	var config := ConfigFile.new()
	if config.load(SFX_SETTINGS_PATH) != OK:
		return DEFAULT_SFX_VOLUME
	return clampf(float(config.get_value("sound_effects", "volume", DEFAULT_SFX_VOLUME)), 0.0, 1.0)


func _save_sfx_volume() -> void:
	var config := ConfigFile.new()
	config.set_value("sound_effects", "volume", sfx_volume)
	config.save(SFX_SETTINGS_PATH)
