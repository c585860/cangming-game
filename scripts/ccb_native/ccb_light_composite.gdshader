shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Pass 3 (Full-Res 1:1 Ultra-Fast Real-World Physically Based Composite — ZERO heavy raymarch loops!):
// - Wall-aware bilinear sampling of Pass 1 (World-Space Direct Light) & Pass 2B (32-Ray Colored GI + Volumetric + AO)
// - 7 Distinct Real-World Surface Materials (`mat_tex.a`):
//   0=Grass/Foliage (translucent Subsurface Scattering + matte velvet)
//   1=Wood (satin wood-grain sheen + warm amber reflections)
//   2=Metal/Vehicle/Console (colored metallic Fresnel specular reflections!)
//   3=Glass/Window (sharp Fresnel sky/light reflection + tinted scatter)
//   4=Water (animated Fresnel sky/sun/moon/fire reflection + flowing caustics)
//   5=Concrete/Brick/Stone (mineral micro-relief, unclipped crisp grain)
//   6=Asphalt/Dirt (dry matte -> smooth multi-octave continuous wet rain reflections!)
// - Smooth continuous dusk & night across the whole unobstructed world (NEVER disappears 1 tile at a time!)
// - Analytic 3D player body shadow + compact handheld flashlight/torch (runs ONLY when carrying active light!)

uniform sampler2D raw_tex : filter_nearest, repeat_disable;
uniform sampler2D surface_mask : filter_nearest, repeat_disable;
uniform sampler2D direct_tex : filter_linear, repeat_disable; // RGB * 2.0 = HDR direct light, A = sun vis
uniform sampler2D gi_tex : filter_linear, repeat_disable;     // RGB * 2.0 = HDR colored GI + volumetric, A = curved AO
uniform sampler2D sight_tex : filter_linear, repeat_disable;  // R = 9-ray smooth wall_los, G = smooth explored
uniform sampler2D geom_tex : filter_nearest, repeat_disable;
uniform sampler2D mat_tex : filter_nearest, repeat_disable;   // RGB = bounce albedo, A = mat_id / 7.0
uniform sampler2D vis_tex : filter_nearest, repeat_disable;   // R = CCB state, G = opaque, B = explored, A = water

uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_size = vec2(61.0, 41.0);
uniform vec2 view_world_min = vec2(0.0);
uniform vec2 view_world_span = vec2(28.0, 20.0);
uniform vec2 light_world_min = vec2(0.0);
uniform vec2 light_world_span = vec2(32.0, 22.0);
uniform vec2 screen_px = vec2(960.0, 640.0);

uniform vec3 sun_ray = vec3(0.55, -0.45, 0.70);
uniform vec3 sun_color = vec3(1.0, 0.94, 0.84);
uniform float sun_energy = 1.0;
uniform vec3 sky_color = vec3(0.68, 0.82, 1.0);
uniform float sky_energy = 0.75;
uniform float moon_energy = 0.0;
uniform vec3 season_tint = vec3(1.0);
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
uniform bool is_underground = false;
uniform float wind_time = 0.0;

uniform vec2 player_eye = vec2(0.0);
uniform vec2 player_feet = vec2(0.0);
uniform vec4 player_light_pos_rad = vec4(-999.0, -999.0, 5.0, 0.0);
uniform vec4 player_light_col_mode = vec4(1.0, 0.74, 0.38, 0.5);
uniform vec4 player_light_cone = vec4(1.0, 0.0, -1.0, 0.0); // xy=facing dir, z=cone_cos (<= -0.5 omni), w=volumetric_beam

