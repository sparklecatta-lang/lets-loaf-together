extends Node2D

const TRAIL_SHADER: Shader = preload("res://xsxb_frame_tuner/runtime/xsxb_attack_trail.gdshader")
const SPEED_PROFILE = [0.94, 1.015, 0.985, 1.025, 1.035, 1.02, 0.97, 1.04]
const TAIL_WIDTH_SPEED_INFLUENCE := 0.18
const DEFAULT_TAIL_HEAD_SPEED_RATIO := 0.7
const DEFAULT_PATH_COLUMNS := 20
const DEFAULT_BEFORE_CHASE_MULTIPLIER := 0.5
const DEFAULT_AFTER_CHASE_MULTIPLIER := 2.0
const LEGACY_BEFORE_CHASE_SPEED := 110.0
const LEGACY_AFTER_CHASE_SPEED := 680.0
const TRAIL_MESH_WIDTH_ROWS := 17
const GLOW_MARGIN_ROWS := 4
const FINAL_HEAD_CAP_MARGIN_RATIO := 0.25

var actor: Node = null
var layer_name: String = "behind"
var bindings: Dictionary = {}
var renderers: Dictionary = {}


func configure(owner_actor: Node, source_bindings: Dictionary, requested_layer: String) -> void:
	actor = owner_actor
	layer_name = requested_layer
	bindings = source_bindings.duplicate(true)
	_rebuild_renderers()


func update_for_animation(animation_name: String, animation_time_s: float) -> void:
	var binding_key := "%s/%s" % [String(actor.get("frame_profile_id")), animation_name]
	var segments: Array = bindings.get(binding_key, []) as Array
	var active_ids: Dictionary = {}
	for segment_value in segments:
		if not segment_value is Dictionary:
			continue
		var segment: Dictionary = segment_value
		var segment_id := "%s:%s" % [binding_key, String(segment.get("id", "trail"))]
		active_ids[segment_id] = true
		var state: Dictionary = renderers.get(segment_id, {})
		if state.is_empty():
			state = _create_renderer(segment_id, segment)
			renderers[segment_id] = state
		_update_renderer(state, segment, animation_name, animation_time_s)
	for renderer_id in renderers.keys():
		var state: Dictionary = renderers.get(renderer_id, {})
		var mesh_instance: MeshInstance2D = state.get("node") as MeshInstance2D
		if mesh_instance != null and not active_ids.has(renderer_id):
			mesh_instance.visible = false
			state["last_animation"] = ""
			state["last_sample_time"] = -1.0


func _rebuild_renderers() -> void:
	for child in get_children():
		child.queue_free()
	renderers.clear()


func _create_renderer(segment_id: String, segment: Dictionary) -> Dictionary:
	var mesh_instance := MeshInstance2D.new()
	mesh_instance.name = "Trail_%s" % segment_id.replace("/", "_").replace(":", "_")
	mesh_instance.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mesh := ArrayMesh.new()
	mesh_instance.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = TRAIL_SHADER
	mesh_instance.material = material
	add_child(mesh_instance)
	_apply_material(material, segment)
	return {
		"node": mesh_instance,
		"mesh": mesh,
		"material": material,
		"signature": "",
		"times": PackedFloat32Array(),
		"path_times": PackedFloat32Array(),
		"path_distances": PackedFloat32Array(),
		"path_total": 0.0,
		"speeds": PackedFloat32Array(),
		"last_animation": "",
		"last_sample_time": -1.0,
		"last_frame": -1,
	}


