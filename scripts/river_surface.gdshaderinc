// River state is sampled in world space so panning and zooming keep the same waves.
vec3 river_normal(vec2 world) {
	vec2 p = world - vec2(0.07, 0.45) * TIME;
	vec2 a = vec2(5.1, 8.2);
	vec2 b = vec2(-8.3, 13.7);
	vec2 c = vec2(19.0, 7.4);
	float bend = sin(dot(p, vec2(0.91, 0.37))) * 1.3;
	vec2 slope = a * (0.024 * cos(dot(p, a) + bend))
		+ b * (0.012 * cos(dot(p, b) - bend + TIME * 1.10))
		+ c * (0.007 * cos(dot(p, c) + TIME * 0.63));
	return normalize(vec3(-slope, 1.0));
}

float river_glint(vec3 normal, vec3 eye, vec3 light) {
	vec3 halfway = normalize(eye + light);
	float alignment = max(dot(normal, halfway), 0.0);
	return 0.36 * pow(alignment, 12.0) + 0.64 * pow(alignment, 46.0);
}

vec3 shade_river(vec3 lit, vec2 world, vec2 local, float water, float sun, float moon, vec3 lamp) {
	float edge = 8.0 * (texture(river_field, local / vec2(map_size)).b - 0.5);
	float depth = smoothstep(0.05, 3.60, edge) * mix(0.28, 1.0, smoothstep(0.22, 0.88, water));
	vec3 normal = river_normal(world);
	vec3 eye = normalize(vec3(0.0, 0.53, 1.0));
	float fresnel = 0.035 + 0.965 * pow(1.0 - clamp(dot(normal, eye), 0.0, 1.0), 5.0);
	float day = clamp(sky_energy * 1.42 + sun_energy * 0.20, 0.0, 1.0);
	vec3 deep_tint = vec3(0.45, 0.70, 0.82);
	vec3 shallow_tint = vec3(0.96, 1.02, 0.90);
	float texture_gain = 1.0 + 0.13 * dot(normal.xy, vec2(0.54, -0.79));
	vec3 body = lit * mix(shallow_tint, deep_tint, depth) * texture_gain;
	vec3 sky_reflection = mix(vec3(0.07, 0.11, 0.17), sky_color * 0.64, day);
	float reflection_weight = clamp(0.09 + 0.16 * depth + 1.55 * fresnel, 0.0, 0.50);
	vec3 reflected = mix(body, sky_reflection, reflection_weight);
	reflected += sun_color * sun * sun_energy * river_glint(normal, eye, sun_ray) * 1.18;
	reflected += vec3(0.64, 0.79, 1.0) * moon * moon_energy * river_glint(normal, eye, moon_ray) * 1.50;
	reflected += lamp * smoothstep(-0.06, 0.24, normal.y) * 0.26;
	// Wet shore detail only on the water side, with breaks that travel downstream.
	float edge_detail = 1.0 - smoothstep(0.05, 0.55, abs(edge - 0.26));
	float streak = smoothstep(0.34, 0.78, noise2(world * vec2(1.39, 2.60) - vec2(0.12, 0.94) * TIME));
	return reflected + sky_reflection * edge_detail * streak * (0.09 + 0.15 * day);
}
