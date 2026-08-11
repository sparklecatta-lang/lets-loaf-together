class_name ActionPreviewWindow
extends Window

signal action_requested(route_id: String)
signal toggle_requested

const ACTION_ROUTES: Array[Dictionary] = [
	{"section": "基础动作", "id": "idle", "label": "待机", "route": "待机循环"},
	{"section": "基础动作", "id": "typing", "label": "打字", "route": "待机完整一轮 → 打字"},
	{"section": "基础动作", "id": "cat_sleep", "label": "黄猫睡觉", "route": "女孩待机 + 黄猫睡觉"},
	{"section": "待机 / 打字分支", "id": "startle_idle", "label": "惊吓（从待机）", "route": "立即打断待机 → 女孩与猫同时惊吓 → 待机"},
	{"section": "待机 / 打字分支", "id": "startle_typing", "label": "惊吓（从打字）", "route": "立即打断打字 → 女孩与猫同时惊吓 → 打字"},
	{"section": "待机 / 打字分支", "id": "stretch", "label": "伸懒腰", "route": "打字完整一轮 → 伸懒腰 → 打字"},
	{"section": "待机 / 打字分支", "id": "nail_polish", "label": "涂指甲", "route": "待机完整一轮 → 进入 → 循环 ×5 → 退出 → 待机"},
	{"section": "待机 / 打字分支", "id": "drink_water", "label": "喝水", "route": "待机完整一轮 → 喝水 → 待机"},
	{"section": "待机 / 打字分支", "id": "phone", "label": "玩手机", "route": "待机完整一轮 → 玩手机 → 待机"},
	{"section": "待机 / 打字分支", "id": "use_mouse_idle", "label": "操作鼠标（从待机）", "route": "待机完整一轮 → 操作鼠标 → 待机"},
	{"section": "待机 / 打字分支", "id": "use_mouse_typing", "label": "操作鼠标（从打字）", "route": "打字完整一轮 → 操作鼠标 → 打字"},
	{"section": "离开剧情链", "id": "leave_idle", "label": "离开（从待机）", "route": "待机完整一轮 → 离开 → 猫捣蛋 → 回来 → 打字 → 喝水 bonus → 打字"},
	{"section": "离开剧情链", "id": "leave_typing", "label": "离开（从打字）", "route": "打字完整一轮 → 离开 → 猫捣蛋 → 回来 → 打字 → 喝水 bonus → 打字"},
	{"section": "离开剧情链", "id": "cat_mischief", "label": "猫捣蛋", "route": "黄猫睡觉完整一轮 → 猫捣蛋 → 回来 → 打字 → 喝水 bonus → 打字"},
	{"section": "离开剧情链", "id": "come_back", "label": "回来", "route": "猫捣蛋 → 回来 → 打字 → 喝水 bonus → 打字"},
	{"section": "离开剧情链", "id": "drink_water_bonus", "label": "喝水 bonus", "route": "回来 → 打字完整一轮 → 喝水 bonus → 打字"},
]

@onready var action_list: VBoxContainer = %ActionList
@onready var status_label: Label = %StatusLabel

var _has_been_positioned := false


func _ready() -> void:
	close_requested.connect(hide)
	_build_action_list()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_T or event.physical_keycode == KEY_T):
		get_viewport().set_input_as_handled()
		toggle_requested.emit()


func toggle_from_main(main_position: Vector2i, main_size: Vector2i) -> void:
	if visible:
		hide()
		return
	if not _has_been_positioned:
		position = _suggested_position(main_position, main_size)
		_has_been_positioned = true
	show()
	grab_focus()


func set_route_status(route_id: String, accepted: bool) -> void:
	var label := route_id
	for route in ACTION_ROUTES:
		if str(route.id) == route_id:
			label = str(route.label)
			break
	status_label.text = ("正在播放：%s" if accepted else "无法播放：%s") % label


func action_button_count() -> int:
	return ACTION_ROUTES.size()


func _build_action_list() -> void:
	var current_section := ""
	for route in ACTION_ROUTES:
		var section := str(route.section)
		if section != current_section:
			current_section = section
			var section_label := Label.new()
			section_label.text = section
			section_label.add_theme_font_size_override("font_size", 17)
			section_label.add_theme_color_override("font_color", Color("f1b36b"))
			action_list.add_child(section_label)
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 3)
		var button := Button.new()
		button.text = str(route.label)
		button.custom_minimum_size = Vector2(0.0, 38.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = str(route.route)
		button.pressed.connect(_on_action_button_pressed.bind(str(route.id)))
		card.add_child(button)
		var route_label := Label.new()
		route_label.text = str(route.route)
		route_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		route_label.add_theme_font_size_override("font_size", 12)
		route_label.add_theme_color_override("font_color", Color("aeb7c7"))
		card.add_child(route_label)
		action_list.add_child(card)


func _on_action_button_pressed(route_id: String) -> void:
	status_label.text = "正在请求动作……"
	action_requested.emit(route_id)


func _suggested_position(main_position: Vector2i, main_size: Vector2i) -> Vector2i:
	var screen_index := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_index)
	var gap := 18
	var desired := Vector2i(main_position.x + main_size.x + gap, main_position.y)
	if desired.x + size.x > usable_rect.end.x:
		desired.x = main_position.x - size.x - gap
	desired.x = clampi(desired.x, usable_rect.position.x, usable_rect.end.x - size.x)
	desired.y = clampi(desired.y, usable_rect.position.y, usable_rect.end.y - size.y)
	return desired
