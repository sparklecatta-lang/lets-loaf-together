extends SceneTree


const CASES: Array[Dictionary] = [
	{"profile": "desk_girl", "animation": "leave", "frames": 28},
	{"profile": "desk_girl", "animation": "come_back", "frames": 61},
	{"profile": "desk_girl", "animation": "use_mouse", "frames": 22},
	{"profile": "desk_girl", "animation": "drink_water_bonus", "frames": 27},
	{"profile": "yellow_cat", "animation": "startled", "frames": 26},
	{"profile": "yellow_cat", "animation": "mischief", "frames": 83},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor_scene: PackedScene = load(
		"res://xsxb_frame_tuner/runtime/xsxb_frame_actor.tscn"
	) as PackedScene
	var all_ok := true
	for profile_id: String in ["desk_girl", "yellow_cat"]:
		var actor: Node = actor_scene.instantiate()
		actor.set("frame_profile_id", profile_id)
		actor.set("use_frame_boxes", false)
		root.add_child(actor)
		await process_frame
		for item: Dictionary in CASES:
			if String(item["profile"]) != profile_id:
				continue
			var animation_id := String(item["animation"])
			var expected_frames := int(item["frames"])
			var has_animation := bool(actor.call("has_frame_animation", animation_id))
			var frame_count := int(actor.call("animation_frame_count", animation_id))
			var first_visible := bool(actor.call("show_frame", animation_id, 0))
			var sprite := actor.get_node("VisualOwner/FrameSprite") as Sprite2D
			var first_size := sprite.texture.get_size() if sprite.texture != null else Vector2.ZERO
			var last_visible := bool(actor.call("show_frame", animation_id, expected_frames - 1))
			var last_size := sprite.texture.get_size() if sprite.texture != null else Vector2.ZERO
			var case_ok := has_animation \
				and frame_count == expected_frames \
				and first_visible \
				and last_visible \
				and first_size == Vector2(1112, 834) \
				and last_size == Vector2(1112, 834)
			all_ok = all_ok and case_ok
			print(
				"GREEN_EDGE_ASSET_SMOKE profile=%s animation=%s frames=%d first=%s last=%s ok=%s"
				% [profile_id, animation_id, frame_count, first_size, last_size, case_ok]
			)
		actor.queue_free()
		await process_frame
	quit(0 if all_ok else 1)
