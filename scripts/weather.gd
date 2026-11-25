extends RefCounted

enum Kind { CLEAR, CLOUDY, LIGHT_RAIN, HEAVY_RAIN, LIGHT_SNOW, HEAVY_SNOW }

const NAMES := {
	Kind.CLEAR: "晴朗",
	Kind.CLOUDY: "多云",
	Kind.LIGHT_RAIN: "烟雨",
	Kind.HEAVY_RAIN: "大雨",
	Kind.LIGHT_SNOW: "小雪",
	Kind.HEAVY_SNOW: "大雪",
}

const BADGE_COLORS := {
	Kind.CLEAR: [Color("e6cf8b"), Color("23251a")],
	Kind.CLOUDY: [Color("b2c0b8"), Color("1b2320")],
	Kind.LIGHT_RAIN: [Color("8cc7d6"), Color("16242a")],
	Kind.HEAVY_RAIN: [Color("72b4d4"), Color("131f28")],
	Kind.LIGHT_SNOW: [Color("d8e8f4"), Color("1b242c")],
	Kind.HEAVY_SNOW: [Color("edf5fc"), Color("1d2732")],
}

var override_kind: int = -1 # -1 = auto by calendar/seed
var current_kind: int = Kind.CLEAR
var rain := 0.0
var snow := 0.0
var cloud := 0.0
var wetness := 0.0
var snow_cover := 0.0
var puddle_phase := 0.0 # Continuous evolving puddle basin drift over real & game time
var wind := Vector2(-0.35, 0.14)

var _target_rain := 0.0
var _target_snow := 0.0
var _target_cloud := 0.0
var _target_wet := 0.0
var _target_snow_cover := 0.0
var _last_game_minutes := -1


static func auto_kind_for(sky: Dictionary, seed: int) -> int:
	var block := int(sky.day_index) * 6 + int(floor(float(sky.hour) / 4.0))
	var n := ((block * 0x9e3779b9) ^ (seed * 0x85ebca6b) ^ 0x4a2f91) & 0xffffffff
	n = ((n ^ (n >> 16)) * 0x7feb352d) & 0xffffffff
	var roll := int((n ^ (n >> 15)) % 100)
	match String(sky.season):
		"春":
			if roll < 44: return Kind.CLEAR
			if roll < 68: return Kind.CLOUDY
			if roll < 92: return Kind.LIGHT_RAIN
			return Kind.HEAVY_RAIN
		"夏":
			if roll < 52: return Kind.CLEAR
			if roll < 74: return Kind.CLOUDY
			if roll < 88: return Kind.LIGHT_RAIN
			return Kind.HEAVY_RAIN
		"秋":
			if roll < 50: return Kind.CLEAR
			if roll < 78: return Kind.CLOUDY
			return Kind.LIGHT_RAIN
		"冬":
			if roll < 36: return Kind.CLEAR
			if roll < 58: return Kind.CLOUDY
			if roll < 84: return Kind.LIGHT_SNOW
			return Kind.HEAVY_SNOW
	return Kind.CLEAR


func set_override(kind: int, sky: Dictionary, seed: int, instant := true) -> void:
	override_kind = kind
	sync(sky, seed, instant)


func sync(sky: Dictionary, seed: int, instant := false, total_minutes := -1) -> void:
	current_kind = override_kind if override_kind >= 0 else auto_kind_for(sky, seed)
	_target_rain = 0.0
	_target_snow = 0.0
	_target_cloud = 0.0
	_target_wet = 0.0
	_target_snow_cover = 0.0
	match current_kind:
		Kind.CLEAR:
			_target_cloud = 0.0
			_target_snow_cover = 0.28 if String(sky.season) == "冬" and override_kind < 0 else 0.0
		Kind.CLOUDY:
			_target_cloud = 0.55
			_target_wet = 0.12 if String(sky.season) != "冬" else 0.0
			_target_snow_cover = 0.35 if String(sky.season) == "冬" and override_kind < 0 else 0.0
		Kind.LIGHT_RAIN:
			_target_rain = 0.55
			_target_cloud = 0.72
			_target_wet = 0.72
		Kind.HEAVY_RAIN:
			_target_rain = 1.0
			_target_cloud = 0.90
			_target_wet = 1.0
		Kind.LIGHT_SNOW:
			_target_snow = 0.55
			_target_cloud = 0.65
			_target_snow_cover = 0.65
		Kind.HEAVY_SNOW:
			_target_snow = 1.0
			_target_cloud = 0.82
			_target_snow_cover = 1.0
	if instant:
		rain = _target_rain
		snow = _target_snow
		cloud = _target_cloud
		wetness = _target_wet
		snow_cover = _target_snow_cover
	elif total_minutes >= 0 and _last_game_minutes >= 0 and total_minutes != _last_game_minutes:
		var dt_min := clampf(float(absi(total_minutes - _last_game_minutes)), 0.0, 240.0)
		var step := 1.0 - exp(-dt_min / 28.0)
		rain = lerpf(rain, _target_rain, clampf(step * 1.6, 0.0, 1.0))
		snow = lerpf(snow, _target_snow, clampf(step * 1.6, 0.0, 1.0))
		cloud = lerpf(cloud, _target_cloud, clampf(step * 1.4, 0.0, 1.0))
		wetness = lerpf(wetness, _target_wet, step)
		snow_cover = lerpf(snow_cover, _target_snow_cover, step)
		puddle_phase += dt_min * (0.018 if rain > 0.05 else 0.004)
	if total_minutes >= 0:
		_last_game_minutes = total_minutes
	wind = Vector2(-0.42 - 0.30 * rain, 0.16 + 0.08 * snow)


