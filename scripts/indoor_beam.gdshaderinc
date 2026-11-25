bool solid_air_boundary(ivec2 cell) {
	if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, map_size))) {
		return true;
	}
	return int(round(texelFetch(geometry, cell, 0).g * 255.0)) == 1;
}

vec3 sample_indoor_beam(vec2 local, vec2 uv, ivec2 cell) {
	// Keep the bilinear footprint out of solid walls, but let it cross open doorways.
	vec2 center = vec2(cell) + vec2(0.5);
	vec2 offset = local - center;
	float limit = 0.5 - volume_sample_inset;
	bvec2 edge = greaterThan(abs(offset), vec2(limit));
	ivec2 step_dir = ivec2(sign(offset));
	vec2 clipped = offset;
	bool block_x = edge.x && solid_air_boundary(cell + ivec2(step_dir.x, 0));
	bool block_y = edge.y && solid_air_boundary(cell + ivec2(0, step_dir.y));
	if (block_x) {
		clipped.x = float(step_dir.x) * limit;
	}
	if (block_y) {
		clipped.y = float(step_dir.y) * limit;
	}
	if (edge.x && edge.y && !block_x && !block_y && solid_air_boundary(cell + step_dir)) {
		if (abs(offset.x) < abs(offset.y)) {
			clipped.x = float(step_dir.x) * limit;
		} else {
			clipped.y = float(step_dir.y) * limit;
		}
	}
	return texture(volume_map, uv + (clipped - offset) / light_span).rgb;
}

vec3 indoor_beam_profile(vec3 visibility, float surface_height, out vec3 air_fraction) {
	// Reconstruct a continuous vertical profile from the three traced heights.
	// Integrate only the part of each slab in front of the receiving surface.
	vec2 midpoints = (AIR_HEIGHTS.xy + AIR_HEIGHTS.yz) * 0.5;
	vec3 slab_low = vec3(0.0, midpoints);
	vec3 slab_high = vec3(midpoints, LIGHT_STORY_HEIGHT);
	vec3 lower = max(vec3(0.0), AIR_HEIGHTS - max(slab_low, vec3(surface_height)));
	vec3 upper = max(vec3(0.0), slab_high - max(AIR_HEIGHTS, vec3(surface_height)));
	vec3 low_v = vec3(visibility.x, (visibility.xy + visibility.yz) * 0.5);
	vec3 high_v = vec3(low_v.yz, visibility.z);
	vec3 low_start = mix(visibility, low_v, lower / (AIR_HEIGHTS - slab_low));
	vec3 high_start = mix(high_v, visibility, upper / (slab_high - AIR_HEIGHTS));
	vec3 length_visible = lower + upper;
	air_fraction = length_visible / (slab_high - slab_low);
	return ((low_start + visibility) * lower + (high_start + high_v) * upper)
		* 0.5 / max(vec3(0.0001), length_visible);
}