func _apply_material(material: ShaderMaterial, segment: Dictionary) -> void:
	var texture_data: Dictionary = segment.get("texture", {}) if segment.get("texture", {}) is Dictionary else {}
	var texture_path := String(texture_data.get("path", ""))
	var texture: Texture2D = load(texture_path) as Texture2D if texture_path != "" else null
	var breakup := _material_layer(segment, "breakup")
	var streaks := _material_layer(segment, "streaks")
	var core := _material_layer(segment, "core")
	var breakup_texture := _material_texture(breakup)
	var streaks_texture := _material_texture(streaks)
	var core_texture := _material_texture(core)
	var glow_radius := clampf(float(segment.get("glowRadius", segment.get("glow_radius", 16.0))), 0.0, 60.0)
	var core_texture_height := float(core_texture.get_height()) if core_texture != null else maxf(1.0, float((core.get("texture", {}) as Dictionary).get("height", 256)))
	material.set_shader_parameter("trail_texture", texture)
	material.set_shader_parameter("trail_color", Color.from_string(String(segment.get("color", "#d9364a")), Color(0.85, 0.15, 0.22, 1.0)))
	material.set_shader_parameter("invert_texture", bool(segment.get("invertTexture", false)))
	var color_mode := String(segment.get("colorMode", "solid"))
	material.set_shader_parameter("use_original_color", color_mode == "original")
	material.set_shader_parameter("use_gradient", color_mode == "gradient")
	material.set_shader_parameter("trail_gradient", _gradient_texture(segment))
	material.set_shader_parameter("alpha_gain", 1.0)
	material.set_shader_parameter("body_opacity_floor", clampf(float(segment.get("bodyOpacityFloor", segment.get("body_opacity_floor", 0.0))), 0.0, 1.0))
	material.set_shader_parameter("body_detail_strength", clampf(float(segment.get("bodyDetailStrength", segment.get("body_detail_strength", 1.0))), 0.0, 1.0))
	material.set_shader_parameter("body_white_threshold", clampf(float(segment.get("bodyWhiteThreshold", segment.get("body_white_threshold", 1.0))), 0.0, 1.0))
	material.set_shader_parameter("tail_fade_start", clampf(float(segment.get("tailFadeStart", 0.6)), 0.0, 0.95))
	material.set_shader_parameter("breakup_texture", breakup_texture)
	material.set_shader_parameter("enable_breakup", _material_enabled(breakup) and breakup_texture != null)
	material.set_shader_parameter("breakup_strength", clampf(float(breakup.get("strength", 0.72)), 0.0, 1.0))
	material.set_shader_parameter("invert_breakup", bool(breakup.get("invert", false)))
	material.set_shader_parameter("breakup_threshold", clampf(float(breakup.get("threshold", 0.0)), 0.0, 1.0))
	material.set_shader_parameter("breakup_softness", clampf(float(breakup.get("softness", 0.0)), 0.0, 1.0))
	material.set_shader_parameter("breakup_expansion", clampf(float(breakup.get("expansion", 0.0)), 0.0, 0.12))
	material.set_shader_parameter("streaks_texture", streaks_texture)
	material.set_shader_parameter("enable_streaks", _material_enabled(streaks) and streaks_texture != null)
	material.set_shader_parameter("streaks_color", Color.from_string(String(streaks.get("color", "#e93f73")), Color(0.91, 0.25, 0.45, 1.0)))
	material.set_shader_parameter("streaks_strength", clampf(float(streaks.get("strength", 0.46)), 0.0, 2.0))
	material.set_shader_parameter("streaks_blend_mode", _blend_mode_id(String(streaks.get("blendMode", "screen"))))
	material.set_shader_parameter("invert_streaks", bool(streaks.get("invert", false)))
	material.set_shader_parameter("streaks_threshold", clampf(float(streaks.get("threshold", 0.0)), 0.0, 1.0))
	material.set_shader_parameter("streaks_softness", clampf(float(streaks.get("softness", 0.0)), 0.0, 1.0))
	material.set_shader_parameter("streaks_expansion", clampf(float(streaks.get("expansion", 0.0)), 0.0, 0.12))
	material.set_shader_parameter("core_texture", core_texture)
	material.set_shader_parameter("enable_core", _material_enabled(core) and core_texture != null)
	material.set_shader_parameter("core_color", Color.from_string(String(core.get("color", "#ffe7ee")), Color(1.0, 0.91, 0.93, 1.0)))
	material.set_shader_parameter("core_strength", clampf(float(core.get("strength", 1.05)), 0.0, 2.0))
	material.set_shader_parameter("core_blend_mode", _blend_mode_id(String(core.get("blendMode", "add"))))
	material.set_shader_parameter("invert_core", bool(core.get("invert", false)))
	material.set_shader_parameter("core_edge_mode", _core_edge_id(String(segment.get("coreEdge", segment.get("core_edge", "top")))))
	material.set_shader_parameter("glow_color", Color.from_string(String(segment.get("glowColor", segment.get("glow_color", "#ff2d6a"))), Color(1.0, 0.18, 0.42, 1.0)))
	material.set_shader_parameter("glow_strength", clampf(float(segment.get("glowStrength", segment.get("glow_strength", 0.28))), 0.0, 3.0))
	material.set_shader_parameter("glow_radius_uv", glow_radius / maxf(1.0, core_texture_height))
	material.set_shader_parameter("head_light_boost", clampf(float(segment.get("headLightBoost", segment.get("head_light_boost", 0.55))), 0.0, 2.0))
	material.set_shader_parameter("head_white_preserve", clampf(float(segment.get("headWhitePreserve", segment.get("head_white_preserve", 0.0))), 0.0, 1.0))
	material.set_shader_parameter("head_white_length", clampf(float(segment.get("headWhiteLength", segment.get("head_white_length", 0.18))), 0.0, 0.5))


func _material_layer(segment: Dictionary, layer_id: String) -> Dictionary:
	var layers: Dictionary = segment.get("materialLayers", segment.get("material_layers", {})) if segment.get("materialLayers", segment.get("material_layers", {})) is Dictionary else {}
	var layer: Variant = layers.get(layer_id, {})
	return layer if layer is Dictionary else {}


func _material_texture(layer: Dictionary) -> Texture2D:
	var texture_data: Dictionary = layer.get("texture", {}) if layer.get("texture", {}) is Dictionary else {}
	var texture_path := String(texture_data.get("path", ""))
	return load(texture_path) as Texture2D if texture_path != "" else null


func _material_enabled(layer: Dictionary) -> bool:
	return not layer.is_empty() and layer.get("enabled", true) != false


func _blend_mode_id(value: String) -> int:
	match value.to_lower():
		"normal":
			return 0
		"screen":
			return 2
		"multiply":
			return 3
		_:
			return 1


func _core_edge_id(value: String) -> int:
	match value.to_lower():
		"bottom":
			return 1
		"both":
			return 2
		_:
			return 0


func _gradient_texture(segment: Dictionary) -> GradientTexture1D:
	var fallback := Color.from_string(String(segment.get("color", "#d9364a")), Color(0.85, 0.15, 0.22, 1.0))
	var stop_values: Array = segment.get("gradientStops", []) as Array
	var normalized: Array[Dictionary] = []
	for index in range(mini(stop_values.size(), 16)):
		var value: Variant = stop_values[index]
		if not value is Dictionary:
			continue
		var stop: Dictionary = value
		normalized.append({
			"position": clampf(float(stop.get("position", stop.get("offset", 0.0))), 0.0, 1.0),
			"color": Color.from_string(String(stop.get("color", fallback.to_html(false))), fallback),
		})
	if normalized.size() < 2:
		normalized = [
			{"position": 0.0, "color": fallback},
			{"position": 1.0, "color": fallback},
		]
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["position"]) < float(b["position"]))
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in normalized:
		offsets.append(float(stop["position"]))
		colors.append(stop["color"] as Color)
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	var texture := GradientTexture1D.new()
	texture.width = 256
	texture.gradient = gradient
	return texture


