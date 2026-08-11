shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec3 blue_tint = vec3(0.22, 0.42, 0.95);
uniform float blue_amount : hint_range(0.0, 1.0, 0.01) = 0.76;
uniform vec2 background_light_source = vec2(0.91, -0.16);
uniform vec2 background_light_direction = vec2(-0.38, 1.0);
uniform float background_light_half_angle : hint_range(0.1, 1.4, 0.01) = 0.82;
uniform float background_light_edge : hint_range(0.01, 0.3, 0.01) = 0.11;
uniform vec3 background_warm_tint = vec3(1.10, 0.98, 0.86);
uniform float background_light_reveal : hint_range(0.0, 0.6, 0.01) = 0.14;
uniform float upper_background_reveal : hint_range(0.0, 1.0, 0.01) = 0.84;
uniform float platform_shadow_left : hint_range(0.0, 1.0, 0.01) = 0.14;
uniform float platform_shadow_right : hint_range(0.0, 1.0, 0.01) = 0.86;
uniform float platform_shadow_top : hint_range(0.0, 1.0, 0.01) = 0.49;
uniform float platform_shadow_depth : hint_range(0.05, 0.6, 0.01) = 0.30;
uniform float platform_shadow_shift_left : hint_range(0.0, 0.3, 0.01) = 0.10;
uniform float platform_shadow_strength : hint_range(0.0, 1.0, 0.01) = 0.54;
uniform float platform_shadow_brightness : hint_range(0.3, 1.0, 0.01) = 0.72;
uniform float platform_shadow_edge : hint_range(0.005, 0.15, 0.005) = 0.045;
uniform vec2 window_min = vec2(0.21, 0.0);
uniform vec2 window_max = vec2(0.84, 0.43);
uniform float window_feather : hint_range(0.001, 0.05, 0.001) = 0.008;

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

vec3 tint_preserving_luminance(vec3 source, vec3 tint) {
	float source_luminance = dot(source, LUMA_WEIGHTS);
	vec3 tinted = source * tint;
	float tinted_luminance = max(dot(tinted, LUMA_WEIGHTS), 0.0001);
	tinted *= source_luminance / tinted_luminance;
	tinted = clamp(tinted, vec3(0.0), vec3(1.0));
	float correction = source_luminance - dot(tinted, LUMA_WEIGHTS);
	return clamp(tinted + vec3(correction), vec3(0.0), vec3(1.0));
}

float rectangle_mask(vec2 uv, vec2 minimum, vec2 maximum, float feather) {
	float inside_left = smoothstep(minimum.x - feather, minimum.x + feather, uv.x);
	float inside_right = 1.0 - smoothstep(maximum.x - feather, maximum.x + feather, uv.x);
	float inside_top = smoothstep(minimum.y - feather, minimum.y + feather, uv.y);
	float inside_bottom = 1.0 - smoothstep(maximum.y - feather, maximum.y + feather, uv.y);
	return inside_left * inside_right * inside_top * inside_bottom;
}

float background_light_cone(vec2 uv) {
	vec2 ray = normalize(uv - background_light_source);
	float alignment = dot(ray, normalize(background_light_direction));
	float cone_edge = cos(background_light_half_angle);
	return smoothstep(
		cone_edge - background_light_edge,
		cone_edge + background_light_edge,
		alignment
	);
}

void fragment() {
	vec4 source_sample = texture(screen_texture, SCREEN_UV);
	float source_luminance = dot(source_sample.rgb, LUMA_WEIGHTS);
	vec3 blue_scene = clamp(
		vec3(source_luminance) * blue_tint + vec3(0.02, 0.04, 0.07),
		vec3(0.0),
		vec3(1.0)
	);
	vec3 night_background = mix(source_sample.rgb, blue_scene, blue_amount);
	vec3 warm_background = tint_preserving_luminance(source_sample.rgb, background_warm_tint);
	float boundary_noise = value_noise(UV * vec2(6.0, 4.0) + 13.7) - 0.5;
	float shadow_depth = clamp(
		(UV.y - platform_shadow_top) / max(platform_shadow_depth, 0.001),
		0.0,
		1.0
	);
	float horizontal_shift = shadow_depth * platform_shadow_shift_left;
	float shadow_left = platform_shadow_left - horizontal_shift;
	float shadow_right = platform_shadow_right - horizontal_shift;
	float edge_variation = boundary_noise * 0.012;
	float inside_left = smoothstep(
		shadow_left - platform_shadow_edge,
		shadow_left + platform_shadow_edge,
		UV.x + edge_variation
	);
	float inside_right = 1.0 - smoothstep(
		shadow_right - platform_shadow_edge,
		shadow_right + platform_shadow_edge,
		UV.x - edge_variation
	);
	float shadow_entry = smoothstep(
		platform_shadow_top - 0.018,
		platform_shadow_top + 0.045,
		UV.y
	);
	float shadow_fade = 1.0 - smoothstep(
		platform_shadow_top + 0.07,
		platform_shadow_top + platform_shadow_depth,
		UV.y
	);
	float platform_shadow = inside_left * inside_right * shadow_entry * shadow_fade;
	vec3 bright_background = mix(
		night_background,
		warm_background,
		upper_background_reveal
	);
	vec3 neutral_shadow = bright_background * platform_shadow_brightness;
	vec3 background_result = mix(
		bright_background,
		neutral_shadow,
		platform_shadow * platform_shadow_strength
	);
	float window_exclusion = rectangle_mask(UV, window_min, window_max, window_feather);
	background_result = mix(background_result, source_sample.rgb, window_exclusion);
	COLOR = vec4(background_result, source_sample.a);
}
