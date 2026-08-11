shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D trail_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D trail_gradient : source_color, filter_linear, repeat_disable;
uniform sampler2D breakup_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D streaks_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D core_texture : source_color, filter_linear_mipmap, repeat_disable;

uniform vec4 trail_color : source_color = vec4(0.85, 0.15, 0.22, 1.0);
uniform vec4 streaks_color : source_color = vec4(0.91, 0.25, 0.45, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.91, 0.93, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.18, 0.42, 1.0);

uniform bool invert_texture = false;
uniform bool use_original_color = false;
uniform bool use_gradient = false;
uniform bool enable_breakup = false;
uniform bool invert_breakup = false;
uniform bool enable_streaks = false;
uniform bool invert_streaks = false;
uniform bool enable_core = false;
uniform bool invert_core = false;

uniform float breakup_strength : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float streaks_strength : hint_range(0.0, 2.0, 0.01) = 0.46;
uniform float core_strength : hint_range(0.0, 2.0, 0.01) = 1.05;
uniform float glow_strength : hint_range(0.0, 3.0, 0.01) = 0.28;
uniform float glow_radius_uv : hint_range(0.0, 0.5, 0.0001) = 0.0625;
uniform float head_light_boost : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform float body_opacity_floor : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float body_detail_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float body_white_threshold : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float breakup_threshold : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float breakup_softness : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float breakup_expansion : hint_range(0.0, 0.12, 0.001) = 0.0;
uniform float streaks_threshold : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float streaks_softness : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float streaks_expansion : hint_range(0.0, 0.12, 0.001) = 0.0;
uniform float head_white_preserve : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float head_white_length : hint_range(0.0, 0.5, 0.01) = 0.18;
uniform float alpha_gain : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float tail_fade_start : hint_range(0.0, 0.95, 0.01) = 0.6;

// 0 normal, 1 add, 2 screen, 3 multiply.
uniform int streaks_blend_mode = 2;
uniform int core_blend_mode = 1;
// 0 top, 1 bottom, 2 both.
uniform int core_edge_mode = 0;


float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}


float uv_inside(vec2 uv) {
	return step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
}


float tail_alpha_at(float u) {
	float fade_u = clamp((u - tail_fade_start) / max(0.001, 1.0 - tail_fade_start), 0.0, 1.0);
	return 1.0 - pow(fade_u, 2.2);
}


float mask_response(float value, float threshold, float softness) {
	if (softness <= 0.0001) {
		return threshold <= 0.0001 ? value : step(threshold, value);
	}
	return smoothstep(threshold, min(1.0, threshold + softness), value);
}


float core_alpha_at(vec2 uv) {
	float inside = uv_inside(uv);
	vec2 safe_uv = clamp(uv, vec2(0.0), vec2(1.0));
	vec4 source = texture(core_texture, safe_uv);
	float mask = invert_core ? 1.0 - luma(source.rgb) : luma(source.rgb);
	if (core_edge_mode != 0) {
		vec2 mirrored_uv = vec2(safe_uv.x, 1.0 - safe_uv.y);
		vec4 mirrored_source = texture(core_texture, mirrored_uv);
		float mirrored = invert_core ? 1.0 - luma(mirrored_source.rgb) : luma(mirrored_source.rgb);
		mask = core_edge_mode == 2 ? max(mask, mirrored) : mirrored;
	}
	float head_boost = 1.0 + head_light_boost * (1.0 - smoothstep(0.0, 0.24, safe_uv.x));
	return clamp(inside * source.a * mask * tail_alpha_at(safe_uv.x) * head_boost, 0.0, 1.0);
}


float blurred_core_alpha(vec2 uv) {
	float radius = glow_radius_uv;
	if (radius <= 0.00001) {
		return core_alpha_at(uv);
	}
	float value = core_alpha_at(uv) * 0.16;
	value += core_alpha_at(uv + vec2(0.0, radius * 0.35)) * 0.12;
	value += core_alpha_at(uv - vec2(0.0, radius * 0.35)) * 0.12;
	value += core_alpha_at(uv + vec2(0.0, radius * 0.70)) * 0.08;
	value += core_alpha_at(uv - vec2(0.0, radius * 0.70)) * 0.08;
	value += core_alpha_at(uv + vec2(radius * 0.45, 0.0)) * 0.08;
	value += core_alpha_at(uv - vec2(radius * 0.45, 0.0)) * 0.08;
	value += core_alpha_at(uv + vec2(radius * 0.38, radius * 0.38)) * 0.06;
	value += core_alpha_at(uv + vec2(radius * 0.38, -radius * 0.38)) * 0.06;
	value += core_alpha_at(uv + vec2(-radius * 0.38, radius * 0.38)) * 0.06;
	value += core_alpha_at(uv + vec2(-radius * 0.38, -radius * 0.38)) * 0.06;
	return clamp(value / 0.96, 0.0, 1.0);
}


vec4 composite_layer(vec4 base_premultiplied, vec3 layer_color, float layer_alpha, int blend_mode) {
	float base_alpha = base_premultiplied.a;
	if (blend_mode == 0) {
		float normal_alpha = layer_alpha + base_alpha * (1.0 - layer_alpha);
		vec3 normal_rgb = layer_color * layer_alpha + base_premultiplied.rgb * (1.0 - layer_alpha);
		return vec4(normal_rgb, normal_alpha);
	}
	if (blend_mode == 1) {
		return vec4(
			base_premultiplied.rgb + layer_color * layer_alpha,
			max(base_alpha, layer_alpha)
		);
	}
	vec3 base_color = base_alpha > 0.00001 ? base_premultiplied.rgb / base_alpha : vec3(0.0);
	vec3 blended = layer_color;
	if (blend_mode == 2) {
		blended = vec3(1.0) - (vec3(1.0) - base_color) * (vec3(1.0) - layer_color);
	} else if (blend_mode == 3) {
		blended = base_color * layer_color;
	}
	float blend_alpha = layer_alpha + base_alpha * (1.0 - layer_alpha);
	vec3 blend_rgb = mix(base_premultiplied.rgb, blended, layer_alpha);
	return vec4(blend_rgb, blend_alpha);
}


