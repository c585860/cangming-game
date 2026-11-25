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
	vec2 light_uv = (center + offset - far_offset) / light_span;
	return texture(bounce_map, light_uv).rgb;
}

vec3 sample_outdoor_bounce(vec2 local, ivec2 cell) {
	if (!in_light_map(cell)) {
		return vec3(0.0);
	}
	vec2 center = vec2(cell) + vec2(0.5);
	vec2 offset = local - center;
	float limit = 0.5 - bounce_sample_inset;
	bvec2 edge = greaterThan(abs(offset), vec2(limit));
	ivec2 step_dir = ivec2(sign(offset));
	if (edge.x) {
		ivec2 nx = cell + ivec2(step_dir.x, 0);
		if (!in_light_map(nx) || enclosed_light_cell(texelFetch(geometry, nx, 0))) {
			offset.x = float(step_dir.x) * limit;
		}
	}
	if (edge.y) {
		ivec2 ny = cell + ivec2(0, step_dir.y);
		if (!in_light_map(ny) || enclosed_light_cell(texelFetch(geometry, ny, 0))) {
			offset.y = float(step_dir.y) * limit;
		}
	}
	vec2 light_uv = (center + offset - far_offset) / light_span;
	return texture(bounce_map, light_uv).rgb;
}
