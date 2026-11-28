shader_type sky;

// Weather- & Atmosphere-Synchronized 3D Sky Shader for CECP 2.0:
// Dawn/dusk golden-rose sunset hues, misty fog horizon, storm cloud darkening,
// calendar sun disc + halo, wind-drifting fbm clouds, thunderstorm lightning flashes & night vision.

uniform vec4 u_sun_dir = vec4(0.4, 0.85, 0.3, 1.0); // xyz in Godot (East,Up,South), w = daylight 0..1
uniform vec4 u_sky_col_mist = vec4(0.74, 0.86, 1.0, 0.16); // rgb = sky_color, w = mist
uniform vec4 u_sun_col_flash = vec4(1.0, 0.94, 0.84, 0.0); // rgb = sun_color, w = lightning_flash
uniform float u_cloudiness = 0.25;
uniform float u_nv_active = 0.0;
uniform vec2 u_wind_offset = vec2(0.0, 0.0);

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
	           mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03) * 0.3 + vnoise(p * 4.09) * 0.2;
}

vec3 nightvision_green(float result) {
	return vec3(result * 0.25, result, result * 0.125);
}

vec3 nightvision_rgb(vec3 rgb) {
	float av = (rgb.r + rgb.g + rgb.b) / 3.0;
	return nightvision_green(min(av * (av * 0.75 + 64.0 / 255.0) + 16.0 / 255.0, 1.0));
}

vec3 overexposed_rgb(vec3 rgb) {
	float av = (rgb.r + rgb.g + rgb.b) / 3.0;
	return nightvision_green(min(64.0 / 255.0 + av * (av * 0.25 + 192.0 / 255.0), 1.0));
}

void sky() {
	vec3 ray = normalize(EYEDIR);
	float daylight = clamp(u_sun_dir.w, 0.0, 1.0);
	float mist = clamp(u_sky_col_mist.w, 0.0, 1.0);
	float flash = clamp(u_sun_col_flash.w, 0.0, 1.0);

	vec3 zenith = mix(vec3(0.008, 0.012, 0.026), u_sky_col_mist.rgb * vec3(0.32, 0.52, 0.84), daylight);
	vec3 horizon = mix(vec3(0.020, 0.026, 0.044), u_sky_col_mist.rgb * vec3(0.76, 0.82, 0.90), daylight);
	horizon = mix(horizon, mix(vec3(0.06, 0.075, 0.10), vec3(0.68, 0.74, 0.80), daylight), mist * 0.72);
	vec3 col;
	if (ray.y >= 0.0) {
		col = mix(horizon, zenith, pow(ray.y, mix(0.6, 1.25, mist)));
	} else {
		vec3 voidc = mix(vec3(0.010, 0.012, 0.018), horizon * 0.45, mist * 0.65) * (0.35 + 0.65 * daylight);
		col = mix(horizon, voidc, clamp(-ray.y * 5.0, 0.0, 1.0));
	}

	// Sun disc + dawn/dusk tinted halo
	vec3 sd = u_sun_dir.xyz;
	if (sd.y > -0.05 && daylight > 0.01) {
		float d = dot(ray, normalize(sd));
		float disc = smoothstep(0.9992, 0.9998, d);
		float halo = pow(max(d, 0.0), 48.0) * 0.30;
		vec3 sc = u_sun_col_flash.rgb;
		col += (sc * disc + sc * halo) * daylight * (1.0 - u_cloudiness * 0.65) * (1.0 - mist * 0.5);
	}

	// Wind-drifting fbm clouds
	if (ray.y > 0.02) {
		vec2 cpos = ray.xz / ray.y * 0.35 + u_wind_offset;
		float n = fbm(cpos);
		float th = 1.02 - u_cloudiness * 0.82;
		float cov = smoothstep(th - 0.10, th + 0.18, n);
		cov *= smoothstep(0.02, 0.14, ray.y);
		vec3 cloud_col = mix(vec3(0.035, 0.04, 0.06), mix(vec3(0.95, 0.96, 1.0), vec3(0.54, 0.59, 0.66), u_cloudiness * 0.6), daylight);
		cloud_col *= 0.6 + 0.5 * fbm(cpos * 1.7 + 3.1);
		col = mix(col, cloud_col, min(cov * 1.15, 0.95));
	}

	// Lightning sky flash
	if (flash > 0.01) {
		col += vec3(0.65, 0.78, 1.0) * (flash * (0.35 + 0.65 * max(ray.y, 0.0)));
	}

	if (u_nv_active > 0.5) {
		col = mix(nightvision_rgb(col), overexposed_rgb(col), smoothstep(0.85, 1.0, daylight));
	}
	COLOR = col;
}