void fragment() {
	float inside = uv_inside(UV);
	vec2 safe_uv = clamp(UV, vec2(0.0), vec2(1.0));
	vec4 source = texture(trail_texture, safe_uv);
	float source_luma = luma(source.rgb);
	float body_luma = invert_texture ? 1.0 - source_luma : source_luma;
	float fade = tail_alpha_at(safe_uv.x);
	float breakup_alpha = 1.0;
	if (enable_breakup) {
		vec4 breakup_source = texture(breakup_texture, safe_uv);
		float breakup_raw = invert_breakup ? 1.0 - luma(breakup_source.rgb) : luma(breakup_source.rgb);
		if (breakup_expansion > 0.0001) {
			vec3 breakup_above = texture(breakup_texture, vec2(safe_uv.x, clamp(safe_uv.y - breakup_expansion, 0.0, 1.0))).rgb;
			vec3 breakup_below = texture(breakup_texture, vec2(safe_uv.x, clamp(safe_uv.y + breakup_expansion, 0.0, 1.0))).rgb;
			float above_raw = invert_breakup ? 1.0 - luma(breakup_above) : luma(breakup_above);
			float below_raw = invert_breakup ? 1.0 - luma(breakup_below) : luma(breakup_below);
			breakup_raw = max(breakup_raw, max(above_raw, below_raw));
		}
		float breakup_luma = mask_response(breakup_raw, breakup_threshold, breakup_softness);
		breakup_alpha = 1.0 - breakup_strength * (1.0 - breakup_luma);
	}

	vec4 tint = use_gradient ? texture(trail_gradient, vec2(1.0 - safe_uv.y, 0.5)) : trail_color;
	float authored_detail = 0.44 + 0.5 * body_luma;
	float body_detail = mix(1.0, authored_detail, body_detail_strength);
	vec3 body_color = use_original_color
		? (invert_texture ? vec3(1.0) - source.rgb : source.rgb)
		: tint.rgb * body_detail;
	if (!use_original_color && body_white_threshold < 0.999) {
		float authored_white = smoothstep(body_white_threshold, min(1.0, body_white_threshold + 0.18), body_luma);
		float head_white = authored_white * (1.0 - smoothstep(
			head_white_length * 0.72,
			max(0.0001, head_white_length),
			safe_uv.x
		));
		float body_white = max(head_white, authored_white * body_detail_strength);
		body_color = mix(body_color, vec3(1.0), body_white);
	}
	float body_alpha = inside * source.a * fade * breakup_alpha;
	if (!use_original_color) {
		float body_mask = mix(body_luma, 1.0, body_opacity_floor);
		body_alpha *= clamp(body_mask * alpha_gain, 0.0, 1.0);
	}
	vec4 result = vec4(body_color * body_alpha, body_alpha);

	if (enable_streaks && streaks_strength > 0.0) {
		vec4 streak_source = texture(streaks_texture, safe_uv);
		float streak_raw = invert_streaks ? 1.0 - luma(streak_source.rgb) : luma(streak_source.rgb);
		if (streaks_expansion > 0.0001) {
			vec3 streak_above = texture(streaks_texture, vec2(safe_uv.x, clamp(safe_uv.y - streaks_expansion, 0.0, 1.0))).rgb;
			vec3 streak_below = texture(streaks_texture, vec2(safe_uv.x, clamp(safe_uv.y + streaks_expansion, 0.0, 1.0))).rgb;
			float above_raw = invert_streaks ? 1.0 - luma(streak_above) : luma(streak_above);
			float below_raw = invert_streaks ? 1.0 - luma(streak_below) : luma(streak_below);
			streak_raw = max(streak_raw, max(above_raw, below_raw));
		}
		float streak_luma = mask_response(streak_raw, streaks_threshold, streaks_softness);
		float head_fade = 1.0 - smoothstep(head_white_length * 0.72, max(0.0001, head_white_length), safe_uv.x);
		float white_body = body_white_threshold < 0.999
			? smoothstep(body_white_threshold, min(1.0, body_white_threshold + 0.18), body_luma)
			: 0.0;
		float white_protection = head_white_preserve * head_fade * white_body;
		float streak_alpha = clamp(inside * streak_source.a * streak_luma * fade * streaks_strength * (1.0 - white_protection), 0.0, 1.0);
		result = composite_layer(result, streaks_color.rgb, streak_alpha, streaks_blend_mode);
	}

	if (enable_core) {
		float halo_alpha = clamp(blurred_core_alpha(UV) * glow_strength, 0.0, 1.0);
		if (halo_alpha > 0.0) {
			result = composite_layer(result, glow_color.rgb, halo_alpha, 1);
		}
		float edge_alpha = clamp(core_alpha_at(UV) * core_strength, 0.0, 1.0);
		if (edge_alpha > 0.0) {
			result = composite_layer(result, core_color.rgb, edge_alpha, core_blend_mode);
		}
	}

	COLOR = result.a > 0.00001
		? vec4(result.rgb / result.a, result.a)
		: vec4(0.0);
}
