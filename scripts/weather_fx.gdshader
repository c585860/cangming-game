shader_type canvas_item;
render_mode unshaded, blend_mix;

// Pure GPU pixel-art harmonized Jiangnan rain streaks, ground impact ticks,
// and drifting parallax snow flecks — 0.0 ms CPU per frame!

uniform float rain = 0.0;
uniform float snow = 0.0;
uniform float daylight = 1.0;
uniform vec2 view_world = vec2(0.0);
uniform vec2 view_span = vec2(32.0, 20.0);
uniform vec2 viewport_px = vec2(1280.0, 720.0);
uniform sampler2D interior_mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin = vec2(0.0);
uniform vec2 mask_size = vec2(1.0, 1.0);
uniform bool has_interior_mask = false;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float rain_layer(vec2 px, float layer_id, float speed, float density, float slant_x, float len_px) {
	// Transform pixel coords into slanted streak space so each drop is a crisp 1px line.
	vec2 p = px;
	p.x += p.y * slant_x;
	p.y -= TIME * speed;
	vec2 cell_size = vec2(26.0 / density, 62.0 / density);
	vec2 id = floor(p / cell_size);
	vec2 local = mod(p, cell_size);
	vec2 h = hash22(id + vec2(layer_id * 37.3, layer_id * 91.7));
	if (h.x > clamp(0.18 + 0.56 * rain * density, 0.0, 0.85)) {
		return 0.0;
	}
	float drop_x = floor(h.y * (cell_size.x - 2.0)) + 1.0;
	float drop_y0 = floor(fract(h.x * 19.7) * max(1.0, cell_size.y - len_px - 2.0));
	float dx = abs(local.x - drop_x);
	if (dx > 0.65) {
		return 0.0;
	}
	float dy = local.y - drop_y0;
	if (dy < 0.0 || dy > len_px) {
		return 0.0;
	}
	// Faint upper tail -> crisp bright lead tip.
	float along = dy / max(len_px, 1.0);
	return mix(0.32, 1.0, along * along);
}

float rain_splashes(vec2 px) {
	vec2 cell_size = vec2(44.0, 44.0);
	vec2 id = floor(px / cell_size);
	vec2 local = floor(mod(px, cell_size));
	float h = hash12(id + vec2(17.1, 83.4));
	if (h > 0.24 + 0.42 * rain) {
		return 0.0;
	}
	float rate = 2.8 + fract(h * 11.3) * 1.4;
	float t = TIME * rate + h * 17.0;
	float cycle = floor(t);
	float phase = fract(t);
	vec2 pos = floor(hash22(id + vec2(cycle * 7.3, cycle * 13.7)) * (cell_size - vec2(8.0))) + vec2(4.0);
	float spread = floor(1.0 + phase * 2.5);
	vec2 d = local - pos;
	bool hit = (abs(d.y) < 0.5 && abs(abs(d.x) - spread) < 0.5)
		|| (phase < 0.42 && abs(d.x) < 0.5 && abs(d.y + 1.0) < 0.5);
	return hit ? (1.0 - phase) * (0.20 + 0.16 * rain) : 0.0;
}

float snow_layer(vec2 px, float layer_id, float fall_speed, float drift_speed, float cell_px, float flake_px, float density) {
	vec2 p = px;
	float row_id = floor((p.y - TIME * fall_speed) / cell_px);
	float sway = sin(TIME * (0.85 + 0.35 * layer_id) + row_id * 1.7 + layer_id * 5.2) * (6.0 + 4.0 * layer_id);
	p.x += TIME * drift_speed - sway;
	p.y -= TIME * fall_speed;
	vec2 id = floor(p / cell_px);
	vec2 local = floor(mod(p, cell_px));
	vec2 h = hash22(id + vec2(layer_id * 53.1, layer_id * 119.3));
	if (h.x > clamp(0.14 + 0.48 * snow * density, 0.0, 0.78)) {
		return 0.0;
	}
	vec2 center = floor(h * max(1.0, cell_px - flake_px - 2.0)) + vec2(1.0);
	vec2 d = local - center;
	if (d.x >= 0.0 && d.x < flake_px && d.y >= 0.0 && d.y < flake_px) {
		return 1.0;
	}
	// Subtle 1px horizontal cross-glint on larger foreground flakes.
	if (flake_px > 1.5 && abs(d.y) < 0.5 && (d.x == -1.0 || d.x == flake_px)) {
		return 0.32;
	}
	return 0.0;
}

void fragment() {
	if (rain <= 0.01 && snow <= 0.01) {
		discard;
	}
	vec2 world_pos = view_world + UV * view_span;
	if (has_interior_mask) {
		vec2 m_uv = (world_pos - mask_origin) / mask_size;
		if (all(greaterThanEqual(m_uv, vec2(0.0))) && all(lessThan(m_uv, vec2(1.0)))) {
			if (texture(interior_mask, m_uv).r > 0.5) {
				discard;
			}
		}
	}

	vec2 px = floor(UV * viewport_px);
	vec4 out_col = vec4(0.0);

	if (rain > 0.01) {
		float bright = mix(0.58, 0.94, daylight);
		float slant = 0.16 + 0.07 * rain;
		float r0 = rain_layer(px, 1.0, 560.0 + 220.0 * rain, 0.85, slant, 18.0 + 10.0 * rain) * 0.48;
		float r1 = rain_layer(px, 2.0, 740.0 + 280.0 * rain, 1.05, slant, 24.0 + 14.0 * rain) * 0.78;
		float r2 = rain_layer(px, 3.0, 920.0 + 340.0 * rain, 0.70, slant, 30.0 + 16.0 * rain) * 1.00;
		float streak = max(r0, max(r1, r2));
		float splash = rain_splashes(px);
		float a = clamp(streak * (0.11 + 0.14 * rain) + splash, 0.0, 0.42);
		vec3 col = vec3(0.84, 0.91, 0.98) * bright;
		out_col = vec4(col, a);
	}

	if (snow > 0.01) {
		float bright = mix(0.68, 1.0, daylight);
		float s0 = snow_layer(px, 1.0, 22.0 + 18.0 * snow, 10.0 + 8.0 * snow, 36.0, 1.0, 0.90) * 0.45;
		float s1 = snow_layer(px, 2.0, 36.0 + 26.0 * snow, 16.0 + 12.0 * snow, 44.0, 1.0, 1.00) * 0.72;
		float s2 = snow_layer(px, 3.0, 52.0 + 34.0 * snow, 22.0 + 16.0 * snow, 58.0, 2.0, 0.75) * 0.95;
		float flake = max(s0, max(s1, s2));
		float sa = clamp(flake * (0.42 + 0.34 * snow), 0.0, 0.84);
		vec3 scol = vec3(0.93, 0.96, 1.0) * bright;
		if (sa > out_col.a) {
			out_col = vec4(scol, sa);
		}
	}

	if (out_col.a <= 0.004) {
		discard;
	}
	COLOR = out_col;
}
