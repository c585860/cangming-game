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
var wind := Vector2(-0.35, 0.14)


static func auto_kind_for(sky: Dictionary, seed: int) -> int:
	# Stable deterministic weather per 4-hour block, weighted by season.
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


func sync(sky: Dictionary, seed: int, instant := false) -> void:
	current_kind = override_kind if override_kind >= 0 else auto_kind_for(sky, seed)
	var target_rain := 0.0
	var target_snow := 0.0
	var target_cloud := 0.0
	var target_wet := 0.0
	var target_snow_cover := 0.0
	match current_kind:
		Kind.CLEAR:
			target_cloud = 0.0
			target_snow_cover = 0.28 if String(sky.season) == "冬" and override_kind < 0 else 0.0
		Kind.CLOUDY:
			target_cloud = 0.55
			target_wet = 0.12 if String(sky.season) != "冬" else 0.0
			target_snow_cover = 0.35 if String(sky.season) == "冬" and override_kind < 0 else 0.0
		Kind.LIGHT_RAIN:
			target_rain = 0.55
			target_cloud = 0.72
			target_wet = 0.68
		Kind.HEAVY_RAIN:
			target_rain = 1.0
			target_cloud = 0.90
			target_wet = 1.0
		Kind.LIGHT_SNOW:
			target_snow = 0.55
			target_cloud = 0.65
			target_snow_cover = 0.65
		Kind.HEAVY_SNOW:
			target_snow = 1.0
			target_cloud = 0.82
			target_snow_cover = 1.0
	if instant:
		rain = target_rain
		snow = target_snow
		cloud = target_cloud
		wetness = target_wet
		snow_cover = target_snow_cover
	else:
		rain = lerpf(rain, target_rain, 0.35)
		snow = lerpf(snow, target_snow, 0.35)
		cloud = lerpf(cloud, target_cloud, 0.35)
		wetness = lerpf(wetness, target_wet, 0.25)
		snow_cover = lerpf(snow_cover, target_snow_cover, 0.25)
	wind = Vector2(-0.42 - 0.30 * rain, 0.16 + 0.08 * snow)


func label() -> String:
	return String(NAMES.get(current_kind, "晴朗"))


func badge() -> Array:
	var pair: Array = BADGE_COLORS.get(current_kind, [Color("e6cf8b"), Color("23251a")])
	return [label(), pair[0], pair[1]]
