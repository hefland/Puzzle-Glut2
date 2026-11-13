// Face avatar: crops any square photo into a cartoon oval with a thick dark
// outline, warm rim light, soft bottom shading, glossy highlight and a hit flash.
shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.10, 0.06, 0.18, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.86, 0.45, 1.0);
uniform vec4 skin_color : source_color = vec4(1.0, 0.82, 0.66, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width = 0.07;
uniform float rim_strength = 0.65;
uniform float oval_x = 0.88;   // horizontal radius (fraction of half-width)
uniform float oval_y = 1.0;
uniform float flash = 0.0;
uniform float saturation = 1.15;
uniform float sick = 0.0;      // greenish tint when in danger

varying vec4 modulate_color;

void vertex() {
	modulate_color = COLOR;
}

void fragment() {
	vec2 d = (UV - 0.5) * 2.0 / vec2(oval_x, oval_y);
	float r = length(d);
	float aa = max(fwidth(r), 0.002) * 1.5;
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = mix(skin_color.rgb, tex.rgb, tex.a);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);
	vec2 n = r > 0.001 ? d / r : vec2(0.0);
	// Rim light from the upper-left, soft shade in the lower-right.
	float edge = smoothstep(0.62, 0.93, r);
	col += rim_color.rgb * edge * max(0.0, dot(n, normalize(vec2(-0.6, -0.8)))) * rim_strength;
	col *= 1.0 - 0.32 * edge * max(0.0, dot(n, normalize(vec2(0.5, 0.85))));
	// Glossy highlight.
	vec2 hp = (UV - vec2(0.34, 0.2)) / vec2(0.16, 0.07);
	col += vec3(1.0) * smoothstep(1.0, 0.2, length(hp)) * 0.28;
	col = mix(col, col * vec3(0.75, 1.1, 0.7), sick);
	col = mix(col, flash_color.rgb, flash);
	float fill = 1.0 - smoothstep(1.0 - outline_width - aa, 1.0 - outline_width + aa, r);
	float outer = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	vec3 final_col = mix(outline_color.rgb, col, fill);
	COLOR = vec4(final_col * modulate_color.rgb, outer * modulate_color.a);
}