func _update_renderer(state: Dictionary, segment: Dictionary, animation_name: String, animation_time_s: float) -> void:
	var node: MeshInstance2D = state.get("node") as MeshInstance2D
	if node == null:
		return
	var sticks: Array = segment.get("sticks", []) as Array
	if segment.get("enabled", true) == false or segment.get("generated", true) == false or sticks.size() < 2:
		node.visible = false
		return
	var signature := _timing_signature(segment, animation_name)
	if String(state.get("signature", "")) != signature:
		_rebuild_path_cache(state, segment, animation_name)
		state["signature"] = signature
		state["last_sample_time"] = -1.0
		state["last_frame"] = -1
		_apply_material(state.get("material") as ShaderMaterial, segment)
	var current_frame := int(actor.get("_current_frame"))
	if String(state.get("last_animation", "")) == animation_name \
			and int(state.get("last_frame", -1)) == current_frame \
			and is_equal_approx(float(state.get("last_sample_time", -1.0)), animation_time_s):
		return
	state["last_animation"] = animation_name
	state["last_sample_time"] = animation_time_s
	state["last_frame"] = current_frame
	var times: PackedFloat32Array = state.get("times", PackedFloat32Array())
	if times.size() < 2:
		node.visible = false
		return
	var frame_slices_value: Variant = segment.get("frameSlices", segment.get("frame_slices", null))
	if frame_slices_value is Dictionary:
		var frame_slices: Dictionary = frame_slices_value
		var slice_value: Variant = frame_slices.get(str(current_frame), null)
		if not slice_value is Dictionary:
			node.visible = false
			return
		var frame_slice: Dictionary = slice_value
		if frame_slice.get("enabled", true) == false:
			node.visible = false
			return
		var tail_progress := clampf(float(frame_slice.get("tailProgress", frame_slice.get("tail_progress", 0.0))), 0.0, 1.0)
		var head_progress := clampf(float(frame_slice.get("headProgress", frame_slice.get("head_progress", 1.0))), 0.0, 1.0)
		if tail_progress > head_progress:
			var swap := tail_progress
			tail_progress = head_progress
			head_progress = swap
		var path_total := float(state.get("path_total", 0.0))
		var current_distance := path_total * head_progress
		var tail_distance := path_total * tail_progress
		if current_distance - tail_distance <= 0.01:
			node.visible = false
			return
		var current_path_time := _local_time_at_distance(state, current_distance)
		var tail_distances := PackedFloat32Array()
		for _row in range(maxi(4, int(segment.get("tailSamples", 5)))):
			tail_distances.append(tail_distance)
		node.visible = _rebuild_mesh(state, segment, current_distance, current_path_time, tail_distances, 0.0)
		return
	var local_time := animation_time_s - times[0]
	if local_time < 0.0:
		node.visible = false
		return
	var motion_duration := maxf(0.000001, float(state.get("motion_duration", times[-1] - times[0])))
	var total_duration := maxf(motion_duration, float(state.get("total_duration", motion_duration)))
	if local_time >= total_duration:
		node.visible = false
		return
	var path_total := float(state.get("path_total", 0.0))
	var current_time := minf(local_time, motion_duration)
	var current_path_time := _head_path_time(sticks, state.get("local_times", PackedFloat32Array()), current_time)
	var current_distance := _distance_at_local_time(state, current_path_time)
	var speeds: PackedFloat32Array = state.get("speeds", PackedFloat32Array())
	var tail_duration := maxf(0.000001, total_duration - motion_duration)
	var tail_progress := clampf((local_time - motion_duration) / tail_duration, 0.0, 1.0)
	var collapse_phase := tail_progress
	var tail_distances := PackedFloat32Array()
	for speed_factor_value in speeds:
		var speed_factor: float = 1.0 + (float(speed_factor_value) - 1.0) * TAIL_WIDTH_SPEED_INFLUENCE
		var endpoint_safe_wobble := (speed_factor - 1.0) * 4.0 * tail_progress * (1.0 - tail_progress)
		var sample_tail_progress := clampf(tail_progress + endpoint_safe_wobble, 0.0, 1.0)
		tail_distances.append(minf(current_distance, path_total * sample_tail_progress))
	tail_distances = _guard_tail_edge_progress(tail_distances)
	if current_distance <= 0.01:
		node.visible = false
		return
	node.visible = true
	if node.visible:
		node.visible = _rebuild_mesh(state, segment, current_distance, current_path_time, tail_distances, collapse_phase)


func _legacy_chase_multiplier(segment: Dictionary, before: bool) -> float:
	var key: String = "beforeStopChaseMultiplier" if before else "afterStopChaseMultiplier"
	var snake_key: String = "before_stop_chase_multiplier" if before else "after_stop_chase_multiplier"
	var fallback: float = DEFAULT_BEFORE_CHASE_MULTIPLIER if before else DEFAULT_AFTER_CHASE_MULTIPLIER
	var minimum: float = 0.0 if before else 0.1
	var maximum: float = 1.0 if before else 20.0
	if segment.has(key):
		return clampf(float(segment.get(key, fallback)), minimum, maximum)
	if segment.has(snake_key):
		return clampf(float(segment.get(snake_key, fallback)), minimum, maximum)
	var legacy_key: String = "beforeStopChaseSpeed" if before else "afterStopChaseSpeed"
	var legacy_snake_key: String = "before_stop_chase_speed" if before else "after_stop_chase_speed"
	var legacy_default: float = LEGACY_BEFORE_CHASE_SPEED if before else LEGACY_AFTER_CHASE_SPEED
	var legacy_value: float = float(segment.get(legacy_key, segment.get(legacy_snake_key, legacy_default)))
	return clampf(legacy_value / legacy_default * fallback, minimum, maximum)


