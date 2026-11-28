shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Pass 1 (World-Space Direct Illumination Buffer, 8 texels/tile, UPDATE_ONCE on world/time/emitter change):
// 100% world-space physical direct light — completely independent of player tile position!
// - 5-sample soft solar-disc 3D DDA direct sunlight & moon shadows (naturally softens under clouds/drizzle)
// - Physical outdoor hemispherical sky dome fill
// - Up to 16 genuine world-space CCB artificial point lights (fires, consoles, lamps, items, vehicle lights)
//   with 3-ray area-light soft penumbra and physical inverse-square attenuation.
// Output RGBA: RGB = HDR direct incident light (linear), A = smooth direct sun visibility (0..1).

uniform sampler2D geom_tex : filter_nearest, repeat_disable;
uniform sampler2D vis_tex : filter_nearest, repeat_disable;

uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_size = vec2(61.0, 41.0);
uniform vec2 light_world_min = vec2(0.0);
uniform vec2 light_world_span = vec2(32.0, 22.0);

uniform vec3 sun_ray = vec3(0.55, -0.45, 0.70);
uniform vec3 sun_color = vec3(1.0, 0.94, 0.84);
uniform float sun_energy = 1.0;
uniform vec3 moon_ray = vec3(-0.45, -0.35, 0.82);
uniform float moon_energy = 0.0;
uniform vec3 sky_color = vec3(0.68, 0.82, 1.0);
uniform float sky_energy = 0.75;
uniform float cloud_cover = 0.0;
uniform bool is_underground = false;
uniform float wind_time = 0.0;
uniform vec2 wind_dir = vec2(0.85, 0.25);
uniform float wind_speed = 4.0;
uniform float mist_level = 0.16;

uniform int point_light_count = 0;
uniform vec4 point_light_pos_rad[16];  // xy=world center, z=radius, w=energy
uniform vec4 point_light_col_mode[16]; // rgb=true emitter color, a=flicker
uniform vec4 point_light_cone[16];     // xy=unit dir, z=cone_cos (<= -0.5 = omni), w=volumetric_beam

const float STORY_HEIGHT = 2.75;
const float WIN_SILL = 0.72;
const float WIN_LINTEL = 1.95;

