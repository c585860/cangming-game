extends RefCounted

# Modular 60 FPS Photorealistic World Effects & Combat Animation Renderer for embedded real CCB:
# - Smooth exponential creature/player movement glide (player, NPCs, monsters)
# - Auto-Move active route & mouse hover Destination Preview
# - Photorealistic dual-blend combat VFX (BLEND_MODE_MIX smoke/debris/casings + BLEND_MODE_ADD fireballs/muzzle plumes/sparks/shockwaves)
# - Exact burst-RPM staggered scheduling so rapid-fire bursts & full-auto fire flicker in lockstep with audio!
# - Physical camera micro-shake trauma for explosions & heavy caliber firearms

const VfxTex = preload("res://scripts/ccb_native/ccb_vfx_textures.gd")

const TILE_FLAG_OVERLAY := 0x20
const CRITTER_PLAYER := 0x01

const PATH_AUTOMOVE := 1
const PATH_PREVIEW := 2
const PATH_DESTINATION := 3

const OV_HIGHLIGHT := 1
const OV_HIT_FLASH := 2
const OV_EXPLOSION := 3
const OV_BULLET := 4
const OV_ZONE := 5
const OV_SOUND := 6
const OV_CURSOR := 7

const VFX_MUZZLE_FLASH := 1
const VFX_TRACER := 2
const VFX_BEAM_LASER := 3
const VFX_BEAM_PLASMA := 4
const VFX_BEAM_LIGHTNING := 5
const VFX_IMPACT_SPARK := 6
const VFX_BLAST := 7
const VFX_FLASHBANG := 8
const VFX_EMP := 9

const CALIBER_DEFAULT := 0
const CALIBER_PISTOL := 1
const CALIBER_RIFLE := 2
const CALIBER_SHOTGUN := 3
const CALIBER_HEAVY := 4
const CALIBER_SUPPRESSED := 5
const CALIBER_ENERGY := 6

const VFX_FLAG_INDOORS := 0x01
const VFX_FLAG_FIERY := 0x02

const GLIDE_SPEED := 20.0

var _critter_visual: Dictionary = {}
var _critter_target: Dictionary = {}
var _player_visual := Vector2.ZERO
var _player_target := Vector2.ZERO
var _has_player := false
var _last_z := 0
var _anim_time := 0.0
var _is_gliding := false
var _cached_overlays: Array = []
var _has_animated_fx := false

var _pending_vfx: Array = [] # Staggered burst VFX waiting for exact RPM delay
var _active_vfx: Array = []  # Live 60fps photorealistic muzzle flashes, tracers, beams, sparks, blasts
var _smoke_puffs: Array = [] # Volumetric dark explosion smoke & drifting cordite gunsmoke (BLEND_MODE_MIX)
var _debris_bits: Array = [] # Charred explosion debris chunks & ejecting golden brass shell casings
var _embers: Array = []      # Ballistic incandescent flying sparks & glowing blast embers (BLEND_MODE_ADD)
var _last_vfx_id := 0

# P2.3 Persistent combat traces, fire heat haze & wet/snow footprints + P3.1 Seasonal ambient particles
var _settled_casings: Array = [] # Landed brass shell casings lingering on ground (~45s)
var _ground_scorch: Array = []   # Persistent charred explosion craters (~90s)
var _footprints: Array = []      # Wet mud/rain & snowy bootprints (including 3 damp steps tracked indoors!)
var _fire_emitters: Array = []   # Active world fire positions for heat haze + rising embers
var _heat_wisps: Array = []      # Shimmering convection wisps above active fires
var _ambient_motes: Array = []   # P3.1 Autumn leaves, spring pollen, twilight fireflies, winter frost motes
var _wet_boots_steps := 0
var _step_foot_side := 1.0
var _prev_step_tile := Vector2i(-99999, -99999)
var _fire_spawn_accum := 0.0
var _mote_spawn_accum := 0.0
var _trace_redraw_accum := 0.0
var _ambient_redraw_accum := 0.0
var _ambient_redraw_due := false
var _env_season := 0
var _env_wetness := 0.0
var _env_snow_cov := 0.0
var _env_daylight := 1.0
var _env_wind := Vector2(0.85, 0.25)
var _env_wind_spd := 4.0
var _env_under := false
var _env_rain := 0.0
var _env_snow := 0.0
var _env_tree_dens := 0.0
var _env_player_in := false

# Camera trauma micro-shake state
var _shake_trauma := 0.0
var _shake_offset := Vector2.ZERO

# Verification telemetry
var total_vfx_spawned := 0
var total_muzzle_flashes := 0
var total_blasts := 0


func reset() -> void:
	_critter_visual.clear()
	_critter_target.clear()
	_cached_overlays.clear()
	_pending_vfx.clear()
	_active_vfx.clear()
	_smoke_puffs.clear()
	_debris_bits.clear()
	_embers.clear()
	_settled_casings.clear()
	_ground_scorch.clear()
	_footprints.clear()
	_fire_emitters.clear()
	_heat_wisps.clear()
	_ambient_motes.clear()
	_wet_boots_steps = 0
	_prev_step_tile = Vector2i(-99999, -99999)
	_has_player = false
	_is_gliding = false
	_has_animated_fx = false
	_shake_trauma = 0.0
	_shake_offset = Vector2.ZERO


func _rng_f(seed_v: int, salt: int) -> float:
	var h := ((seed_v ^ (salt * 2654435761)) * 2246822519) & 0x7FFFFFFF
	h = ((h ^ (h >> 15)) * 3266489917) & 0x7FFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


func sync_environment(bundle: Dictionary) -> void:
	if bundle.is_empty():
		return
	_env_season = clampi(int(bundle.get("season", _env_season)), 0, 3)
	_env_wetness = float(bundle.get("wetness", 0.0))
	_env_snow_cov = float(bundle.get("snow_cover", 0.0))
	_env_daylight = clampf(float(bundle.get("daylight", 1.0)), 0.0, 1.0)
	_env_wind = bundle.get("wind_dir", Vector2(0.85, 0.25))
	_env_wind_spd = float(bundle.get("wind_speed", 4.0))
	_env_under = bool(bundle.get("is_underground", false))
	_env_rain = float(bundle.get("rain", 0.0))
	_env_snow = float(bundle.get("snow", 0.0))


func sync_snapshot(snap: Dictionary) -> void:
	VfxTex.ensure_ready()
	var z := int(snap.get("z", 0))
	var p_tile: Vector2i = snap.get("player", Vector2i.ZERO)
	var p_vec := Vector2(p_tile)
	if not _has_player or z != _last_z:
		_critter_visual.clear()
		_critter_target.clear()
		_settled_casings.clear()
		_ground_scorch.clear()
		_footprints.clear()
		_heat_wisps.clear()
		_ambient_motes.clear()
		_prev_step_tile = p_tile
		_has_player = true
	_last_z = z
	# Authentic vanilla CCB instant tile movement (no smooth glide interpolation)
	_player_visual = p_vec
	_player_target = p_vec
	_is_gliding = false

	_env_player_in = bool(snap.get("player_indoors", false))
	_env_tree_dens = clampf(float(snap.get("tree_density", 0.0)), 0.0, 1.0)
	_env_season = clampi(int(snap.get("season", _env_season)), 0, 3)
	_env_under = bool(snap.get("is_underground", false)) or z < 0

	# P2.3 Wet rain / puddle & snow bootprints (including 3 damp prints tracked onto indoor floors!)
	if _prev_step_tile.x > -90000 and p_tile != _prev_step_tile:
		var step_delta := Vector2(p_tile - _prev_step_tile)
		if step_delta.length_squared() >= 0.5 and step_delta.length_squared() <= 5.0:
			var pmat := int(snap.get("player_mat_id", 6))
			var is_wet_tile := (pmat == 4) or ((not _env_player_in) and (not _env_under) and _env_wetness >= 0.35)
			var is_snow_tile := (not _env_player_in) and (not _env_under) and _env_snow_cov >= 0.35 and pmat != 4
			if is_wet_tile:
				_wet_boots_steps = 4
			var fp_kind := -1 # 0=wet, 1=snow
			if is_snow_tile:
				fp_kind = 1
			elif is_wet_tile or _wet_boots_steps > 0:
				fp_kind = 0
				if not is_wet_tile:
					_wet_boots_steps = maxi(0, _wet_boots_steps - 1)
			if fp_kind >= 0:
				_step_foot_side = -_step_foot_side
				var ang := step_delta.angle()
				var perp := Vector2(-sin(ang), cos(ang)) * (_step_foot_side * 0.14)
				_footprints.append({
					"pos": Vector2(_prev_step_tile) + Vector2(0.5, 0.58) + perp,
					"ang": ang,
					"kind": fp_kind,
					"age": 0.0,
					"dur": 26.0 if fp_kind == 1 else 20.0,
				})
				while _footprints.size() > 48:
					_footprints.pop_front()
	_prev_step_tile = p_tile

	# Cache active world fire emitters for P2.3 rising embers & thermal heat haze!
	_fire_emitters.clear()
	var lights: Array = snap.get("lights", [])
	for l_var in lights:
		var ld: Dictionary = l_var
		if (int(ld.get("flags", 0)) & 1) != 0:
			_fire_emitters.append(Vector3(float(ld.get("x", 0)) + 0.5, float(ld.get("y", 0)) + 0.5, float(ld.get("intensity", 6.0))))
			if _fire_emitters.size() >= 18:
				break

	var alive_uids := {}
	var creatures: Array = snap.get("creatures", [])
	for c_var in creatures:
		var cd: Dictionary = c_var
		var uid := int(cd.get("uid", 0))
		if uid == 0:
			continue
		var tgt := Vector2(float(cd.get("x", 0)), float(cd.get("y", 0)))
		alive_uids[uid] = true
		_critter_target[uid] = tgt
		_critter_visual[uid] = tgt

	var stale: Array = []
	for uid in _critter_visual:
		if not alive_uids.has(uid):
			stale.append(uid)
	for uid in stale:
		_critter_visual.erase(uid)
		_critter_target.erase(uid)

	_cached_overlays.clear()
	var has_pulsing_ov := false
	if bool(snap.get("has_overlays", true)):
		var origin: Vector2i = snap.get("origin", Vector2i.ZERO)
		var grid_sz: Vector2i = snap.get("size", Vector2i.ZERO)
		var tiles_bytes: PackedByteArray = snap.get("tiles", PackedByteArray())
		var stride: int = int(snap.get("tile_stride", 48))
		if grid_sz.x > 0 and grid_sz.y > 0 and tiles_bytes.size() >= grid_sz.x * grid_sz.y * stride:
			for ty in range(grid_sz.y):
				var wy := origin.y + ty
				var row_idx := ty * grid_sz.x
				for tx in range(grid_sz.x):
					var off := (row_idx + tx) * stride
					if (tiles_bytes.decode_u8(off + 24) & TILE_FLAG_OVERLAY) == 0:
						continue
					var ov_kind := tiles_bytes.decode_u8(off + 44)
					if ov_kind == 0 or ov_kind == OV_EXPLOSION or ov_kind == OV_BULLET:
						continue
					var wx := origin.x + tx
					var cp := tiles_bytes.decode_u32(off + 32)
					var fg_col := _unpack_rgba(tiles_bytes.decode_u32(off + 36), 0.96)
					var bg_col := _unpack_rgba(tiles_bytes.decode_u32(off + 40), 0.96)
					_cached_overlays.append([wx, wy, ov_kind, cp, fg_col, bg_col])
					if ov_kind == OV_SOUND or ov_kind == OV_CURSOR:
						has_pulsing_ov = true

	var path_pts: Array = snap.get("path_points", [])
	var sct_list: Array = snap.get("sct", [])

	# Ingest new gunfire / beam / impact / explosion VFX events (with exact burst stagger delay_ms!)
	var vfx_list: Array = snap.get("vfx_events", [])
	for v_var in vfx_list:
		var vd: Dictionary = v_var
		var vid := int(vd.get("id", 0))
		if vid <= _last_vfx_id:
			continue
		_last_vfx_id = vid
		var delay_s := float(int(vd.get("delay_ms", 0))) * 0.001
		var entry := {
			"id": vid,
			"kind": int(vd.get("kind", VFX_BLAST)),
			"ox": float(vd.get("ox", 0)),
			"oy": float(vd.get("oy", 0)),
			"tx": float(vd.get("tx", 0)),
			"ty": float(vd.get("ty", 0)),
			"radius": float(vd.get("radius", 6.0)),
			"light_intensity": float(vd.get("light_intensity", 16.0)),
			"color": _unpack_rgba(int(vd.get("rgba", 0xFF46C2FF)), 1.0),
			"arc_deg": int(vd.get("arc_deg", 0)),
			"caliber": int(vd.get("caliber", CALIBER_DEFAULT)),
			"shot_index": int(vd.get("shot_index", 0)),
			"flags": int(vd.get("flags", 0)),
			"seed": vid * 2654435761 + int(vd.get("shot_index", 0)) * 7919,
			"delay_rem": delay_s,
		}
		if delay_s <= 0.003:
			_spawn_vfx_now(entry)
		else:
			_pending_vfx.append(entry)
	while _pending_vfx.size() > 96:
		_pending_vfx.pop_front()

	_has_animated_fx = (not path_pts.is_empty()) or bool(snap.get("is_looking", false)) \
		or has_pulsing_ov or (not sct_list.is_empty())


