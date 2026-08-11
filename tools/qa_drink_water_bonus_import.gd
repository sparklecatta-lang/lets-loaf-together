extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor_scene: PackedScene = load(
		"res://xsxb_frame_tuner/runtime/xsxb_frame_actor.tscn"
	) as PackedScene
	var actor: Node = actor_scene.instantiate()
	actor.set("frame_profile_id", "desk_girl")
	actor.set("frame_animation", "drink_water_bonus")
	actor.set("loop_animation", false)
	actor.set("use_frame_boxes", false)
	root.add_child(actor)
	await process_frame

	var has_animation := bool(actor.call("has_frame_animation", "drink_water_bonus"))
	var frame_count := int(actor.call("animation_frame_count", "drink_water_bonus"))
	var duration := float(actor.call("animation_duration", "drink_water_bonus"))
	var fps := float(actor.call("animation_fps", "drink_water_bonus"))
	actor.call("play_frame_animation", "drink_water_bonus", false, true)
	var first_frame := int(actor.get("_current_frame"))
	await create_timer(0.21).timeout
	var advanced_frame := int(actor.get("_current_frame"))
	var last_frame_visible := bool(actor.call("show_frame", "drink_water_bonus", 26))
	var sprite := actor.get_node("VisualOwner/FrameSprite") as Sprite2D
	var texture_size := sprite.texture.get_size() if sprite.texture != null else Vector2.ZERO
	actor.call("play_frame_animation", "drink_water_bonus", false, true)
	await create_timer(duration + 0.15).timeout
	var one_shot_finished := bool(actor.get("_animation_finished")) \
		and int(actor.get("_current_frame")) == 26

	var no_bonus_boxes := true
	var frame_boxes: Dictionary = actor.get("_frame_box_overrides")
	for key_value: Variant in frame_boxes.keys():
		if str(key_value).begins_with("desk_girl/drink_water_bonus"):
			no_bonus_boxes = false
			break

	var ok := has_animation \
		and frame_count == 27 \
		and is_equal_approx(fps, 5.263158) \
		and is_equal_approx(duration, 5.13) \
		and first_frame == 0 \
		and advanced_frame > first_frame \
		and last_frame_visible \
		and texture_size == Vector2(1112, 834) \
		and one_shot_finished \
		and no_bonus_boxes
	print(
		"XSXB_DRINK_WATER_BONUS_IMPORT_SMOKE frames=%d fps=%.6f duration=%.3f first=%d advanced=%d texture=%s finished=%s no_boxes=%s ok=%s"
		% [
			frame_count,
			fps,
			duration,
			first_frame,
			advanced_frame,
			texture_size,
			one_shot_finished,
			no_bonus_boxes,
			ok,
		]
	)
	actor.queue_free()
	quit(0 if ok else 1)
