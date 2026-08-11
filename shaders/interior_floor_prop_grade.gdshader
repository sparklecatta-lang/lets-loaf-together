shader_type canvas_item;
render_mode unshaded;

uniform float saturation : hint_range(0.0, 1.5, 0.01) = 0.72;
uniform float exposure : hint_range(0.4, 1.2, 0.01) = 0.84;
uniform vec3 night_tint = vec3(0.86, 0.94, 1.04);
uniform float contrast : hint_range(0.5, 1.5, 0.01) = 0.92;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luminance = dot(source.rgb, LUMA);
	vec3 graded = mix(vec3(luminance), source.rgb, saturation);
	graded = (graded - vec3(0.5)) * contrast + vec3(0.5);
	graded *= night_tint * exposure;
	COLOR = vec4(clamp(graded, vec3(0.0), vec3(1.0)), source.a);
}
