shader_type canvas_item;
render_mode unshaded;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rain_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float wind = 0.16;

float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 345.45));
	point += dot(point, point + 34.345);
	return fract(point.x * point.y);
}

float rain_drop_layer(
	vec2 uv,
	vec2 grid,
	float speed,
	float radius_min,
	float radius_max,
	float density,
	float seed
) {
	vec2 point = uv;
	point.x += point.y * wind * 0.16;
	point.y -= TIME * speed;
	vec2 cell = floor(point * grid);
	vec2 local = fract(point * grid);
	float random_value = hash21(cell + seed);
	vec2 center = vec2(
		0.12 + hash21(cell + seed + 5.73) * 0.76,
		0.12 + hash21(cell + seed + 19.6) * 0.76
	);
	vec2 delta = local - center;
	// A small rounded bead, not a line segment. The mild vertical oval keeps
	// individual drops readable without creating a tail or directional streak.
	delta.y *= 0.82;
	float radius = mix(radius_min, radius_max, random_value);
	float bead = 1.0 - smoothstep(radius, radius * 1.85, length(delta));
	float presence = step(1.0 - density, hash21(cell + seed + 13.1));
	return bead * presence * mix(0.42, 1.0, random_value);
}

float glass_drop(vec2 uv) {
	vec2 point = uv * vec2(23.0, 13.0);
	point.y -= TIME * 0.052;
	vec2 cell = floor(point);
	vec2 local = fract(point);
	float random_value = hash21(cell + 91.7);
	float center = 0.18 + hash21(cell + 37.4) * 0.64;
	float head_y = 0.22 + hash21(cell + 7.2) * 0.58;
	vec2 delta = vec2((local.x - center) * 3.6, local.y - head_y);
	float bead = 1.0 - smoothstep(0.025, 0.068, length(delta));
	return bead * 0.34 * step(0.88, random_value);
}

void fragment() {
	vec2 uv = UV;
	float far_rain = rain_drop_layer(uv, vec2(50.0, 31.0), 0.38, 0.012, 0.028, 0.36, 4.0);
	float middle_rain = rain_drop_layer(uv, vec2(38.0, 23.0), 0.56, 0.018, 0.036, 0.42, 23.0);
	float near_rain = rain_drop_layer(uv, vec2(27.0, 17.0), 0.76, 0.024, 0.046, 0.46, 58.0);
	float drops = glass_drop(uv);
	float lower_mist = smoothstep(0.72, 1.0, uv.y) * 0.06;
	float alpha = (far_rain * 0.16 + middle_rain * 0.28 + near_rain * 0.42 + drops + lower_mist) * intensity;
	vec3 color = rain_color.rgb * mix(0.72, 1.15, clamp(near_rain + drops, 0.0, 1.0));
	COLOR = vec4(color, clamp(alpha, 0.0, 0.78));
}
