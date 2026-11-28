shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

// Real-Time PBR + Raymarched Shadows + 32-Ray Colored GI + Weather 3D Terrain Shader for CECP 2.0.
// Combines CCB's multi-Z instanced 3D geometry & occlusion cutouts with our decoupled HDR world lightmaps
// (direct sunbeams, soft directional shadows, 16 shadowed world emitters, colored GI bounce, curved AO),
// wet rain puddles & ripples, snow frost dusting, thunderstorm lightning flashes, and 3D distance fog!

uniform sampler2D atlas_tex : source_color, filter_nearest, repeat_disable;
uniform int u_mode = 0; // 0=box, 1=xquad, 2=billboard, 3=billboard_snap, 4=linequad, 5=flatquad
uniform vec3 u_cam_right = vec3(1.0, 0.0, 0.0);
uniform vec3 u_cam_up = vec3(0.0, 1.0, 0.0);
uniform vec3 u_cam_fwd = vec3(0.0, 0.0, -1.0);
uniform vec4 u_sun_dir = vec4(0.4, 0.85, 0.3, 1.0); // xyz in Godot (East,Up,South), w=sun_up

uniform vec3 u_eye_pos = vec3(0.0, 10.0, 10.0);
uniform vec3 u_player_pos = vec3(0.5, 1.0, 0.5);
uniform vec4 u_mask_params = vec4(3.2, 2.2, 0.0, 1.0); // rx, ry, player_ground_y, enabled
uniform vec4 u_cursor_params = vec4(-1.0, -1.0, 0.0, 0.0); // uv.xy, enabled, 0
uniform vec4 u_effect_params = vec4(0.075, 0.10, 0.39215686, 0.0); // cursor rx/ry, 1/WALL_HEIGHT, same_level_cut
uniform int u_memory_preset = 0;
uniform vec4 u_nv_params = vec4(0.0, 0.55, 0.85, 0.0); // active, night_floor, overexpose_start

// World-space HDR Direct/GI/Geometry/Material textures from CcbRtLightingPipeline
uniform bool u_has_lightmap = false;
uniform sampler2D u_direct_tex : filter_linear, repeat_disable; // RGB * 2.0 = HDR direct, A = sun_vis
uniform sampler2D u_gi_tex : filter_linear, repeat_disable;     // RGB * 2.0 = HDR GI + volumetric, A = AO
uniform sampler2D u_geom_tex : filter_nearest, repeat_disable;  // A bit0 = indoors
uniform sampler2D u_mat_tex : filter_nearest, repeat_disable;   // A * 7 = mat_id (0..6)
uniform vec2 u_center_xy = vec2(0.0, 0.0);
uniform vec2 u_light_min = vec2(0.0, 0.0);
uniform vec2 u_light_span = vec2(44.0, 36.0);
uniform vec2 u_grid_origin = vec2(0.0, 0.0);
uniform vec2 u_grid_size = vec2(61.0, 41.0);

// Astronomical & Weather parameters
uniform vec4 u_sun_col_energy = vec4(1.0, 0.94, 0.84, 0.85);   // rgb, w = sun_energy
uniform vec4 u_sky_col_energy = vec4(0.74, 0.86, 1.0, 0.75);   // rgb, w = sky_energy
uniform vec4 u_weather_params = vec4(0.0, 0.0, 0.0, 0.16);     // x=wetness, y=rain, z=snow_cover, w=mist
uniform vec4 u_weather_fx = vec4(0.0, 0.0, 0.0, 0.0);          // x=wind_time, y=lightning_flash, z=moon_energy, w=is_underground
uniform vec4 u_fog_color = vec4(0.45, 0.54, 0.66, 1.0);
uniform vec4 u_player_light = vec4(0.5, 1.2, 0.5, 0.0);        // xyz in Godot scene coords, w = active_light
uniform vec4 u_player_light_cone = vec4(1.0, 0.0, -1.0, 0.0);  // xy = facing XZ dir, z = cone_cos (<= -0.5 omni), w = vol_beam

