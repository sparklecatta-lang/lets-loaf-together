shader_type canvas_item;

uniform bool show_upper = true;
uniform float split_y : hint_range(0.0, 1.0, 0.005) = 0.69;
uniform float feather : hint_range(0.0, 0.1, 0.002) = 0.018;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float lower_weight = smoothstep(split_y - feather, split_y + feather, UV.y);
	float keep_weight = show_upper ? 1.0 - lower_weight : lower_weight;
	source.a *= keep_weight;
	if (source.a <= 0.001) {
		source = vec4(0.0);
	}
	COLOR = source;
}
