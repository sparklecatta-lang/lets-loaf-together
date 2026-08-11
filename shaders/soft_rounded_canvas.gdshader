shader_type canvas_item;
render_mode unshaded;

uniform float corner_radius_px : hint_range(0.0, 120.0, 1.0) = 36.0;
uniform float feather_px : hint_range(1.0, 32.0, 1.0) = 18.0;
uniform vec2 canvas_size_px = vec2(1112.0, 834.0);
uniform vec3 night_tint = vec3(0.72, 0.88, 1.12);
uniform float night_tint_strength : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float night_shadow_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float night_exposure : hint_range(0.5, 1.2, 0.01) = 0.95;
uniform float night_contrast : hint_range(0.8, 1.4, 0.01) = 1.06;
uniform vec3 warm_highlight_tint = vec3(1.08, 0.98, 0.82);
uniform float warm_highlight_strength : hint_range(0.0, 0.5, 0.01) = 0.10;

const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

float rounded_rect_distance(vec2 point_px, vec2 half_size_px, float radius_px) {
	vec2 inset = max(half_size_px - vec2(radius_px), vec2(0.0));
	vec2 delta = abs(point_px) - inset;
	return length(max(delta, vec2(0.0))) + min(max(delta.x, delta.y), 0.0) - radius_px;
}

vec3 tint_preserving_luminance(vec3 source, vec3 tint) {
	float source_luminance = dot(source, LUMA_WEIGHTS);
	vec3 tinted = source * tint;
	float tinted_luminance = max(dot(tinted, LUMA_WEIGHTS), 0.0001);
	return tinted * (source_luminance / tinted_luminance);
}

void fragment() {
	vec2 point_px = (UV - vec2(0.5)) * canvas_size_px;
	float distance_px = rounded_rect_distance(point_px, canvas_size_px * 0.5, corner_radius_px);
	// Restore the soft alpha falloff while keeping a two-pixel transparent safety
	// inset. Unlike the old implementation, this does not blur neighboring RGB
	// samples, so dark room pixels cannot smear into the transparent edge.
	float antialias_px = max(fwidth(distance_px), 1.0);
	float edge_center_px = -2.0;
	float mask = 1.0 - smoothstep(
		edge_center_px - feather_px - antialias_px * 0.5,
		edge_center_px + antialias_px * 0.5,
		distance_px
	);
	COLOR = texture(TEXTURE, UV);
	float luminance = dot(COLOR.rgb, LUMA_WEIGHTS);
	float shadow_weight = 1.0 - smoothstep(0.18, 0.72, luminance);
	float tint_mix = night_tint_strength + night_shadow_strength * shadow_weight;
	vec3 tinted = tint_preserving_luminance(COLOR.rgb, night_tint);
	vec3 graded = mix(COLOR.rgb, tinted, tint_mix);
	float highlight_weight = smoothstep(0.56, 0.94, luminance);
	vec3 warm_highlight = tint_preserving_luminance(graded, warm_highlight_tint);
	graded = mix(graded, warm_highlight, warm_highlight_strength * highlight_weight);
	graded = (graded - vec3(0.5)) * night_contrast + vec3(0.5);
	COLOR.rgb = clamp(graded * night_exposure, vec3(0.0), vec3(1.0));
	COLOR.a *= mask;
	if (COLOR.a <= 0.001) {
		COLOR = vec4(0.0);
	}
}