// Up to 12 extra dynamic 3D lights (transient muzzle flashes, blasts & upper-Z lights)
uniform int u_light_count = 0;
uniform vec4 u_light_pos_rad[12]; // xyz in Godot space, w = radius
uniform vec4 u_light_col_int[12]; // rgb, w = intensity

varying vec4 v_color;
varying vec2 v_uv;
varying vec4 v_uv_rect;
varying float v_flags;
varying float v_shade;
varying vec3 v_world;
varying vec3 v_normal;
varying vec2 v_screen;

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

vec3 filmic_tone_map(vec3 hdr) {
	vec3 x = max(hdr, vec3(0.0));
	vec3 aces = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
	float luma = dot(x, vec3(0.2126, 0.7152, 0.0722));
	float soft_peak = luma / (1.0 + max(0.0, luma - 0.65) * 0.68);
	vec3 preserved = x * (soft_peak / max(luma, 0.0001));
	return clamp(mix(preserved, aces, 0.42), vec3(0.0), vec3(1.0));
}

vec3 memory_keep_black(vec3 rgb, vec3 result_rgb) {
	return mix(result_rgb, rgb, step(rgb.r + rgb.g + rgb.b, 0.0));
}

vec3 memory_mixer(vec3 rgb, vec3 dark, vec3 light, float gamma) {
	float av = (rgb.r + rgb.g + rgb.b) / 3.0;
	float p = clamp(pow(max(av, 0.0), gamma) * 1.5, 0.0, 1.0);
	return memory_keep_black(rgb, mix(dark, light, p));
}

vec3 apply_memory_preset(int preset, vec3 rgb) {
	if (preset == 0) {
		return memory_keep_black(rgb, max(rgb * (85.0 / 256.0), vec3(1.0 / 255.0)));
	} else if (preset == 1) {
		return memory_mixer(rgb, vec3(39.0, 23.0, 19.0) / 255.0, vec3(241.0, 220.0, 163.0) / 255.0, 1.6);
	} else if (preset == 2) {
		return memory_mixer(rgb, vec3(39.0, 23.0, 19.0) / 255.0, vec3(70.0, 66.0, 60.0) / 255.0, 1.0);
	}
	return memory_mixer(rgb, vec3(19.0, 23.0, 39.0) / 255.0, vec3(60.0, 66.0, 70.0) / 255.0, 1.0);
}

vec3 nightvision_green(float result) {
	return vec3(result * 0.25, result, result * 0.125);
}