func _tail_head_speed_ratio(segment: Dictionary) -> float:
	if segment.has("tailHeadSpeedRatio"):
		return clampf(float(segment.get("tailHeadSpeedRatio", DEFAULT_TAIL_HEAD_SPEED_RATIO)), 0.01, 0.9)
	if segment.has("tail_head_speed_ratio"):
		return clampf(float(segment.get("tail_head_speed_ratio", DEFAULT_TAIL_HEAD_SPEED_RATIO)), 0.01, 0.9)
	var has_legacy_timing := segment.has("beforeStopChaseMultiplier") \
		or segment.has("before_stop_chase_multiplier") \
		or segment.has("afterStopChaseMultiplier") \
		or segment.has("after_stop_chase_multiplier") \
		or segment.has("beforeStopChaseSpeed") \
		or segment.has("before_stop_chase_speed") \
		or segment.has("afterStopChaseSpeed") \
		or segment.has("after_stop_chase_speed")
	if not has_legacy_timing:
		return DEFAULT_TAIL_HEAD_SPEED_RATIO
	var before := _legacy_chase_multiplier(segment, true)
	var after := _legacy_chase_multiplier(segment, false)
	return clampf(1.0 / (1.0 + maxf(0.0, 1.0 - before) / maxf(0.0001, after)), 0.01, 0.9)


func _total_duration_s(segment: Dictionary, animation_name: String, sticks: Array) -> float:
	var saved_ms := float(segment.get("totalDurationMs", segment.get("total_duration_ms", 0.0)))
	if saved_ms > 0.0:
		return clampf(saved_ms / 1000.0, 0.001, 60.0)
	if sticks.is_empty():
		return 1.0 / 12.0
	var first_stick: Dictionary = sticks[0] if sticks[0] is Dictionary else {}
	var frame := int(first_stick.get("frame", 0))
	if actor.has_method("trail_frame_duration"):
		return clampf(float(actor.call("trail_frame_duration", animation_name, frame)), 0.001, 60.0)
	return 1.0 / 12.0


func _timing_signature(segment: Dictionary, animation_name: String) -> String:
	var parts: PackedStringArray = []
	for stick_value in segment.get("sticks", []) as Array:
		if not stick_value is Dictionary:
			continue
		var stick: Dictionary = stick_value
		var frame := int(stick.get("frame", 0))
		parts.append("%d:%.6f:%.6f" % [frame, float(stick.get("framePhase", 0.5)), float(actor.call("trail_frame_arrival_time", animation_name, frame, float(stick.get("framePhase", 0.5))))])
	parts.append(JSON.stringify(segment.get("sticks", [])))
	parts.append(str(segment.get("tailSamples", 5)))
	parts.append(str(segment.get("widthMode", segment.get("width_mode", "authored"))))
	parts.append(str(segment.get("fixedWidth", segment.get("fixed_width", 160.0))))
	parts.append(str(segment.get("widthScale", segment.get("width_scale", 1.0))))
	parts.append(str(segment.get("widthOffset", segment.get("width_offset", 0.0))))
	parts.append(str(segment.get("widthChaseStrength", segment.get("width_chase_strength", 1.0))))
	parts.append(str(segment.get("pathScaleX", segment.get("path_scale_x", 1.0))))
	parts.append(str(segment.get("pathScaleY", segment.get("path_scale_y", 1.0))))
	parts.append(str(segment.get("stableSeed", 73129)))
	parts.append(str(segment.get("tailFadeStart", 0.6)))
	parts.append(str(segment.get("totalDurationMs", segment.get("total_duration_ms", 0))))
	parts.append(str(_tail_head_speed_ratio(segment)))
	parts.append(str(_total_duration_s(segment, animation_name, segment.get("sticks", []) as Array)))
	return "|".join(parts)


