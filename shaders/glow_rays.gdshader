// Rotating sunburst glow (behind loot chests, draft cards and boss defeats).
shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float rays = 12.0;
uniform float spin = 0.4;
uniform float intensity = 1.0;

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float r = 0.5 + 0.5 * sin(a * rays + TIME * spin * 6.2831);
	float core = smoothstep(1.0, 0.0, d);
	float beams = smoothstep(0.35, 0.9, r) * smoothstep(1.0, 0.15, d);
	float alpha = clamp(core * core * 0.9 + beams * 0.55, 0.0, 1.0) * intensity;
	COLOR = vec4(glow_color.rgb + core * 0.3, alpha * glow_color.a);
}
