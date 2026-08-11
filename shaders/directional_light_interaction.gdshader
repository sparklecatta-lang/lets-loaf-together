shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform vec2 main_source = vec2(0.91, -0.16);
uniform vec2 main_direction = vec2(-0.38, 1.0);
uniform float main_half_angle : hint_range(0.1, 1.4, 0.01) = 0.82;
uniform float main_edge_softness : hint_range(0.01, 0.25, 0.01) = 0.09;
uniform vec3 main_warm_tint = vec3(1.10, 0.98, 0.86);
uniform float main_warm_influence : hint_range(0.0, 0.4, 0.01) = 0.10;
uniform float main_occlusion_strength : hint_range(0.0, 0.4, 0.01) = 0.12;

uniform vec3 shadow_blue_tint = vec3(0.36, 0.68, 1.28);
uniform float monitor_screen_x : hint_range(0.0, 1.0, 0.01) = 0.79;
uniform float monitor_near_top : hint_range(0.0, 1.0, 0.01) = 0.14;
uniform float monitor_near_bottom : hint_range(0.0, 1.0, 0.01) = 0.56;
uniform float monitor_far_x : hint_range(0.0, 1.0, 0.01) = 0.17;
uniform float monitor_far_top : hint_range(-0.2, 1.0, 0.01) = 0.00;
uniform float monitor_far_bottom : hint_range(0.0, 1.2, 0.01) = 0.78;
uniform float monitor_white_influence : hint_range(0.0, 1.0, 0.01) = 0.36;
uniform float brush_variation : hint_range(0.0, 0.12, 0.005) = 0.03;
uniform vec2 window_min = vec2(0.21, 0.0);
uniform vec2 window_max = vec2(0.84, 0.43);
uniform float window_feather : hint_range(0.001, 0.05, 0.001) = 0.008;
uniform vec3 lower_shadow_blue_tint = vec3(0.34, 0.55, 1.16);
uniform float lower_shadow_strength : hint_range(0.0, 1.0, 0.01) = 0.50;
uniform float lower_shadow_brightness : hint_range(0.3, 1.0, 0.01) = 0.62;
uniform float lower_shadow_start_left : hint_range(0.3, 0.9, 0.01) = 0.58;
uniform float lower_shadow_start_right : hint_range(0.3, 0.9, 0.01) = 0.71;
uniform float lower_shadow_end : hint_range(0.6, 1.2, 0.01) = 0.96;

const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float rectangle_mask(vec2 uv, vec2 minimum, vec2 maximum, float feather) {
	float inside_left = smoothstep(minimum.x - feather, minimum.x + feather, uv.x);
	float inside_right = 1.0 - smoothstep(maximum.x - feather, maximum.x + feather, uv.x);
	float inside_top = smoothstep(minimum.y - feather, minimum.y + feather, uv.y);
	float inside_bottom = 1.0 - smoothstep(maximum.y - feather, maximum.y + feather, uv.y);
	return inside_left * inside_right * inside_top * inside_bottom;
}

float lower_shadow_mask(vec2 uv, float paint_noise) {
	float horizontal_blend = smoothstep(0.36, 0.70, uv.x);
	float gradient_start = mix(
		lower_shadow_start_left,
		lower_shadow_start_right,
		horizontal_blend
	);
	gradient_start += (paint_noise - 0.5) * 0.025;
	gradient_start += sin(uv.x * 10.0 + 1.2) * 0.008;
	float gradient_end = lower_shadow_end + (paint_noise - 0.5) * 0.02;
	float combined_shadow = smoothstep(gradient_start, gradient_end, uv.y);
	float table_left = smoothstep(0.275, 0.325, uv.x);
	float table_top = smoothstep(0.50, 0.55, uv.y);
	float table_bottom = 1.0 - smoothstep(0.72, 0.78, uv.y);
	float table_surface_protection = table_left * table_top * table_bottom;
	return combined_shadow * (1.0 - table_surface_protection);
}

vec3 tint_preserving_luminance(vec3 source, vec3 tint) {
	float source_luminance = dot(source, LUMA_WEIGHTS);
	vec3 tinted = source * tint;
	float tinted_luminance = max(dot(tinted, LUMA_WEIGHTS), 0.0001);
	tinted *= source_luminance / tinted_luminance;
	tinted = clamp(tinted, vec3(0.0), vec3(1.0));
	float correction = source_luminance - dot(tinted, LUMA_WEIGHTS);
	return clamp(tinted + vec3(correction), vec3(0.0), vec3(1.0));
}

float ray_x_at_y(vec2 source, vec2 blocker_point, float y) {
	float vertical_span = max(blocker_point.y - source.y, 0.001);
	float travel = (y - source.y) / vertical_span;
	return source.x + (blocker_point.x - source.x) * travel;
}

float main_light_cone(vec2 uv, float paint_noise) {
	vec2 ray = normalize(uv - main_source);
	float alignment = dot(ray, normalize(main_direction));
	alignment += (paint_noise - 0.5) * brush_variation * 0.24;
	float cone_edge = cos(main_half_angle);
	return smoothstep(
		cone_edge - main_edge_softness,
		cone_edge + main_edge_softness,
		alignment
	);
}