float hash21(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float smooth_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

// Large-scale wind-drifting overhead cloud shadow field (P0.2 Moving Cloud Shadows!)
float eval_cloud_shadow(vec2 wp) {
	float spd = 0.18 + clamp(wind_speed * 0.018, 0.0, 0.95);
	vec2 drift = wind_dir * (wind_time * spd);
	vec2 p = wp * 0.048 - drift;
	float n = smooth_noise2(p) * 0.62 + smooth_noise2(p * 2.15 + vec2(7.3, -4.1)) * 0.38;
	float thresh = mix(0.84, 0.24, clamp(cloud_cover, 0.0, 1.0));
	float occ = smoothstep(thresh - 0.16, thresh + 0.18, n);
	// Soft realistic shadow floor (clouds dim direct sun shafts cleanly without blacking out the ground)
	return mix(1.0, mix(0.46, 0.22, clamp(cloud_cover, 0.0, 1.0)), occ * smoothstep(0.08, 0.35, cloud_cover));
}

float eval_sun_obstacle(vec4 data, ivec2 cell, vec2 from_p, vec2 to_p, float z0, float z1, bool is_receiver) {
	int kind = int(round(data.g * 255.0));
	float h = data.r * 3.0;
	if (kind == 0 || z0 >= h) {
		return 1.0;
	}
	if (kind == 1) {
		return is_receiver ? 1.0 : 0.0;
	}
	if (kind >= 2 && kind <= 4) {
		bool normal_x = data.b > 0.5;
		float s0 = normal_x ? from_p.x : from_p.y;
		float s1 = normal_x ? to_p.x : to_p.y;
		if ((s0 - 0.5) * (s1 - 0.5) > 0.0) {
			return 1.0;
		}
		float w = s1 - s0;
		float at = abs(w) < 0.0001 ? 0.0 : clamp((0.5 - s0) / w, 0.0, 1.0);
		vec2 ap = mix(from_p, to_p, at);
		float across = abs((normal_x ? ap.y : ap.x) - 0.5);
		float z = mix(z0, z1, at);
		float frame = (kind == 4)
			? (1.0 - smoothstep(0.38, 0.48, across))
			: (1.0 - smoothstep(0.31, 0.42, across));
		float sill = (kind == 4) ? 0.0 : WIN_SILL;
		float lintel = (kind == 4) ? 2.16 : WIN_LINTEL;
		float opening = frame
			* smoothstep(sill - 0.04, sill + 0.08, z)
			* (1.0 - smoothstep(lintel - 0.08, lintel + 0.04, z));
		return opening * (kind == 2 ? 0.68 : 1.0);
	}
	if (is_receiver) {
		return 1.0;
	}
	vec2 seg = to_p - from_p;
	float t = clamp(dot(vec2(0.5) - from_p, seg) / max(dot(seg, seg), 0.0001), 0.0, 1.0);
	vec2 closest = mix(from_p, to_p, t);
	float zat = mix(z0, z1, t);

	if (kind == 5) {
		if (zat < 0.74) {
			return smoothstep(0.07, 0.16, length(closest - vec2(0.5, 0.56)));
		}
		float crown_t = clamp((zat - 0.74) / max(0.2, h - 0.74), 0.0, 1.0);
		float rad = mix(0.46, 0.64, sin(crown_t * 2.6));
		vec2 sway = vec2(sin(wind_time * 1.2 + float(cell.x) * 0.7), cos(wind_time * 0.9 + float(cell.y) * 0.9)) * 0.035;
		float d = length(closest - vec2(0.5, 0.46) + sway);
		float dapple = hash21(floor((closest + vec2(cell) + sway) * 4.5));
		return mix(0.18 + 0.26 * dapple, 1.0, smoothstep(rad - 0.14, rad + 0.14, d));
	}
	if (kind == 6) {
		return mix(0.48, 1.0, smoothstep(0.20, 0.48, length(closest - vec2(0.5))));
	}
	float d_box = length(max(abs(closest - vec2(0.5)) - vec2(0.25), vec2(0.0)));
	return smoothstep(0.06, 0.22, d_box);
}

float trace_sun_single(vec2 local_p, float start_z, vec3 ray3, bool allow_self) {
	vec2 dir2 = ray3.xy;
	float len2 = length(dir2);
	if (len2 < 0.0001) {
		return 1.0;
	}
	vec2 dir = dir2 / len2;
	float slope = max(ray3.z, 0.08) / len2;

	ivec2 cell = ivec2(floor(local_p));
	ivec2 sdir = ivec2(sign(dir));
	vec2 inv_d = 1.0 / max(abs(dir), vec2(0.0001));
	vec2 within = fract(local_p);
	vec2 edge = vec2(dir.x < 0.0 ? within.x : 1.0 - within.x, dir.y < 0.0 ? within.y : 1.0 - within.y);
	vec2 cross_t = edge * inv_d;
	if (sdir.x == 0) { cross_t.x = 999.0; }
	if (sdir.y == 0) { cross_t.y = 999.0; }

	float enter_t = 0.0;
	float vis = 1.0;
	ivec2 gsz = ivec2(grid_size);
	for (int i = 0; i < 28; i++) {
		if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, gsz))) {
			break;
		}
		float leave_t = min(min(cross_t.x, cross_t.y), 22.0);
		float z0 = start_z + enter_t * slope;
		float z1 = start_z + leave_t * slope;
		vec4 data = texelFetch(geom_tex, cell, 0);
		bool roofed = (int(round(data.a * 3.0)) & 2) != 0;
		if (roofed && z0 < STORY_HEIGHT && z1 >= STORY_HEIGHT) {
			return 0.0;
		}
		if (z0 >= STORY_HEIGHT) {
			break;
		}
		vis *= eval_sun_obstacle(
			data, cell,
			local_p + enter_t * dir - vec2(cell),
			local_p + leave_t * dir - vec2(cell),
			z0, z1, allow_self && (i == 0)
		);
		if (vis < 0.015) {
			return 0.0;
		}
		if (leave_t >= 22.0) {
			break;
		}
		enter_t = leave_t;
		if (cross_t.x < cross_t.y) {
			cell.x += sdir.x;
			cross_t.x += inv_d.x;
		} else {
			cell.y += sdir.y;
			cross_t.y += inv_d.y;
		}
	}
	return vis;
}

