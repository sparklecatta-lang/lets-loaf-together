extends SceneTree


const EXPECTED_POSITION := Vector2(-83.56177102005883, 308.17965799278005)
const EXPECTED_SCALE := Vector2(0.8219271067593513, 0.8219271067593513)
const EXPECTED_TEXTURE_SIZE := Vector2(59, 269)


func _initialize() -> void:
	_run.call_deferred()


func _spawn_actor(profile_id: String, animation_id: String) -> Node:
	var actor_scene: PackedScene = load(
		"res://xsxb_frame_tuner/runtime/xsxb_frame_actor.tscn"
	) as PackedScene
	var actor: Node = actor_scene.instantiate()
	actor.set("frame_profile_id", profile_id)
	actor.set("frame_animation", animation_id)
	actor.set("loop_animation", false)
	actor.set("use_frame_boxes", false)
	root.add_child(actor)
	return actor


func _attachment_matches(actor: Node, expected_below_count: int, expected_above_count: int) -> bool:
	var below := actor.get_node("VisualOwner/AttachmentsBelow") as Node2D
	var above := actor.get_node("VisualOwner/AttachmentsAbove") as Node2D
	if below.get_child_count() != expected_below_count or above.get_child_count() != expected_above_count:
		return false
	if expected_below_count == 0:
		return true
	var leg := below.get_child(0) as Sprite2D
	if leg == null or leg.texture == null:
		return false
	return leg.texture.get_size() == EXPECTED_TEXTURE_SIZE \
		and leg.position.is_equal_approx(EXPECTED_POSITION) \
		and leg.scale.is_equal_approx(EXPECTED_SCALE) \
		and is_zero_approx(leg.rotation_degrees)


func _show_and_check(
	actor: Node,
	animation_id: String,
	frame_index: int,
	expected_below_count: int,
	expected_above_count: int = 0
) -> bool:
	var shown := bool(actor.call("show_frame", animation_id, frame_index))
	await process_frame
	return shown and _attachment_matches(actor, expected_below_count, expected_above_count)


func _run() -> void:
	var girl := _spawn_actor("desk_girl", "typing")
	await process_frame
	var typing_ok := await _show_and_check(girl, "typing", 0, 1)
	var leave_last_ok := await _show_and_check(girl, "leave", 27, 1)
	var startled_existing_attachment_preserved := await _show_and_check(
		girl,
		"startled_recover",
		5,
		1,
		1
	)

	var cat := _spawn_actor("yellow_cat", "mischief")
	await process_frame
	var mischief_ok := await _show_and_check(cat, "mischief", 0, 1)
	var sleep_excluded := await _show_and_check(cat, "sleep", 0, 0)
	var startled_excluded := await _show_and_check(cat, "startled", 0, 0)

	var ok := typing_ok and leave_last_ok and startled_existing_attachment_preserved \
		and mischief_ok and sleep_excluded and startled_excluded
	print(
		"XSXB_DESK_LEG_ATTACHMENT_SMOKE typing=%s leave28=%s startled_existing=%s mischief=%s sleep_excluded=%s cat_startled_excluded=%s position=%s scale=%s texture=%s ok=%s"
		% [
			typing_ok,
			leave_last_ok,
			startled_existing_attachment_preserved,
			mischief_ok,
			sleep_excluded,
			startled_excluded,
			EXPECTED_POSITION,
			EXPECTED_SCALE,
			EXPECTED_TEXTURE_SIZE,
			ok,
		]
	)
	girl.free()
	cat.free()
	quit(0 if ok else 1)
