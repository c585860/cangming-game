shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D geometry : filter_nearest, repeat_disable;
uniform sampler2D solar_map : filter_linear, repeat_disable;
uniform sampler2D materials : filter_nearest, repeat_disable;
uniform ivec2 map_size;
uniform vec2 view_offset;
uniform vec2 light_size;
uniform vec3 sun_ray;
uniform bool sunlight_enabled;

#include "res://scripts/diffuse_room.gdshaderinc"

void fragment() {
	vec3 outgoing = vec3(0.0);
	ivec2 own = ivec2(floor(view_offset + UV * light_size));
	if (sunlight_enabled && in_light_map(own)) {
		vec4 data = texelFetch(geometry, own, 0);
		int kind = light_kind(data);
		ivec2 face = own + ivec2(0, 1);
		bool wall = kind == 1 && room_surface(face) && opening_faces(face, ivec2(0, -1));
		if (enclosed_light_cell(data) && (wall || kind == 0 || kind == 4 || kind >= 5)) {
			vec2 uv = (vec2(own) + vec2(0.5) - view_offset) / light_size;
			vec2 d = vec2(0.25) / light_size;
			vec3 incident = (texture(solar_map, uv + d).rgb + texture(solar_map, uv - d).rgb
				+ texture(solar_map, uv + vec2(d.x, -d.y)).rgb + texture(solar_map, uv + vec2(-d.x, d.y)).rgb) * 0.25;
			float horizontal = mix(0.55, 1.0, smoothstep(0.04, 0.72, sun_ray.z));
			float energy = incident.r * horizontal;
			if (wall) {
				energy = incident.g * max(0.0, sun_ray.y) * 0.82;
			} else if (kind == 7) {
				energy = max(energy * 0.72, max(incident.b * horizontal * 0.91, incident.g * 0.32));
			}
			outgoing = texelFetch(materials, own, 0).rgb * energy;
		}
	}
	COLOR = vec4(outgoing, 1.0);
}