float trace_sun_soft(vec2 local_p, float start_z, vec3 ray3, bool allow_self) {
	vec2 dir2 = normalize(max(abs(ray3.xy), vec2(0.0001)) * sign(ray3.xy + vec2(1e-6)));
	vec2 perp = vec2(-dir2.y, dir2.x);
	float spread = mix(0.028, 0.068, clamp(cloud_cover, 0.0, 1.0));
	vec3 r1 = normalize(vec3(ray3.xy + perp * spread, ray3.z * 0.95));
	vec3 r2 = normalize(vec3(ray3.xy - perp * spread, ray3.z * 1.05));
	vec3 r3 = normalize(vec3(ray3.xy + perp * (spread * 0.5), ray3.z * 1.05));
	vec3 r4 = normalize(vec3(ray3.xy - perp * (spread * 0.5), ray3.z * 0.95));
	return trace_sun_single(local_p, start_z, ray3, allow_self) * 0.30
		+ (trace_sun_single(local_p, start_z, r1, allow_self)
		+ trace_sun_single(local_p, start_z, r2, allow_self)
		+ trace_sun_single(local_p, start_z, r3, allow_self)
		+ trace_sun_single(local_p, start_z, r4, allow_self)) * 0.175;
}

float trace_point_ray(vec2 start_local, vec2 end_local, ivec2 target_cell, bool target_wall) {
	vec2 delta = end_local - start_local;
	float dist = length(delta);
	if (dist < 0.08) {
		return 1.0;
	}
	vec2 dir = delta / dist;
	ivec2 cell = ivec2(floor(start_local));
	ivec2 start_cell = cell;
	ivec2 sdir = ivec2(sign(dir));
	vec2 inv_d = 1.0 / max(abs(dir), vec2(0.0001));
	vec2 within = fract(start_local);
	vec2 edge = vec2(dir.x < 0.0 ? within.x : 1.0 - within.x, dir.y < 0.0 ? within.y : 1.0 - within.y);
	vec2 cross_t = edge * inv_d;
	if (sdir.x == 0) { cross_t.x = 999.0; }
	if (sdir.y == 0) { cross_t.y = 999.0; }

	float vis = 1.0;
	ivec2 gsz = ivec2(grid_size);
	for (int s = 0; s < 26; s++) {
		float next_t = min(cross_t.x, cross_t.y);
		if (next_t >= dist - 0.03) {
			break;
		}
		if (cross_t.x < cross_t.y) {
			cell.x += sdir.x;
			cross_t.x += inv_d.x;
		} else {
			cell.y += sdir.y;
			cross_t.y += inv_d.y;
		}
		if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, gsz))) {
			return 0.0;
		}
		if (cell == start_cell) {
			continue;
		}
		if (cell == target_cell && target_wall) {
			return vis;
		}
		vec4 g = texelFetch(geom_tex, cell, 0);
		int k = int(round(g.g * 255.0));
		if (k == 1) {
			return 0.0;
		} else if (k == 2) {
			vis *= 0.52;
		} else if (k == 3 || k == 4) {
			vis *= 0.96;
		} else if (k == 5) {
			// Circular tree trunk occlusion instead of a square block
			float t_proj = clamp(dot((vec2(cell) + vec2(0.5)) - start_local, dir), 0.0, dist);
			float d_tr = length((start_local + dir * t_proj) - (vec2(cell) + vec2(0.5)));
			vis *= smoothstep(0.14, 0.34, d_tr);
		} else if (k == 7) {
			float h = g.r * 3.0;
			if (h > 1.15) {
				vis *= 0.45;
			}
		}
		if (vis < 0.02) {
			return 0.0;
		}
	}
	return vis;
}

