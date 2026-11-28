shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_draw_never;

// Decal-pass variant (depth WRITE off, depth TEST on) with full world-space PBR shadows, GI, wet puddles,
// snow frost & 3D atmospheric fog matching ccb_terrain3d.gdshader!

uniform sampler2D atlas_tex : source_color, filter_nearest, repeat_disable;
uniform int u_mode = 5;
uniform vec3 u_cam_right = vec3(1.0, 0.0, 0.0);
uniform vec3 u_cam_up = vec3(0.0, 1.0, 0.0);
uniform vec3 u_cam_fwd = vec3(0.0, 0.0, -1.0);
uniform vec4 u_sun_dir = vec4(0.4, 0.85, 0.3, 1.0);

uniform vec3 u_eye_pos = vec3(0.0, 10.0, 10.0);
uniform vec3 u_player_pos = vec3(0.5, 1.0, 0.5);
uniform vec4 u_mask_params = vec4(3.2, 2.2, 0.0, 0.0);
uniform vec4 u_cursor_params = vec4(-1.0, -1.0, 0.0, 0.0);
uniform vec4 u_effect_params = vec4(0.075, 0.10, 0.39215686, 0.0);
uniform int u_memory_preset = 0;
uniform vec4 u_nv_params = vec4(0.0, 0.55, 0.85, 0.0);

uniform bool u_has_lightmap = false;
uniform sampler2D u_direct_tex : filter_linear, repeat_disable;
uniform sampler2D u_gi_tex : filter_linear, repeat_disable;
uniform sampler2D u_geom_tex : filter_nearest, repeat_disable;
uniform sampler2D u_mat_tex : filter_nearest, repeat_disable;
uniform vec2 u_center_xy = vec2(0.0, 0.0);
uniform vec2 u_light_min = vec2(0.0, 0.0);
uniform vec2 u_light_span = vec2(44.0, 36.0);
uniform vec2 u_grid_origin = vec2(0.0, 0.0);
uniform vec2 u_grid_size = vec2(61.0, 41.0);

uniform vec4 u_sun_col_energy = vec4(1.0, 0.94, 0.84, 0.85);
uniform vec4 u_sky_col_energy = vec4(0.74, 0.86, 1.0, 0.75);
uniform vec4 u_weather_params = vec4(0.0, 0.0, 0.0, 0.16);
uniform vec4 u_weather_fx = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 u_fog_color = vec4(0.45, 0.54, 0.66, 1.0);
uniform vec4 u_player_light = vec4(0.5, 1.2, 0.5, 0.0);

uniform int u_light_count = 0;
uniform vec4 u_light_pos_rad[12];
uniform vec4 u_light_col_int[12];

varying vec4 v_color;
varying vec2 v_uv;
varying float v_flags;
varying float v_shade;
varying vec3 v_world;
varying vec2 v_screen;

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
	float shade;

	if (u_mode == 4) {
		vec3 axis = inst_pad > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		world = inst_pos + axis * (VERTEX.x * inst_scale.x) + vec3(0.0, VERTEX.y * inst_scale.y, 0.0);
		uv_local = UV;
		shade = 0.94;
	} else {
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
		vec3 light_dir = u_sun_dir.w > 0.5 ? normalize(u_sun_dir.xyz) : normalize(vec3(0.4, 0.85, 0.3));
		shade = 0.56 + 0.44 * max(light_dir.y, 0.0);
	}

	v_world = world;
	vec4 view_pos = VIEW_MATRIX * vec4(world, 1.0);
	VERTEX = view_pos.xyz;
	vec4 clip = PROJECTION_MATRIX * view_pos;
	vec2 ndc = clip.xy / max(abs(clip.w), 1e-5);
	v_screen = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);

	v_color = COLOR;
	v_uv = mix(INSTANCE_CUSTOM.xy, INSTANCE_CUSTOM.zw, uv_local);
	v_flags = inst_flags;
	v_shade = shade;
}

