shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, skip_vertex_transform;

// Pure GPU-Driven 3D Rain & Snow Precipitation Volume (0.0 ms CPU per frame!):
// - Renders 480 camera-facing 3D rain streaks or drifting snowflakes in a 30x14x30m volume
// - Depth-tested cleanly against 3D walls, roofs & trees
// - Samples geom_tex (indoors bit) so rain & snow NEVER fall inside roofed buildings!

uniform float u_rain = 0.0;
uniform float u_snow = 0.0;
uniform float u_daylight = 1.0;
uniform float u_lightning = 0.0;
uniform float u_time = 0.0;
uniform vec2 u_wind = vec2(0.8, 0.25);
uniform vec3 u_cam_right = vec3(1.0, 0.0, 0.0);

uniform bool u_has_geom = false;
uniform sampler2D u_geom_tex : filter_nearest, repeat_disable;
uniform vec2 u_center_xy = vec2(0.0, 0.0);
uniform vec2 u_grid_origin = vec2(0.0, 0.0);
uniform vec2 u_grid_size = vec2(61.0, 41.0);

varying vec2 v_uv;
varying float v_alpha;
varying float v_is_snow;

void vertex() {
	// Per-instance deterministic seed stored in MODEL_MATRIX[3].xyz in [0, 1]^3, density gate in INSTANCE_CUSTOM.x
	vec3 seed = MODEL_MATRIX[3].xyz;
	float gate = INSTANCE_CUSTOM.x;
	float is_snow = (u_snow > u_rain) ? 1.0 : 0.0;
	float strength = max(u_rain, u_snow);

	// Hide surplus particles smoothly as precipitation intensity changes
	if (strength <= 0.02 || gate > strength) {
		VERTEX = vec3(0.0, 0.0, 10000.0);
		v_alpha = 0.0;
		v_uv = UV;
		v_is_snow = is_snow;
	} else {
		float fall_spd = mix(17.5, 2.2, is_snow) * (0.85 + 0.30 * INSTANCE_CUSTOM.y);
		float y_span = 14.0;
		float xz_span = 30.0;

		float py = mod(seed.y * y_span - u_time * fall_spd, y_span);
		float drift_t = u_time * mix(3.2, 0.9, is_snow);
		float sway_x = sin(u_time * 1.9 + seed.x * 37.0 + seed.z * 19.0) * (is_snow * 0.65);
		float sway_z = cos(u_time * 1.5 + seed.z * 41.0) * (is_snow * 0.55);
		float px = mod(seed.x * xz_span + u_wind.x * drift_t + sway_x, xz_span) - xz_span * 0.5 + 0.5;
		float pz = mod(seed.z * xz_span + u_wind.y * drift_t + sway_z, xz_span) - xz_span * 0.5 + 0.5;

		// Skip indoor roofed columns cleanly so rain/snow stays strictly outdoors!
		bool indoors = false;
		if (u_has_geom && py < 2.8) {
			vec2 wxy = vec2(px + u_center_xy.x, pz + u_center_xy.y);
			vec2 loc = wxy - u_grid_origin;
			if (loc.x >= 0.0 && loc.y >= 0.0 && loc.x < u_grid_size.x && loc.y < u_grid_size.y) {
				vec4 gm = texelFetch(u_geom_tex, ivec2(floor(loc)), 0);
				indoors = (int(round(gm.a * 3.0)) & 1) != 0;
			}
		}

		if (indoors) {
			VERTEX = vec3(0.0, 0.0, 10000.0);
			v_alpha = 0.0;
		} else {
			vec3 base = vec3(px, py, pz);
			vec3 rgt = normalize(vec3(u_cam_right.x, 0.0, u_cam_right.z));
			float w = mix(0.044, 0.155, is_snow);
			float h = mix(1.08, 0.155, is_snow);
			vec3 slant = is_snow > 0.5 ? vec3(0.0, 1.0, 0.0) : normalize(vec3(-u_wind.x * 0.22, 1.0, -u_wind.y * 0.22));
			vec3 world = base + rgt * (VERTEX.x * w) + slant * ((VERTEX.y - 0.5) * h);
			VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
			// Soft fade near ground & top ceiling
			float y_fade = smoothstep(0.0, 0.55, py) * (1.0 - smoothstep(y_span - 2.2, y_span, py));
			v_alpha = y_fade * mix(0.58, 0.86, is_snow) * clamp(0.50 + strength * 0.50, 0.0, 1.0);
		}
		v_uv = UV;
		v_is_snow = is_snow;
	}
}

void fragment() {
	if (v_alpha <= 0.005) {
		discard;
	}
	float shape = 0.0;
	if (v_is_snow > 0.5) {
		float r = length((v_uv - vec2(0.5)) * 2.0);
		shape = smoothstep(1.0, 0.15, r);
	} else {
		float cx = 1.0 - abs(v_uv.x - 0.5) * 2.0;
		float cy = smoothstep(0.0, 0.35, v_uv.y) * smoothstep(1.0, 0.15, v_uv.y);
		shape = pow(max(cx, 0.0), 1.6) * cy;
	}
	float a = shape * v_alpha;
	if (a < 0.015) {
		discard;
	}
	vec3 rain_col = mix(vec3(0.42, 0.52, 0.68), vec3(0.82, 0.90, 0.98), clamp(u_daylight, 0.0, 1.0));
	vec3 snow_col = mix(vec3(0.55, 0.64, 0.78), vec3(0.96, 0.98, 1.0), clamp(u_daylight, 0.0, 1.0));
	vec3 col = mix(rain_col, snow_col, v_is_snow) + vec3(0.65, 0.75, 0.95) * (u_lightning * 0.75);
	ALBEDO = col;
	ALPHA = a;
}
