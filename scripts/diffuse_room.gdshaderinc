bool in_light_map(ivec2 tile) {
	return all(greaterThanEqual(tile, ivec2(0))) && all(lessThan(tile, map_size));
}

int light_kind(vec4 data) {
	return int(round(data.g * 255.0));
}

bool enclosed_light_cell(vec4 data) {
	return (int(round(data.a * 3.0)) & 1) != 0;
}

bool room_surface(ivec2 tile) {
	if (!in_light_map(tile)) {
		return false;
	}
	vec4 data = texelFetch(geometry, tile, 0);
	int kind = light_kind(data);
	return enclosed_light_cell(data) && (kind == 0 || kind == 4 || kind >= 5);
}

bool opening_faces(ivec2 tile, ivec2 step_dir) {
	vec4 data = texelFetch(geometry, tile, 0);
	return light_kind(data) != 4 || (data.b > 0.5 ? step_dir.y == 0 : step_dir.x == 0);
}

bool room_edge(ivec2 from, ivec2 to) {
	ivec2 step_dir = to - from;
	return room_surface(to) && opening_faces(from, step_dir) && opening_faces(to, step_dir);
}

bool room_diagonal(ivec2 from, ivec2 to) {
	ivec2 a = ivec2(to.x, from.y);
	ivec2 b = ivec2(from.x, to.y);
	return room_edge(from, a) && room_edge(from, b) && room_edge(a, to) && room_edge(b, to);
}