float monitor_shadow_wedge(vec2 uv, float paint_noise) {
	vec2 blocker_top_left = vec2(0.775, 0.13);
	vec2 blocker_bottom_right = vec2(0.84, 0.56);
	float left_edge = ray_x_at_y(main_source, blocker_top_left, uv.y);
	float right_edge = ray_x_at_y(main_source, blocker_bottom_right, uv.y);
	float depth = clamp((uv.y - blocker_top_left.y) / 0.87, 0.0, 1.0);
	float penumbra = mix(0.018, 0.075, depth);
	float edge_wobble = (paint_noise - 0.5) * brush_variation * 0.30;
	float inside_left = smoothstep(left_edge - penumbra, left_edge + penumbra, uv.x + edge_wobble);
	float inside_right = 1.0 - smoothstep(right_edge - penumbra, right_edge + penumbra, uv.x - edge_wobble);
	return inside_left * inside_right * smoothstep(0.16, 0.34, uv.y);
}

float trapezoid_beam(
	vec2 uv,
	float near_x,
	float far_x,
	float near_top,
	float near_bottom,
	float far_top,
	float far_bottom,
	float edge_softness,
	float paint_noise
) {
	float span = max(near_x - far_x, 0.001);
	float travel = clamp((near_x - uv.x) / span, 0.0, 1.0);
	float top_edge = mix(near_top, far_top, travel);
	float bottom_edge = mix(near_bottom, far_bottom, travel);
	float brush_edge = (paint_noise - 0.5) * brush_variation * 0.40;
	float inside_top = smoothstep(top_edge - edge_softness, top_edge + edge_softness, uv.y + brush_edge);
	float inside_bottom = 1.0 - smoothstep(bottom_edge - edge_softness, bottom_edge + edge_softness, uv.y - brush_edge);
	float starts_at_screen = 1.0 - smoothstep(near_x, near_x + 0.015, uv.x);
	float ends_at_far_edge = smoothstep(far_x - 0.03, far_x + 0.04, uv.x);
	return inside_top * inside_bottom * starts_at_screen * ends_at_far_edge;
}

void fragment() {
	vec4 source_sample = texture(screen_texture, SCREEN_UV);
	if (source_sample.a <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = UV;
		float paint_noise = value_noise(uv * vec2(8.0, 10.0) + 7.4) * 0.72;
		paint_noise += value_noise(uv * vec2(27.0, 19.0) + 19.6) * 0.28;

		float main_cone = main_light_cone(uv, paint_noise);
		float monitor_shadow = monitor_shadow_wedge(uv, paint_noise);
		vec3 warm_scene = tint_preserving_luminance(source_sample.rgb, main_warm_tint);
		vec3 result = mix(source_sample.rgb, warm_scene, main_cone * main_warm_influence);

		vec3 blue_shadow_scene = tint_preserving_luminance(result, shadow_blue_tint);
		result = mix(
			result,
			blue_shadow_scene,
			monitor_shadow * main_occlusion_strength
		);

		float monitor_inner = trapezoid_beam(
			uv,
			monitor_screen_x,
			monitor_far_x + 0.14,
			monitor_near_top,
			monitor_near_bottom,
			monitor_far_top + 0.08,
			monitor_far_bottom - 0.08,
			0.025,
			paint_noise
		);
		float monitor_outer = trapezoid_beam(
			uv,
			monitor_screen_x + 0.01,
			monitor_far_x,
			monitor_near_top - 0.035,
			monitor_near_bottom + 0.035,
			monitor_far_top,
			monitor_far_bottom,
			0.075,
			paint_noise
		);
		float beam_travel = clamp(
			(monitor_screen_x - uv.x) / max(monitor_screen_x - monitor_far_x, 0.001),
			0.0,
			1.0
		);
		float distance_falloff = 1.0 - smoothstep(0.18, 1.0, beam_travel);
		float monitor_field = clamp(monitor_inner * 0.72 + monitor_outer * 0.34, 0.0, 1.0);
		monitor_field *= distance_falloff;

		float result_luminance = dot(result, LUMA_WEIGHTS);
		vec3 white_light_scene = mix(result, vec3(result_luminance), 0.32);
		white_light_scene += vec3(0.05) * monitor_field * (1.0 - result_luminance);
		result = mix(result, white_light_scene, monitor_field * monitor_white_influence);

		float lower_shadow = lower_shadow_mask(uv, paint_noise);
		vec3 lower_shadow_scene = tint_preserving_luminance(result, lower_shadow_blue_tint);
		lower_shadow_scene *= lower_shadow_brightness;
		result = mix(result, lower_shadow_scene, lower_shadow * lower_shadow_strength);

		float window_exclusion = rectangle_mask(uv, window_min, window_max, window_feather);
		result = mix(result, source_sample.rgb, window_exclusion);
		COLOR = vec4(clamp(result, vec3(0.0), vec3(1.0)), source_sample.a);
	}
}