void vertex() {
	vec3 inst_pos = MODEL_MATRIX[3].xyz;
	vec3 inst_scale = vec3(MODEL_MATRIX[0].x, MODEL_MATRIX[1].y, MODEL_MATRIX[2].z);
	float inst_flags = MODEL_MATRIX[0].y;
	float inst_pad = MODEL_MATRIX[0].z;
	int iflags = int(inst_flags + 0.5);

	vec3 world;
	vec2 uv_local;
	vec3 surf_n = vec3(0.0, 1.0, 0.0);
	float shade;
	vec3 light_dir = u_sun_dir.w > 0.5 ? normalize(u_sun_dir.xyz) : normalize(vec3(0.4, 0.85, 0.3));

	if (u_mode == 2 || u_mode == 3) {
		vec3 rgt = normalize(vec3(u_cam_right.x, 0.0, u_cam_right.z));
		if (u_mode == 3) {
			if (abs(rgt.x) >= abs(rgt.z)) {
				rgt = vec3(sign(rgt.x), 0.0, 0.0);
			} else {
				rgt = vec3(0.0, 0.0, sign(rgt.z));
			}
		}
		vec3 hf = normalize(vec3(u_cam_fwd.x, 0.0, u_cam_fwd.z));
		world = inst_pos - hf * inst_scale.z
			+ rgt * (VERTEX.x * inst_scale.x)
			+ vec3(0.0, VERTEX.y * inst_scale.y, 0.0);
		uv_local = UV;
		surf_n = normalize(vec3(-hf.x * 0.45, 0.88, -hf.z * 0.45));
		shade = 0.94;
	} else if (u_mode == 4) {
		vec3 axis = inst_pad > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		world = inst_pos + axis * (VERTEX.x * inst_scale.x) + vec3(0.0, VERTEX.y * inst_scale.y, 0.0);
		uv_local = UV;
		surf_n = inst_pad > 0.5 ? vec3(1.0, 0.25, 0.0) : vec3(0.0, 0.25, 1.0);
		shade = 0.92;
	} else if (u_mode == 5) {
		world = inst_pos + vec3(VERTEX.x * inst_scale.x, 0.0, VERTEX.z * inst_scale.y);
		int rota = (iflags >> 2) & 3;
		vec2 q = VERTEX.xz;
		if (rota == 1) {
			q = vec2(q.y, 1.0 - q.x);
		} else if (rota == 2) {
			q = vec2(1.0 - q.x, 1.0 - q.y);
		} else if (rota == 3) {
			q = vec2(1.0 - q.y, q.x);
		}
		uv_local = q;
		surf_n = vec3(0.0, 1.0, 0.0);
		shade = 0.56 + 0.44 * max(light_dir.y, 0.0);
	} else if (u_mode == 1) {
		world = inst_pos + vec3(VERTEX.x * inst_scale.x, VERTEX.y * inst_scale.z, VERTEX.z * inst_scale.y);
		uv_local = UV;
		surf_n = vec3(0.0, 0.85, 0.0);
		shade = 0.92;
	} else {
		world = inst_pos + vec3(VERTEX.x * inst_scale.x, VERTEX.y * inst_scale.z, VERTEX.z * inst_scale.y);
		vec3 n = NORMAL;
		surf_n = n;
		int rota = (iflags >> 2) & 3;
		if (abs(n.y) > 0.5) {
			vec2 q = VERTEX.xz;
			if (rota == 1) {
				q = vec2(q.y, 1.0 - q.x);
			} else if (rota == 2) {
				q = vec2(1.0 - q.x, 1.0 - q.y);
			} else if (rota == 3) {
				q = vec2(1.0 - q.y, q.x);
			}
			uv_local = q;
		} else {
			float su = (abs(n.z) > 0.5) ? VERTEX.x : VERTEX.z;
			float sv = 1.0 - VERTEX.y;
			uv_local = vec2(su, sv);
		}
		float diff = max(dot(n, light_dir), 0.0);
		shade = 0.52 + 0.48 * diff;
	}

	v_world = world;
	v_normal = normalize(surf_n);
	vec4 view_pos = VIEW_MATRIX * vec4(world, 1.0);
	VERTEX = view_pos.xyz;
	vec4 clip = PROJECTION_MATRIX * view_pos;
	vec2 ndc = clip.xy / max(abs(clip.w), 1e-5);
	v_screen = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);

	v_color = COLOR;
	v_uv_rect = INSTANCE_CUSTOM;
	v_uv = mix(INSTANCE_CUSTOM.xy, INSTANCE_CUSTOM.zw, uv_local);
	v_flags = inst_flags;
	v_shade = shade;
}