func _rebuild_path_cache(state: Dictionary, segment: Dictionary, animation_name: String) -> void:
	var sticks: Array = segment.get("sticks", []) as Array
	var head_indices := PackedInt32Array()
	var head_times := PackedFloat32Array()
	var previous_time := -1.0
	for stick_index in range(sticks.size()):
		var stick_value: Variant = sticks[stick_index]
		var stick: Dictionary = stick_value if stick_value is Dictionary else {}
		if not _stick_is_head_frame(stick):
			continue
		var arrival := float(actor.call("trail_frame_arrival_time", animation_name, int(stick.get("frame", 0)), float(stick.get("framePhase", 0.5))))
		arrival = maxf(arrival, previous_time + 0.0001)
		head_indices.append(stick_index)
		head_times.append(arrival)
		previous_time = arrival
	if not sticks.is_empty() and (head_indices.is_empty() or head_indices[0] != 0):
		var first_stick: Dictionary = sticks[0] if sticks[0] is Dictionary else {}
		head_indices.insert(0, 0)
		head_times.insert(0, float(actor.call("trail_frame_arrival_time", animation_name, int(first_stick.get("frame", 0)), float(first_stick.get("framePhase", 0.5)))))
	if sticks.size() > 1 and head_indices[-1] != sticks.size() - 1:
		head_indices.append(sticks.size() - 1)
		var last_stick: Dictionary = sticks[-1] if sticks[-1] is Dictionary else {}
		head_times.append(maxf(float(actor.call("trail_frame_arrival_time", animation_name, int(last_stick.get("frame", 0)), float(last_stick.get("framePhase", 0.5)))), head_times[-1] + 0.0001))
	var authored_origin := head_times[0] if not head_times.is_empty() else 0.0
	var lifecycle_first_stick: Dictionary = sticks[0] if not sticks.is_empty() and sticks[0] is Dictionary else {}
	var origin := float(actor.call("trail_frame_arrival_time", animation_name, int(lifecycle_first_stick.get("frame", 0)), 0.0))
	var total_duration := _total_duration_s(segment, animation_name, sticks)
	var speed_ratio := _tail_head_speed_ratio(segment)
	var motion_duration := maxf(0.000001, total_duration * speed_ratio / (1.0 + speed_ratio))
	var authored_span := maxf(0.0001, head_times[-1] - authored_origin)
	var head_local_times := PackedFloat32Array()
	for head_index in range(head_times.size()):
		if head_index == head_times.size() - 1:
			head_local_times.append(motion_duration)
		else:
			head_local_times.append(motion_duration * clampf((head_times[head_index] - authored_origin) / authored_span, 0.0, 1.0))
	var local_times := PackedFloat32Array()
	local_times.resize(sticks.size())
	local_times.fill(head_local_times[0] if not head_local_times.is_empty() else 0.0)
	for head_index in range(head_indices.size() - 1):
		var start_index := head_indices[head_index]
		var end_index := head_indices[head_index + 1]
		for stick_index in range(start_index, end_index + 1):
			var phase := float(stick_index - start_index) / float(maxi(1, end_index - start_index))
			local_times[stick_index] = lerpf(head_local_times[head_index], head_local_times[head_index + 1], phase)
	var absolute_times := PackedFloat32Array()
	for local_time in local_times:
		absolute_times.append(origin + local_time)
	state["times"] = absolute_times
	state["local_times"] = local_times
	state["motion_duration"] = motion_duration
	state["total_duration"] = total_duration
	var sample_count := maxi(32, int(segment.get("pathCacheSamples", 192)))
	var path_times := PackedFloat32Array()
	var path_distances := PackedFloat32Array()
	var duration := maxf(0.0001, local_times[-1])
	var previous_pose := _pose_at_local_time(sticks, local_times, 0.0)
	var cumulative := 0.0
	for sample_index in range(sample_count):
		var sample_time := duration * float(sample_index) / float(sample_count - 1)
		var pose := _pose_at_local_time(sticks, local_times, sample_time)
		if sample_index > 0:
			cumulative += Vector2(previous_pose["center"]).distance_to(Vector2(pose["center"]))
		path_times.append(sample_time)
		path_distances.append(cumulative)
		previous_pose = pose
	state["path_times"] = path_times
	state["path_distances"] = path_distances
	state["path_total"] = maxf(cumulative, 0.001)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(segment.get("stableSeed", 73129))
	var row_count := clampi(int(segment.get("tailSamples", 5)), 4, 8)
	var variation := clampf(float(segment.get("speedVariation", 0.008)), 0.0, 0.25)
	var speeds := PackedFloat32Array()
	var speed_sum := 0.0
	for row in range(row_count):
		var base: float = float(SPEED_PROFILE[mini(row, SPEED_PROFILE.size() - 1)])
		var speed: float = clampf(base + rng.randf_range(-variation, variation), 0.1, 2.0)
		speeds.append(speed)
		speed_sum += speed
	var speed_mean := speed_sum / float(row_count)
	for index in range(speeds.size()):
		speeds[index] /= speed_mean
	state["speeds"] = speeds


func _stick_is_head_frame(stick: Dictionary) -> bool:
	if stick.has("headFrame"):
		return stick.get("headFrame", true) != false
	if stick.has("head_frame"):
		return stick.get("head_frame", true) != false
	return true


func _head_path_time(sticks: Array, times: PackedFloat32Array, local_time: float) -> float:
	if sticks.is_empty() or times.is_empty():
		return 0.0
	var result := times[0]
	for index in range(mini(sticks.size(), times.size())):
		var stick: Dictionary = sticks[index] if sticks[index] is Dictionary else {}
		if not _stick_is_head_frame(stick):
			continue
		if times[index] > local_time + 0.000001:
			break
		result = times[index]
	return result


func _distance_at_local_time(state: Dictionary, local_time: float) -> float:
	var times: PackedFloat32Array = state.get("path_times", PackedFloat32Array())
	var distances: PackedFloat32Array = state.get("path_distances", PackedFloat32Array())
	if times.size() < 2:
		return 0.0
	var target := clampf(local_time, 0.0, times[-1])
	var low := 0
	var high := times.size() - 1
	while low + 1 < high:
		var middle: int = (low + high) >> 1
		if times[middle] <= target:
			low = middle
		else:
			high = middle
	var span := times[high] - times[low]
	var fraction := 0.0 if span <= 0.000001 else (target - times[low]) / span
	return lerpf(distances[low], distances[high], fraction)


func _local_time_at_distance(state: Dictionary, distance_px: float) -> float:
	var times: PackedFloat32Array = state.get("path_times", PackedFloat32Array())
	var distances: PackedFloat32Array = state.get("path_distances", PackedFloat32Array())
	if distances.size() < 2:
		return 0.0
	var target := clampf(distance_px, 0.0, distances[-1])
	var low := 0
	var high := distances.size() - 1
	while low + 1 < high:
		var middle: int = (low + high) >> 1
		if distances[middle] <= target:
			low = middle
		else:
			high = middle
	var span := distances[high] - distances[low]
	var fraction := 0.0 if span <= 0.000001 else (target - distances[low]) / span
	return lerpf(times[low], times[high], fraction)


