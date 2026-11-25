shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://scripts/air_heights.gdshaderinc"

uniform sampler2D scene : hint_screen_texture, filter_nearest;
uniform sampler2D solar_map : filter_linear, repeat_disable;
uniform sampler2D solar_near_map : filter_linear, repeat_disable;
uniform sampler2D volume_map : filter_linear, repeat_disable;
uniform sampler2D bounce_map : filter_linear, repeat_disable;
uniform sampler2D surface_mask : filter_nearest, repeat_disable;
uniform sampler2D lamp_slots : filter_nearest, repeat_disable;
uniform sampler2D lamp_sources : filter_nearest, repeat_disable;
uniform sampler2D ambient_map : filter_nearest, repeat_disable;
uniform sampler2D sky_transport : filter_nearest, repeat_disable;
uniform sampler2D geometry : filter_nearest, repeat_disable;
uniform sampler2D river_field : filter_linear, repeat_disable;
uniform ivec2 map_size;
uniform vec2 view_world;
uniform vec2 map_offset;
uniform vec2 view_span;
uniform vec2 far_offset;
uniform vec2 light_span;
uniform float light_margin;
uniform vec2 near_offset;
uniform float near_span = 18.0;
uniform float volume_sample_inset;
uniform float bounce_sample_inset;
uniform vec2 mask_sample_scale;
uniform float lamp_power;
uniform vec3 sun_ray;
uniform vec3 sun_color;
uniform float sun_energy;
uniform vec3 moon_ray;
uniform float moon_energy;
uniform vec3 sky_color;
uniform float sky_energy;
uniform float indoor_daylight;
uniform vec3 outdoor_ambient = vec3(0.45, 0.50, 0.54);
uniform vec3 season_tint = vec3(1.0);
uniform float mist_time;
uniform float rain_level = 0.0;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
uniform float cloud_cover = 0.0;
uniform float puddle_phase = 0.0;
uniform float noise_seed;
uniform bool below_ground;
uniform vec2 player_feet;

float hash21(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

int surface_class(ivec2 at) {
	vec4 tile = texelFetch(geometry, at, 0);
	int kind = int(round(tile.g * 255.0));
	return kind >= 1 && kind <= 4 ? 2 : (int(round(tile.a * 3.0)) & 1);
}

vec3 sky_at(ivec2 p, float aperture_weight) {
	if (indoor_daylight <= 0.001) {
		return vec3(0.0);
	}
	vec2 access = texelFetch(sky_transport, p, 0).rg;
	return sky_color * indoor_daylight * (access.r * aperture_weight + access.g * 0.53);
}

vec3 ambient_at(vec2 local, ivec2 own) {
	ivec2 start = ivec2(floor(local - 0.5));
	vec2 fraction = fract(local - 0.5);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	vec3 total = vec3(0.0);
	float weight = 0.0;
	int same_class = surface_class(own);
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			ivec2 p = clamp(start + ivec2(x, y), ivec2(0), map_size - ivec2(1));
			if (surface_class(p) != same_class) {
				continue;
			}
			if (p.x != own.x && p.y != own.y && surface_class(ivec2(p.x, own.y)) != same_class
				&& surface_class(ivec2(own.x, p.y)) != same_class) {
				continue;
			}
			float w = (x == 1 ? fraction.x : 1.0 - fraction.x) * (y == 1 ? fraction.y : 1.0 - fraction.y);
			vec3 incident = texelFetch(ambient_map, p, 0).rgb;
			if (same_class != 0) {
				incident += sky_at(p, same_class == 1 ? 1.40 : 0.73);
			}
			total += incident * w;
			weight += w;
		}
	}
	return total / max(weight, 0.001);
}

vec3 sample_cascaded_solar(vec2 receiver_local) {
	vec2 far_uv = (receiver_local - far_offset) / light_span;
	vec3 far_vis = texture(solar_map, far_uv).rgb;
	vec2 near_uv = (receiver_local - near_offset) / vec2(near_span);
	vec2 margin = abs(near_uv - vec2(0.5)) * 2.0;
	float edge = max(margin.x, margin.y);
	if (edge >= 0.98) {
		return far_vis;
	}
	vec3 near_vis = texture(solar_near_map, near_uv).rgb;
	float blend = 1.0 - smoothstep(0.72, 0.96, edge);
	return mix(far_vis, near_vis, blend);
}