func _spawn_vfx_now(ev: Dictionary) -> void:
	total_vfx_spawned += 1
	var kind := int(ev["kind"])
	var ox := float(ev["ox"]) + 0.5
	var oy := float(ev["oy"]) + 0.5
	var tx := float(ev["tx"]) + 0.5
	var ty := float(ev["ty"]) + 0.5
	var radius := float(ev["radius"])
	var cal := int(ev["caliber"])
	var seed_v := int(ev["seed"])
	var col: Color = ev["color"]
	var flags := int(ev["flags"])

	var dur := 0.12
	match kind:
		VFX_MUZZLE_FLASH:
			total_muzzle_flashes += 1
			dur = 0.085 if cal == CALIBER_SUPPRESSED else (0.115 if cal == CALIBER_PISTOL else 0.145)
			var dir := Vector2(tx - ox, ty - oy)
			dir = dir.normalized() if dir.length_squared() > 0.01 else Vector2(1.0, 0.0)
			var perp := Vector2(-dir.y, dir.x)
			# Camera recoil micro-shake
			var recoil_shake := 0.04 if cal == CALIBER_SUPPRESSED else (
				0.10 if cal == CALIBER_PISTOL else (
				0.18 if cal == CALIBER_RIFLE else (
				0.28 if cal == CALIBER_SHOTGUN else 0.38)))
			var dist_p := Vector2(ox, oy).distance_to(_player_visual + Vector2(0.5, 0.5))
			if dist_p < 8.0:
				_shake_trauma = minf(1.0, _shake_trauma + recoil_shake * maxf(0.15, 1.0 - dist_p / 9.0))
			# Drifting cordite gunsmoke puffs emerging from muzzle (lingers 2.3x longer indoors!)
			var is_ind_shot := (flags & VFX_FLAG_INDOORS) != 0
			var puff_cnt := 2 if cal == CALIBER_SUPPRESSED else (3 if cal == CALIBER_PISTOL else (5 if is_ind_shot else 4))
			for i in range(puff_cnt):
				var r1 := _rng_f(seed_v, 10 + i)
				var r2 := _rng_f(seed_v, 30 + i)
				var spread := (r1 - 0.5) * 0.72
				var sdir := dir.rotated(spread)
				var spd := (0.65 + r2 * 1.15) * (0.65 if cal == CALIBER_SUPPRESSED else 1.0) * (0.48 if is_ind_shot else 1.0)
				_smoke_puffs.append({
					"pos": Vector2(ox, oy) + dir * (0.14 + r1 * 0.20),
					"vel": sdir * spd + Vector2(0.05, -0.14 if is_ind_shot else -0.22),
					"drag": 2.2 if is_ind_shot else 2.9,
					"size0": 0.30 + r2 * 0.22,
					"size1": (1.28 if is_ind_shot else 0.95) + r1 * 0.55 + (0.35 if cal == CALIBER_SHOTGUN else 0.0),
					"age": 0.0,
					"dur": (0.42 + r2 * 0.34) * (2.35 if is_ind_shot else 1.0),
					"alpha": (0.28 if cal == CALIBER_SUPPRESSED else (0.38 if cal == CALIBER_SHOTGUN else 0.32)) * (1.15 if is_ind_shot else 1.0),
					"tint": Color(0.66, 0.70, 0.76, 1.0),
					"rot": r1 * TAU,
					"vrot": (r2 - 0.5) * (0.9 if is_ind_shot else 1.6),
					"tex_idx": (seed_v + i) & 3,
				})
			# Hot glowing gunpowder sparks shooting out the barrel cone
			var spark_cnt := 3 if cal == CALIBER_SUPPRESSED else (9 if cal == CALIBER_PISTOL else (15 if cal == CALIBER_SHOTGUN else 12))
			for i in range(spark_cnt):
				var r1 := _rng_f(seed_v, 100 + i)
				var r2 := _rng_f(seed_v, 200 + i)
				var spread := (r1 - 0.5) * (1.35 if cal == CALIBER_SHOTGUN else 0.85)
				var sdir := dir.rotated(spread)
				var spd := (3.2 + r2 * 6.5) * (0.55 if cal == CALIBER_SUPPRESSED else 1.0)
				_embers.append({
					"pos": Vector2(ox, oy) + dir * 0.12,
					"vel": sdir * spd,
					"drag": 6.8,
					"age": 0.0,
					"dur": 0.10 + r2 * 0.18,
					"len": 0.30 + r1 * 0.34,
					"width": 0.08 + r2 * 0.06,
					"color": Color(1.0, 0.84 + 0.14 * r1, 0.42 + 0.28 * r2, 1.0),
				})
			# Ejecting golden brass shell casing spinning out sideways from breech
			if cal != CALIBER_ENERGY and cal != CALIBER_SUPPRESSED:
				var r1 := _rng_f(seed_v, 333)
				var r2 := _rng_f(seed_v, 334)
				var eject_dir := (perp * (0.85 + 0.3 * r1) - dir * (0.35 + 0.25 * r2)).normalized()
				_debris_bits.append({
					"pos": Vector2(ox, oy) - dir * 0.18,
					"vel": eject_dir * (1.8 + r1 * 1.4),
					"drag": 3.4,
					"age": 0.0,
					"dur": 0.36 + r2 * 0.18,
					"size": 0.095,
					"color": Color(0.95, 0.78, 0.34, 1.0),
					"is_casing": true,
					"rot": r1 * TAU,
					"vrot": 18.0 + r2 * 14.0,
				})

		VFX_TRACER:
			dur = 0.12
		VFX_BEAM_LASER, VFX_BEAM_PLASMA, VFX_BEAM_LIGHTNING:
			dur = 0.24
		VFX_IMPACT_SPARK:
			dur = 0.18
			for i in range(10):
				var r1 := _rng_f(seed_v, 400 + i)
				var r2 := _rng_f(seed_v, 500 + i)
				var ang := r1 * TAU
				var spd := 2.4 + r2 * 5.2
				_embers.append({
					"pos": Vector2(ox, oy),
					"vel": Vector2(cos(ang), sin(ang)) * spd,
					"drag": 6.0,
					"age": 0.0,
					"dur": 0.14 + r2 * 0.20,
					"len": 0.28 + r1 * 0.30,
					"width": 0.08 + r2 * 0.05,
					"color": Color(1.0, 0.86, 0.44, 1.0),
				})
			_smoke_puffs.append({
				"pos": Vector2(ox, oy),
				"vel": Vector2(0.0, -0.25),
				"drag": 2.4,
				"size0": 0.24,
				"size1": 0.78,
				"age": 0.0,
				"dur": 0.42,
				"alpha": 0.32,
				"tint": Color(0.56, 0.54, 0.50, 1.0),
				"rot": _rng_f(seed_v, 555) * TAU,
				"vrot": 0.8,
				"tex_idx": seed_v & 3,
			})

		VFX_BLAST, VFX_FLASHBANG, VFX_EMP:
			total_blasts += 1
			var scale_r := clampf(radius, 1.6, 12.0)
			dur = 0.55 if kind == VFX_FLASHBANG else (0.72 if kind == VFX_EMP else clampf(0.85 + scale_r * 0.10, 0.90, 1.65))
			# Physical camera blast trauma (distance-attenuated)
			var dist_p := Vector2(ox, oy).distance_to(_player_visual + Vector2(0.5, 0.5))
			var shake_add := clampf((0.42 + scale_r * 0.09) * maxf(0.12, 1.0 - dist_p / 24.0), 0.12, 1.0)
			_shake_trauma = minf(1.0, _shake_trauma + shake_add)

			if kind == VFX_BLAST:
				var is_fiery := (flags & VFX_FLAG_FIERY) != 0 or (col.r >= 0.75 and col.b <= 0.45)
				# P2.3 Persistent charred ground crater scorch mark lingering for ~90s
				_ground_scorch.append({
					"pos": Vector2(ox, oy),
					"radius": clampf(scale_r * 0.65, 1.1, 5.5),
					"age": 0.0,
					"dur": 90.0,
					"alpha": 0.56 if is_fiery else 0.38,
				})
				while _ground_scorch.size() > 24:
					_ground_scorch.pop_front()
				# 1. Thick billowing dark charcoal/ash explosion mushroom smoke plumes!
				var smoke_cnt := clampi(int(6 + scale_r * 1.4), 8, 18)
				for i in range(smoke_cnt):
					var r1 := _rng_f(seed_v, 600 + i)
					var r2 := _rng_f(seed_v, 700 + i)
					var r3 := _rng_f(seed_v, 800 + i)
					var ang := (float(i) / float(smoke_cnt)) * TAU + (r1 - 0.5) * 0.55
					var radial_spd := (0.9 + r2 * 2.4) * sqrt(scale_r * 0.45)
					var soot := 0.14 + r3 * 0.18 if is_fiery else 0.34 + r3 * 0.20
					_smoke_puffs.append({
						"pos": Vector2(ox, oy) + Vector2(cos(ang), sin(ang)) * (scale_r * 0.14 * r1),
						"vel": Vector2(cos(ang), sin(ang)) * radial_spd + Vector2(0.06, -0.28 - 0.18 * r3),
						"drag": 2.05 + r2 * 0.9,
						"size0": maxf(0.65, scale_r * (0.28 + 0.20 * r1)),
						"size1": maxf(1.85, scale_r * (0.85 + 0.48 * r2)),
						"age": -0.04 - r1 * 0.12, # Blooms right as fireball cools!
						"dur": 1.35 + r3 * 0.85,
						"alpha": 0.72 + r2 * 0.16,
						"tint": Color(soot, soot * 0.96, soot * 0.92, 1.0) if is_fiery else Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 1.0),
						"rot": r1 * TAU,
						"vrot": (r2 - 0.5) * 1.15,
						"tex_idx": (seed_v + i) & 3,
					})
				# 2. High-velocity incandescent blast embers & sparks flying outward with air drag
				var ember_cnt := clampi(int(18 + scale_r * 3.8), 22, 44)
				for i in range(ember_cnt):
					var r1 := _rng_f(seed_v, 900 + i)
					var r2 := _rng_f(seed_v, 1000 + i)
					var r3 := _rng_f(seed_v, 1100 + i)
					var ang := r1 * TAU
					var spd := (3.5 + r2 * 9.5) * sqrt(scale_r * 0.38)
					var ecol := Color(1.0, 0.72 + 0.25 * r3, 0.22 + 0.30 * r3, 1.0) if is_fiery else Color(col.r, col.g, col.b, 1.0)
					_embers.append({
						"pos": Vector2(ox, oy) + Vector2(cos(ang), sin(ang)) * (0.15 * scale_r * r3),
						"vel": Vector2(cos(ang), sin(ang)) * spd,
						"drag": 2.6 + r3 * 2.4,
						"age": 0.0,
						"dur": 0.42 + r2 * 0.75,
						"len": 0.42 + r1 * 0.52,
						"width": 0.10 + r3 * 0.09,
						"color": ecol,
					})
				# 3. Charred flying shrapnel / rubble debris chunks
				var deb_cnt := clampi(int(8 + scale_r * 1.8), 10, 22)
				for i in range(deb_cnt):
					var r1 := _rng_f(seed_v, 1200 + i)
					var r2 := _rng_f(seed_v, 1300 + i)
					var ang := r1 * TAU
					var spd := (2.6 + r2 * 6.4) * sqrt(scale_r * 0.40)
					_debris_bits.append({
						"pos": Vector2(ox, oy),
						"vel": Vector2(cos(ang), sin(ang)) * spd,
						"drag": 2.8,
						"age": 0.0,
						"dur": 0.50 + r2 * 0.55,
						"size": 0.10 + r1 * 0.10,
						"color": Color(0.14, 0.12, 0.11, 0.92),
						"is_casing": false,
						"rot": r1 * TAU,
						"vrot": (r2 - 0.5) * 14.0,
					})

	ev["age"] = 0.0
	ev["duration"] = dur
	_active_vfx.append(ev)
	while _active_vfx.size() > 64:
		_active_vfx.pop_front()
	while _smoke_puffs.size() > 96:
		_smoke_puffs.pop_front()
	while _embers.size() > 160:
		_embers.pop_front()
	while _debris_bits.size() > 72:
		_debris_bits.pop_front()


