shader_type canvas_item;

// Subtle tilt-shift edge polish + photographic split-tone & micro film grain for the 3D SubViewport composite.
// Keeps the center gameplay area 100% razor-sharp while harmonizing tileset colors into a cohesive realistic look.

uniform float u_tilt_strength = 0.38;
uniform float u_time = 0.0;
uniform float u_grain_strength = 0.011;

float hash21(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

void fragment() {
	vec4 sharp = texture(TEXTURE, UV);
	float edge = abs(UV.y - 0.5) * 2.0;
	float amount = smoothstep(0.58, 0.98, edge) * u_tilt_strength;
	vec3 col = sharp.rgb;
	if (amount > 0.002) {
		vec2 px = TEXTURE_PIXEL_SIZE * 1.5;
		vec3 soft = sharp.rgb * 0.40;
		soft += texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb * 0.12;
		soft += texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb * 0.12;
		soft += texture(TEXTURE, UV + vec2(0.0, px.y)).rgb * 0.12;
		soft += texture(TEXTURE, UV - vec2(0.0, px.y)).rgb * 0.12;
		soft += texture(TEXTURE, UV + px).rgb * 0.03;
		soft += texture(TEXTURE, UV - px).rgb * 0.03;
		soft += texture(TEXTURE, UV + vec2(px.x, -px.y)).rgb * 0.03;
		soft += texture(TEXTURE, UV + vec2(-px.x, px.y)).rgb * 0.03;
		col = mix(sharp.rgb, soft, amount);
	}
	// Subtle realistic photographic vignette, cool-shadow / warm-highlight balance & fine 35mm grain
	vec2 cv = (UV - vec2(0.5)) * 2.0;
	float vig = 1.0 - 0.075 * smoothstep(0.65, 1.48, dot(cv, cv));
	col *= vig;
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 grade = mix(vec3(0.96, 0.985, 1.03), vec3(1.015, 1.005, 0.985), smoothstep(0.15, 0.75, lum));
	float g = (hash21(floor(FRAGCOORD.xy * 0.5) + fract(u_time * 7.3) * 31.0) - 0.5) * u_grain_strength * mix(1.4, 0.55, smoothstep(0.05, 0.6, lum));
	COLOR = vec4(clamp(col * grade + vec3(g), vec3(0.0), vec3(1.0)), 1.0);
}
