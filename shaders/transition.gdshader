// Circular iris wipe used between screens.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0; // 0 = open, 1 = fully covered
uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform vec4 fill_color : source_color = vec4(0.11, 0.06, 0.2, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * screen_size;
	float maxr = length(screen_size) * 0.5 + 4.0;
	float r = (1.0 - progress) * maxr;
	float d = length(p);
	float inside = smoothstep(r - 2.0, r + 2.0, d);
	// Polka-dot rim for extra candy.
	float ring = smoothstep(r + 18.0, r + 2.0, d) * inside;
	vec3 col = mix(fill_color.rgb, vec3(1.0, 0.43, 0.71), ring * 0.8);
	COLOR = vec4(col, inside);
}
