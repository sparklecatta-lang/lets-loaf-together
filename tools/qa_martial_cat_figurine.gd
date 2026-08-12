extends SceneTree


const EXPECTED_FIGURINE_POSITION := Vector2(260, 333)
const EXPECTED_SHADOW_POSITION := Vector2(-4, 60)
const EXPECTED_SHADOW_SCALE := Vector2(0.17, 0.022)


func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var scene := packed.instantiate()
	var figurine := scene.get_node(
		"VisualViewport/CharacterLayer/MartialCatFigurine"
	) as Sprite2D
	var shadow := figurine.get_node("MartialCatFigurineShadow") as Sprite2D
	var rose_shadow := scene.get_node(
		"VisualViewport/CharacterLayer/RosePotShadow"
	) as Sprite2D

	var reference_style_matches := shadow.texture == rose_shadow.texture \
		and shadow.self_modulate.is_equal_approx(rose_shadow.self_modulate)
	var ok := figurine.position.is_equal_approx(EXPECTED_FIGURINE_POSITION) \
		and shadow.position.is_equal_approx(EXPECTED_SHADOW_POSITION) \
		and shadow.scale.is_equal_approx(EXPECTED_SHADOW_SCALE) \
		and shadow.z_index < 0 \
		and reference_style_matches
	print(
		"MARTIAL_CAT_FIGURINE_SMOKE position=%s shadow_position=%s shadow_scale=%s reference_style=%s ok=%s"
		% [
			figurine.position,
			shadow.position,
			shadow.scale,
			reference_style_matches,
			ok,
		]
	)
	scene.free()
	quit(0 if ok else 1)