void fragment() {
	int flags = int(v_flags + 0.5);
	float hash = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);

	if (u_mask_params.w > 0.5 && v_world.y > u_mask_params.z + 0.15) {
		vec3 pa = v_world - u_eye_pos;
		vec3 ba = u_player_pos - u_eye_pos;
		float t_raw = dot(pa, ba) / max(dot(ba, ba), 1e-6);
		float t = clamp(t_raw, 0.0, 1.0);
		vec3 off = pa - ba * t;
		float er = dot(off, u_cam_right) / u_mask_params.x;
		float eu = dot(off, u_cam_up) / u_mask_params.y;
		float de = sqrt(er * er + eu * eu);
		float hide = (1.0 - smoothstep(1.0, 1.5, de)) * (1.0 - smoothstep(0.9, 1.1, t_raw));
		if (hash < hide) {
			discard;
		}
		if (u_cursor_params.z > 0.5) {
			vec2 cursor_delta = (v_screen - u_cursor_params.xy) / u_effect_params.xy;
			float chide = 1.0 - smoothstep(1.0, 1.5, length(cursor_delta));
			if (hash < chide) {
				discard;
			}
		}
	}

	if ((flags & 32) != 0 && hash > 0.5) {
		discard;
	}

	vec4 sampled = vec4(1.0);
	if ((flags & 1) != 0) {
		sampled = texture(atlas_tex, v_uv);
		if (sampled.a < 0.1) {
			discard;
		}
		if ((flags & 128) != 0 && sampled.a < 0.9 && hash > sampled.a) {
			discard;
		}
	}

	vec3 raw = ((flags & 1) != 0) ? sampled.rgb : v_color.rgb;
	vec3 out_rgb = raw;
	if ((flags & 64) != 0) {
		out_rgb = apply_memory_preset(u_memory_preset, raw);
	} else if (u_nv_params.x > 0.5) {
		float light = clamp(v_color.a, 0.0, 1.0);
		float av = (raw.r + raw.g + raw.b) / 3.0;
		float night = min(av * (av * 0.75 + 64.0 / 255.0) + 16.0 / 255.0, 1.0);
		float over = min(64.0 / 255.0 + av * (av * 0.25 + 192.0 / 255.0), 1.0);
		vec3 dim = nightvision_green(night * mix(u_nv_params.y, 1.0, light));
		vec3 nv = mix(dim, nightvision_green(over), smoothstep(u_nv_params.z, 1.0, light));
		out_rgb = nv * v_shade;
	} else {
		vec3 sky_col = u_sky_col_energy.rgb;
		float sky_energy = u_sky_col_energy.w;
		float mist_lvl = u_weather_params.w;
		float lightning_flash = u_weather_fx.y;
		bool is_under = u_weather_fx.w > 0.5;
		vec2 world_xy = vec2(v_world.x + u_center_xy.x, v_world.z + u_center_xy.y);
		vec2 luv = (world_xy - u_light_min) / max(u_light_span, vec2(1.0));
		bool in_lmap = u_has_lightmap && luv.x > 0.005 && luv.x < 0.995 && luv.y > 0.005 && luv.y < 0.995;

		bool indoors = false;
		vec3 direct_light = vec3(0.0);
		vec3 gi_light = vec3(0.0);
		float ao = 1.0;
		if (in_lmap) {
			ivec2 gsz = ivec2(u_grid_size);
			ivec2 own = clamp(ivec2(floor(world_xy - u_grid_origin)), ivec2(0), gsz - ivec2(1));
			vec4 geom = texelFetch(u_geom_tex, own, 0);
			indoors = (int(round(geom.a * 3.0)) & 1) != 0;
			vec4 ds = texture(u_direct_tex, luv);
			vec4 gs = texture(u_gi_tex, luv);
			direct_light = ds.rgb * 2.0;
			gi_light = gs.rgb * 2.0;
			ao = gs.a;
		} else {
			direct_light = v_color.rgb * v_shade;
		}

		if (u_player_light.w > 0.6) {
			float dp = length(u_player_light.xyz - v_world);
			float prad = clamp(u_player_light.w * 0.75 + 3.0, 4.0, 14.0);
			if (dp < prad) {
				float att = 1.0 - smoothstep(prad * 0.25, prad, dp);
				vec3 pcol = (u_player_light.w >= 18.0) ? vec3(0.95, 0.97, 1.0) : vec3(1.0, 0.74, 0.38);
				direct_light += pcol * (att * att * clamp(u_player_light.w * 0.08 + 0.45, 0.45, 1.65));
			}
		}
		for (int i = 0; i < 12; i++) {
			if (i >= u_light_count) {
				break;
			}
			vec3 lp = u_light_pos_rad[i].xyz;
			float rad = max(u_light_pos_rad[i].w, 0.5);
			float d = length(v_world - lp);
			if (d < rad) {
				float att = 1.0 - (d / rad);
				direct_light += u_light_col_int[i].rgb * (att * att * u_light_col_int[i].w * 0.85);
			}
		}
		if (lightning_flash > 0.01 && !indoors && !is_under) {
			direct_light += vec3(0.76, 0.86, 1.0) * lightning_flash;
		}

		float sky_day = clamp(sky_energy, 0.0, 1.0);
		vec3 base_ambient = is_under ? vec3(0.06, 0.068, 0.088) : (indoors ? mix(vec3(0.055, 0.064, 0.090), vec3(0.155, 0.152, 0.158), sky_day) : mix(vec3(0.055, 0.078, 0.138), sky_col * 0.14, sky_day));
		vec3 lit = raw * ((base_ambient + gi_light) * ao + direct_light) + gi_light * 0.06;
		out_rgb = filmic_tone_map(lit);

		if (!is_under && mist_lvl > 0.02) {
			float dist = length(v_world - u_eye_pos);
			float fog_start = mix(22.0, 9.0, clamp(mist_lvl, 0.0, 1.0));
			float fog_density = mix(0.008, 0.048, clamp(mist_lvl, 0.0, 1.0));
			float fog_amt = clamp(1.0 - exp(-max(0.0, dist - fog_start) * fog_density), 0.0, 0.82);
			if (indoors && dist < 16.0) {
				fog_amt *= 0.25;
			}
			out_rgb = mix(out_rgb, u_fog_color.rgb, fog_amt);
		}
	}
	ALBEDO = out_rgb;
}