void fragment() {
	vec2 world_p = light_world_min + UV * light_world_span;
	vec2 local_p = world_p - grid_origin;
	ivec2 gsz = ivec2(grid_size);
	ivec2 own = clamp(ivec2(floor(local_p)), ivec2(0), gsz - ivec2(1));
	vec4 geom = texelFetch(geom_tex, own, 0);
	int kind = int(round(geom.g * 255.0));
	bool indoors = (int(round(geom.a * 3.0)) & 1) != 0;
	bool is_wall = (kind >= 1 && kind <= 4);

	// Fast GPU early-out: unseen deep indoor tiles with no nearby artificial lights cannot bounce sky light into view
	if (point_light_count == 0 && indoors && kind == 0 && texelFetch(vis_tex, own, 0).r < 0.05) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		// Solid walls: evaluate cleanly at tile center (ZERO collinear 45-deg sawtooth triangles on south/north walls!)
		// Exterior walls fade smoothly from outdoor parapet illumination on the outdoor edge to shaded interior concrete on the indoor edge!
		vec2 sun_origin = local_p;
		float z_recv = 0.05;
		bool ext_wall = false;
		float wall_ext_grad = 0.0;
		if (kind == 1) {
			vec2 fp = fract(local_p);
			ivec2 nbs[4] = { ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1) };
			float edge_t[4] = { fp.x, 1.0 - fp.x, fp.y, 1.0 - fp.y };
			for (int ni = 0; ni < 4; ni++) {
				ivec2 nc = clamp(own + nbs[ni], ivec2(0), gsz - ivec2(1));
				vec4 ng = texelFetch(geom_tex, nc, 0);
				int nk = int(round(ng.g * 255.0));
				bool n_in = (int(round(ng.a * 3.0)) & 1) != 0;
				if (!n_in && nk != 1) {
					ext_wall = true;
					wall_ext_grad = max(wall_ext_grad, smoothstep(0.10, 0.92, edge_t[ni]));
				}
			}
			sun_origin = vec2(own) + vec2(0.5);
			z_recv = 2.42;
		} else if (kind >= 5) {
			z_recv = clamp(geom.r * 1.4, 0.25, 1.35);
		}

		// 1. Direct Sunlight & Moonlight (with wind-drifting overhead cloud shadows!)
		float sun_vis = 0.0;
		if (!is_underground && sun_energy > 0.004 && (kind != 1 || ext_wall)) {
			sun_vis = trace_sun_soft(sun_origin, z_recv, sun_ray, is_wall || kind >= 5);
			if (sun_vis > 0.01 && cloud_cover > 0.08) {
				sun_vis *= eval_cloud_shadow(world_p);
			}
		}
		float moon_vis = 0.0;
		if (!is_underground && moon_energy > 0.004 && (kind != 1 || ext_wall)) {
			moon_vis = trace_sun_single(sun_origin, z_recv, moon_ray, is_wall || kind >= 5);
		}

		// World-space architectural parapet shading: calm shaded interior wall face, clean sunlit exterior wall face!
		float wall_sun_scale = (kind == 1) ? mix(0.14, 0.50, wall_ext_grad) : 1.0;
		vec3 moon_col = vec3(0.46, 0.62, 0.92);
		vec3 direct = sun_color * (sun_vis * sun_energy * 0.98 * wall_sun_scale)
			+ moon_col * (moon_vis * moon_energy * 0.44 * wall_sun_scale);

		// 2. Direct Outdoor Sky Hemisphere (physically energy-conserving: crisp shadow contrast on clear days,
		//    soft luminous overcast dome fill during clouds/drizzle/fog!)
		if (!is_underground) {
			float sky_fill_gain = mix(0.24, 0.44, clamp(cloud_cover, 0.0, 1.0));
			if (!indoors && kind != 1) {
				direct += sky_color * (0.045 + sky_fill_gain * sky_energy);
			} else if (kind == 1 && ext_wall) {
				// Balanced exterior wall parapet sky gradient (never blinding chalk-white inside a dark shelter!)
				direct += sky_color * ((0.025 + 0.13 * sky_energy) * mix(0.32, 1.0, wall_ext_grad));
			}
		}

		// 3. Genuine World-Space CCB Artificial Point Lights (Fires, Consoles, Lamps, Lit Items, Vehicle Headlights)
		if (point_light_count > 0) {
			for (int i = 0; i < 16; i++) {
				if (i >= point_light_count) {
					break;
				}
				vec4 pr = point_light_pos_rad[i];
				vec4 cm = point_light_col_mode[i];
				vec4 cn = point_light_cone[i];
				float radius = pr.z;
				float energy = pr.w;
				if (energy <= 0.001 || radius <= 0.1) {
					continue;
				}
				vec2 lpos = pr.xy;
				vec2 delta_l = world_p - lpos;
				float d2 = length(delta_l);
				if (d2 >= radius) {
					continue;
				}
				vec2 dir2 = (d2 > 0.001) ? (delta_l / d2) : vec2(1.0, 0.0);
				// P0.1 Directional spotlight shaping for vehicle headlights & floodlights (with soft near-lamp spill!)
				float spot = 1.0;
				float beam_vol = 0.0;
				if (cn.z > -0.5) {
					float c_align = dot(dir2, cn.xy);
					float cone_shape = smoothstep(cn.z - 0.16, cn.z + 0.08, c_align);
					float near_spill = 0.24 * exp(-d2 * 0.85);
					spot = max(cone_shape, near_spill);
					if (spot < 0.015) {
						continue;
					}
					float fog_w = clamp(mist_level * 1.15 + (1.0 - sky_energy) * 0.45 + (is_underground ? 0.40 : 0.0), 0.10, 1.0);
					beam_vol = cone_shape * (1.0 - smoothstep(0.5, radius * 0.92, d2)) * fog_w * cn.w;
				}
				float phase = lpos.x * 1.73 + lpos.y * 2.41;
				float wave = 1.0 + (sin(wind_time * 6.4 + phase) * 0.55 + sin(wind_time * 13.7 - phase) * 0.45) * (0.09 * cm.a);
				vec2 l_local = lpos - grid_origin;
				vec2 perp = vec2(-dir2.y, dir2.x) * (0.14 + 0.06 * smoothstep(0.5, 4.5, d2));

				float vis = trace_point_ray(l_local, local_p, own, is_wall) * 0.50
					+ trace_point_ray(l_local + perp, local_p, own, is_wall) * 0.25
					+ trace_point_ray(l_local - perp, local_p, own, is_wall) * 0.25;
				if (vis <= 0.005) {
					continue;
				}
				float cutoff = 1.0 - smoothstep(radius * 0.26, radius, d2);
				float d3 = sqrt(d2 * d2 + 0.58);
				float atten = cutoff / (0.30 + 0.42 * d3 * d3);
				// Warm blackbody core shift on flames; crisp saturated hue on consoles/LEDs/bioluminescence
				float warm = clamp((cm.r - cm.b) * 1.5, 0.0, 1.0);
				vec3 col = mix(cm.rgb, vec3(1.0, 0.94, 0.80), exp(-d2 * d2 * 1.6) * 0.42 * warm);
				float raw_e = energy * wave * atten * vis * spot;
				direct += col * ((1.0 - exp(-raw_e * 0.165)) * 1.28 + beam_vol * vis * 0.26);
			}
		}

		// Pack 2x HDR range (* 0.5) so both RGBA16F and 8-bit Compatibility buffers preserve highlight headroom
		COLOR = vec4(direct * 0.5, sun_vis);
	}
}
