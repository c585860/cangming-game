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

void fragment() {
	vec3 bounce = vec3(0.0);
	vec2 local = view_offset + UV * light_size;
	ivec2 own = ivec2(floor(local));
	if (sunlight_enabled && room_surface(own)) {
		bounce += source_at(own) * 0.12;
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
					float falloff = 1.0 / (1.0 + 0.85 * dot(offset, offset));
					bool connected = dx != 0 && dy != 0 ? room_diagonal(from, to) : room_edge(from, to);
					if (!connected) {
						// A lit wall face can terminate a ray, but never carry it into the next room.
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
	}
	COLOR = vec4(vec3(1.0) - exp(-bounce * 0.82), 1.0);
}