func tick_visual(delta: float) -> void:
	# Decoupled FPS visual evolution: puddles slowly accumulate/evaporate & shift organically in real time.
	var rate := delta * 0.16
	rain = move_toward(rain, _target_rain, rate * 2.0)
	snow = move_toward(snow, _target_snow, rate * 2.0)
	cloud = move_toward(cloud, _target_cloud, rate * 1.5)
	if rain > 0.05:
		# Rain fills puddles dynamically up to target wetness and gently oscillates level.
		wetness = clampf(move_toward(wetness, _target_wet, delta * 0.065), 0.0, 1.0)
		puddle_phase += delta * (0.045 + 0.055 * rain)
	else:
		# Dry weather slowly evaporates remaining puddles.
		wetness = move_toward(wetness, _target_wet, delta * 0.032)
		if wetness > 0.01:
			puddle_phase += delta * 0.015
	if snow > 0.05:
		snow_cover = clampf(move_toward(snow_cover, _target_snow_cover, delta * 0.055), 0.0, 1.0)
	else:
		snow_cover = move_toward(snow_cover, _target_snow_cover, delta * 0.025)


static func _hash21(p: Vector2) -> float:
	var hx := fposmod(p.x * 0.1031, 1.0)
	var hy := fposmod(p.y * 0.1031, 1.0)
	var hz := fposmod(p.x * 0.1031, 1.0)
	var d := hx * (hy + 33.33) + hy * (hz + 33.33) + hz * (hx + 33.33)
	return fposmod((hx + d + hy + d) * (hz + d), 1.0)


static func _noise2(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	f = Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	var a := _hash21(i)
	var b := _hash21(i + Vector2(1.0, 0.0))
	var c := _hash21(i + Vector2(0.0, 1.0))
	var d := _hash21(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


func puddle_depth_at(world_pos: Vector2, stone_hold: float, seed: int) -> float:
	# Mirrors atmosphere.gdshader puddle basin so gameplay/footprints know exact live puddle locations!
	if wetness <= 0.12 or snow_cover > 0.08 or stone_hold <= 0.08:
		return 0.0
	var ns := float(seed % 193)
	var drift := Vector2(sin(puddle_phase * 0.37) * 0.55, cos(puddle_phase * 0.29) * 0.55)
	var b1 := _noise2(world_pos * Vector2(0.22, 0.25) + Vector2(ns * 0.37, 11.4) + drift)
	var b2 := _noise2(world_pos * Vector2(0.58, 0.54) - Vector2(7.1, ns * 0.19) - drift * 0.65)
	var surge := 0.035 * sin(puddle_phase * 0.72 + b1 * 4.0)
	var basin := b1 * 0.64 + b2 * 0.36 + surge
	var threshold := lerpf(0.84, 0.64, stone_hold) - wetness * 0.14
	return smoothstep(threshold, threshold + 0.09, basin) * smoothstep(0.14, 0.45, wetness) * smoothstep(0.08, 0.52, stone_hold)


func label() -> String:
	return String(NAMES.get(current_kind, "晴朗"))


func badge() -> Array:
	var pair: Array = BADGE_COLORS.get(current_kind, [Color("e6cf8b"), Color("23251a")])
	return [label(), pair[0], pair[1]]
