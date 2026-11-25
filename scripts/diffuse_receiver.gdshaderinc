#include "res://scripts/diffuse_room.gdshaderinc"

vec3 sample_room_bounce(vec2 local, ivec2 cell) {
	if (!room_surface(cell)) {
		return vec3(0.0);
	}
	vec2 center = vec2(cell) + vec2(0.5);
	vec2 offset = local - center;
	float limit = 0.5 - bounce_sample_inset;
	bvec2 edge = greaterThan(abs(offset), vec2(limit));
	ivec2 step_dir = ivec2(sign(offset));
	bool block_x = edge.x && !room_edge(cell, cell + ivec2(step_dir.x, 0));
	bool block_y = edge.y && !room_edge(cell, cell + ivec2(0, step_dir.y));
	if (edge.x && edge.y && !block_x && !block_y && !room_diagonal(cell, cell + step_dir)) {
		block_x = abs(offset.x) < abs(offset.y);
		block_y = !block_x;
	}
	if (block_x) {
		offset.x = float(step_dir.x) * limit;
	}
	if (block_y) {
		offset.y = float(step_dir.y) * limit;
	}
	vec2 light_uv = (center + offset - map_offset + vec2(light_margin)) / light_span;
	return texture(bounce_map, light_uv).rgb;
}
