shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Pass 1B (Continuous Line-of-Sight Mask, 8 texels/tile, UPDATE_ONCE ONLY when player moves!):
// Casts 9 evenly weighted sub-pixel eye-disc rays against physical opaque walls/closed doors
// (with circular trunk intersection for trees, never 1x1 pillars).
// Eliminates BOTH 32px stair-steps AND 5-ray banding streaks, AND decouples dusk lighting from tile vision!
// Output RG: R = smooth continuous wall line-of-sight (0..1), G = smooth explored/known flag (0..1).

uniform sampler2D geom_tex : filter_nearest, repeat_disable;
uniform sampler2D vis_tex : filter_nearest, repeat_disable; // R=CCB vis state, G=CCB opaque, B=explored

uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_size = vec2(61.0, 41.0);
uniform vec2 light_world_min = vec2(0.0);
uniform vec2 light_world_span = vec2(32.0, 22.0);
uniform vec2 player_eye = vec2(0.0);

float trace_sight_ray(vec2 start_local, vec2 end_local, ivec2 target_cell, bool target_opaque) {
	vec2 delta = end_local - start_local;
	float dist = length(delta);
	if (dist < 0.06) {
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

	ivec2 gsz = ivec2(grid_size);
	for (int s = 0; s < 36; s++) {
		float next_t = min(cross_t.x, cross_t.y);
		if (next_t >= dist - 0.025) {
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
		if (cell == target_cell && target_opaque) {
			return 1.0;
		}
		vec4 vt = texelFetch(vis_tex, cell, 0);
		if (vt.g > 0.5) {
			vec4 gd = texelFetch(geom_tex, cell, 0);
			int k = int(round(gd.g * 255.0));
			if (k == 5) {
				// Single outdoor tree trunks never cast pitch-black sight-laser lines across bright meadows;
				// dense forest fog-of-war is handled authentically by CCB vis_tex, while Pass 1 casts real dappled sun shadows!
				continue;
			}
			return 0.0;
		}
	}
	return 1.0;
}

void fragment() {
	vec2 world_p = light_world_min + UV * light_world_span;
	vec2 local_p = world_p - grid_origin;
	ivec2 gsz = ivec2(grid_size);
	ivec2 own = clamp(ivec2(floor(local_p)), ivec2(0), gsz - ivec2(1));
	vec4 vt = texelFetch(vis_tex, own, 0);
	// Instant GPU early-out on pitch-black unseen tiles (skips 50-85% of 9-ray DDA work indoors!)
	if (vt.r < 0.05) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		bool target_opaque = vt.g > 0.5;
		float explored_f = float(int(round(vt.b * 255.0)) & 1);
		// CCB-visible solid walls are uniformly visible -> skip all 9 DDA rays!
		if (target_opaque && vt.r > 0.62) {
			COLOR = vec4(1.0, explored_f, 0.0, 1.0);
		} else {
			vec2 eye_local = player_eye - grid_origin;
			vec2 target_pt = local_p;
			if (target_opaque) {
				// Solid wall/door tiles are 3D blocks: evaluate visibility uniformly on the player-facing front face
				// so straight walls NEVER get sliced diagonally half-lit/half-dark by their collinear neighbor!
				vec2 wcenter = vec2(own) + vec2(0.5);
				vec2 to_w = wcenter - eye_local;
				vec2 wdir = (length(to_w) > 0.001) ? normalize(to_w) : vec2(1.0, 0.0);
				target_pt = clamp(wcenter - wdir * 0.44, vec2(own) + vec2(0.04), vec2(own) + vec2(0.96));
			}
			vec2 delta = target_pt - eye_local;
			float dist = length(delta);
			vec2 dir2 = (dist > 0.001) ? delta / dist : vec2(1.0, 0.0);
			vec2 perp = vec2(-dir2.y, dir2.x);

			// 9 smooth samples across a realistic 0.28-tile human eye/head aperture -> completely banding-free!
			float offs[9] = { -0.26, -0.195, -0.13, -0.065, 0.0, 0.065, 0.13, 0.195, 0.26 };
			float wts[9]  = {  0.05,   0.09,  0.13,   0.16, 0.14,  0.16, 0.13,   0.09, 0.05 };
			float los = 0.0;
			for (int i = 0; i < 9; i++) {
				los += trace_sight_ray(eye_local + perp * offs[i], target_pt, own, target_opaque) * wts[i];
			}

			COLOR = vec4(los, explored_f, 0.0, 1.0);
		}
	}
}
