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
uniform bool soft_cascade = false;
uniform float wind_time = 0.0;

const float TRACE_RANGE = 28.0;
const float WINDOW_SILL = 0.77;
const float WINDOW_LINTEL = 1.89;

float hash21(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float obstacle(vec4 data, ivec2 cell, vec2 from, vec2 to, float low, float high, float bottom, bool receiver, float beam_distance) {
	int kind = int(round(data.g * 255.0));
	float height = data.r * 3.0;
	if (kind == 0 || low >= bottom + height) {
		return 1.0;
	}
	if (kind == 1) {
		return receiver ? 1.0 : 0.0;
	}
	if (kind >= 2 && kind <= 4) {
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
	vec2 seg = to - from;
	float t = clamp(dot(vec2(0.5) - from, seg) / max(dot(seg, seg), 0.0001), 0.0, 1.0);
	vec2 closest = mix(from, to, t);
	float z_at = mix(low, high, t) - bottom;

	if (kind == 8) {
		// Carved timber lantern post + hanging lantern head
		if (z_at > height) {
			return 1.0;
		}
		float r = z_at > height * 0.75 ? 0.14 : 0.07;
		return smoothstep(r * 0.55, r * 1.25, length(closest - vec2(0.5)));
	}
	if (kind == 5) {
		// Organic rounded tree canopy + trunk with gentle wind-dappled foliage shadow (non-grid!)
		float d_center = length(closest - vec2(0.5, 0.46));
		if (z_at < 0.78) {
			// Narrow trunk near ground
			return smoothstep(0.07, 0.14, length(closest - vec2(0.5, 0.56)));
		}
		float crown_t = clamp((z_at - 0.78) / max(0.2, height - 0.78), 0.0, 1.0);
		float radius = mix(0.42, 0.56, sin(crown_t * 2.55));
		vec2 sway = vec2(sin(wind_time * 1.4 + float(cell.x) * 0.7), cos(wind_time * 1.1 + float(cell.y) * 0.9)) * 0.04;
		float d = length(closest - vec2(0.5, 0.46) + sway);
		float dapple = hash21(floor((closest + vec2(cell) + sway) * 5.0));
		float edge = smoothstep(radius - 0.14, radius + 0.08, d);
		return mix(0.22 + 0.24 * dapple, 1.0, edge);
	}
	if (kind == 6) {
		// Rounded organic bush / shrub / fence shadow instead of hard 1x1 square
		float d = length(closest - vec2(0.5));
		return mix(0.46, 1.0, smoothstep(0.22, 0.48, d));
	}
	// Rounded beveled furniture / crates / fixtures
	float d_box = length(max(abs(closest - vec2(0.5)) - vec2(0.24), vec2(0.0)));
	return smoothstep(0.06, 0.18, d_box);
}

float trace_sun_dir(vec2 point, float receiver_z, bool allow_surface, bool indoor_beam, vec2 dir, float slope_rise) {
	ivec2 cell = ivec2(floor(point));
	ivec2 step_dir = ivec2(sign(dir));
	vec2 inv_speed = 1.0 / max(abs(dir), vec2(0.0001));
	vec2 within = fract(point);
	vec2 edge = vec2(dir.x < 0.0 ? within.x : 1.0 - within.x,
		dir.y < 0.0 ? within.y : 1.0 - within.y);
	vec2 crossing = edge * inv_speed;
	if (step_dir.x == 0) { crossing.x = TRACE_RANGE + 1.0; }
	if (step_dir.y == 0) { crossing.y = TRACE_RANGE + 1.0; }
	float enter = 0.0;
	float visibility = 1.0;
	for (int i = 0; i < 40; i++) {
		if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, map_size))) {
			break;
		}
		float leave = min(min(crossing.x, crossing.y), TRACE_RANGE);
		float z0 = receiver_z + enter * slope_rise;
		float z1 = receiver_z + leave * slope_rise;
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
			float a = max(enter, (bottom - receiver_z) / slope_rise);
			float b = min(leave, (top - receiver_z) / slope_rise);
			visibility *= obstacle(data, cell, point + a * dir - vec2(cell), point + b * dir - vec2(cell),
				receiver_z + a * slope_rise, receiver_z + b * slope_rise, bottom, allow_surface && i == 0 && layer == 0,
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

float trace_sun(vec2 point, float receiver_z, bool allow_surface, bool indoor_beam) {
	if (!soft_cascade) {
		return trace_sun_dir(point, receiver_z, allow_surface, indoor_beam, toward_sun, rise);
	}
	// Cascade 0 (near high-res): 3-sample angular sun-disc penumbra produces natural soft shadows
	// that stay sharp near wall bases and soften physically with shadow throw distance!
	vec2 perp = vec2(-toward_sun.y, toward_sun.x);
	float spread = 0.028;
	vec2 d1 = normalize(toward_sun + perp * spread);
	vec2 d2 = normalize(toward_sun - perp * spread);
	float c0 = trace_sun_dir(point, receiver_z, allow_surface, indoor_beam, toward_sun, rise);
	float c1 = trace_sun_dir(point, receiver_z, allow_surface, indoor_beam, d1, rise * 0.96);
	float c2 = trace_sun_dir(point, receiver_z, allow_surface, indoor_beam, d2, rise * 1.04);
	return c0 * 0.46 + (c1 + c2) * 0.27;
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
