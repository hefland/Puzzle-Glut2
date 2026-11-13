// Animated candy gradient background with drifting soft bubbles and stripes.
shader_type canvas_item;

uniform vec4 color_top : source_color = vec4(0.32, 0.16, 0.62, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.98, 0.35, 0.55, 1.0);
uniform vec4 color_accent : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform float speed = 1.0;
uniform float stripe_alpha = 0.06;
uniform float danger = 0.0;   // 0..1 tints the scene red when the board is nearly full

float bubble(vec2 uv, vec2 c, float r) {
	float d = length(uv - c);
	return smoothstep(r, r * 0.55, d);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float wave = sin(uv.x * 3.0 + t * 0.6) * 0.06 + sin(uv.y * 4.0 - t * 0.4) * 0.04;
	vec3 col = mix(color_top.rgb, color_bottom.rgb, clamp(uv.y + wave, 0.0, 1.0));
	// Diagonal candy stripes.
	float s = step(0.5, fract((uv.x * 1.8 + uv.y) * 7.0 - t * 0.15));
	col += s * stripe_alpha;
	// Floating bubbles.
	float b = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		vec2 c = vec2(fract(fi * 0.137 + 0.11 + sin(t * 0.07 + fi) * 0.05),
			1.15 - fract(t * (0.025 + fi * 0.004) + fi * 0.29) * 1.3);
		b += bubble(vec2(uv.x * 1.78, uv.y), vec2(c.x * 1.78, c.y), 0.06 + 0.03 * sin(fi * 2.1)) * 0.16;
	}
	col = mix(col, color_accent.rgb, clamp(b, 0.0, 0.35));
	// Soft vignette.
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.55;
	// Danger pulse.
	col = mix(col, vec3(0.9, 0.12, 0.2), danger * (0.25 + 0.12 * sin(TIME * 7.0)));
	COLOR = vec4(col, 1.0);
}