func _pose_at_local_time(sticks: Array, times: PackedFloat32Array, local_time: float) -> Dictionary:
	if sticks.is_empty():
		return {"top": Vector2.ZERO, "bottom": Vector2(0.0, 1.0), "center": Vector2(0.0, 0.5)}
	if sticks.size() == 1 or local_time <= times[0]:
		return _stick_pose(sticks[0])
	if local_time >= times[-1]:
		return _stick_pose(sticks[-1])
	var segment_index := 0
	for index in range(times.size() - 1):
		if local_time <= times[index + 1]:
			segment_index = index
			break
	var from_stick: Dictionary = sticks[segment_index]
	var to_stick: Dictionary = sticks[segment_index + 1]
	var from_pose := _stick_pose(from_stick)
	var to_pose := _stick_pose(to_stick)
	var span := maxf(0.0001, times[segment_index + 1] - times[segment_index])
	var t := clampf((local_time - times[segment_index]) / span, 0.0, 1.0)
	var from_direction := _stick_direction(from_stick)
	var to_direction := _stick_direction(to_stick)
	var from_strength := float(from_stick.get("tangentStrength", 0.8))
	var to_strength := float(to_stick.get("tangentStrength", 0.8))
	var from_top := Vector2(from_pose["top"])
	var to_top := Vector2(to_pose["top"])
	var from_bottom := Vector2(from_pose["bottom"])
	var to_bottom := Vector2(to_pose["bottom"])
	var top_distance := from_top.distance_to(to_top)
	var bottom_distance := from_bottom.distance_to(to_bottom)
	var top := _hermite(from_top, from_direction * top_distance * from_strength, to_top, to_direction * top_distance * to_strength, t)
	var bottom := _hermite(from_bottom, from_direction * bottom_distance * from_strength, to_bottom, to_direction * bottom_distance * to_strength, t)
	return {"top": top, "bottom": bottom, "center": (top + bottom) * 0.5}


func _stick_pose(stick_value: Variant) -> Dictionary:
	var stick: Dictionary = stick_value if stick_value is Dictionary else {}
	var top := _vector(stick.get("top", {}), Vector2(0.0, -60.0))
	var bottom := _vector(stick.get("bottom", {}), Vector2(0.0, 60.0))
	if stick.get("reverseDirection", false) == true:
		var swap := top
		top = bottom
		bottom = swap
	return {"top": top, "bottom": bottom, "center": (top + bottom) * 0.5}


func _stick_direction(stick: Dictionary) -> Vector2:
	var pose := _stick_pose(stick)
	var axis := (Vector2(pose["bottom"]) - Vector2(pose["top"])).normalized()
	# The Tuner defines the forward normal as (-dy, dx). Godot's
	# Vector2.orthogonal() returns (dy, -dx), which is the opposite direction.
	var tuner_normal := Vector2(-axis.y, axis.x)
	return tuner_normal.rotated(deg_to_rad(clampf(float(stick.get("directionOffset", 0.0)), -180.0, 180.0)))


func _direction_at_local_time(sticks: Array, times: PackedFloat32Array, local_time: float) -> Vector2:
	if sticks.is_empty():
		return Vector2.RIGHT
	if sticks.size() == 1 or local_time <= times[0]:
		return _stick_direction(sticks[0])
	if local_time >= times[-1]:
		return _stick_direction(sticks[-1])
	var segment_index := 0
	for index in range(times.size() - 1):
		if local_time <= times[index + 1]:
			segment_index = index
			break
	var span := maxf(0.0001, times[segment_index + 1] - times[segment_index])
	var phase := clampf((local_time - times[segment_index]) / span, 0.0, 1.0)
	var direction := _stick_direction(sticks[segment_index]).lerp(_stick_direction(sticks[segment_index + 1]), phase)
	return direction.normalized() if direction.length_squared() > 0.000001 else _stick_direction(sticks[segment_index])


func _layer_at_local_time(sticks: Array, times: PackedFloat32Array, local_time: float, fallback: String) -> String:
	if sticks.is_empty():
		return fallback
	if sticks.size() == 1 or local_time <= times[0]:
		return String((sticks[0] as Dictionary).get("layer", fallback))
	if local_time >= times[-1]:
		return String((sticks[-1] as Dictionary).get("layer", fallback))
	var segment_index := 0
	for index in range(times.size() - 1):
		if local_time <= times[index + 1]:
			segment_index = index
			break
	var span := maxf(0.0001, times[segment_index + 1] - times[segment_index])
	var phase := clampf((local_time - times[segment_index]) / span, 0.0, 1.0)
	var selected_index := segment_index if phase < 0.5 else segment_index + 1
	return String((sticks[selected_index] as Dictionary).get("layer", fallback))


func _triangle_touches_layer(sticks: Array, times: PackedFloat32Array, sample_times: PackedFloat32Array, triangle: PackedInt32Array, fallback: String) -> bool:
	# Keep the one mesh cell that crosses a layer boundary in both render
	# passes. The tiny overlap closes the seam without moving the rest of a
	# behind trail in front of the character.
	for vertex_index in triangle:
		if _layer_at_local_time(sticks, times, sample_times[vertex_index], fallback) == layer_name:
			return true
	return false


