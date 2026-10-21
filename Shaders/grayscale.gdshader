shader_type canvas_item;

// 1 keeps the original colors, 0 renders the texture in grayscale.
uniform float saturation : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 color = COLOR;
	float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(vec3(luminance), color.rgb, saturation);
}