float body_shadow(vec2 world, float height, vec3 heading) {
	vec3 scale = vec3(0.22, 0.16, 0.54);
	vec3 origin = vec3(world - player_feet, height - 0.55) / scale;
	vec3 direction = heading / scale;
	float t = max(0.0, -dot(origin, direction) / max(dot(direction, direction), 0.001));
	float edge = length(origin + direction * t);
	return (1.0 - smoothstep(0.78, 1.18, edge)) * (1.0 - smoothstep(12.0, 18.0, t));
}

float player_shadow(vec2 world, float height) {
	return body_shadow(world, height, sun_ray);
}

float lamp_shadow(vec3 receiver, vec3 light_pos) {
	vec3 scale = vec3(0.23, 0.17, 0.55);
	vec2 player_local = player_feet - view_world + map_offset;
	vec3 origin = (receiver - vec3(player_local, 0.56)) / scale;
	vec3 ray = (light_pos - receiver) / scale;
	float t = clamp(-dot(origin, ray) / max(dot(ray, ray), 0.001), 0.0, 1.0);
	return 1.0 - smoothstep(0.73, 1.22, length(origin + ray * t));
}

vec3 local_lighting_cell(ivec2 cell, vec3 receiver, bool self_character) {
	vec4 indices = texelFetch(lamp_slots, cell, 0);
	vec4 transmission = texelFetch(lamp_slots, cell + ivec2(map_size.x, 0), 0);
	vec3 total = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		int index = int(round(indices[i]));
		if (index <= 0) {
			break;
		}
		vec4 lamp = texelFetch(lamp_sources, ivec2(index - 1, 0), 0);
		vec4 meta = texelFetch(lamp_sources, ivec2(index - 1, 1), 0);
		float flicker_kind = floor(meta.a);
		float always_level = fract(meta.a);
		float power = max(lamp_power, always_level);
		if (power <= 0.001) {
			continue;
		}
		float d = length(receiver - lamp.xyz);
		float cutoff = 1.0 - smoothstep(4.8, 8.8, d);
		float shadow = 0.0;
		if (!self_character) {
			vec2 player_local = player_feet - view_world + map_offset;
			shadow = distance(receiver.xy, player_local) < 9.4 ? lamp_shadow(receiver, lamp.xyz) : 0.0;
		}
		float wave = 1.0;
		if (flicker_kind > 1.5) {
			wave = 0.90 + 0.10 * sin(TIME * 2.1 + lamp.x * 0.7 + lamp.y * 0.4);
		} else if (flicker_kind > 0.5) {
			float phase = lamp.x * 1.9 + lamp.y * 2.7;
			wave = 0.96 + 0.025 * sin(TIME * 5.2 + phase) + 0.015 * sin(TIME * 11.7 - phase * 1.3);
		}
		float energy = cutoff * lamp.w * transmission[i] * (1.0 - 0.94 * shadow) * power * wave / (0.80 + 0.32 * d * d);
		total += meta.rgb * energy;
	}
	return vec3(0.94) * (vec3(1.0) - exp(-total * 0.145));
}

vec3 local_lighting(ivec2 own, vec3 receiver, bool self_character) {
	// Non-grid smooth bilinear blend of point light visibility across neighboring open cells
	// so lantern illumination flows continuously without 32px square tile seams!
	ivec2 start = ivec2(floor(receiver.xy - 0.5));
	vec2 f = fract(receiver.xy - 0.5);
	f = f * f * (3.0 - 2.0 * f);
	int same_class = surface_class(own);
	vec3 total = vec3(0.0);
	float weight = 0.0;
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			ivec2 c = clamp(start + ivec2(x, y), ivec2(0), map_size - ivec2(1));
			if (surface_class(c) != same_class) {
				continue;
			}
			if (c.x != own.x && c.y != own.y && surface_class(ivec2(c.x, own.y)) != same_class
				&& surface_class(ivec2(own.x, c.y)) != same_class) {
				continue;
			}
			float w = (x == 1 ? f.x : 1.0 - f.x) * (y == 1 ? f.y : 1.0 - f.y);
			total += local_lighting_cell(c, receiver, self_character) * w;
			weight += w;
		}
	}
	if (weight <= 0.001) {
		return local_lighting_cell(own, receiver, self_character);
	}
	return total / weight;
}

