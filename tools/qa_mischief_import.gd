extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor_scene: PackedScene = load(
		"res://xsxb_frame_tuner/runtime/xsxb_frame_actor.tscn"
	) as PackedScene
	var actor: Node = actor_scene.instantiate()
	actor.set("frame_profile_id", "yellow_cat")
	actor.set("frame_animation", "mischief")
	actor.set("loop_animation", false)
	actor.set("use_frame_boxes", false)
	root.add_child(actor)
	await process_frame

	var has_animation := bool(actor.call("has_frame_animation", "mischief"))
	var frame_count := int(actor.call("animation_frame_count", "mischief"))
	var duration := float(actor.call("animation_duration", "mischief"))
	var fps := float(actor.call("animation_fps", "mischief"))
	actor.call("play_frame_animation", "mischief", false, true)
	var first_frame := int(actor.get("_current_frame"))
	await create_timer(0.23).timeout
	var advanced_frame := int(actor.get("_current_frame"))
	var last_frame_visible := bool(actor.call("show_frame", "mischief", 90))
	var sprite := actor.get_node("VisualOwner/FrameSprite") as Sprite2D
	var texture_size := sprite.texture.get_size() if sprite.texture != null else Vector2.ZERO

	var no_mischief_boxes := true
	var frame_boxes: Dictionary = actor.get("_frame_box_overrides")
	for key_value: Variant in frame_boxes.keys():
		if str(key_value).begins_with("yellow_cat/mischief"):
			no_mischief_boxes = false
			break

	var ok := has_animation \
		and frame_count == 91 \
		and is_equal_approx(fps, 6.25) \
		and is_equal_approx(duration, 14.56) \
		and first_frame == 0 \
		and advanced_frame > first_frame \
		and last_frame_visible \
		and texture_size == Vector2(1112, 834) \
		and no_mischief_boxes
	print(
		"XSXB_MISCHIEF_IMPORT_SMOKE frames=%d fps=%.6f duration=%.3f first=%d advanced=%d texture=%s no_boxes=%s ok=%s"
		% [
			frame_count,
			fps,
			duration,
			first_frame,
			advanced_frame,
			texture_size,
			no_mischief_boxes,
			ok,
		]
	)
	actor.queue_free()
	quit(0 if ok else 1)
