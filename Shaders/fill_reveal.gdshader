shader_type canvas_item;

// Splash photo: dark and grey above the fill line, in colour below it, with a
// thin glowing edge on the line. The borders fade into the background.
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(0.95, 0.85, 0.25, 1.0);
uniform float edge_width = 0.012;
uniform float empty_brightness = 0.22;
uniform float border_fade = 0.12;

void fragment() {
	vec4 photo = texture(TEXTURE, UV);
	float grey = dot(photo.rgb, vec3(0.299, 0.587, 0.114));
	vec3 empty = vec3(grey) * empty_brightness;
	// The line climbs from below the image (fill 0) to above it (fill 1).
	float line_y = mix(1.0 + edge_width, -edge_width, fill);
	float filled = smoothstep(line_y - 0.004, line_y + 0.004, UV.y);
	vec3 color = mix(empty, photo.rgb, filled);
	float edge = 1.0 - smoothstep(0.0, edge_width, abs(UV.y - line_y));
	color = mix(color, edge_color.rgb, edge * 0.85 * step(0.001, fill) * step(fill, 0.999));
	vec2 border = smoothstep(vec2(0.0), vec2(border_fade), UV) * smoothstep(vec2(0.0), vec2(border_fade), 1.0 - UV);
	COLOR = vec4(color, photo.a * border.x * border.y);
}