func has_high_fps_activity() -> bool:
	return _is_gliding or (not _active_vfx.is_empty()) \
		or (not _pending_vfx.is_empty()) or (not _smoke_puffs.is_empty()) \
		or (not _debris_bits.is_empty()) or _shake_trauma > 0.005 \
		or ((not _embers.is_empty()) and _fire_emitters.is_empty())


func needs_continuous_redraw() -> bool:
	if has_high_fps_activity():
		return true
	# Throttle ambient & gentle-pulse overlays (falling leaves, pollen, fire heat wisps, campfire embers,
	# pulsing sound '?' markers, look reticle, fading traces) to ~18-20 FPS instead of 60 FPS!
	if _ambient_redraw_due:
		_ambient_redraw_due = false
		return true
	return false


func get_camera_shake_offset() -> Vector2:
	return _shake_offset


func get_active_vfx_lights() -> Array:
	if _active_vfx.is_empty():
		return []
	var out: Array = []
	for vf_var in _active_vfx:
		var vf: Dictionary = vf_var
		var li := float(vf["light_intensity"])
		if li <= 0.1:
			continue
		var u := clampf(float(vf["age"]) / maxf(0.01, float(vf["duration"])), 0.0, 1.0)
		var kind := int(vf["kind"])
		var fade := 1.0
		var col: Color = vf["color"]
		var rad := float(vf["radius"])
		if kind == VFX_MUZZLE_FLASH:
			# Blinding crisp photographic flash spike with ultra-fast incandescent falloff
			fade = pow(1.0 - u, 2.6)
			col = Color(1.0, lerpf(0.88, 0.52, u), lerpf(0.45, 0.12, u), 1.0)
			rad = clampf(rad * (0.95 + 0.25 * (1.0 - u)), 3.5, 14.0)
		elif kind == VFX_BLAST:
			# 2-stage physical detonation light: piercing white-yellow spike -> flickering orange fireball -> dying embers
			var spike := exp(-u * 14.0) * 1.45
			var flicker := 0.86 + 0.14 * sin(_anim_time * 42.0 + float(int(vf["seed"]) & 255))
			var fire_glow := pow(1.0 - u, 1.55) * flicker
			fade = maxf(spike, fire_glow)
			var temp := clampf(1.0 - u * 1.25, 0.0, 1.0)
			col = Color(1.0, lerpf(0.32, 0.92, temp), lerpf(0.06, 0.65, temp * temp), 1.0)
			rad = clampf(rad * (1.55 + 0.85 * sin(minf(1.0, u * 2.2) * PI * 0.5)), 6.5, 20.0)
		elif kind == VFX_FLASHBANG:
			fade = pow(1.0 - u, 1.8) * 1.65
			col = Color(1.0, 0.99, 0.96, 1.0)
			rad = clampf(rad * 1.8, 8.0, 22.0)
		else:
			fade = pow(1.0 - u, 1.6)
			rad = clampf(rad * (0.85 + 0.30 * (1.0 - u)), 3.2, 14.0)

		var energy := li * 1.65 * fade
		if energy <= 0.25:
			continue
		var pos := Vector2(float(vf["ox"]) + 0.5, float(vf["oy"]) + 0.5)
		if kind == VFX_BEAM_LASER or kind == VFX_BEAM_PLASMA or kind == VFX_BEAM_LIGHTNING or kind == VFX_TRACER:
			var tgt := Vector2(float(vf["tx"]) + 0.5, float(vf["ty"]) + 0.5)
			pos = pos.lerp(tgt, clampf(u * 1.6, 0.0, 1.0))
		out.append({
			"pos": pos,
			"color": col,
			"radius": rad,
			"energy": energy,
		})
	return out