vec3 local_lighting_halo(ivec2 own, vec2 receiver_xy) {
	vec4 indices = texelFetch(lamp_slots, own, 0);
	vec4 transmission = texelFetch(lamp_slots, own + ivec2(map_size.x, 0), 0);
	vec3 halo = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		int index = int(round(indices[i]));
		if (index <= 0) {
			break;
		}
		vec4 lamp = texelFetch(lamp_sources, ivec2(index - 1, 0), 0);
		vec4 meta = texelFetch(lamp_sources, ivec2(index - 1, 1), 0);
		float always_level = fract(meta.a);
		float power = max(lamp_power, always_level);
		if (power <= 0.001) {
			continue;
		}
		float d = length(receiver_xy - lamp.xy);
		if (d < 2.2) {
			float falloff = exp(-d * d * 1.85) * transmission[i] * power;
			halo += meta.rgb * falloff * (0.11 + 0.003 * lamp.w);
		}
	}
	return halo;
}

vec3 ambient_motes(vec2 world, vec2 local, bool indoors, float river_prox) {
	if (below_ground || rain_level > 0.25 || snow_cover > 0.4) {
		return vec3(0.0);
	}
	vec2 drift = indoors ? vec2(0.05, -0.04) : vec2(-0.12, -0.07);
	vec2 cell_uv = world * 0.55 + drift * TIME;
	vec2 id = floor(cell_uv);
	vec2 f = fract(cell_uv) - 0.5;
	float h = hash21(id + vec2(noise_seed * 0.13, noise_seed * 0.29));
	if (h < 0.72) {
		return vec3(0.0);
	}
	vec2 jitter = vec2(sin(TIME * (0.9 + fract(h * 13.7)) + h * 41.0),
		cos(TIME * (0.8 + fract(h * 27.3)) + h * 19.0)) * 0.24;
	float dist = length(f - jitter);
	float spark = exp(-dist * dist * 190.0);
	float pulse = 0.5 + 0.5 * sin(TIME * (2.2 + fract(h * 17.1) * 2.5) + h * 60.0);
	if (!indoors && lamp_power > 0.25 && river_prox > 0.15) {
		vec3 fly_col = mix(vec3(0.88, 0.94, 0.45), vec3(0.45, 0.96, 0.76), fract(h * 7.3));
		return fly_col * spark * pulse * lamp_power * river_prox * 0.36;
	}
	if (!indoors && sun_energy > 0.15 && mist_time > 0.2) {
		return sun_color * spark * pulse * sun_energy * mist_time * 0.12;
	}
	return vec3(0.0);
}

#include "res://scripts/weather_surface.gdshaderinc"
#include "res://scripts/river_surface.gdshaderinc"
#include "res://scripts/indoor_beam.gdshaderinc"
#include "res://scripts/diffuse_receiver.gdshaderinc"

