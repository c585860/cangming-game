shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://scripts/air_heights.gdshaderinc"

uniform sampler2D geometry : filter_nearest, repeat_disable;
uniform sampler2D river_field : filter_nearest, repeat_disable;
uniform ivec2 map_size;
uniform vec2 view_offset;
uniform vec2 light_size;
uniform int layer_count;
uniform vec2 toward_sun;
uniform float rise;
uniform bool sunlight_enabled;
uniform bool sample_air = false;
uniform bool sample_moon = false;

const float TRACE_RANGE = 24.0;
const float WINDOW_SILL = 0.77;
const float WINDOW_LINTEL = 1.89;

float obstacle(vec4 data, vec2 from, vec2 to, float low, float high, float bottom, bool receiver, float beam_distance) {
	int kind = int(round(data.g * 255.0));
	float height = data.r * 3.0;
	if (kind == 0 || low >= bottom + height) {
		return 1.0;
	}
	if (kind == 1) {
		// Accept light on the receiver's exposed face, but not through another wall.
		return receiver ? 1.0 : 0.0;
	}
	if (kind >= 2 && kind <= 4) {
		// Each opening lives in a wall plane, with a real width, sill and lintel.
		bool normal_x = data.b > 0.5;
		float start = normal_x ? from.x : from.y;
		float finish = normal_x ? to.x : to.y;
		if ((start - 0.5) * (finish - 0.5) > 0.0) {
			return 1.0;
		}
		float width = finish - start;
		float at = abs(width) < 0.0001 ? 0.0 : clamp((0.5 - start) / width, 0.0, 1.0);
		vec2 aperture = mix(from, to, at);
		float across = abs((normal_x ? aperture.y : aperture.x) - 0.5);
		float z = mix(low, high, at) - bottom;
		float spread = 0.0;
		if (beam_distance > 0.0) {
			float incidence = abs(normal_x ? toward_sun.x : toward_sun.y);
			spread = min(0.09, beam_distance * 0.00465 * length(vec2(1.0, rise)) / max(0.35, incidence));
		}
		float frame = kind == 4 ? 1.0 - smoothstep(0.39 - spread, 0.47 + spread, across)
			: 1.0 - smoothstep(0.32 - spread, 0.41 + spread, across);
		float sill = kind == 4 ? 0.0 : WINDOW_SILL;
		float lintel = kind == 4 ? 2.13 : WINDOW_LINTEL;
		float opening = frame * smoothstep(sill - 0.035 - spread, sill + 0.07 + spread, z)
			* (1.0 - smoothstep(lintel - 0.07 - spread, lintel + 0.035 + spread, z));
		return opening * (kind == 2 ? 0.76 : 1.0);
	}
	if (receiver) {
		return 1.0;
	}
	if (kind == 8) {
		// A lamp post occupies only the center of its tile.
		vec2 segment = to - from;
		float t = clamp(dot(vec2(0.5) - from, segment) / max(dot(segment, segment), 0.0001), 0.0, 1.0);
		return (mix(low, high, t) - bottom < height) ? smoothstep(0.045, 0.095, length(mix(from, to, t) - vec2(0.5))) : 1.0;
	}
	// Tree crowns and shrubs leave a penumbra, while furniture blocks the lower ray.
	if (kind == 5 && high < bottom + 0.75) {
		return 1.0;
	}
	return kind == 5 ? 0.29 : kind == 6 ? 0.51 : 0.0;
}

