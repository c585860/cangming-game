shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D bounce_sources : filter_nearest, repeat_disable;
uniform sampler2D geometry : filter_nearest, repeat_disable;
uniform ivec2 map_size;
uniform vec2 view_offset;
uniform vec2 light_size;
uniform bool sunlight_enabled;

#include "res://scripts/diffuse_room.gdshaderinc"

vec3 source_at(ivec2 tile) {
	return texelFetch(bounce_sources, tile - ivec2(view_offset), 0).rgb;
}

bool outdoor_passable(ivec2 tile) {
	if (!in_light_map(tile)) {
		return false;
	}
	vec4 d = texelFetch(geometry, tile, 0);
	return !enclosed_light_cell(d) && light_kind(d) != 1;
}

void fragment() {
	vec3 bounce = vec3(0.0);
	vec2 local = view_offset + UV * light_size;
	ivec2 own = ivec2(floor(local));
	if (sunlight_enabled && in_light_map(own)) {
		bool indoors = room_surface(own);
		bool outdoors = outdoor_passable(own);
		if (indoors) {
			bounce += source_at(own) * 0.14;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					ivec2 step_dir = ivec2(dx, dy);
					if (dx == 0 && dy == 0) {
						continue;
					}
					ivec2 from = own;
					for (int reach = 1; reach <= 4; reach++) {
						ivec2 to = from + step_dir;
						ivec2 index = to - ivec2(view_offset);
						if (any(lessThan(index, ivec2(0))) || any(greaterThanEqual(index, ivec2(light_size)))) {
							break;
						}
						vec2 offset = vec2(to) + vec2(0.5) - local;
						float falloff = 1.0 / (1.0 + 0.80 * dot(offset, offset));
						bool connected = dx != 0 && dy != 0 ? room_diagonal(from, to) : room_edge(from, to);
						if (!connected) {
							ivec2 face = to + ivec2(0, 1);
							if (dy == -1 && in_light_map(to) && light_kind(texelFetch(geometry, to, 0)) == 1
									&& (dx == 0 || room_edge(from, face)) && opening_faces(face, ivec2(0, -1))) {
								bounce += source_at(to) * falloff;
							}
							break;
						}
						bounce += source_at(to) * falloff;
						from = to;
					}
				}
			}
			COLOR = vec4(vec3(1.0) - exp(-bounce * 0.88), 1.0);
		} else if (outdoors) {
			// Outdoor colored GI: river cyan, sunlit foliage green, plaster warm ochre bounce into nearby shade!
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					ivec2 step_dir = ivec2(dx, dy);
					if (dx == 0 && dy == 0) {
						continue;
					}
					ivec2 from = own;
					for (int reach = 1; reach <= 4; reach++) {
						ivec2 to = from + step_dir;
						ivec2 index = to - ivec2(view_offset);
						if (any(lessThan(index, ivec2(0))) || any(greaterThanEqual(index, ivec2(light_size)))) {
							break;
						}
						vec2 offset = vec2(to) + vec2(0.5) - local;
						float falloff = 1.0 / (1.0 + 0.95 * dot(offset, offset));
						if (!outdoor_passable(to)) {
							if (in_light_map(to) && light_kind(texelFetch(geometry, to, 0)) == 1) {
								bounce += source_at(to) * falloff * 0.85;
							}
							break;
						}
						bounce += source_at(to) * falloff;
						from = to;
					}
				}
			}
			COLOR = vec4(vec3(1.0) - exp(-bounce * 0.42), 1.0);
		} else {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		}
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	}
}