vec3 height_density(vec2 world, vec2 local, bool indoors) {
	vec2 seed = vec2(noise_seed, noise_seed * 0.41);
	if (indoors) {
		float dust = mix(0.72, 1.16, noise2((world + seed) * 0.77 + TIME * vec2(0.04, -0.026)));
		return vec3(0.012, 0.041, 0.054) * dust;
	}
	vec2 wind = vec2(-0.22, 0.095) * TIME;
	vec2 pos = world + seed + wind;
	float broad = noise2(pos * vec2(0.11, 0.18));
	float wisps = noise2((pos + wind * 0.55) * vec2(0.31, 0.51));
	float bank = smoothstep(0.24, 0.77, broad * 0.72 + wisps * 0.28);
	float river = texture(river_field, local / vec2(map_size)).r;
	float depth = mix(0.55, 1.0, smoothstep(0.8, 8.0, distance(world, player_feet)));
	float high = noise2((world + seed - wind * 0.38) * vec2(0.13, 0.22));
	return vec3((0.036 + 0.37 * river) * bank,
		(0.023 + 0.15 * river) * mix(bank, high, 0.34),
		(0.018 + 0.055 * river) * high) * mist_time * depth;
}

vec3 integrate_air(vec3 surface, vec2 local, vec2 world, vec2 light_uv, ivec2 cell,
		float surface_height, bool indoors, vec3 reflected) {
	if (below_ground || (!indoors && mist_time <= 0.001)) {
		return surface;
	}
	vec3 density = height_density(world, local, indoors);
	vec3 air_fraction = smoothstep(vec3(-0.12), vec3(0.12), AIR_HEIGHTS - vec3(surface_height));
	vec3 visibility = vec3(0.0);
	bool shaped_beam = indoors && sun_energy > 0.0001;
	if (shaped_beam) {
		visibility = sample_indoor_beam(local, light_uv, cell);
		for (int i = 0; i < 3; i++) {
			if (visibility[i] > 0.001) {
				visibility[i] *= 1.0 - 0.90 * player_shadow(world, AIR_HEIGHTS[i]);
			}
		}
		vec3 clipped_air;
		visibility = indoor_beam_profile(visibility, surface_height, clipped_air);
		air_fraction = mix(air_fraction, clipped_air, smoothstep(0.0001, 0.12, sun_energy));
	} else if (sun_energy > 0.0001) {
		visibility = texture(volume_map, light_uv).rgb;
	}
	density *= air_fraction;
	float day = clamp(sky_energy * 1.5 + sun_energy * 0.3, 0.0, 1.0);
	vec3 air_ambient = mix(vec3(0.095, 0.14, 0.20), vec3(0.50, 0.60, 0.67), day) * mix(vec3(1.0), season_tint, 0.55);
	if (indoors) {
		air_ambient = vec3(0.025, 0.033, 0.048) + sky_at(cell, 0.58) * 0.60 + reflected * 0.34;
	}
	float phase = mix(1.62, 0.76, smoothstep(0.13, 0.91, sun_ray.z));
	vec3 lamp = local_lighting_cell(cell, vec3(local, AIR_HEIGHTS.y), false);
	vec3 fog_light = air_ambient + lamp * 0.62;
	vec3 radiant = vec3(0.0);
	float through = 1.0;
	for (int i = 2; i >= 0; i--) {
		float height = AIR_HEIGHTS[i];
		float blocked = !shaped_beam && visibility[i] > 0.001 ? player_shadow(world, height) : 0.0;
		float solar = visibility[i] * (1.0 - 0.90 * blocked) * sun_energy;
		float transmitted = exp(-density[i]);
		radiant += through * (1.0 - transmitted) * (fog_light + sun_color * solar * phase * (indoors ? 4.0 : 1.20));
		through *= transmitted;
	}
	return surface * through + radiant;
}

vec3 roll_off_highlights(vec3 light) {
	float key = max(light.r, max(light.g, light.b));
	float excess = max(0.0, key - 0.78);
	float peak = min(key, 0.78) + excess / (1.0 + 4.2 * excess);
	return light * (peak / max(key, 0.001));
}

ivec2 sprite_owner(vec4 mask) {
	ivec3 packed_cell = ivec3(round(mask.rgb * 255.0));
	ivec2 offset = packed_cell.xy + 256 * ivec2(packed_cell.z & 7, (packed_cell.z >> 4) & 7);
	return ivec2(floor(map_offset)) + offset - ivec2(2);
}

bool is_character_mask(vec4 mask) {
	return mask.a > 0.5 && (int(round(mask.b * 255.0)) & 128) != 0;
}