func _hermite(start: Vector2, start_tangent: Vector2, end: Vector2, end_tangent: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * start + (t3 - 2.0 * t2 + t) * start_tangent + (-2.0 * t3 + 3.0 * t2) * end + (t3 - t2) * end_tangent


func _rebuild_mesh(state: Dictionary, segment: Dictionary, current_distance: float, current_time: float, tail_distances: PackedFloat32Array, collapse_phase: float) -> bool:
	var mesh: ArrayMesh = state.get("mesh") as ArrayMesh
	var sticks: Array = segment.get("sticks", []) as Array
	var local_times: PackedFloat32Array = state.get("local_times", PackedFloat32Array())
	if mesh == null or local_times.size() < 2:
		return false
	# Chase samples control lag, not visible tessellation. A five-row mesh makes
	# an otherwise curved leading edge read as a diamond-shaped point.
	var body_row_count: int = maxi(TRAIL_MESH_WIDTH_ROWS, tail_distances.size())
	var glow_padding := _glow_padding(segment)
	var glow_uv_padding := _glow_uv_padding(segment)
	var glow_margin_rows := GLOW_MARGIN_ROWS if glow_padding > 0.0 and glow_uv_padding > 0.0 else 0
	var row_count: int = body_row_count + glow_margin_rows * 2
	var column_count := clampi(maxi(16, int(segment.get("pathColumns", DEFAULT_PATH_COLUMNS)) * 2), 16, 192)
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var sample_times := PackedFloat32Array()
	var indices := PackedInt32Array()
	var path_pivot := _path_pivot(sticks)
	var current_pose := _styled_width_pose(
		_styled_path_pose(
			_pose_at_local_time(sticks, local_times, current_time),
			segment,
			path_pivot
		),
		segment
	)
	var raw_head_direction := _direction_at_local_time(sticks, local_times, current_time)
	var scaled_head_direction := Vector2(
		raw_head_direction.x * clampf(float(segment.get("pathScaleX", segment.get("path_scale_x", 1.0))), 0.25, 3.0),
		raw_head_direction.y * clampf(float(segment.get("pathScaleY", segment.get("path_scale_y", 1.0))), 0.25, 3.0)
	)
	var head_direction := scaled_head_direction.normalized()
	var head_half_width := Vector2(current_pose["top"]).distance_to(Vector2(current_pose["bottom"])) * 0.5
	var head_curvature := float(segment.get("headCurvature", 0.0))
	var terminal_cap_depth := maxf(2.0, head_half_width * (absf(head_curvature) + FINAL_HEAD_CAP_MARGIN_RATIO)) * (1.0 - collapse_phase)
	var terminal_cap_blend := _terminal_head_cap_blend(current_distance, tail_distances, terminal_cap_depth, collapse_phase)
	var center_tail_distance := _mesh_tail_distance(tail_distances, 0.5)
	var width_chase_strength := clampf(float(segment.get("widthChaseStrength", segment.get("width_chase_strength", 1.0))), 0.0, 1.0)
	for row in range(row_count):
		var v := _mesh_v(row, body_row_count, glow_margin_rows, glow_uv_padding)
		var authored_tail_distance: float = _mesh_tail_distance(tail_distances, v)
		var tail_distance := lerpf(center_tail_distance, authored_tail_distance, width_chase_strength)
		for column in range(column_count):
			var u := float(column) / float(column_count - 1)
			var sample_distance := lerpf(current_distance, tail_distance, u)
			var sample_time := _local_time_at_distance(state, sample_distance)
			var pose := _styled_width_pose(
				_styled_path_pose(
					_pose_at_local_time(sticks, local_times, sample_time),
					segment,
					path_pivot
				),
				segment
			)
			var point := _width_point(pose, v, glow_padding, glow_uv_padding)
			var head_profile: float = _head_curve_profile(v) * _head_curve_blend(u)
			var bulge := head_curvature * head_half_width * head_profile
			point -= head_direction * bulge
			if terminal_cap_blend > 0.0:
				var cap_base := _width_point(current_pose, v, glow_padding, glow_uv_padding)
				var cap_point := cap_base - head_direction * (bulge + terminal_cap_depth * u)
				point = point.lerp(cap_point, terminal_cap_blend)
				if terminal_cap_blend >= 0.5:
					sample_time = current_time
			vertices.append(point)
			uvs.append(Vector2(u, v))
			sample_times.append(sample_time)
	for row in range(row_count - 1):
		for column in range(column_count - 1):
			var top_left := row * column_count + column
			var top_right := top_left + 1
			var bottom_left := (row + 1) * column_count + column
			var bottom_right := bottom_left + 1
			var first := PackedInt32Array([top_left, top_right, bottom_right])
			var second := PackedInt32Array([top_left, bottom_right, bottom_left])
			for triangle_value in [first, second]:
				var triangle: PackedInt32Array = triangle_value
				if _triangle_touches_layer(sticks, local_times, sample_times, triangle, String(segment.get("layer", "behind"))):
					indices.append_array(triangle)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.clear_surfaces()
	if indices.is_empty():
		return false
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return true


func _glow_padding(segment: Dictionary) -> float:
	var core := _material_layer(segment, "core")
	if not _material_enabled(core):
		return 0.0
	if float(segment.get("glowStrength", segment.get("glow_strength", 0.28))) <= 0.0:
		return 0.0
	return clampf(float(segment.get("glowRadius", segment.get("glow_radius", 16.0))), 0.0, 60.0)


func _glow_uv_padding(segment: Dictionary) -> float:
	var core := _material_layer(segment, "core")
	var texture_data: Dictionary = core.get("texture", {}) if core.get("texture", {}) is Dictionary else {}
	var texture_height := maxf(1.0, float(texture_data.get("height", 256)))
	return minf(0.45, _glow_padding(segment) / texture_height)


func _mesh_v(row: int, body_row_count: int, margin_rows: int, uv_padding: float) -> float:
	if margin_rows <= 0:
		return float(row) / float(maxi(1, body_row_count - 1))
	if row < margin_rows:
		return -uv_padding * float(margin_rows - row) / float(margin_rows)
	if row >= margin_rows + body_row_count:
		return 1.0 + uv_padding * float(row - (margin_rows + body_row_count) + 1) / float(margin_rows)
	return float(row - margin_rows) / float(maxi(1, body_row_count - 1))


func _width_point(pose: Dictionary, v: float, padding: float, uv_padding: float) -> Vector2:
	var top := Vector2(pose["top"])
	var bottom := Vector2(pose["bottom"])
	var point := top.lerp(bottom, clampf(v, 0.0, 1.0))
	if uv_padding <= 0.000001 or (v >= 0.0 and v <= 1.0):
		return point
	var axis := (bottom - top).normalized()
	if v < 0.0:
		return point - axis * padding * minf(1.0, -v / uv_padding)
	return point + axis * padding * minf(1.0, (v - 1.0) / uv_padding)


func _styled_width_pose(pose: Dictionary, segment: Dictionary) -> Dictionary:
	var top := Vector2(pose["top"])
	var bottom := Vector2(pose["bottom"])
	var center := Vector2(pose["center"])
	var delta := bottom - top
	var authored_width := maxf(0.001, delta.length())
	var axis := delta / authored_width
	var width_mode := String(segment.get("widthMode", segment.get("width_mode", "authored")))
	var base_width := clampf(float(segment.get("fixedWidth", segment.get("fixed_width", 160.0))), 8.0, 600.0) if width_mode == "fixed" else authored_width
	var width_scale := clampf(float(segment.get("widthScale", segment.get("width_scale", 1.0))), 0.1, 3.0)
	var width := maxf(0.001, base_width * width_scale)
	var width_offset := clampf(float(segment.get("widthOffset", segment.get("width_offset", 0.0))), -1.0, 1.0)
	center += axis * width * 0.5 * width_offset
	return {
		"top": center - axis * width * 0.5,
		"bottom": center + axis * width * 0.5,
		"center": center,
	}


func _path_pivot(sticks: Array) -> Vector2:
	if sticks.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	var count := 0
	for stick_value in sticks:
		if not stick_value is Dictionary:
			continue
		var pose := _stick_pose(stick_value as Dictionary)
		total += Vector2(pose["center"])
		count += 1
	return total / float(maxi(1, count))


func _styled_path_pose(pose: Dictionary, segment: Dictionary, pivot: Vector2) -> Dictionary:
	var scale_x := clampf(float(segment.get("pathScaleX", segment.get("path_scale_x", 1.0))), 0.25, 3.0)
	var scale_y := clampf(float(segment.get("pathScaleY", segment.get("path_scale_y", 1.0))), 0.25, 3.0)
	var top := Vector2(pose["top"])
	var bottom := Vector2(pose["bottom"])
	var center := Vector2(pose["center"])
	return {
		"top": Vector2(pivot.x + (top.x - pivot.x) * scale_x, pivot.y + (top.y - pivot.y) * scale_y),
		"bottom": Vector2(pivot.x + (bottom.x - pivot.x) * scale_x, pivot.y + (bottom.y - pivot.y) * scale_y),
		"center": Vector2(pivot.x + (center.x - pivot.x) * scale_x, pivot.y + (center.y - pivot.y) * scale_y),
	}


func _mesh_tail_distance(tail_distances: PackedFloat32Array, v: float) -> float:
	if tail_distances.size() <= 1:
		return tail_distances[0] if not tail_distances.is_empty() else 0.0
	var scaled: float = clampf(v, 0.0, 1.0) * float(tail_distances.size() - 1)
	var index: int = mini(tail_distances.size() - 2, floori(scaled))
	var phase: float = scaled - float(index)
	var smooth_phase: float = phase * phase * (3.0 - 2.0 * phase)
	return lerpf(tail_distances[index], tail_distances[index + 1], smooth_phase)


func _guard_tail_edge_progress(tail_distances: PackedFloat32Array) -> PackedFloat32Array:
	if tail_distances.size() <= 2:
		return tail_distances
	var interior_mean := 0.0
	for index in range(1, tail_distances.size() - 1):
		interior_mean += tail_distances[index]
	interior_mean /= float(tail_distances.size() - 2)
	# Edge rows may trail slightly, but they cannot outrun the interior and
	# overwrite the authored rough alpha edge with a geometric round cap.
	tail_distances[0] = minf(tail_distances[0], interior_mean)
	tail_distances[-1] = minf(tail_distances[-1], interior_mean)
	return tail_distances


func _terminal_head_cap_blend(current_distance: float, tail_distances: PackedFloat32Array, cap_depth: float, collapse_phase: float) -> float:
	if collapse_phase <= 0.0 or cap_depth <= 0.001:
		return 0.0
	var maximum_lag := 0.0
	for tail_distance in tail_distances:
		maximum_lag = maxf(maximum_lag, absf(current_distance - float(tail_distance)))
	var phase := clampf(1.0 - maximum_lag / maxf(0.001, cap_depth), 0.0, 1.0)
	return phase * phase * (3.0 - 2.0 * phase)


func _head_curve_profile(v: float) -> float:
	# Keep the midpoint exactly on the authored leading edge. The upper and
	# lower portions alone recede into the texture as a circular cap.
	var centered: float = clampf(v, 0.0, 1.0) * 2.0 - 1.0
	return 1.0 - sqrt(maxf(0.0, 1.0 - centered * centered))


func _head_curve_blend(u: float) -> float:
	var phase: float = clampf(u / 0.35, 0.0, 1.0)
	return 1.0 - phase * phase * (3.0 - 2.0 * phase)


func _vector(value: Variant, fallback: Vector2) -> Vector2:
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return value if value is Vector2 else fallback
