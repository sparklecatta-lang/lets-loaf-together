shader_type canvas_item;
render_mode unshaded;

uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.28;
uniform vec3 night_tint = vec3(0.52, 0.74, 1.18);
uniform float night_tint_strength : hint_range(0.0, 1.0, 0.01) = 0.46;
uniform float building_darkening : hint_range(0.0, 0.7, 0.01) = 0.30;
uniform float window_gain : hint_range(1.0, 2.0, 0.01) = 1.34;
uniform float window_glow : hint_range(0.0, 0.5, 0.01) = 0.16;
uniform vec3 window_glow_color = vec3(1.0, 0.50, 0.16);
uniform float tree_visibility : hint_range(0.0, 0.6, 0.01) = 0.30;
uniform float tree_saturation : hint_range(0.5, 2.0, 0.01) = 1.24;

const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

float luminance_of(vec3 color_value) {
	return dot(color_value, LUMA_WEIGHTS);
}

float warm_window_mask(vec3 color_value) {
	float luminance = luminance_of(color_value);
	float red_over_blue = smoothstep(0.035, 0.24, color_value.r - color_value.b);
	float green_over_blue = smoothstep(-0.02, 0.12, color_value.g - color_value.b);
	float bright_enough = smoothstep(0.24, 0.62, luminance);
	return red_over_blue * green_over_blue * bright_enough;
}

float tree_color_mask(vec3 color_value) {
	float luminance = luminance_of(color_value);
	float green_signal = color_value.g - max(color_value.r * 0.88, color_value.b * 0.84);
	float green_dominance = smoothstep(-0.025, 0.095, green_signal);
	float mid_dark = 1.0 - smoothstep(0.44, 0.70, luminance);
	return green_dominance * mid_dark;
}

vec3 tint_preserving_luminance(vec3 source, vec3 tint) {
	float source_luminance = luminance_of(source);
	vec3 tinted = source * tint;
	float tinted_luminance = max(luminance_of(tinted), 0.0001);
	return clamp(tinted * (source_luminance / tinted_luminance), vec3(0.0), vec3(1.0));
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luminance = luminance_of(source.rgb);
	vec3 saturated = clamp(
		mix(vec3(luminance), source.rgb, saturation),
		vec3(0.0),
		vec3(1.0)
	);

	float window_mask = warm_window_mask(saturated);
	float tree_mask = tree_color_mask(saturated) * (1.0 - window_mask);
	float building_mask = clamp(1.0 - window_mask - tree_mask * 0.82, 0.0, 1.0);

	vec3 cool_night = tint_preserving_luminance(saturated, night_tint);
	vec3 graded = mix(saturated, cool_night, night_tint_strength * building_mask);
	float midtone_weight = smoothstep(0.07, 0.52, luminance);
	graded *= 1.0 - building_darkening * building_mask * midtone_weight;

	vec3 tree_night = tint_preserving_luminance(saturated, vec3(0.56, 1.04, 1.02));
	float tree_luminance = luminance_of(tree_night);
	tree_night = mix(vec3(tree_luminance), tree_night, tree_saturation);
	tree_night *= 0.92 + tree_visibility * 0.18;
	tree_night += vec3(0.018, 0.028, 0.025) * tree_visibility;
	graded = mix(graded, tree_night, tree_mask * (0.72 + tree_visibility * 0.28));

	vec3 lit_window = saturated * window_gain;
	lit_window += window_glow_color * 0.08 * window_mask * (1.0 - luminance);
	graded = mix(graded, lit_window, window_mask);

	vec2 glow_step = TEXTURE_PIXEL_SIZE * 4.0;
	float neighboring_warmth = 0.0;
	neighboring_warmth = max(neighboring_warmth, warm_window_mask(texture(TEXTURE, UV + vec2(glow_step.x, 0.0)).rgb));
	neighboring_warmth = max(neighboring_warmth, warm_window_mask(texture(TEXTURE, UV - vec2(glow_step.x, 0.0)).rgb));
	neighboring_warmth = max(neighboring_warmth, warm_window_mask(texture(TEXTURE, UV + vec2(0.0, glow_step.y)).rgb));
	neighboring_warmth = max(neighboring_warmth, warm_window_mask(texture(TEXTURE, UV - vec2(0.0, glow_step.y)).rgb));
	neighboring_warmth = max(neighboring_warmth, warm_window_mask(texture(TEXTURE, UV + glow_step).rgb));
	neighboring_warmth = max(neighboring_warmth, warm_window_mask(texture(TEXTURE, UV - glow_step).rgb));
	neighboring_warmth = max(neighboring_warmth, warm_window_mask(texture(TEXTURE, UV + vec2(glow_step.x, -glow_step.y)).rgb));
	neighboring_warmth = max(neighboring_warmth, warm_window_mask(texture(TEXTURE, UV + vec2(-glow_step.x, glow_step.y)).rgb));
	float glow_halo = neighboring_warmth * (1.0 - window_mask * 0.55);
	graded += window_glow_color * glow_halo * window_glow * (1.0 - luminance);

	COLOR = vec4(clamp(graded, vec3(0.0), vec3(1.0)), source.a);
}