void fragment() {
	int flags = int(v_flags + 0.5);
	bool same_level_wall = (flags & 1024) != 0;
	bool mask_candidate = (u_mask_params.w > 0.5) && !same_level_wall && (v_world.y > u_mask_params.z + 0.15);

	float hash = 0.0;
	if (same_level_wall || mask_candidate || (flags & (32 | 128)) != 0) {
		hash = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	}

	// Same-level wall cutaway (z toggle)
	if (same_level_wall && u_effect_params.w > 0.5) {
		float wall_h = clamp((v_world.y - u_mask_params.z) * u_effect_params.z, 0.0, 1.0);
		if (wall_h >= 0.5) {
			discard;
		}
		float hide = smoothstep(0.333333, 0.5, wall_h);
		if (hash < hide) {
			discard;
		}
	}

	// Camera -> Player screen-door elliptical occlusion mask
	bool player_mask_eligible = (u_mask_params.w > 0.5) && (v_world.y > u_mask_params.z + 0.15)
		&& !(same_level_wall && u_effect_params.w > 0.5);
	if (player_mask_eligible) {
		vec3 pa = v_world - u_eye_pos;
		vec3 ba = u_player_pos - u_eye_pos;
		float t_raw = dot(pa, ba) / max(dot(ba, ba), 1e-6);
		float t = clamp(t_raw, 0.0, 1.0);
		vec3 off = pa - ba * t;
		float er = dot(off, u_cam_right) / u_mask_params.x;
		float eu = dot(off, u_cam_up) / u_mask_params.y;
		float de = sqrt(er * er + eu * eu);
		float hide = (1.0 - smoothstep(1.0, 1.5, de)) * (1.0 - smoothstep(0.9, 1.1, t_raw));
		if (hide > 0.001) {
			float h2 = (hash > 0.0) ? hash : fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
			if (h2 < hide) {
				discard;
			}
		}
	}

	// Cursor-centered peek hole (Z toggle)
	if (u_cursor_params.z > 0.5 && player_mask_eligible) {
		vec2 cursor_delta = (v_screen - u_cursor_params.xy) / u_effect_params.xy;
		float hide = 1.0 - smoothstep(1.0, 1.5, length(cursor_delta));
		if (hide > 0.001) {
			float h3 = (hash > 0.0) ? hash : fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
			if (h3 < hide) {
				discard;
			}
		}
	}

	// Ghost roof (bit5 = 32): dithered 50% translucent roof above visible indoor columns
	if ((flags & 32) != 0 && hash > 0.5) {
		discard;
	}

	bool textured = (flags & 1) != 0;
	bool no_discard = (flags & 2) != 0;
	int rel_flags = flags & (2048 | 4096 | 8192);
	vec4 sampled = vec4(1.0);
	bool drew_outline = false;
	vec3 out_rgb = vec3(1.0);

	if (textured) {
		sampled = texture(atlas_tex, v_uv);
		if (!no_discard && sampled.a < 0.1) {
			if (rel_flags != 0) {
				vec2 tsz = vec2(textureSize(atlas_tex, 0));
				vec2 step_uv = 1.0 / max(tsz, vec2(1.0));
				vec2 uv_min = min(v_uv_rect.xy, v_uv_rect.zw);
				vec2 uv_max = max(v_uv_rect.xy, v_uv_rect.zw);
				float nb = 0.0;
				nb = max(nb, texture(atlas_tex, clamp(v_uv + vec2(step_uv.x, 0.0), uv_min, uv_max)).a);
				nb = max(nb, texture(atlas_tex, clamp(v_uv - vec2(step_uv.x, 0.0), uv_min, uv_max)).a);
				nb = max(nb, texture(atlas_tex, clamp(v_uv + vec2(0.0, step_uv.y), uv_min, uv_max)).a);
				nb = max(nb, texture(atlas_tex, clamp(v_uv - vec2(0.0, step_uv.y), uv_min, uv_max)).a);
				if (nb >= 0.15) {
					out_rgb = vec3(1.0, 0.85, 0.05);
					if ((flags & 2048) != 0) {
						out_rgb = vec3(1.0, 0.10, 0.10);
					} else if ((flags & 8192) != 0) {
						out_rgb = vec3(0.10, 1.0, 0.22);
					}
					drew_outline = true;
				}
			}
			if (!drew_outline) {
				discard;
			}
		} else if ((flags & 128) != 0 && sampled.a < 0.9 && hash > sampled.a) {
			discard;
		}
	}

	if (!drew_outline) {
		vec3 raw = textured ? sampled.rgb : v_color.rgb;
		if ((flags & 64) != 0) {
			// Map memory preset + subtle 3D distance fog
			vec3 mem = apply_memory_preset(u_memory_preset, raw);
			float mdist = length(v_world - u_eye_pos);
			float mfog = clamp((mdist - 18.0) * (0.015 + u_weather_params.w * 0.032), 0.0, 0.72);
			out_rgb = mix(mem, u_fog_color.rgb * 0.35, mfog);
		} else if (u_nv_params.x > 0.5) {
			float light = clamp(v_color.a, 0.0, 1.0);
			float av = (raw.r + raw.g + raw.b) / 3.0;
			float night = min(av * (av * 0.75 + 64.0 / 255.0) + 16.0 / 255.0, 1.0);
			float over = min(64.0 / 255.0 + av * (av * 0.25 + 192.0 / 255.0), 1.0);
			vec3 dim = nightvision_green(night * mix(u_nv_params.y, 1.0, light));
			vec3 nv = mix(dim, nightvision_green(over), smoothstep(u_nv_params.z, 1.0, light));
			out_rgb = nv * v_shade;
		} else {
			// ---- REAL-TIME 3D PBR LIGHTING, SHADOWS, COLORED GI & WEATHER ----
			vec3 n = normalize(v_normal);
			vec3 sun_col = u_sun_col_energy.rgb;
			float sun_energy = u_sun_col_energy.w;
			vec3 sky_col = u_sky_col_energy.rgb;
			float sky_energy = u_sky_col_energy.w;
			float wetness = u_weather_params.x;
			float snow_cov = u_weather_params.z;
			float mist_lvl = u_weather_params.w;
			float wind_t = u_weather_fx.x;
			float lightning_flash = u_weather_fx.y;
			float moon_energy = u_weather_fx.z;
			bool is_under = u_weather_fx.w > 0.5;
			vec3 sun_g = u_sun_dir.w > 0.5 ? normalize(u_sun_dir.xyz) : normalize(vec3(0.4, 0.85, 0.3));
			vec3 view_dir = normalize(u_eye_pos - v_world);

			vec2 world_xy = vec2(v_world.x + u_center_xy.x, v_world.z + u_center_xy.y);
			bool is_vert_face = (u_mode == 0 && abs(n.y) < 0.5);
			bool is_horiz_top = (n.y > 0.65);
			bool is_creature_or_char = (u_mode == 2 && (rel_flags != 0 || length(v_world.xz - u_player_pos.xz) < 0.65));

			// Vertical 3D wall faces sample slightly outward along face normal so exterior sunlit faces,
			// indoor doorway sunbeams, and shadowed interior faces each receive distinct true light!
			vec2 sample_xy = is_vert_face ? (world_xy + n.xz * 0.28) : world_xy;
			vec2 luv = (sample_xy - u_light_min) / max(u_light_span, vec2(1.0));
			bool in_lmap = u_has_lightmap && (v_world.y > -1.0 && v_world.y < 3.2) &&
				luv.x > 0.005 && luv.x < 0.995 && luv.y > 0.005 && luv.y < 0.995;

			bool indoors = false;
			bool is_rooftop = (u_mode == 0 && n.y > 0.5 && v_world.y >= 2.15);
			int mat_id = 6;
			vec3 direct_light = vec3(0.0);
			vec3 gi_light = vec3(0.0);
			float sun_vis = 0.0;
			float ao = 1.0;

			if (in_lmap) {
				ivec2 gsz = ivec2(u_grid_size);
				ivec2 own = clamp(ivec2(floor(world_xy - u_grid_origin)), ivec2(0), gsz - ivec2(1));
				vec4 geom = texelFetch(u_geom_tex, own, 0);
				vec4 mat_info = texelFetch(u_mat_tex, own, 0);
				indoors = (int(round(geom.a * 3.0)) & 1) != 0;
				mat_id = int(round(mat_info.a * 7.0));

				if (is_rooftop && !is_under) {
					// Roof surfaces sit above the indoor ceiling and receive open sky, sun, rain & snow!
					indoors = false;
					float r_ndl = 0.45 + 0.55 * max(sun_g.y, 0.08);
					direct_light = sun_col * (sun_energy * r_ndl * 0.92) + vec3(0.45, 0.56, 0.78) * (moon_energy * 0.40);
					gi_light = sky_col * (sky_energy * 0.36);
					sun_vis = (sun_energy > 0.02) ? 1.0 : 0.0;
					ao = 1.0;
				} else {
					vec4 ds = texture(u_direct_tex, luv);
					vec4 gs = texture(u_gi_tex, luv);
					direct_light = ds.rgb * 2.0;
					sun_vis = ds.a;
					gi_light = gs.rgb * 2.0;
					ao = is_creature_or_char ? mix(1.0, gs.a, 0.35) : gs.a;

					// 3D directional face shading & vertical gradient on walls (crisp sunlit top vs grounded base AO!)
					float face_ndl = is_vert_face ? (0.48 + 0.52 * max(dot(n, sun_g), 0.0)) : (0.78 + 0.22 * max(dot(n, sun_g), 0.0));
					direct_light *= mix(1.0, face_ndl, clamp(sun_vis * 0.85 + 0.25, 0.0, 1.0));
					if (is_vert_face) {
						float h_norm = clamp(v_world.y / 2.55, 0.0, 1.0);
						// Grounded contact AO at floor-wall seam + subtle brighter roofline catch
						ao *= mix(0.72, 1.04, smoothstep(0.0, 0.42, h_norm));
						if (!indoors && !is_under) {
							// Exterior upper wall catches direct sun/sky cleanly even when base is shaded
							float upper_sun = max(dot(n, sun_g), 0.0) * sun_energy * sun_vis * smoothstep(0.25, 0.85, h_norm) * 0.18;
							direct_light += sun_col * upper_sun;
						}
					}
				}
			} else {
				// Upper Z-levels (2nd+ floors, distant roofs) or outside lightmap bounds: physical sky + sun!
				float ndl = max(dot(n, sun_g), 0.0);
				if (!is_under) {
					direct_light = sun_col * (sun_energy * ndl * 0.92) + vec3(0.45, 0.56, 0.78) * (moon_energy * (0.4 + 0.6 * ndl) * 0.45);
					gi_light = sky_col * (sky_energy * (0.28 + 0.20 * max(n.y, 0.0)));
					sun_vis = (sun_energy > 0.02 && ndl > 0.05) ? 1.0 : 0.0;
				}
				direct_light *= v_color.rgb;
				gi_light *= v_color.rgb;
			}

			// Player's active portable flashlight / torch in 3D space (with focused directional cone & Tyndall mist sheen!)
			if (u_player_light.w > 0.6) {
				vec3 to_p = u_player_light.xyz - v_world;
				float dp = length(to_p);
				float prad = clamp(u_player_light.w * 0.78 + 3.4, 4.5, 16.0);
				if (dp < prad) {
					vec2 out_xz = v_world.xz - u_player_light.xz;
					float d_xz = length(out_xz);
					float spot = 1.0;
					float vol_h = 0.0;
					if (u_player_light_cone.z > -0.5 && d_xz > 0.01) {
						float calign = dot(out_xz / d_xz, u_player_light_cone.xy);
						float cone = smoothstep(u_player_light_cone.z - 0.20, u_player_light_cone.z + 0.08, calign);
						spot = max(cone, 0.26 * exp(-d_xz * 0.62));
						vol_h = cone * (1.0 - smoothstep(0.6, prad * 0.9, d_xz)) * u_player_light_cone.w;
					}
					float att = 1.0 - smoothstep(prad * 0.25, prad, dp);
					float pndl = 0.45 + 0.55 * max(dot(n, to_p / max(dp, 0.001)), 0.0);
					vec3 pcol = (u_player_light.w >= 12.0) ? vec3(0.95, 0.97, 1.0) : vec3(1.0, 0.74, 0.38);
					direct_light += pcol * (att * att * pndl * spot * clamp(u_player_light.w * 0.085 + 0.48, 0.48, 1.75) + vol_h * 0.14);
				}
			}

			// Extra transient 3D point lights (muzzle flashes, fireballs, explosions!)
			for (int i = 0; i < 12; i++) {
				if (i >= u_light_count) {
					break;
				}
				vec3 lp = u_light_pos_rad[i].xyz;
				float rad = max(u_light_pos_rad[i].w, 0.5);
				vec3 to_l = lp - v_world;
				float d = length(to_l);
				if (d < rad) {
					float att = 1.0 - (d / rad);
					float lndl = 0.5 + 0.5 * max(dot(n, to_l / max(d, 0.001)), 0.0);
					direct_light += u_light_col_int[i].rgb * (att * att * lndl * u_light_col_int[i].w * 0.85);
				}
			}

			// Thunderstorm lightning illumination outdoors
			if (lightning_flash > 0.01 && !indoors && !is_under) {
				direct_light += vec3(0.76, 0.86, 1.0) * (lightning_flash * (0.55 + 0.45 * max(n.y, 0.2)));
			}

			// Natural ambient floor (matches 2D dusk/night/indoor/underground mood cleanly!)
			float sky_day = clamp(sky_energy, 0.0, 1.0);
			vec3 base_ambient;
			if (is_under) {
				base_ambient = vec3(0.070, 0.075, 0.088);
			} else if (indoors) {
				base_ambient = mix(vec3(0.075, 0.082, 0.100), vec3(0.218, 0.211, 0.207), sky_day);
			} else {
				base_ambient = mix(vec3(0.055, 0.078, 0.138), sky_col * 0.14, sky_day);
			}

			float gi_gain = is_vert_face ? 0.75 : (indoors ? 1.21 : 0.90);
			vec3 incident = (base_ambient + gi_light * gi_gain) * ao + direct_light;
			if (is_creature_or_char) {
				incident = max(incident, vec3(0.24, 0.26, 0.31));
			}

			vec3 lit = raw * incident;

			// Per-material 3D PBR highlights (wood sheen, metal specular, glass reflection, water caustics)
			vec3 half_sun = normalize(sun_g + view_dir);
			float ndh = max(dot(n, half_sun), 0.0);
			if (!is_creature_or_char) {
				if (mat_id == 2) {
					float spec_m = pow(ndh, 28.0) * sun_vis * sun_energy * 0.55;
					lit += sun_col * spec_m + sky_col * (sky_energy * 0.08 * (1.0 - max(dot(n, view_dir), 0.0)));
				} else if (mat_id == 3) {
					float fres = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);
					lit += sun_col * (pow(ndh, 48.0) * sun_vis * sun_energy * 0.42) + sky_col * (fres * (0.06 + 0.24 * sky_energy));
				} else if (mat_id == 4 && is_horiz_top) {
					float blue_lead = (raw.b - raw.r) + 0.35 * (raw.g - raw.r);
					float water_mask = smoothstep(0.015, 0.14, blue_lead) * smoothstep(0.04, 0.18, raw.b + raw.g);
					if (water_mask > 0.01) {
						float w1 = smooth_noise2(world_xy * 3.2 + vec2(wind_t * 0.65, -wind_t * 0.42));
						float w2 = smooth_noise2(world_xy * 6.4 + vec2(-wind_t * 0.48, wind_t * 0.72));
						float caustic = smoothstep(0.56, 0.92, (w1 + w2) * 0.5);
						vec3 water_sky = mix(vec3(0.14, 0.24, 0.44) * max(moon_energy, 0.22), sky_col * (0.42 + 0.36 * sky_energy), sky_day);
						lit = mix(lit, water_sky * 0.55 + lit * 0.68, 0.24 * water_mask) + (sun_col * sun_vis * sun_energy + gi_light * 0.32) * caustic * (0.20 * water_mask);
					}
				}
			}

			// ---- WEATHER SURFACE EFFECTS (WET RAIN PUDDLES + RIPPLES + SNOW FROST!) ----
			if (!indoors && !is_under && !is_creature_or_char) {
				// Wetness & rain puddles + ripples on outdoor horizontal ground/roofs
				if (wetness > 0.04 && is_horiz_top) {
					float p1 = smooth_noise2(world_xy * 0.78);
					float p2 = smooth_noise2(world_xy * 2.15 + vec2(11.3, 7.1));
					float puddle = smoothstep(0.32, 0.72, p1 * 0.64 + p2 * 0.36) * wetness;
					// Expanding raindrop ripples on puddles when actively raining
					float ripple = 0.0;
					if (u_weather_params.y > 0.08) {
						vec2 rcell = floor(world_xy * 2.5);
						vec2 rfrac = fract(world_xy * 2.5) - 0.5;
						float phase = fract(wind_t * 1.45 + hash21(rcell));
						float ring = abs(length(rfrac) - phase * 0.44);
						ripple = smoothstep(0.055, 0.0, ring) * (1.0 - phase) * u_weather_params.y * 0.28;
					}
					float fres = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);
					vec3 wet_sky = mix(vec3(0.14, 0.19, 0.28), sky_col * (0.42 + 0.48 * sky_energy), sky_day);
					vec3 wet_refl = mix(wet_sky, direct_light + gi_light * 0.8, 0.38);
					float wet_spec = pow(ndh, 24.0) * (sun_vis * sun_energy * 0.45 + lightning_flash * 0.8) * puddle;
					lit = mix(lit, lit * 0.74 + wet_refl * (0.34 + 0.36 * fres + ripple), puddle * 0.62) + sun_col * wet_spec;
				}
				// Winter / snowfall frost & snow accumulation on outdoor horizontal surfaces & trees
				if (snow_cov > 0.05 && (is_horiz_top || u_mode == 1)) {
					float sn = smooth_noise2(world_xy * 1.65 + vec2(4.2, -3.7));
					float s_amt = clamp((snow_cov * 0.78 + sn * 0.32 - 0.25) * (is_horiz_top ? 0.72 : 0.42), 0.0, 0.78);
					vec3 snow_lit = vec3(0.84, 0.90, 0.98) * (incident + vec3(0.06, 0.08, 0.12));
					lit = mix(lit, snow_lit, s_amt);
				}
			}

			// Volumetric doorway bounce bloom & ACES filmic tone mapping
			lit += gi_light * (is_vert_face ? 0.03 : (indoors ? 0.14 : 0.04));
			if (is_vert_face) {
				float peak = max(lit.r, max(lit.g, lit.b));
				lit /= 1.0 + max(0.0, peak - 0.26) * 0.70;
			}
			out_rgb = filmic_tone_map(lit);

			// ---- REAL 3D ATMOSPHERIC DISTANCE FOG / MIST ----
			if (!is_under && mist_lvl > 0.02) {
				float dist = length(v_world - u_eye_pos);
				float fog_start = mix(22.0, 9.0, clamp(mist_lvl, 0.0, 1.0));
				float fog_density = mix(0.008, 0.048, clamp(mist_lvl, 0.0, 1.0));
				float height_f = exp(-max(v_world.y, 0.0) * 0.12);
				float fog_amt = clamp(1.0 - exp(-max(0.0, dist - fog_start) * fog_density * height_f), 0.0, 0.82);
				// Indoor foreground stays clear of exterior fog
				if (indoors && dist < 16.0) {
					fog_amt *= 0.25;
				}
				vec3 fcol = u_fog_color.rgb + vec3(0.55, 0.65, 0.82) * (lightning_flash * 0.45);
				out_rgb = mix(out_rgb, fcol, fog_amt);
			}
		}
	}
	ALBEDO = out_rgb;
}