func tick(delta: float) -> bool:
	var dt := clampf(delta, 0.0, 0.05)
	_anim_time += dt

	# Release staggered burst VFX right on schedule (exact RPM cadence!)
	if not _pending_vfx.is_empty():
		var still_pending: Array = []
		for pv_var in _pending_vfx:
			var pv: Dictionary = pv_var
			var rem := float(pv["delay_rem"]) - dt
			if rem <= 0.0:
				_spawn_vfx_now(pv)
			else:
				pv["delay_rem"] = rem
				still_pending.append(pv)
		_pending_vfx = still_pending

	if not _active_vfx.is_empty():
		var kept: Array = []
		for vf_var in _active_vfx:
			var vf: Dictionary = vf_var
			vf["age"] = float(vf["age"]) + dt
			if float(vf["age"]) < float(vf["duration"]):
				kept.append(vf)
		_active_vfx = kept

	if not _smoke_puffs.is_empty():
		var kept_s: Array = []
		for sp_var in _smoke_puffs:
			var sp: Dictionary = sp_var
			var age := float(sp["age"]) + dt
			sp["age"] = age
			if age >= float(sp["dur"]):
				continue
			if age >= 0.0:
				var vel: Vector2 = sp["vel"]
				sp["pos"] = (sp["pos"] as Vector2) + vel * dt
				sp["vel"] = vel * exp(-float(sp["drag"]) * dt)
				sp["rot"] = float(sp["rot"]) + float(sp["vrot"]) * dt
			kept_s.append(sp)
		_smoke_puffs = kept_s

	if not _embers.is_empty():
		var kept_e: Array = []
		for em_var in _embers:
			var em: Dictionary = em_var
			var age := float(em["age"]) + dt
			em["age"] = age
			if age >= float(em["dur"]):
				continue
			var vel: Vector2 = em["vel"]
			em["pos"] = (em["pos"] as Vector2) + vel * dt
			em["vel"] = vel * exp(-float(em["drag"]) * dt)
			kept_e.append(em)
		_embers = kept_e

	if not _debris_bits.is_empty():
		var kept_d: Array = []
		for db_var in _debris_bits:
			var db: Dictionary = db_var
			var age := float(db["age"]) + dt
			db["age"] = age
			if age >= float(db["dur"]):
				# P2.3 Landed brass shell casings persist on the floor (~45s)!
				if bool(db.get("is_casing", false)):
					_settled_casings.append({
						"pos": db["pos"],
						"rot": float(db["rot"]),
						"size": float(db["size"]),
						"age": 0.0,
						"dur": 45.0,
					})
					while _settled_casings.size() > 96:
						_settled_casings.pop_front()
				continue
			var vel: Vector2 = db["vel"]
			db["pos"] = (db["pos"] as Vector2) + vel * dt
			db["vel"] = vel * exp(-float(db["drag"]) * dt)
			db["rot"] = float(db["rot"]) + float(db["vrot"]) * dt
			kept_d.append(db)
		_debris_bits = kept_d

	# Age persistent brass casings, blast scorch & wet/snow footprints
	var has_traces := (not _settled_casings.is_empty()) or (not _ground_scorch.is_empty()) or (not _footprints.is_empty())
	if has_traces:
		_trace_redraw_accum += dt
		if _trace_redraw_accum > 0.20:
			_trace_redraw_accum = 0.0
		if not _settled_casings.is_empty():
			var kc: Array = []
			for c_var in _settled_casings:
				var c: Dictionary = c_var
				c["age"] = float(c["age"]) + dt
				if float(c["age"]) < float(c["dur"]):
					kc.append(c)
			_settled_casings = kc
		if not _ground_scorch.is_empty():
			var ks: Array = []
			for s_var in _ground_scorch:
				var s: Dictionary = s_var
				s["age"] = float(s["age"]) + dt
				if float(s["age"]) < float(s["dur"]):
					ks.append(s)
			_ground_scorch = ks
		if not _footprints.is_empty():
			var kf: Array = []
			for f_var in _footprints:
				var f: Dictionary = f_var
				f["age"] = float(f["age"]) + dt
				if float(f["age"]) < float(f["dur"]):
					kf.append(f)
			_footprints = kf
	else:
		_trace_redraw_accum = 0.0

	# P2.3 Fire thermal heat-haze wisps + rising incandescent fire embers above active fires!
	if not _fire_emitters.is_empty():
		_fire_spawn_accum += dt
		if _fire_spawn_accum >= 0.085:
			_fire_spawn_accum = 0.0
			var tick_seed := int(_anim_time * 1000.0)
			for fi in range(_fire_emitters.size()):
				var fe: Vector3 = _fire_emitters[fi]
				var r1 := _rng_f(tick_seed + fi * 131, 1)
				var r2 := _rng_f(tick_seed + fi * 131, 2)
				if r1 > 0.45 and _heat_wisps.size() < 42:
					_heat_wisps.append({
						"pos": Vector2(fe.x + (r1 - 0.5) * 0.42, fe.y - 0.10),
						"vel": Vector2(_env_wind.x * 0.25 + (r2 - 0.5) * 0.35, -0.85 - r1 * 0.65),
						"age": 0.0,
						"dur": 0.75 + r2 * 0.55,
						"size": 0.32 + clampf(fe.z * 0.03, 0.0, 0.35),
						"phase": r2 * TAU,
					})
				if r2 > 0.68 and _embers.size() < 140:
					_embers.append({
						"pos": Vector2(fe.x + (r2 - 0.5) * 0.36, fe.y - 0.05),
						"vel": Vector2(_env_wind.x * 0.55 + (r1 - 0.5) * 0.9, -1.6 - r2 * 1.4),
						"drag": 1.1,
						"age": 0.0,
						"dur": 0.55 + r1 * 0.65,
						"len": 0.16 + r2 * 0.14,
						"width": 0.065,
						"color": Color(1.0, 0.68 + 0.26 * r1, 0.18, 1.0),
					})
	if not _heat_wisps.is_empty():
		var kw: Array = []
		for hw_var in _heat_wisps:
			var hw: Dictionary = hw_var
			var age := float(hw["age"]) + dt
			hw["age"] = age
			if age < float(hw["dur"]):
				var vel: Vector2 = hw["vel"]
				var sway := sin(age * 11.0 + float(hw["phase"])) * 0.35
				hw["pos"] = (hw["pos"] as Vector2) + (vel + Vector2(sway, 0.0)) * dt
				kw.append(hw)
		_heat_wisps = kw

	# P3.1 Seasonal Outdoor Atmosphere Particles (Autumn falling leaves, Spring pollen, Summer twilight fireflies, Winter frost motes!)
	var want_motes := (not _env_under) and _env_rain < 0.35 and _env_snow < 0.35 and _has_player
	var mote_kind := -1 # 0=spring_pollen, 1=summer_firefly, 2=autumn_leaf, 3=winter_frost
	if want_motes:
		if _env_season == 2:
			mote_kind = 2
		elif _env_season == 0 and _env_daylight > 0.35:
			mote_kind = 0
		elif _env_season == 1 and _env_daylight >= 0.06 and _env_daylight <= 0.48 and _env_tree_dens > 0.08:
			mote_kind = 1
		elif _env_season == 3:
			mote_kind = 3
	if mote_kind >= 0:
		_mote_spawn_accum += dt
		var spawn_iv := 0.22 if mote_kind == 2 else (0.30 if mote_kind == 1 else 0.28)
		var max_motes := 26 if mote_kind == 2 else 18
		if _mote_spawn_accum >= spawn_iv and _ambient_motes.size() < max_motes:
			_mote_spawn_accum = 0.0
			var ms := int(_anim_time * 1000.0) ^ (_ambient_motes.size() * 7919)
			var rx := (_rng_f(ms, 11) - 0.5) * 26.0
			var ry := (_rng_f(ms, 12) - 0.5) * 18.0
			var r3 := _rng_f(ms, 13)
			var wmul := clampf(0.55 + _env_wind_spd * 0.06, 0.5, 2.2)
			var mcol := Color(0.95, 0.96, 0.72, 0.52)
			if mote_kind == 2:
				mcol = Color(0.84, 0.38 + r3 * 0.28, 0.12, 0.86) if r3 < 0.65 else Color(0.76, 0.22, 0.14, 0.86)
			elif mote_kind == 1:
				mcol = Color(0.78, 1.0, 0.42, 0.92)
			elif mote_kind == 3:
				mcol = Color(0.82, 0.91, 1.0, 0.48)
			_ambient_motes.append({
				"pos": _player_visual + Vector2(rx, ry),
				"vel": (_env_wind * (1.25 * wmul) + Vector2(0.0, 0.42)) if mote_kind == 2 else (_env_wind * (0.45 * wmul) + Vector2(0.0, -0.15 if mote_kind == 1 else 0.12)),
				"kind": mote_kind,
				"age": 0.0,
				"dur": 4.2 + r3 * 3.8,
				"size": (0.14 + r3 * 0.09) if mote_kind == 2 else (0.09 + r3 * 0.05),
				"rot": r3 * TAU,
				"vrot": (r3 - 0.5) * 4.5,
				"phase": _rng_f(ms, 14) * TAU,
				"color": mcol,
			})
	if not _ambient_motes.is_empty():
		var km: Array = []
		for m_var in _ambient_motes:
			var m: Dictionary = m_var
			var age := float(m["age"]) + dt
			m["age"] = age
			if age < float(m["dur"]):
				var mk := int(m["kind"])
				var vel: Vector2 = m["vel"]
				var ph := float(m["phase"])
				var flutter := Vector2(sin(age * 2.4 + ph) * 0.48, cos(age * 1.9 + ph) * 0.28) if mk == 2 else Vector2(sin(age * 1.6 + ph) * 0.30, cos(age * 1.3 + ph) * 0.26)
				m["pos"] = (m["pos"] as Vector2) + (vel + flutter) * dt
				m["rot"] = float(m["rot"]) + float(m["vrot"]) * dt
				km.append(m)
		_ambient_motes = km

	# Exponentially decaying micro-shake
	if _shake_trauma > 0.005:
		_shake_trauma = maxf(0.0, _shake_trauma - dt * 3.6)
		var mag := _shake_trauma * _shake_trauma * 8.5
		_shake_offset = Vector2(
			sin(_anim_time * 92.0) * mag,
			cos(_anim_time * 117.0 + 1.3) * mag * 0.82
		)
	else:
		_shake_trauma = 0.0
		_shake_offset = Vector2.ZERO

	# Schedule ~18-20 FPS ambient overlay redraw ONLY when ambient particles/wisps/pulsing overlays/traces are present
	var has_ambient := _has_animated_fx or (not _fire_emitters.is_empty()) or (not _heat_wisps.is_empty()) \
		or (not _ambient_motes.is_empty()) or (not _embers.is_empty())
	if has_ambient:
		_ambient_redraw_accum += dt
		if _ambient_redraw_accum >= 0.055:
			_ambient_redraw_accum = 0.0
			_ambient_redraw_due = true
	elif _trace_redraw_accum >= 0.14:
		_trace_redraw_accum = 0.0
		_ambient_redraw_due = true
	else:
		_ambient_redraw_accum = 0.0

	# Vanilla CCB instant grid movement: visual coordinates stay locked 1:1 to authoritative tile coordinates
	_is_gliding = false
	return false


