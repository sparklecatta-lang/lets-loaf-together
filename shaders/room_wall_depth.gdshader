shader_type canvas_item;

uniform float wall_darkening : hint_range(0.0, 0.2, 0.005) = 0.065;
uniform float wall_top : hint_range(0.0, 1.0, 0.005) = 0.41;
uniform float wall_bottom : hint_range(0.0, 1.0, 0.005) = 0.84;
uniform float vertical_feather : hint_range(0.0, 0.15, 0.005) = 0.035;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float below_window = smoothstep(wall_top - vertical_feather, wall_top + vertical_feather, UV.y);
	float above_baseboard = 1.0 - smoothstep(
		wall_bottom - vertical_feather,
		wall_bottom + vertical_feather,
		UV.y
	);
	float wall_mask = below_window * above_baseboard;
	source.rgb *= 1.0 - wall_darkening * wall_mask;
	COLOR = source;
}