float trace_sun(vec2 point, float receiver_z, bool allow_surface, bool indoor_beam) {
	vec2 direction = toward_sun;
	ivec2 cell = ivec2(floor(point));
	ivec2 step_dir = ivec2(sign(direction));
	vec2 inv_speed = 1.0 / max(abs(direction), vec2(0.0001));
	vec2 within = fract(point);
	vec2 edge = vec2(direction.x < 0.0 ? within.x : 1.0 - within.x,
		direction.y < 0.0 ? within.y : 1.0 - within.y);
	vec2 crossing = edge * inv_speed;
	if (step_dir.x == 0) { crossing.x = TRACE_RANGE + 1.0; }
	if (step_dir.y == 0) { crossing.y = TRACE_RANGE + 1.0; }
	float enter = 0.0;
	float visibility = 1.0;
	for (int i = 0; i < 37; i++) {
		if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, map_size))) {
			break;
		}
		float leave = min(min(crossing.x, crossing.y), TRACE_RANGE);
		float z0 = receiver_z + enter * rise;
		float z1 = receiver_z + leave * rise;
		if (z0 >= float(layer_count) * LIGHT_STORY_HEIGHT) {
			break;
		}
		for (int layer = 0; layer < 4; layer++) {
			if (layer >= layer_count) {
				break;
			}
			float bottom = float(layer) * LIGHT_STORY_HEIGHT;
			float top = bottom + LIGHT_STORY_HEIGHT;
			vec4 data = texelFetch(geometry, cell + ivec2(layer * map_size.x, 0), 0);
			if (z0 < top && z1 >= top && (int(round(data.a * 3.0)) & 2) != 0) {
				return 0.0;
			}
			if (z1 < bottom || z0 >= top) {
				continue;
			}
			float a = max(enter, (bottom - receiver_z) / rise);
			float b = min(leave, (top - receiver_z) / rise);
			visibility *= obstacle(data, point + a * direction - vec2(cell), point + b * direction - vec2(cell),
				receiver_z + a * rise, receiver_z + b * rise, bottom, allow_surface && i == 0 && layer == 0,
				indoor_beam ? 0.5 * (a + b) : 0.0);
			if (visibility < 0.015) {
				return 0.0;
			}
		}
		if (leave >= TRACE_RANGE) {
			break;
		}
		enter = leave;
		if (crossing.x < crossing.y) {
			cell.x += step_dir.x;
			crossing.x += inv_speed.x;
		} else if (crossing.y < crossing.x) {
			cell.y += step_dir.y;
			crossing.y += inv_speed.y;
		} else {
			cell += step_dir;
			crossing += inv_speed;
		}
	}
	return visibility;
}

void fragment() {
	vec3 visibility = vec3(0.0);
	if (sunlight_enabled || sample_moon) {
		vec2 point = view_offset + UV * light_size;
		ivec2 cell = ivec2(floor(point));
		if (all(greaterThanEqual(cell, ivec2(0))) && all(lessThan(cell, map_size))) {
			if (sample_moon) {
				if (texelFetch(river_field, cell, 0).g > 0.15) {
					visibility.r = trace_sun(point, 0.045, false, false);
				}
			} else if (sample_air) {
				vec4 data = texelFetch(geometry, cell, 0);
				bool indoors = (int(round(data.a * 3.0)) & 1) != 0;
				visibility = vec3(trace_sun(point, AIR_HEIGHTS.x, false, indoors),
					trace_sun(point, AIR_HEIGHTS.y, false, indoors), trace_sun(point, AIR_HEIGHTS.z, false, indoors));
			} else {
				vec4 data = texelFetch(geometry, cell, 0);
				float height = data.r * 3.0;
				int kind = int(round(data.g * 255.0));
				float side;
				float top;
				if (kind == 2 || kind == 3) {
					// A window sprite receives light at the pane, not at roof height.
					vec2 pane = data.b > 0.5 ? vec2(float(cell.x) + 0.5, point.y) : vec2(point.x, float(cell.y) + 0.5);
					pane += toward_sun * 0.012;
					side = trace_sun(pane, mix(WINDOW_SILL, WINDOW_LINTEL, 0.28), true, false);
					top = trace_sun(pane, mix(WINDOW_SILL, WINDOW_LINTEL, 0.76), true, false);
				} else {
					vec2 face = vec2(point.x, float(cell.y) + 0.996);
					side = kind == 1 ? trace_sun(face, height * 0.57, true, false) : trace_sun(point, max(0.47, height * 0.55), true, false);
					top = trace_sun(point, height > 0.01 ? height + 0.025 : 1.45, true, false);
				}
				visibility = vec3(trace_sun(point, 0.04, false, false), side, top);
			}
		}
	}
	COLOR = vec4(visibility, 1.0);
}
