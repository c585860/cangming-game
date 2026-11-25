// Weather surface effects: continuous ground-material interpolation, dynamic rain puddles with SSR,
// raindrop ripples, and textured snow accumulation.

float rain_ripples(vec2 p, float t) {
	vec2 uv = p * 1.35;
	vec2 id = floor(uv);
	vec2 f = fract(uv) - 0.5;
	float h = hash21(id + vec2(noise_seed * 0.17, 3.7));
	if (h < 0.68) {
		return 0.0;
	}
	float cycle = fract(t * (1.35 + 0.55 * h) + h * 11.3);
	vec2 center = vec2(hash21(id + vec2(1.3, 9.1)), hash21(id + vec2(5.7, 2.4))) - 0.5;
	vec2 d = (f - center * 0.44) * vec2(1.0, 1.55);
	float dist = length(d);
	float ring = 1.0 - smoothstep(0.0, 0.032, abs(dist - cycle * 0.34));
	return ring * (1.0 - cycle) * smoothstep(0.0, 0.12, cycle);
}

float ground_hold_at(vec2 local, vec2 world) {
	vec2 warp = vec2(
		noise2(world * 1.15 + vec2(3.1, 7.4)) - 0.5,
		noise2(world * 1.15 + vec2(12.7, 2.3)) - 0.5
	) * 0.42;
	vec2 p_sample = local + warp - vec2(0.5);
	ivec2 start = ivec2(floor(p_sample));
	vec2 f = fract(p_sample);
	f = f * f * (3.0 - 2.0 * f);
	float total = 0.0;
	float weight = 0.0;
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			ivec2 c = clamp(start + ivec2(x, y), ivec2(0), map_size - ivec2(1));
			vec4 t = texelFetch(geometry, c, 0);
			int k = int(round(t.g * 255.0));
			bool enc = (int(round(t.a * 3.0)) & 1) != 0;
			float hold = (!enc && k == 0) ? t.b : 0.0;
			float w = (x == 1 ? f.x : 1.0 - f.x) * (y == 1 ? f.y : 1.0 - f.y);
			total += hold * w;
			weight += w;
		}
	}
	return total / max(weight, 0.001);
}

vec3 apply_rain_puddles(vec3 lit, vec3 base, vec2 world, vec2 cache_uv, float direct, vec3 lamp, float smooth_hold) {
	if (wetness <= 0.01) {
		return lit;
	}
	float base_luma = dot(base, vec3(0.299, 0.587, 0.114));
	float day = clamp(sky_energy * 1.45 + sun_energy * 0.20, 0.0, 1.0);
	vec3 sky_refl = mix(vec3(0.05, 0.08, 0.13), sky_color * (0.44 + 0.14 * day), day);

	float damp_dark = mix(0.84, 0.75, smooth_hold);
	vec3 wet_surface = lit * mix(1.0, damp_dark, wetness);
	float sheen_mask = smoothstep(0.26, 0.62, base_luma) * wetness * (0.04 + 0.07 * smooth_hold);
	wet_surface += (sky_refl * 0.85 + lamp * 1.15) * sheen_mask;

	// Dynamically evolving puddles: basins shift & swell organically with puddle_phase over time.
	vec2 drift = vec2(sin(puddle_phase * 0.37) * 0.55, cos(puddle_phase * 0.29) * 0.55);
	float b1 = noise2(world * vec2(0.22, 0.25) + vec2(noise_seed * 0.37, 11.4) + drift);
	float b2 = noise2(world * vec2(0.58, 0.54) - vec2(7.1, noise_seed * 0.19) - drift * 0.65);
	float b3 = noise2(world * vec2(1.45, 1.38) + vec2(4.2, 9.6));
	float surge = 0.035 * sin(puddle_phase * 0.72 + b1 * 4.0);
	float relief = (0.42 - clamp(base_luma, 0.14, 0.62)) * 0.11 * smooth_hold;
	float basin = b1 * 0.62 + b2 * 0.28 + b3 * 0.10 + surge + relief;

	float threshold = mix(0.84, 0.64, smooth_hold) - wetness * 0.14;
	float damp_halo = smoothstep(threshold - 0.10, threshold + 0.03, basin) * smoothstep(0.10, 0.42, wetness) * (0.25 + 0.75 * smooth_hold);
	wet_surface *= 1.0 - 0.16 * damp_halo;

	float puddle = smoothstep(threshold, threshold + 0.09, basin) * smoothstep(0.14, 0.45, wetness) * smoothstep(0.08, 0.52, smooth_hold);
	if (puddle <= 0.005) {
		return wet_surface;
	}

	float depth = clamp(puddle * (1.05 - base_luma * 0.35), 0.0, 1.0);
	vec3 water_bed = wet_surface * mix(0.82, 0.62, depth);

	float ripple = rain_level > 0.03 ? rain_ripples(world, TIME) * rain_level : 0.0;
	float wave = sin(world.x * 8.5 + world.y * 6.0 - TIME * 2.2) * 0.04;
	vec2 tile_shift = vec2(wave + ripple * 0.09, -(0.62 + 0.28 * depth) + ripple * 0.09);
	vec2 refl_uv = clamp(cache_uv + tile_shift / max(cache_world_span, vec2(1.0)), vec2(0.002), vec2(0.998));
	vec3 ssr = texture(world_tex, refl_uv).rgb * (outdoor_ambient * 0.90 + lamp * 0.75 + vec3(0.03));

	vec3 reflection = mix(sky_refl * 0.85, ssr, 0.48);
	reflection += sun_color * direct * sun_energy * 0.22;
	reflection += lamp * (0.85 + 0.35 * ripple);
	reflection += (sky_refl * 0.85 + lamp * 0.75 + vec3(0.16)) * ripple * 0.22;

	float fresnel_mix = clamp(0.18 + 0.24 * depth + 0.08 * ripple, 0.0, 0.44);
	return mix(water_bed, reflection, fresnel_mix * puddle);
}

vec3 apply_snow_blanket(vec3 lit, vec3 base, vec3 exposure, vec2 world, float strength, float stone_hold) {
	if (strength <= 0.01) {
		return lit;
	}
	float drift = noise2(world * vec2(0.28, 0.31) + vec2(noise_seed * 0.19, 4.3));
	float detail = noise2(world * vec2(1.25, 1.25) - vec2(2.1, noise_seed * 0.11));
	float base_luma = dot(base, vec3(0.299, 0.587, 0.114));
	float stone_grooves = smoothstep(0.10, 0.42, base_luma);
	float trampled = mix(1.0, 0.84, stone_hold);
	float coverage = clamp(strength * trampled * (0.70 + 0.34 * drift) * mix(0.45, 1.0, stone_grooves), 0.0, 0.88);
	float sparkle = pow(detail, 7.0) * (0.16 * sun_energy + 0.07 * sky_energy);
	vec3 snow_shadow = vec3(0.74, 0.82, 0.91);
	vec3 snow_bright = vec3(0.94, 0.96, 0.99);
	vec3 snow_albedo = mix(snow_shadow, snow_bright, 0.40 + 0.40 * drift + 0.20 * detail);
	vec3 snow_lit = snow_albedo * (exposure + vec3(0.04, 0.06, 0.09) * (0.30 + sky_energy)) + vec3(sparkle);
	return mix(lit, snow_lit, coverage);
}