func is_gliding() -> bool:
	return _is_gliding


func get_player_visual() -> Vector2:
	return _player_visual


func get_creature_visual(uid: int, fallback: Vector2) -> Vector2:
	if uid != 0 and _critter_visual.has(uid):
		return _critter_visual[uid]
	return fallback


static func _unpack_rgba(rgba: int, alpha_override := -1.0) -> Color:
	var a := alpha_override if alpha_override >= 0.0 else float((rgba >> 24) & 0xFF) / 255.0
	return Color(
		float(rgba & 0xFF) / 255.0,
		float((rgba >> 8) & 0xFF) / 255.0,
		float((rgba >> 16) & 0xFF) / 255.0,
		a
	)


# ==============================================================================
# PASS 1 (BLEND_MODE_MIX): Routes, Ground Scorch, Billowing Volumetric Smoke,
# Flying Debris, Brass Casings, Reticles, SCT & Monster HP Bars
# ==============================================================================
func draw_overlays(canvas: Control, snap: Dictionary, view_origin_world: Vector2,
		tile_px: float, ui_font: Font) -> void:
	if not bool(snap.get("valid", false)):
		return

	var pulse := 0.5 + 0.5 * sin(_anim_time * 5.2)

	# 0. P2.3 Persistent ground blast scorch craters, wet/snow bootprints & landed brass shell casings
	if not _ground_scorch.is_empty() and VfxTex.glow_halo != null:
		for sc_var in _ground_scorch:
			var sc: Dictionary = sc_var
			var u := clampf(float(sc["age"]) / maxf(1.0, float(sc["dur"])), 0.0, 1.0)
			var pos: Vector2 = sc["pos"]
			var p_px := (pos - view_origin_world) * tile_px
			var rad := float(sc["radius"]) * tile_px
			if p_px.x < -rad or p_px.y < -rad or p_px.x > canvas.size.x + rad or p_px.y > canvas.size.y + rad:
				continue
			var a := float(sc["alpha"]) * (1.0 - smoothstep(0.65, 1.0, u))
			canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(p_px - Vector2(rad, rad), Vector2(rad * 2.0, rad * 2.0)), false, Color(0.04, 0.035, 0.03, a))

	if not _footprints.is_empty():
		for fp_var in _footprints:
			var fp: Dictionary = fp_var
			var u := clampf(float(fp["age"]) / maxf(1.0, float(fp["dur"])), 0.0, 1.0)
			var pos: Vector2 = fp["pos"]
			var p_px := (pos - view_origin_world) * tile_px
			if p_px.x < -tile_px or p_px.y < -tile_px or p_px.x > canvas.size.x + tile_px or p_px.y > canvas.size.y + tile_px:
				continue
			var fade := 1.0 - smoothstep(0.45, 1.0, u)
			var is_snow := int(fp["kind"]) == 1
			var col := Color(0.42, 0.48, 0.58, 0.46 * fade) if is_snow else Color(0.05, 0.06, 0.08, 0.36 * fade)
			var fw := maxf(4.0, tile_px * 0.22)
			var fh := maxf(2.4, tile_px * 0.11)
			canvas.draw_set_transform(p_px, float(fp["ang"]), Vector2.ONE)
			canvas.draw_rect(Rect2(-fw * 0.5, -fh * 0.5, fw, fh), col)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if not _settled_casings.is_empty():
		for cs_var in _settled_casings:
			var cs: Dictionary = cs_var
			var u := clampf(float(cs["age"]) / maxf(1.0, float(cs["dur"])), 0.0, 1.0)
			var pos: Vector2 = cs["pos"]
			var p_px := (pos - view_origin_world) * tile_px
			if p_px.x < -tile_px or p_px.y < -tile_px or p_px.x > canvas.size.x + tile_px or p_px.y > canvas.size.y + tile_px:
				continue
			var fade := 1.0 - smoothstep(0.70, 1.0, u)
			var sz := float(cs["size"]) * tile_px
			canvas.draw_set_transform(p_px, float(cs["rot"]), Vector2.ONE)
			canvas.draw_rect(Rect2(-sz * 0.65, -sz * 0.24, sz * 1.3, sz * 0.48), Color(0.86, 0.70, 0.30, 0.85 * fade))
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 1. Auto-Move Route & Destination Preview
	var path_pts: Array = snap.get("path_points", [])
	if not path_pts.is_empty():
		_draw_route(canvas, snap, path_pts, view_origin_world, tile_px, pulse)

	# 2. Sparse cached tile overlays (aim lines, hit flashes, zones, cursors, sound ripples)
	for ov_var in _cached_overlays:
		var ov: Array = ov_var
		var sx := (float(ov[0]) - view_origin_world.x) * tile_px
		var sy := (float(ov[1]) - view_origin_world.y) * tile_px
		if sx < -tile_px or sy < -tile_px or sx > canvas.size.x + tile_px or sy > canvas.size.y + tile_px:
			continue
		_draw_tile_effect(canvas, int(ov[2]), int(ov[3]), sx, sy, tile_px, ov[4], ov[5], ui_font, pulse)

	# 2b. Ground blast scorch & expanding ground dust ring (underneath volumetric smoke)
	for vf_var in _active_vfx:
		var vf: Dictionary = vf_var
		if int(vf["kind"]) != VFX_BLAST:
			continue
		var u := clampf(float(vf["age"]) / maxf(0.01, float(vf["duration"])), 0.0, 1.0)
		var o_px := Vector2((float(vf["ox"]) + 0.5 - view_origin_world.x) * tile_px, (float(vf["oy"]) + 0.5 - view_origin_world.y) * tile_px)
		var scale_r := clampf(float(vf["radius"]), 1.6, 12.0) * tile_px
		# Darkened ground scorch shadow fading gently over duration
		var sc_rad := scale_r * (0.42 + 0.45 * minf(1.0, u * 2.5))
		var sc_a := 0.44 * pow(1.0 - u, 0.7)
		if VfxTex.glow_halo != null and sc_a > 0.02:
			canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(o_px - Vector2(sc_rad, sc_rad), Vector2(sc_rad * 2.0, sc_rad * 2.0)), false, Color(0.05, 0.04, 0.03, sc_a))
		# Expanding ground dust kick-up wave
		if u < 0.72 and VfxTex.shockwave_ring != null:
			var du := u / 0.72
			var dr := scale_r * (0.35 + 1.15 * pow(du, 0.65))
			canvas.draw_texture_rect(VfxTex.shockwave_ring, Rect2(o_px - Vector2(dr, dr), Vector2(dr * 2.0, dr * 2.0)), false, Color(0.36, 0.33, 0.28, 0.38 * (1.0 - du)))

	# 2c. Volumetric Billowing Explosion Smoke & Drifting Cordite Gunsmoke (BLEND_MODE_MIX)
	if not _smoke_puffs.is_empty() and not VfxTex.smokes.is_empty():
		for sp_var in _smoke_puffs:
			var sp: Dictionary = sp_var
			var age := float(sp["age"])
			if age < 0.0:
				continue
			var u := clampf(age / maxf(0.01, float(sp["dur"])), 0.0, 1.0)
			var pos: Vector2 = sp["pos"]
			var p_px := Vector2((pos.x - view_origin_world.x) * tile_px, (pos.y - view_origin_world.y) * tile_px)
			var sz := lerpf(float(sp["size0"]), float(sp["size1"]), pow(u, 0.58)) * tile_px
			if p_px.x < -sz or p_px.y < -sz or p_px.x > canvas.size.x + sz or p_px.y > canvas.size.y + sz:
				continue
			var fade_in := smoothstep(0.0, 0.14, u)
			var fade_out := pow(1.0 - u, 1.35)
			var a := float(sp["alpha"]) * fade_in * fade_out
			if a <= 0.01:
				continue
			var tint: Color = sp["tint"]
			var tex := VfxTex.smokes[int(sp["tex_idx"]) % VfxTex.smokes.size()]
			canvas.draw_set_transform(p_px, float(sp["rot"]), Vector2.ONE)
			canvas.draw_texture_rect(tex, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false, Color(tint.r, tint.g, tint.b, a))
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2d. Charred Shrapnel Debris & Spinning Golden Brass Shell Casings
	if not _debris_bits.is_empty():
		for db_var in _debris_bits:
			var db: Dictionary = db_var
			var u := clampf(float(db["age"]) / maxf(0.01, float(db["dur"])), 0.0, 1.0)
			var pos: Vector2 = db["pos"]
			var p_px := Vector2((pos.x - view_origin_world.x) * tile_px, (pos.y - view_origin_world.y) * tile_px)
			var sz := float(db["size"]) * tile_px
			var col: Color = db["color"]
			col.a *= (1.0 - u * u)
			canvas.draw_set_transform(p_px, float(db["rot"]), Vector2.ONE)
			if bool(db["is_casing"]):
				# Glinting brass cartridge rectangle
				var glint := 0.72 + 0.28 * absf(sin(float(db["rot"]) * 2.0))
				canvas.draw_rect(Rect2(-sz * 0.7, -sz * 0.28, sz * 1.4, sz * 0.56), Color(col.r * glint, col.g * glint, col.b * glint, col.a))
			else:
				canvas.draw_rect(Rect2(-sz * 0.5, -sz * 0.35, sz, sz * 0.7), col)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2e. P3.1 Seasonal falling leaves / pollen / frost motes (strictly outdoors & visible tiles — never over black unseen void!)
	if not _ambient_motes.is_empty():
		var origin_t: Vector2i = snap.get("origin", Vector2i.ZERO)
		var gsz_t: Vector2i = snap.get("size", Vector2i.ZERO)
		var rmask: PackedByteArray = snap.get("rain_mask", PackedByteArray())
		var vrgba: PackedByteArray = snap.get("vis_rgba", PackedByteArray())
		var has_rmask := (rmask.size() >= gsz_t.x * gsz_t.y and gsz_t.x > 0)
		var has_vis := (vrgba.size() >= gsz_t.x * gsz_t.y * 4 and gsz_t.x > 0)
		for m_var in _ambient_motes:
			var m: Dictionary = m_var
			var mk := int(m["kind"])
			if mk == 1:
				continue # Summer fireflies are drawn in luminous additive pass!
			var pos: Vector2 = m["pos"]
			# Keep falling leaves / pollen strictly outdoors & inside visible FOV!
			if has_rmask or has_vis:
				var mtx := int(floor(pos.x)) - origin_t.x
				var mty := int(floor(pos.y)) - origin_t.y
				if mtx < 0 or mty < 0 or mtx >= gsz_t.x or mty >= gsz_t.y:
					continue
				var midx := mty * gsz_t.x + mtx
				if has_rmask and rmask[midx] == 0:
					continue
				if has_vis and vrgba[midx * 4] < 130:
					continue
			var p_px := (pos - view_origin_world) * tile_px
			if p_px.x < -16.0 or p_px.y < -16.0 or p_px.x > canvas.size.x + 16.0 or p_px.y > canvas.size.y + 16.0:
				continue
			var u := clampf(float(m["age"]) / maxf(0.5, float(m["dur"])), 0.0, 1.0)
			var fade := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.80, 1.0, u))
			var col: Color = m["color"]
			var sz := maxf(2.2, float(m["size"]) * tile_px)
			if mk == 2:
				# Organic drifting autumn leaf silhouette
				canvas.draw_set_transform(p_px, float(m["rot"]), Vector2.ONE)
				canvas.draw_rect(Rect2(-sz * 0.55, -sz * 0.28, sz * 1.1, sz * 0.56), Color(col.r, col.g, col.b, col.a * fade))
				canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				canvas.draw_circle(p_px, sz * 0.45, Color(col.r, col.g, col.b, col.a * fade))

	# 3. Look-around / aiming center cursor
	if bool(snap.get("is_looking", false)):
		var center: Vector2i = snap.get("center", Vector2i.ZERO)
		var cx := (float(center.x) - view_origin_world.x) * tile_px
		var cy := (float(center.y) - view_origin_world.y) * tile_px
		var ccol := Color(1.0, 0.92, 0.25, 0.78 + 0.22 * pulse)
		_draw_corner_reticle(canvas, Rect2(cx + 1.0, cy + 1.0, tile_px - 2.0, tile_px - 2.0), ccol, 2.0)

	# 4. Scrolling Combat Text (SCT)
	var sct_list: Array = snap.get("sct", [])
	if ui_font != null and not sct_list.is_empty():
		var fsize := maxi(12, int(tile_px * 0.48))
		for s_var in sct_list:
			var sd: Dictionary = s_var
			var txt := str(sd.get("text", ""))
			if txt.is_empty():
				continue
			var wx := float(sd.get("x", 0))
			var wy := float(sd.get("y", 0))
			var step := float(sd.get("step", 0))
			var max_st := maxf(1.0, float(sd.get("max_steps", 8)))
			var alpha := clampf(1.25 - (step / max_st), 0.25, 1.0)
			var sx := (wx - view_origin_world.x) * tile_px
			var sy := (wy - view_origin_world.y + 0.72) * tile_px
			if sx < -tile_px * 3.0 or sy < -tile_px or sx > canvas.size.x + tile_px * 3.0 or sy > canvas.size.y + tile_px:
				continue
			var col := _unpack_rgba(int(sd.get("rgba", 0xFFFFFFFF)), alpha)
			var shadow := Color(0.0, 0.0, 0.0, alpha * 0.85)
			canvas.draw_string(ui_font, Vector2(sx + 1.0, sy + 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, shadow)
			canvas.draw_string(ui_font, Vector2(sx, sy), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, col)

	# 5. Subtle damage indicator bar under injured creatures
	var creatures: Array = snap.get("creatures", [])
	for c_var in creatures:
		var cd: Dictionary = c_var
		var hp_pct := int(cd.get("hp_pct", 100))
		var cflags := int(cd.get("flags", 0))
		if hp_pct >= 100 or (cflags & CRITTER_PLAYER) != 0:
			continue
		var uid := int(cd.get("uid", 0))
		var vpos := get_creature_visual(uid, Vector2(float(cd.get("x", 0)), float(cd.get("y", 0))))
		var sx := (vpos.x - view_origin_world.x) * tile_px
		var sy := (vpos.y - view_origin_world.y) * tile_px
		if sx < -tile_px or sy < -tile_px or sx > canvas.size.x + tile_px or sy > canvas.size.y + tile_px:
			continue
		var bw := tile_px - 4.0
		var fill_w := bw * clampf(float(hp_pct) / 100.0, 0.0, 1.0)
		canvas.draw_rect(Rect2(sx + 2.0, sy + tile_px - 4.0, bw, 3.0), Color(0.0, 0.0, 0.0, 0.82))
		var bar_col := Color(0.28, 0.90, 0.30) if hp_pct > 60 else (Color(0.95, 0.80, 0.18) if hp_pct > 30 else Color(0.95, 0.24, 0.22))
		canvas.draw_rect(Rect2(sx + 2.0, sy + tile_px - 4.0, fill_w, 3.0), bar_col)


# ==============================================================================
# PASS 2 (BLEND_MODE_ADD): Luminous Photorealistic Fireballs, Supersonic Muzzle
# Plumes, Optical Bloom Halos, Shockwaves, Incandescent Embers, Tracers & Beams!
# ==============================================================================
func draw_additive_vfx(canvas: Control, view_origin_world: Vector2, tpx: float) -> void:
	var has_fireflies := false
	for m_var in _ambient_motes:
		if int((m_var as Dictionary)["kind"]) == 1:
			has_fireflies = true
			break
	if _active_vfx.is_empty() and _embers.is_empty() and _heat_wisps.is_empty() and not has_fireflies:
		return
	VfxTex.ensure_ready()

	# P2.3 Luminous shimmering thermal heat-haze glow above active fires (zero dark grey blotches!)
	if not _heat_wisps.is_empty() and VfxTex.glow_halo != null:
		for hw_var in _heat_wisps:
			var hw: Dictionary = hw_var
			var u := clampf(float(hw["age"]) / maxf(0.1, float(hw["dur"])), 0.0, 1.0)
			var p_px := ((hw["pos"] as Vector2) - view_origin_world) * tpx
			var r := float(hw["size"]) * (0.45 + 0.65 * u) * tpx
			if p_px.x < -r or p_px.y < -r or p_px.x > canvas.size.x + r or p_px.y > canvas.size.y + r:
				continue
			var a := sin(u * PI) * 0.15
			canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(p_px - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, Color(1.0, 0.62, 0.20, a))

	if has_fireflies and VfxTex.glow_halo != null:
		for m_var in _ambient_motes:
			var m: Dictionary = m_var
			if int(m["kind"]) != 1:
				continue
			var pos: Vector2 = m["pos"]
			var p_px := (pos - view_origin_world) * tpx
			if p_px.x < -20.0 or p_px.y < -20.0 or p_px.x > canvas.size.x + 20.0 or p_px.y > canvas.size.y + 20.0:
				continue
			var u := clampf(float(m["age"]) / maxf(0.5, float(m["dur"])), 0.0, 1.0)
			var blink := pow(0.5 + 0.5 * sin(_anim_time * 3.2 + float(m["phase"])), 2.4)
			var a := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.80, 1.0, u)) * blink * 0.85
			if a > 0.02:
				var r := maxf(4.5, tpx * 0.22)
				canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(p_px - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, Color(0.75, 1.0, 0.36, a))

	for vf_var in _active_vfx:
		var vf: Dictionary = vf_var
		var kind := int(vf["kind"])
		var u := clampf(float(vf["age"]) / maxf(0.01, float(vf["duration"])), 0.0, 1.0)
		var inv := 1.0 - u
		var col: Color = vf["color"]
		var o_px := Vector2((float(vf["ox"]) + 0.5 - view_origin_world.x) * tpx, (float(vf["oy"]) + 0.5 - view_origin_world.y) * tpx)
		var t_px := Vector2((float(vf["tx"]) + 0.5 - view_origin_world.x) * tpx, (float(vf["ty"]) + 0.5 - view_origin_world.y) * tpx)
		var seed_v := int(vf["seed"])
		var cal := int(vf["caliber"])

		match kind:
			VFX_MUZZLE_FLASH:
				var dir := t_px - o_px
				dir = dir.normalized() if dir.length_squared() >= 1.0 else Vector2(1.0, 0.0)
				var base_ang := dir.angle() + (_rng_f(seed_v, 1) - 0.5) * 0.10
				var scale_cal := 0.45 if cal == CALIBER_SUPPRESSED else (
					0.88 if cal == CALIBER_PISTOL else (
					1.22 if cal == CALIBER_RIFLE else (
					1.42 if cal == CALIBER_SHOTGUN else 1.65)))
				# Ultra-snappy photographic burn curve (peaks instantly, lingers as hot ionized gas)
				var core_a := pow(inv, 2.3)
				var bloom_a := pow(inv, 1.85)
				# 1. Soft optical bloom halo lighting the barrel area
				var halo_r := tpx * (1.15 * scale_cal * (0.72 + 0.35 * inv))
				canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(o_px - Vector2(halo_r, halo_r), Vector2(halo_r * 2.0, halo_r * 2.0)), false, Color(1.0, 0.62, 0.18, 0.52 * bloom_a))
				# 2. Photographic asymmetric forward supersonic muzzle-flash flame plume
				if not VfxTex.muzzle_plumes.is_empty():
					var ptex := VfxTex.muzzle_plumes[seed_v % VfxTex.muzzle_plumes.size()]
					var flip_y := -1.0 if ((seed_v >> 3) & 1) != 0 else 1.0
					var pw := tpx * 1.95 * scale_cal * (0.75 + 0.32 * inv)
					var ph := tpx * 1.24 * scale_cal * (0.72 + 0.34 * inv)
					canvas.draw_set_transform(o_px, base_ang, Vector2(1.0, flip_y))
					canvas.draw_texture_rect(ptex, Rect2(-pw * 0.14, -ph * 0.5, pw, ph), false, Color(1.0, 0.92, 0.76, 0.96 * core_a))
					# Compensator / muzzle-brake side flame vents (authentic on rifles, SMGs, heavy firearms)
					if cal == CALIBER_RIFLE or cal == CALIBER_HEAVY or cal == CALIBER_DEFAULT:
						var bw := tpx * 1.05 * scale_cal * (0.70 + 0.35 * inv)
						canvas.draw_texture_rect(VfxTex.muzzle_baffle, Rect2(-bw * 0.38, -bw * 0.5, bw, bw), false, Color(1.0, 0.78, 0.38, 0.78 * core_a))
					# Extra turbulent orange fireball blast for shotguns & heavy caliber
					if (cal == CALIBER_SHOTGUN or cal == CALIBER_HEAVY) and not VfxTex.fireballs.is_empty():
						var ftex := VfxTex.fireballs[seed_v & 3]
						var fr := tpx * 0.95 * scale_cal * (0.55 + 0.55 * u)
						canvas.draw_texture_rect(ftex, Rect2(tpx * 0.12 - fr * 0.35, -fr * 0.5, fr, fr), false, Color(1.0, 0.72, 0.32, 0.72 * pow(inv, 1.45)))
					canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				# 3. Blinding white-yellow core point right at muzzle crown
				var cr := tpx * 0.42 * scale_cal * core_a
				canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(o_px - Vector2(cr, cr), Vector2(cr * 2.0, cr * 2.0)), false, Color(1.0, 0.98, 0.88, 0.92 * core_a))

			VFX_TRACER:
				var seg := t_px - o_px
				var slen := seg.length()
				if slen >= 2.0:
					var head_t := clampf(u * 1.55, 0.0, 1.0)
					var tail_t := clampf(head_t - 0.46, 0.0, 1.0)
					var p_tail := o_px.lerp(t_px, tail_t)
					var p_head := o_px.lerp(t_px, head_t)
					var a := pow(inv, 0.80)
					var span := p_head.distance_to(p_tail)
					if span > 2.0 and VfxTex.spark_streak != null:
						var thick := maxf(5.0, tpx * 0.24)
						canvas.draw_set_transform(p_tail, (p_head - p_tail).angle(), Vector2.ONE)
						canvas.draw_texture_rect(VfxTex.spark_streak, Rect2(0.0, -thick * 0.5, span, thick), false, Color(1.0, 0.88, 0.56, 0.92 * a))
						canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					var hr := maxf(4.0, tpx * 0.20)
					canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(p_head - Vector2(hr, hr), Vector2(hr * 2.0, hr * 2.0)), false, Color(1.0, 0.94, 0.72, 0.85 * a))

			VFX_BEAM_LASER, VFX_BEAM_PLASMA:
				var a := pow(inv, 1.15)
				var w_outer := maxf(8.0, tpx * 0.36) * (0.55 + 0.45 * inv)
				var w_mid := maxf(3.2, tpx * 0.14) * (0.60 + 0.40 * inv)
				canvas.draw_line(o_px, t_px, Color(col.r, col.g, col.b, 0.42 * a), w_outer, true)
				canvas.draw_line(o_px, t_px, Color(col.r, col.g, col.b, 0.92 * a), w_mid, true)
				canvas.draw_line(o_px, t_px, Color(1.0, 0.97, 0.98, 0.98 * a), maxf(1.5, w_mid * 0.44), true)
				var r0 := tpx * 0.48 * a
				var r1 := tpx * 0.70 * a
				canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(o_px - Vector2(r0, r0), Vector2(r0 * 2.0, r0 * 2.0)), false, Color(col.r, col.g, col.b, 0.85 * a))
				canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(t_px - Vector2(r1, r1), Vector2(r1 * 2.0, r1 * 2.0)), false, Color(1.0, 0.94, 0.92, 0.95 * a))

			VFX_BEAM_LIGHTNING:
				var a := pow(inv, 1.05)
				var seg := t_px - o_px
				var dist := seg.length()
				var steps := clampi(int(dist / maxf(10.0, tpx * 0.42)), 3, 18)
				var perp := Vector2(-seg.y, seg.x).normalized() if dist > 1.0 else Vector2(0.0, 1.0)
				var pts := PackedVector2Array()
				pts.append(o_px)
				var tick_salt := int(_anim_time * 48.0)
				for k in range(1, steps):
					var f := float(k) / float(steps)
					var hk := ((seed_v ^ (k * 4999) ^ (tick_salt * 131)) & 0xFF)
					var jitter := (float(hk) / 255.0 - 0.5) * tpx * 0.58
					pts.append(o_px.lerp(t_px, f) + perp * jitter)
				pts.append(t_px)
				canvas.draw_polyline(pts, Color(col.r, col.g, col.b, 0.52 * a), maxf(6.0, tpx * 0.25), true)
				canvas.draw_polyline(pts, Color(0.90, 0.97, 1.0, 0.98 * a), maxf(2.0, tpx * 0.08), true)
				var rt := tpx * 0.64 * a
				canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(t_px - Vector2(rt, rt), Vector2(rt * 2.0, rt * 2.0)), false, Color(0.84, 0.96, 1.0, 0.90 * a))

			VFX_IMPACT_SPARK:
				var a := pow(inv, 1.5)
				var ir := tpx * 0.55 * a
				canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(o_px - Vector2(ir, ir), Vector2(ir * 2.0, ir * 2.0)), false, Color(1.0, 0.84, 0.36, 0.85 * a))

			VFX_BLAST:
				var scale_r := clampf(float(vf["radius"]), 1.6, 12.0) * tpx
				var is_fiery := (int(vf["flags"]) & VFX_FLAG_FIERY) != 0 or (col.r >= 0.75 and col.b <= 0.45)
				# 1. Instant blinding detonation core flash (0..18% of duration)
				if u < 0.22:
					var fu := u / 0.22
					var flash_r := scale_r * (0.75 + 0.95 * pow(fu, 0.45))
					var flash_a := pow(1.0 - fu, 1.8)
					canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(o_px - Vector2(flash_r, flash_r), Vector2(flash_r * 2.0, flash_r * 2.0)), false, Color(1.0, 0.97, 0.84, 0.96 * flash_a))
				# 2. Fast supersonic shockwave compression ring (0..42% of duration)
				if u < 0.44 and VfxTex.shockwave_ring != null:
					var su := u / 0.44
					var sw_r := scale_r * (0.28 + 1.48 * pow(su, 0.62))
					var sw_a := pow(1.0 - su, 1.25) * 0.82
					var sw_col := Color(1.0, 0.88, 0.70, sw_a) if is_fiery else Color(col.r, col.g, col.b, sw_a)
					canvas.draw_texture_rect(VfxTex.shockwave_ring, Rect2(o_px - Vector2(sw_r, sw_r), Vector2(sw_r * 2.0, sw_r * 2.0)), false, sw_col)
				# 3. Wide warm atmospheric bloom halo during roaring fireball phase
				if u < 0.88:
					var bu := u / 0.88
					var br := scale_r * (1.25 + 0.55 * sin(minf(1.0, bu * 1.8) * PI * 0.5))
					var ba := pow(1.0 - bu, 1.45) * 0.62
					var bcol := Color(1.0, lerpf(0.55, 0.20, bu), lerpf(0.14, 0.02, bu), ba) if is_fiery else Color(col.r, col.g, col.b, ba)
					canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(o_px - Vector2(br, br), Vector2(br * 2.0, br * 2.0)), false, bcol)
				# 4. Multi-lobe counter-rotating turbulent FBM fireballs cooling along blackbody curve!
				if u < 0.78 and not VfxTex.fireballs.is_empty():
					var fu := u / 0.78
					var lobe_cnt := clampi(int(4 + float(vf["radius"]) * 0.7), 5, 9)
					var expand := pow(minf(1.0, fu * 1.65), 0.46)
					var fade_fire := pow(1.0 - fu, 1.35)
					for l in range(lobe_cnt):
						var r1 := _rng_f(seed_v, 2000 + l)
						var r2 := _rng_f(seed_v, 2100 + l)
						var ang := (float(l) / float(lobe_cnt)) * TAU + r1 * 0.8
						var offset_r := 0.0 if l == 0 else scale_r * (0.24 + 0.34 * r2) * expand
						var lpos := o_px + Vector2(cos(ang), sin(ang)) * offset_r + Vector2(0.0, -tpx * 0.22 * fu)
						var lsz := scale_r * (1.22 if l == 0 else (0.72 + 0.40 * r1)) * (0.36 + 0.82 * expand)
						var rot := r1 * TAU + fu * (1.4 if (l & 1) == 0 else -1.4)
						var tex := VfxTex.fireballs[(seed_v + l) % VfxTex.fireballs.size()]
						# Blackbody cooling tint: blinding white-gold -> roaring amber -> deep crimson embers
						var t_cool := clampf(fu * 1.15 + r2 * 0.12, 0.0, 1.0)
						var lcol := Color(1.0, lerpf(0.98, 0.34, t_cool), lerpf(0.86, 0.06, pow(t_cool, 0.85)), fade_fire * (0.94 if l == 0 else 0.78)) if is_fiery \
							else Color(lerpf(1.0, col.r, t_cool), lerpf(1.0, col.g, t_cool), lerpf(1.0, col.b, t_cool), fade_fire * 0.85)
						canvas.draw_set_transform(lpos, rot, Vector2.ONE)
						canvas.draw_texture_rect(tex, Rect2(-lsz * 0.5, -lsz * 0.5, lsz, lsz), false, lcol)
					canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

			VFX_FLASHBANG:
				var scale_r := clampf(float(vf["radius"]), 3.0, 12.0) * tpx
				var flash_r := scale_r * (0.85 + 1.15 * pow(u, 0.42))
				var fa := pow(inv, 1.65)
				canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(o_px - Vector2(flash_r, flash_r), Vector2(flash_r * 2.0, flash_r * 2.0)), false, Color(1.0, 0.99, 0.96, 0.98 * fa))
				if u < 0.50 and VfxTex.shockwave_ring != null:
					var su := u / 0.50
					var sr := scale_r * (0.25 + 1.35 * su)
					canvas.draw_texture_rect(VfxTex.shockwave_ring, Rect2(o_px - Vector2(sr, sr), Vector2(sr * 2.0, sr * 2.0)), false, Color(0.96, 0.98, 1.0, 0.72 * (1.0 - su)))

			VFX_EMP:
				var scale_r := clampf(float(vf["radius"]), 2.5, 11.0) * tpx
				var sr := scale_r * (0.25 + 1.32 * pow(u, 0.65))
				var ea := pow(inv, 1.2)
				canvas.draw_texture_rect(VfxTex.glow_halo, Rect2(o_px - Vector2(sr * 0.75, sr * 0.75), Vector2(sr * 1.5, sr * 1.5)), false, Color(0.35, 0.68, 1.0, 0.46 * ea))
				if VfxTex.shockwave_ring != null:
					canvas.draw_texture_rect(VfxTex.shockwave_ring, Rect2(o_px - Vector2(sr, sr), Vector2(sr * 2.0, sr * 2.0)), false, Color(0.55, 0.85, 1.0, 0.92 * ea))

	# Flying incandescent sparks & glowing blast embers (motion-blurred along velocity!)
	if not _embers.is_empty() and VfxTex.spark_streak != null:
		for em_var in _embers:
			var em: Dictionary = em_var
			var u := clampf(float(em["age"]) / maxf(0.01, float(em["dur"])), 0.0, 1.0)
			var pos: Vector2 = em["pos"]
			var vel: Vector2 = em["vel"]
			var p_px := Vector2((pos.x - view_origin_world.x) * tpx, (pos.y - view_origin_world.y) * tpx)
			if p_px.x < -tpx * 2.0 or p_px.y < -tpx * 2.0 or p_px.x > canvas.size.x + tpx * 2.0 or p_px.y > canvas.size.y + tpx * 2.0:
				continue
			var spd := vel.length()
			var streak_len := maxf(3.0, (float(em["len"]) * clampf(spd * 0.24, 0.35, 1.6)) * tpx)
			var streak_w := maxf(2.0, float(em["width"]) * tpx)
			var col: Color = em["color"]
			var a := pow(1.0 - u, 1.25)
			canvas.draw_set_transform(p_px, vel.angle(), Vector2.ONE)
			canvas.draw_texture_rect(VfxTex.spark_streak, Rect2(-streak_len * 0.82, -streak_w * 0.5, streak_len, streak_w), false, Color(col.r, col.g * (1.0 - u * 0.35), col.b * (1.0 - u * 0.65), a))
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_route(canvas: Control, snap: Dictionary, path_pts: Array, view_origin_world: Vector2,
		tile_px: float, pulse: float) -> void:
	var is_active := int((path_pts[0] as Dictionary).get("kind", PATH_PREVIEW)) == PATH_AUTOMOVE
	var line_col := Color(0.32, 0.92, 0.72, 0.82) if is_active else Color(0.42, 0.80, 1.0, 0.74)
	var glow_col := Color(line_col.r, line_col.g, line_col.b, 0.22)

	var pts := PackedVector2Array()
	var p_vis := _player_visual if _has_player else Vector2(snap.get("player", Vector2i.ZERO))
	pts.append((p_vis + Vector2(0.5, 0.5) - view_origin_world) * tile_px)
	for p_var in path_pts:
		var pd: Dictionary = p_var
		var w := Vector2(float(pd.get("x", 0)) + 0.5, float(pd.get("y", 0)) + 0.5)
		pts.append((w - view_origin_world) * tile_px)

	if pts.size() >= 2:
		canvas.draw_polyline(pts, glow_col, maxf(4.0, tile_px * 0.22), true)
		canvas.draw_polyline(pts, line_col, maxf(2.0, tile_px * 0.08), true)

	for i in range(path_pts.size()):
		var pd: Dictionary = path_pts[i]
		var wx := float(pd.get("x", 0))
		var wy := float(pd.get("y", 0))
		var center := Vector2((wx + 0.5 - view_origin_world.x) * tile_px, (wy + 0.5 - view_origin_world.y) * tile_px)
		var kind := int(pd.get("kind", PATH_PREVIEW))
		if kind == PATH_DESTINATION or i == path_pts.size() - 1:
			var r := tile_px * (0.34 + 0.06 * pulse)
			var dest_col := Color(1.0, 0.94, 0.42, 0.92) if is_active else Color(0.55, 0.92, 1.0, 0.90)
			canvas.draw_arc(center, r, 0.0, TAU, 24, Color(dest_col.r, dest_col.g, dest_col.b, 0.28), 3.5, true)
			canvas.draw_arc(center, r * 0.78, 0.0, TAU, 24, dest_col, 1.8, true)
			var d := tile_px * 0.14
			var diamond := PackedVector2Array([
				center + Vector2(0, -d), center + Vector2(d, 0),
				center + Vector2(0, d), center + Vector2(-d, 0),
			])
			canvas.draw_colored_polygon(diamond, dest_col)
		else:
			var wave := 0.5 + 0.5 * sin(_anim_time * 7.0 - float(i) * 0.7)
			var br := maxf(2.0, tile_px * (0.08 + 0.04 * wave))
			canvas.draw_circle(center, br, Color(line_col.r, line_col.g, line_col.b, 0.55 + 0.40 * wave))


