extends RefCounted

const MINUTES_PER_DAY := 1440
const DAYS_PER_SEASON := 91
const DAYS_PER_YEAR := DAYS_PER_SEASON * 4
const LUNAR_MONTH := 29.530588853
const AXIAL_TILT := deg_to_rad(23.439279)
const LATITUDE := deg_to_rad(40.8)
const SEASONS := ["春", "夏", "秋", "冬"]
const MOON_PHASES := ["朔月", "娥眉月", "上弦月", "盈凸月", "满月", "亏凸月", "下弦月", "残月"]


static func at_minute(total_minutes: int) -> Dictionary:
	var day_index := maxi(0, floori(total_minutes / float(MINUTES_PER_DAY)))
	var minute_of_day := posmod(total_minutes, MINUTES_PER_DAY)
	var day_of_year := posmod(day_index, DAYS_PER_YEAR)
	var declination := AXIAL_TILT * sin(TAU * day_of_year / float(DAYS_PER_YEAR))
	var latitude_factor := -tan(LATITUDE) * tan(declination)
	var daylight_half_angle := acos(clampf(latitude_factor, -1.0, 1.0))
	var sunrise := 12.0 - daylight_half_angle * 12.0 / PI
	var sunset := 12.0 + daylight_half_angle * 12.0 / PI
	var hour := minute_of_day / 60.0
	var solar_hour_angle := (hour - 12.0) * PI / 12.0
	var altitude := asin(clampf(sin(LATITUDE) * sin(declination) + cos(LATITUDE) * cos(declination) * cos(solar_hour_angle), -1.0, 1.0))
	var daylight := smoothstep(deg_to_rad(-7.0), deg_to_rad(8.0), altitude)
	var sun_direction := Vector2(-sin(solar_hour_angle), cos(solar_hour_angle) * sin(LATITUDE) - sin(declination) * cos(LATITUDE)).normalized()
	var dawn_warmth := smoothstep(sunrise - 1.0, sunrise, hour) * (1.0 - smoothstep(sunrise, sunrise + 1.5, hour))
	var dusk_warmth := smoothstep(sunset - 1.5, sunset, hour) * (1.0 - smoothstep(sunset, sunset + 0.8, hour))
	var twilight := maxf(dawn_warmth, dusk_warmth)
	var phase := fposmod(day_index / LUNAR_MONTH, 1.0) * TAU
	var moon_illumination := (1.0 - cos(phase)) * 0.5
	var moon_transit := fposmod(12.0 + phase * 24.0 / TAU, 24.0)
	var moon_hour_angle := fposmod(hour - moon_transit + 12.0, 24.0) - 12.0
	var lunar_angle := moon_hour_angle * PI / 12.0
	var moon_altitude := asin(clampf(cos(LATITUDE) * cos(lunar_angle), -1.0, 1.0))
	var moon_direction := Vector2(-sin(lunar_angle), cos(lunar_angle) * sin(LATITUDE)).normalized()
	var moon_above_horizon := smoothstep(deg_to_rad(-3.0), deg_to_rad(5.0), moon_altitude)
	var moonlight := moon_illumination * moon_above_horizon * (1.0 - daylight) * 0.10
	var phase_index := posmod(roundi(phase / TAU * MOON_PHASES.size()), MOON_PHASES.size())
	var season_index := floori(day_of_year / float(DAYS_PER_SEASON))
	var sun_warmth := maxf(twilight, 0.0) * (1.0 - daylight * 0.35)
	var visible_sun_altitude := maxf(altitude, deg_to_rad(4.0))
	var shadow_length := clampf(cos(visible_sun_altitude) / sin(visible_sun_altitude), 0.25, 8.0)
	return {
		"day_index": day_index,
		"minute_of_day": minute_of_day,
		"season": SEASONS[season_index],
		"season_day": posmod(day_of_year, DAYS_PER_SEASON) + 1,
		"year": floori(day_index / float(DAYS_PER_YEAR)) + 1,
		"hour": hour,
		"sunrise": sunrise,
		"sunset": sunset,
		"sun_altitude": altitude,
		"sun_direction": sun_direction,
		"daylight": daylight,
		"sun_warmth": sun_warmth,
		"shadow_length": shadow_length,
		"moon_phase": MOON_PHASES[phase_index],
		"moon_illumination": moon_illumination,
		"moon_above_horizon": moon_above_horizon,
		"moonlight": moonlight,
		"moon_altitude": moon_altitude,
		"moon_direction": moon_direction,
	}


static func time_label(total_minutes: int) -> String:
	var sky := at_minute(total_minutes)
	var minute_of_day: int = sky.minute_of_day
	var hour := floori(minute_of_day / 60.0)
	var minute := minute_of_day % 60
	return "%s季 第%d日 · 第%d年  %02d:%02d · %s" % [sky.season, sky.season_day, sky.year, hour, minute, sky.moon_phase]