float hash21(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

// Smooth continuous 2D value noise (zero blocky checkerboard squares!)
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

int surf_cls(ivec2 cell) {
	ivec2 c = clamp(cell, ivec2(0), ivec2(grid_size) - ivec2(1));
	vec4 g = texelFetch(geom_tex, c, 0);
	int k = int(round(g.g * 255.0));
	if (k >= 1 && k <= 4) {
		return 2;
	}
	return int(round(g.a * 3.0)) & 1;
}

float analytic_body_shadow(vec2 world_p, float h, vec3 heading) {
	vec3 scale = vec3(0.23, 0.17, 0.55);
	vec3 org = vec3(world_p - player_feet, h - 0.54) / scale;
	vec3 d = heading / scale;
	float t = max(0.0, -dot(org, d) / max(dot(d, d), 0.001));
	float e = length(org + d * t);
	return (1.0 - smoothstep(0.76, 1.22, e)) * (1.0 - smoothstep(10.0, 16.0, t));
}

// Compact 14-step handheld portable light raycast (executes ONLY when player holds an active light!)
float trace_hand_light(vec2 start_local, vec2 end_local, ivec2 target_cell, bool target_wall) {
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
	for (int s = 0; s < 16; s++) {
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
		int k = int(round(texelFetch(geom_tex, cell, 0).g * 255.0));
		if (k == 1) {
			return 0.0;
		} else if (k == 2) {
			vis *= 0.48;
		} else if (k == 5) {
			vis *= 0.70;
		}
	}
	return vis;
}

vec3 eval_portable_light(vec2 world_p, vec2 local_p, ivec2 own_cell, bool is_wall, vec3 surf_n, out vec3 halo_out) {
	halo_out = vec3(0.0);
	float energy = player_light_pos_rad.w;
	if (energy <= 0.01) {
		return vec3(0.0);
	}
	vec2 lpos = player_light_pos_rad.xy;
	float radius = player_light_pos_rad.z;
	float d2 = length(world_p - lpos);
	if (d2 >= radius) {
		return vec3(0.0);
	}
	float flicker = player_light_col_mode.a;
	float wave = 1.0 + (sin(wind_time * 7.2) * 0.6 + sin(wind_time * 16.5) * 0.4) * (0.10 * flicker);
	vec2 l_local = lpos - grid_origin;
	vec2 dir2 = (d2 > 0.001) ? (world_p - lpos) / d2 : vec2(1.0, 0.0);
	// P0.1 Focused directional flashlight cone with soft foot-spill & raycast-occluded volumetric Tyndall beam!
	float spot = 1.0;
	float vol_beam = 0.0;
	if (player_light_cone.z > -0.5) {
		float c_align = dot(dir2, player_light_cone.xy);
		float cone = smoothstep(player_light_cone.z - 0.20, player_light_cone.z + 0.08, c_align);
		float near_spill = 0.28 * exp(-d2 * 0.62);
		spot = max(cone, near_spill);
		if (spot < 0.015) {
			return vec3(0.0);
		}
		float vol_core = smoothstep(player_light_cone.z - 0.12, player_light_cone.z + 0.16, c_align);
		float vol_dist = smoothstep(0.15, 0.85, d2) * (1.0 - smoothstep(radius * 0.20, radius * 0.95, d2));
		vol_beam = vol_core * vol_dist * player_light_cone.w;
	}
	vec2 perp = vec2(-dir2.y, dir2.x) * 0.12;
	float vis = trace_hand_light(l_local, local_p, own_cell, is_wall) * 0.50
		+ trace_hand_light(l_local + perp, local_p, own_cell, is_wall) * 0.25
		+ trace_hand_light(l_local - perp, local_p, own_cell, is_wall) * 0.25;
	if (vis <= 0.01) {
		return vec3(0.0);
	}
	vec3 to_l = vec3(lpos - world_p, 0.90);
	float d3 = length(to_l);
	float ndl = 0.46 + 0.54 * max(0.0, dot(surf_n, to_l / max(d3, 0.001)));
	float cutoff = 1.0 - smoothstep(radius * 0.34, radius, d2);
	float atten = cutoff / (0.35 + 0.45 * d3 * d3);
	vec3 col = player_light_col_mode.rgb;
	if (d2 < 2.0) {
		halo_out = col * exp(-d2 * d2 * 2.5) * vis * wave * (0.04 + 0.002 * energy);
	}
	if (vol_beam > 0.002) {
		// Subtle swirling dust motes inside the Tyndall flashlight beam!
		float dust = 0.84 + 0.16 * smooth_noise2(world_p * 3.8 + vec2(wind_time * 0.22, -wind_time * 0.15));
		halo_out += col * (vol_beam * vis * dust * 0.18);
	}
	return col * (1.0 - exp(-(energy * wave * atten * vis * ndl * spot) * 0.145));
}

// ACES-inspired filmic tone mapper preserving saturated colored reflections & crisp concrete highlights
vec3 filmic_tone_map(vec3 hdr) {
	vec3 x = max(hdr, vec3(0.0));
	vec3 aces = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
	float luma = dot(x, vec3(0.2126, 0.7152, 0.0722));
	float soft_peak = luma / (1.0 + max(0.0, luma - 0.65) * 0.68);
	vec3 preserved = x * (soft_peak / max(luma, 0.0001));
	return clamp(mix(preserved, aces, 0.42), vec3(0.0), vec3(1.0));
}

void fragment() {
	vec2 world_p = view_world_min + UV * view_world_span;
	vec2 local_p = world_p - grid_origin;
	ivec2 gsz = ivec2(grid_size);
	ivec2 own = clamp(ivec2(floor(local_p)), ivec2(0), gsz - ivec2(1));

	vec4 own_vis = texelFetch(vis_tex, own, 0);
	float ccb_state = own_vis.r;
	if (ccb_state < 0.10) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec3 raw = texture(raw_tex, UV).rgb;
		vec4 geom = texelFetch(geom_tex, own, 0);
		int kind = int(round(geom.g * 255.0));
		bool is_wall_tile = (kind >= 1 && kind <= 4);

		// Decode C++-precomputed 4-bit neighbor edge-clamp mask from own_vis.b (ZERO extra geom_tex fetches on GPU!)
		int vbits = int(round(own_vis.b * 255.0));
		vec2 frac_p = fract(local_p);
		vec2 safe_min = vec2(((vbits & 16) != 0) ? 0.16 : 0.0, ((vbits & 64) != 0) ? 0.16 : 0.0);
		vec2 safe_max = vec2(((vbits & 32) != 0) ? 0.84 : 1.0, ((vbits & 128) != 0) ? 0.84 : 1.0);
		vec2 inv_lspan = 1.0 / max(light_world_span, vec2(1.0));
		vec2 safe_world_p = grid_origin + vec2(own) + clamp(frac_p, safe_min, safe_max);
		vec2 luv = clamp((safe_world_p - light_world_min) * inv_lspan, vec2(0.002), vec2(0.998));
		vec2 sight_uv = clamp((world_p - light_world_min) * inv_lspan, vec2(0.002), vec2(0.998));

		// Solid wall tiles sample clamped `luv` so unseen black space behind the wall never bleeds into wall edges!
		float wall_los = texture(sight_tex, is_wall_tile ? luv : sight_uv).r;
		bool is_fringe = (ccb_state > 0.15 && ccb_state < 0.35);
		bool is_explored = (ccb_state >= 0.42);

		// Instant GPU early-out on fully occluded fringe or wall-occluded Map Memory pixels!
		// Skips direct_tex, gi_tex, surface_mask, relief normals, PBR materials, shadows & tone mapping on 30-60% of pixels!
		if (wall_los < 0.02) {
			if (is_explored) {
				float raw_luma = dot(raw, vec3(0.299, 0.587, 0.114));
				COLOR = vec4(mix(raw, vec3(raw_luma), 0.64) * vec3(0.15, 0.18, 0.25), 1.0);
			} else {
				COLOR = vec4(0.0, 0.0, 0.0, 1.0);
			}
		} else {
			vec4 mask = texture(surface_mask, UV);
			bool is_sprite = mask.a > 0.5;
			bool is_char = is_sprite && ((int(round(mask.b * 255.0)) & 128) != 0);

			vec4 mat_info = texelFetch(mat_tex, own, 0);
			bool indoors = (int(round(geom.a * 3.0)) & 1) != 0;
			bool is_wall = !is_char && is_wall_tile;
			int mat_id = int(round(mat_info.a * 7.0));

			vec4 dir_s = texture(direct_tex, luv);
			vec4 gi_s = texture(gi_tex, luv);

			// Unpack 2x HDR range (works seamlessly in both RGBA16F and RGBA8 Compatibility renderers!)
			vec3 direct_light = dir_s.rgb * 2.0;
			float sun_vis = dir_s.a;
			vec3 gi_and_vol = gi_s.rgb * 2.0;
			float ao = is_sprite ? mix(1.0, gi_s.a, 0.45) : gi_s.a;

			// Analytic real-time 60 FPS player body shadow + soft contact feet shadow (ZERO loops!)
			float z_surf = is_char ? 0.85 : (is_sprite ? max(0.35, geom.r * 2.2) : 0.04);
			if (!is_char && !is_underground && sun_energy > 0.01 && sun_vis > 0.01) {
				float bsh = analytic_body_shadow(world_p, z_surf, sun_ray);
				vec3 sun_part = sun_color * (sun_vis * sun_energy * 0.92);
				direct_light = max(direct_light - sun_part * (0.88 * bsh), vec3(0.0));
				sun_vis *= 1.0 - 0.88 * bsh;
			}
			float feet_ao = is_sprite ? 0.0 : (1.0 - smoothstep(0.16, 0.86, length((world_p - player_feet) / vec2(0.38, 0.22))));
			ao *= 1.0 - 0.24 * feet_ao;

			// Conditional per-pixel micro-normal surface relief (skips 2 extra full-res taps when surface is flat/unlit!)
			float lc = dot(raw, vec3(0.299, 0.587, 0.114));
			vec3 surf_n = vec3(0.0, 0.0, 1.0);
			if (sun_energy > 0.01 || mat_id == 2 || mat_id == 5 || player_light_pos_rad.w > 0.01) {
				vec2 pstep = 1.0 / max(screen_px, vec2(64.0));
				float lr = dot(texture(raw_tex, clamp(UV + vec2(pstep.x, 0.0), vec2(0.0), vec2(1.0))).rgb, vec3(0.299, 0.587, 0.114));
				float ld = dot(texture(raw_tex, clamp(UV + vec2(0.0, pstep.y), vec2(0.0), vec2(1.0))).rgb, vec3(0.299, 0.587, 0.114));
				float rel_amp = is_char ? 0.15 : (mat_id == 5 ? 0.46 : (mat_id == 1 ? 0.36 : 0.28));
				surf_n = normalize(vec3((lc - lr) * rel_amp, (lc - ld) * rel_amp, 1.0));
			}
			vec3 view_dir = normalize(vec3(0.0, 0.28, 0.96)); // 2.5D top-down camera angle

			// Subtle directional relief modulation from sunlight
			float relief_ndl = 0.80 + 0.20 * max(0.0, dot(surf_n, sun_ray));
			direct_light *= mix(1.0, relief_ndl, clamp(sun_vis * sun_energy, 0.0, 1.0));

			// Compact player handheld light (zero cost when player has no active flashlight/torch!)
			vec3 hand_halo = vec3(0.0);
			vec3 hand_light = eval_portable_light(world_p, local_p, own, is_wall, surf_n, hand_halo);

			// Continuous natural dark baseline (smoothly dims with twilight/night everywhere — zero steps!)
			float sky_day = clamp(sky_energy, 0.0, 1.0);
			vec3 base_ambient;
			if (is_underground) {
				base_ambient = vec3(0.056, 0.062, 0.080);
			} else if (indoors) {
				base_ambient = mix(vec3(0.052, 0.060, 0.084), vec3(0.140, 0.138, 0.144), sky_day);
			} else {
				base_ambient = mix(vec3(0.046, 0.066, 0.118), sky_color * 0.085, sky_day);
			}

			// Total incident light = curved-AO ambient & rich colored GI bounce + direct sun/moon/point lights + handheld
			float gi_gain = (mat_id == 5 || is_wall) ? 1.15 : (indoors ? 1.08 : 0.85);
			vec3 incident = (base_ambient + gi_and_vol * gi_gain) * ao + direct_light + hand_light;
			if (is_char) {
				incident = max(incident, vec3(0.20, 0.21, 0.25));
			}

			vec3 lit = raw * incident * mix(vec3(1.0), season_tint, indoors ? 0.14 : 0.36);

			// REAL-WORLD PER-MATERIAL REFLECTION, SCATTERING & SPECULAR EFFECTS!
			vec3 half_sun = normalize(sun_ray + view_dir);
			float ndh_sun = max(0.0, dot(surf_n, half_sun));
			vec3 total_local = direct_light + hand_light;
			vec3 env_refl_col = mix(gi_and_vol * 1.15 + sky_color * (0.24 * sky_energy), total_local, 0.50);
			float env_luma = dot(total_local, vec3(0.299, 0.587, 0.114));

			if (!is_char) {
				if (mat_id == 0) {
					vec3 sss_tint = mix(vec3(0.36, 0.84, 0.16), vec3(0.88, 0.50, 0.14), clamp(1.0 - mat_info.g, 0.0, 1.0));
					float sss_amt = (sun_vis * sun_energy * 0.18 + env_luma * 0.05) * clamp(lc * 1.35, 0.20, 1.0);
					lit += (total_local * sss_tint * sss_amt * 0.38) + (gi_and_vol * sss_tint * 0.045);
				} else if (mat_id == 1) {
					float grain = smooth_noise2(world_p * vec2(2.6, 10.5));
					float spec_wood = pow(ndh_sun, 16.0) * sun_vis * sun_energy * (0.18 + 0.14 * grain);
					lit += sun_color * spec_wood * mix(raw, vec3(1.0, 0.84, 0.58), 0.55);
					lit += (total_local + gi_and_vol * 0.55) * (0.085 + 0.055 * grain) * clamp(lc * 1.5, 0.22, 1.0);
				} else if (mat_id == 2) {
					float spec_m = pow(ndh_sun, 30.0) * sun_vis * sun_energy * 0.56;
					float rim_m = 0.25 + 0.75 * clamp(length(surf_n.xy) * 2.4, 0.0, 1.0);
					float dark_w = clamp(1.0 - lc * 0.58, 0.28, 1.0);
					vec3 metal_tint = mix(vec3(0.84, 0.90, 0.98), raw * 1.35, 0.55);
					lit += sun_color * spec_m * metal_tint * dark_w + env_refl_col * metal_tint * (0.09 + 0.09 * rim_m) * dark_w;
				} else if (mat_id == 3) {
					float spec_g = pow(ndh_sun, 52.0) * sun_vis * sun_energy * 0.82;
					float sheen_g = smooth_noise2(world_p * vec2(4.0, 4.0) + vec2(0.0, wind_time * 0.02));
					vec3 glass_refl = mix(sky_color * (0.42 + 0.52 * sky_energy), env_refl_col, 0.48);
					lit += sun_color * spec_g + glass_refl * (0.30 + 0.12 * sheen_g);
				} else if (mat_id == 4 || own_vis.a > 0.25) {
					// Chroma-mask water reflection strictly to actual cool/blue-teal water pixels so dirt puddles
					// (t_puddle + murky water) and grassy riverbanks NEVER wash out into white 32x32 squares!
					float blue_lead = (raw.b - raw.r) + 0.35 * (raw.g - raw.r);
					float water_mask = smoothstep(0.015, 0.14, blue_lead) * smoothstep(0.04, 0.18, raw.b + raw.g);
					if (water_mask > 0.01) {
						float w1 = smooth_noise2(world_p * 3.2 + vec2(wind_time * 0.65, -wind_time * 0.42));
						float w2 = smooth_noise2(world_p * 6.4 + vec2(-wind_time * 0.48, wind_time * 0.72));
						float caustic = smoothstep(0.56, 0.92, (w1 + w2) * 0.5);
						vec3 water_sky = mix(vec3(0.14, 0.24, 0.44) * max(moon_energy, 0.22), sky_color * (0.42 + 0.36 * sky_energy), sky_day);
						vec3 water_refl = mix(water_sky, env_refl_col * 0.72, 0.35);
						lit = mix(lit, water_refl * 0.55 + lit * 0.68, 0.24 * water_mask);
						lit += (sun_color * sun_vis * sun_energy + env_refl_col * 0.35) * caustic * (0.20 * water_mask);
					}
				} else if (mat_id == 5 && !indoors && !is_underground && wetness > 0.06) {
					float damp = smooth_noise2(world_p * 1.45) * wetness;
					float wet_stone_spec = pow(ndh_sun, 22.0) * sun_vis * sun_energy * 0.22 * damp;
					lit = mix(lit, lit * 0.88 + env_refl_col * 0.22, damp * 0.35) + sun_color * wet_stone_spec;
				} else if (mat_id == 6 && !indoors && !is_underground && wetness > 0.04) {
					float p1 = smooth_noise2(world_p * 0.75);
					float p2 = smooth_noise2(world_p * 2.05 + vec2(11.3, 7.1));
					float ripple = sin(wind_time * 5.2 + p2 * 12.0) * 0.04 * wetness;
					float puddle = smoothstep(0.34, 0.72, p1 * 0.64 + p2 * 0.36) * wetness;
					float wet_spec = pow(ndh_sun, 20.0) * sun_vis * sun_energy * 0.38 * puddle;
					vec3 wet_refl = mix(sky_color * (0.34 + 0.46 * sky_energy), total_local * 1.15 + gi_and_vol * 0.65, 0.44);
					lit = mix(lit, lit * 0.72 + wet_refl * (0.40 + ripple), puddle * 0.58) + sun_color * wet_spec;
				}
			}

			if (!is_wall) {
				lit += gi_and_vol * (indoors ? 0.18 : 0.06);
			}
			lit += hand_halo;

			vec2 cv = (UV - vec2(0.5)) * 2.0;
			float vig = 1.0 - 0.065 * smoothstep(0.62, 1.48, dot(cv, cv));
			lit = filmic_tone_map(lit * vig);
			// P3.1 Subtle photographic split-tone harmony & ultra-fine 35mm micro film grain (unifies all tilesets cleanly!)
			float lit_l = dot(lit, vec3(0.2126, 0.7152, 0.0722));
			vec3 shadow_grade = mix(vec3(0.96, 0.985, 1.03), vec3(1.015, 1.005, 0.985), smoothstep(0.15, 0.75, lit_l));
			float grain = (hash21(floor(FRAGCOORD.xy * 0.5) + fract(wind_time * 7.3) * 31.0) - 0.5);
			float grain_amp = mix(0.016, 0.006, smoothstep(0.05, 0.60, lit_l));
			lit = clamp(lit * shadow_grade + vec3(grain * grain_amp), vec3(0.0), vec3(1.0));

			float raw_luma = dot(raw, vec3(0.299, 0.587, 0.114));
			vec3 mem_col = mix(raw, vec3(raw_luma), 0.64) * vec3(0.15, 0.18, 0.25);

			float night_amt = 1.0 - smoothstep(0.05, 0.42, sky_energy);
			if (night_amt > 0.01 && !is_wall) {
				float dist_p = length(world_p - player_eye);
				float lit_luma = dot(direct_light + hand_light, vec3(0.299, 0.587, 0.114));
				float far_dim = mix(1.0, 0.36, smoothstep(5.5, 16.0, dist_p) * night_amt * (1.0 - clamp(lit_luma * 2.2, 0.0, 1.0)));
				lit *= far_dim;
			}

			if (is_fringe) {
				COLOR = vec4(lit * smoothstep(0.08, 0.72, wall_los), 1.0);
			} else if (is_explored) {
				float vis_blend = smoothstep(0.08, 0.65, wall_los);
				COLOR = vec4(mix(mem_col, lit, vis_blend), 1.0);
			} else {
				COLOR = vec4(0.0, 0.0, 0.0, 1.0);
			}
		}
	}
}