func _draw_tile_effect(canvas: Control, kind: int, cp: int, sx: float, sy: float, tpx: float,
		fg_col: Color, bg_col: Color, ui_font: Font, pulse: float) -> void:
	var center := Vector2(sx + tpx * 0.5, sy + tpx * 0.5)
	var rect := Rect2(sx + 1.0, sy + 1.0, tpx - 2.0, tpx - 2.0)

	match kind:
		OV_HIT_FLASH:
			var fcol := Color(bg_col.r, bg_col.g, bg_col.b, 0.42)
			canvas.draw_rect(rect, fcol)
			canvas.draw_rect(rect, Color(bg_col.r, bg_col.g, bg_col.b, 0.88), false, 2.0)
		OV_ZONE:
			canvas.draw_rect(rect, Color(0.25, 0.88, 0.40, 0.22))
			canvas.draw_rect(rect, Color(0.40, 0.95, 0.52, 0.65), false, 1.0)
		OV_HIGHLIGHT:
			var hcol := Color(0.95, 0.86, 0.32, 0.22) if (bg_col.r + bg_col.g > 0.8) else Color(bg_col.r, bg_col.g, bg_col.b, 0.24)
			canvas.draw_rect(rect, hcol)
			canvas.draw_rect(rect, Color(hcol.r, hcol.g, hcol.b, 0.70), false, 1.2)
		OV_CURSOR:
			var ccol := Color(0.40, 1.0, 0.62, 0.88) if cp == 88 else Color(0.45, 0.92, 1.0, 0.88)
			_draw_corner_reticle(canvas, rect, ccol, 1.8)
		OV_SOUND:
			var rad := tpx * (0.28 + 0.18 * pulse)
			canvas.draw_arc(center, rad, 0.0, TAU, 20, Color(fg_col.r, fg_col.g, fg_col.b, 0.65 * (1.0 - pulse * 0.5)), 1.5, true)
			if ui_font != null:
				canvas.draw_string(ui_font, Vector2(sx + tpx * 0.28, sy + tpx * 0.76), "?", HORIZONTAL_ALIGNMENT_LEFT, -1.0, maxi(12, int(tpx * 0.60)), fg_col)


static func _draw_corner_reticle(canvas: Control, r: Rect2, col: Color, w: float) -> void:
	var arm := minf(r.size.x, r.size.y) * 0.30
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	canvas.draw_line(Vector2(x0, y0), Vector2(x0 + arm, y0), col, w)
	canvas.draw_line(Vector2(x0, y0), Vector2(x0, y0 + arm), col, w)
	canvas.draw_line(Vector2(x1, y0), Vector2(x1 - arm, y0), col, w)
	canvas.draw_line(Vector2(x1, y0), Vector2(x1, y0 + arm), col, w)
	canvas.draw_line(Vector2(x0, y1), Vector2(x0 + arm, y1), col, w)
	canvas.draw_line(Vector2(x0, y1), Vector2(x0, y1 - arm), col, w)
	canvas.draw_line(Vector2(x1, y1), Vector2(x1 - arm, y1), col, w)
	canvas.draw_line(Vector2(x1, y1), Vector2(x1, y1 - arm), col, w)