float interior_shadow_gain(vec3 exposure) {
	float level = dot(exposure, vec3(0.2126, 0.7152, 0.0722));
	float shadow_weight = smoothstep(0.06, 0.27, indoor_daylight) * (1.0 - smoothstep(0.22, 0.52, level));
	return 1.0 + 0.24 * shadow_weight;
}

float contact_shade(vec2 local, ivec2 own, vec4 own_tile) {
	vec2 at = fract(local);
	float shade = 0.0;
	for (int axis = 0; axis < 2; axis++) {
		float coordinate = axis == 0 ? at.x : at.y;
		int side = coordinate < 0.5 ? -1 : 1;
		ivec2 step_dir = axis == 0 ? ivec2(side, 0) : ivec2(0, side);
		ivec2 other = own + step_dir;
		if (all(greaterThanEqual(other, ivec2(0))) && all(lessThan(other, map_size))) {
			float difference = max(texelFetch(geometry, other, 0).r - own_tile.r, 0.0);
			shade += smoothstep(0.12, 0.65, difference) * (1.0 - smoothstep(0.0, 0.40, min(coordinate, 1.0 - coordinate)));
		}
	}
	return min(0.23, shade * 0.16);
}

void fragment() {
	vec2 viewport_pos = UV * view_span;
	vec2 world = view_world + viewport_pos;
	vec2 local = viewport_pos + map_offset;
	ivec2 own = clamp(ivec2(floor(local)), ivec2(0), map_size - ivec2(1));
	vec4 mask = texture(surface_mask, UV * mask_sample_scale);
	ivec2 owner = sprite_owner(mask);
	bool sprite = mask.a > 0.5 && all(greaterThanEqual(owner, ivec2(0))) && all(lessThan(owner, map_size));
	bool character = sprite && is_character_mask(mask);
	if (sprite) {
		own = owner;
	}
	vec4 ambient = texelFetch(ambient_map, own, 0);
	vec3 base = texture(scene, SCREEN_UV).rgb;
	if (ambient.a < 0.5) {
		COLOR = vec4(base, 1.0);
	} else {
		vec4 tile = texelFetch(geometry, own, 0);
		int material = int(round(tile.g * 255.0));
		bool indoors = (int(round(tile.a * 3.0)) & 1) != 0;
		bool wall = !character && material >= 1 && material <= 4;
		bool window = sprite && !character && (material == 2 || material == 3);
		vec2 receiver = sprite ? vec2(own) + clamp(local - vec2(own), vec2(0.13), vec2(0.87)) : local;
		vec2 light_uv = (receiver - far_offset) / light_span;
		vec3 skylight = ambient_at(receiver, own);
		vec3 solar = sample_cascaded_solar(receiver);
		float height = character ? 1.15 : max(0.14, tile.r * 3.0);
		float cap = 1.0 - smoothstep(0.13, 0.50, local.y - float(own.y));
		float z_surface = character ? mix(0.45, 1.05, cap) : sprite ? mix(height * 0.55, height, cap) : 0.04;
		float face_sun = wall ? 0.14 + 0.78 * smoothstep(-0.07, 0.54, sun_ray.y) : 0.83;
		float direct = character ? mix(solar.g * 0.90, solar.b, 0.35 + 0.30 * cap) : sprite ? mix(solar.g * face_sun, solar.b, cap) : solar.r;
		if (window) {
			z_surface = mix(1.08, 1.62, cap);
			float angle = abs(tile.b > 0.5 ? sun_ray.x : sun_ray.y);
			direct = mix(solar.g, solar.b, cap) * angle * (material == 2 ? 0.48 : 0.65);
		}
		vec2 world_receiver = receiver - map_offset + view_world;
		if (!character) {
			direct *= 1.0 - 0.94 * player_shadow(world_receiver, z_surface);
		}
		float contact = sprite ? 0.0 : 1.0 - smoothstep(0.18, 1.0, length((world - player_feet) / vec2(0.37, 0.20)));
		float ao = sprite ? 0.0 : contact_shade(local, own, tile);
		vec3 bounce = vec3(0.0);
		if (sun_energy > 0.0001) {
			if (indoors && (character || material != 1)) {
				bounce = sample_room_bounce(receiver, own);
			} else if (!indoors) {
				// Outdoor colored environmental bounce (foliage green, river aqua, warm plaster ochre)
				// shines most noticeably into shaded corners, wall bases, and under-eaves!
				float shade_boost = mix(1.0, 0.45, clamp(direct, 0.0, 1.0));
				bounce = sample_outdoor_bounce(receiver, own) * (0.58 * shade_boost);
			}
		}
		if (sprite && wall) {
			ivec2 face = own + ivec2(0, 1);
			if (material == 1 && face.y < map_size.y) {
				if (surface_class(face) == 1) {
					skylight += sky_at(face, 1.12) * (0.55 - 0.30 * cap);
					if (sun_energy > 0.0001) {
						bounce = sample_room_bounce(vec2(receiver.x, float(face.y) + 0.08), face) * (0.85 - 0.25 * cap);
					}
				} else if (sun_energy > 0.0001 && surface_class(face) == 0) {
					// Exterior south wall base picks up colored bounce from adjacent sunlit grass, stone, or river!
					bounce = sample_outdoor_bounce(vec2(receiver.x, float(face.y) + 0.12), face) * (0.72 - 0.30 * cap);
				}
			}
		}
		vec3 reflected = sun_color * bounce * sun_energy * (0.86 - ao);
		vec3 lamp = local_lighting(own, vec3(receiver, z_surface), character);
		vec3 exposure = skylight * (1.0 - 0.27 * contact - ao)
			+ sun_color * direct * sun_energy + reflected + lamp;
		if (character) {
			exposure = max(exposure, vec3(0.16, 0.18, 0.21));
		}
		vec3 lit = base * exposure * mix(vec3(1.0), season_tint, indoors ? 0.25 : 0.65);
		vec3 river_sample = texture(river_field, local / vec2(map_size)).rgb;
		if (!sprite && !indoors) {
			float water_mask = texelFetch(river_field, own, 0).g;
			if (water_mask > 0.15) {
				float moon = moon_energy > 0.0001 ? solar.r * (1.0 - 0.94 * body_shadow(world, 0.045, moon_ray)) : 0.0;
				lit = shade_river(lit, world, local, river_sample.g, direct, moon, lamp);
			} else {
				float smooth_hold = ground_hold_at(local, world);
				float shore_dist = 8.0 * (river_sample.b - 0.5);
				float wet_bank = (1.0 - smoothstep(-0.95, 0.02, shore_dist)) * smoothstep(-1.4, -0.05, shore_dist);
				if (wet_bank > 0.001) {
					lit *= 1.0 - 0.17 * wet_bank;
					lit += sky_color * (0.03 + 0.04 * direct * sun_energy) * wet_bank;
				}
				if (snow_cover > 0.01) {
					lit = apply_snow_blanket(lit, base, exposure, world, snow_cover, smooth_hold);
				} else if (wetness > 0.01) {
					lit = apply_rain_puddles(lit, base, world, SCREEN_UV, direct, lamp, smooth_hold);
				}
			}
		} else if (sprite && !indoors && !character && snow_cover > 0.01) {
			lit = apply_snow_blanket(lit, base, exposure, world, snow_cover * cap * 0.45, 0.0);
		}
		if (indoors && !wall) {
			lit *= interior_shadow_gain(exposure);
		}
		if (!(sprite && wall)) {
			lit = integrate_air(lit, receiver, world_receiver, light_uv, own, z_surface, indoors, reflected);
		}
		lit += local_lighting_halo(own, receiver);
		lit += ambient_motes(world, local, indoors, river_sample.r);
		vec2 centered = (UV - vec2(0.5)) * 2.0;
		float vignette = 1.0 - 0.10 * smoothstep(0.55, 1.42, dot(centered, centered));
		COLOR = vec4(roll_off_highlights(lit) * vignette, 1.0);
	}
}
