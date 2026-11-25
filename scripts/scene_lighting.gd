extends RefCounted

const Geometry = preload("res://scripts/light_geometry.gd")
const SolarShader = preload("res://scripts/solar_visibility.gdshader")
const AirShader = preload("res://scripts/atmosphere.gdshader")
const BounceSourceShader = preload("res://scripts/diffuse_source.gdshader")
const BounceShader = preload("res://scripts/diffuse_bounce.gdshader")
const SurfaceMask = preload("res://scripts/surface_mask.gd")
const PointLighting = preload("res://scripts/point_lighting.gd")
const SkyTransport = preload("res://scripts/sky_transport.gd")
const Lighting = preload("res://scripts/lighting.gd")
const SAMPLES_PER_TILE := 4
const NEAR_SPAN := 18
const NEAR_SAMPLES_PER_TILE := 8
const VOLUME_SAMPLES_PER_TILE := 3
const BOUNCE_SAMPLES_PER_TILE := 2
const LIGHT_MARGIN := 6

var solar_view: SubViewport
var solar_rect: ColorRect
var solar_near_view: SubViewport
var solar_near_rect: ColorRect
var volume_view: SubViewport
var volume_rect: ColorRect
var bounce_view: SubViewport
var bounce_rect: ColorRect
var bounce_source_view: SubViewport
var bounce_source_rect: ColorRect
var mask_view: SubViewport
var surface_mask: SurfaceMask
var bounce := ShaderMaterial.new()
var bounce_source := ShaderMaterial.new()
var solar := ShaderMaterial.new()
var solar_near := ShaderMaterial.new()
var volume := ShaderMaterial.new()
var air := ShaderMaterial.new()
var layer := ColorRect.new()
var active_emitters: Dictionary = {}
var current_lamp_power := 0.0
var current_daylight := 1.0
var current_roof_light := Color(0.85, 0.88, 0.90)
var _sunlight_enabled := false
var _moon_active := false
var _near_origin := Vector2.ZERO
var _near_wind_accum := 0.0


func build(board: Control) -> void:
	bounce_view = SubViewport.new()
	bounce_view.disable_3d = true
	bounce_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	board.add_child(bounce_view)
	bounce_source_view = SubViewport.new()
	bounce_source_view.disable_3d = true
	bounce_source_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	bounce_view.add_child(bounce_source_view)
	solar_view = SubViewport.new()
	solar_view.disable_3d = true
	solar_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	bounce_source_view.add_child(solar_view)
	solar.shader = SolarShader
	solar_rect = ColorRect.new()
	solar_rect.material = solar
	solar_view.add_child(solar_rect)

	# Cascade 0: High-resolution near shadow map (8 samples/tile + soft penumbra) around player.
	solar_near_view = SubViewport.new()
	solar_near_view.disable_3d = true
	solar_near_view.size = Vector2i.ONE * (NEAR_SPAN * NEAR_SAMPLES_PER_TILE)
	solar_near_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	board.add_child(solar_near_view)
	solar_near.shader = SolarShader
	solar_near.set_shader_parameter("soft_cascade", true)
	solar_near.set_shader_parameter("light_size", Vector2.ONE * float(NEAR_SPAN))
	solar_near_rect = ColorRect.new()
	solar_near_rect.size = Vector2(solar_near_view.size)
	solar_near_rect.material = solar_near
	solar_near_view.add_child(solar_near_rect)

	bounce_source.shader = BounceSourceShader
	bounce_source.set_shader_parameter("solar_map", solar_view.get_texture())
	bounce_source_rect = ColorRect.new()
	bounce_source_rect.material = bounce_source
	bounce_source_view.add_child(bounce_source_rect)
	volume_view = SubViewport.new()
	volume_view.disable_3d = true
	volume_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	board.add_child(volume_view)
	volume.shader = SolarShader
	volume.set_shader_parameter("sample_air", true)
	volume_rect = ColorRect.new()
	volume_rect.material = volume
	volume_view.add_child(volume_rect)
	bounce.shader = BounceShader
	bounce.set_shader_parameter("bounce_sources", bounce_source_view.get_texture())
	bounce_rect = ColorRect.new()
	bounce_rect.material = bounce
	bounce_view.add_child(bounce_rect)
	mask_view = SubViewport.new()
	mask_view.disable_3d = true
	mask_view.transparent_bg = true
	mask_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	board.add_child(mask_view)
	surface_mask = SurfaceMask.new()
	mask_view.add_child(surface_mask)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	board.add_child(copy)
	air.shader = AirShader
	air.set_shader_parameter("solar_map", solar_view.get_texture())
	air.set_shader_parameter("solar_near_map", solar_near_view.get_texture())
	air.set_shader_parameter("near_span", float(NEAR_SPAN))
	air.set_shader_parameter("volume_map", volume_view.get_texture())
	air.set_shader_parameter("volume_sample_inset", 0.5 / float(VOLUME_SAMPLES_PER_TILE))
	air.set_shader_parameter("bounce_map", bounce_view.get_texture())
	air.set_shader_parameter("bounce_sample_inset", 0.5 / float(BOUNCE_SAMPLES_PER_TILE))
	air.set_shader_parameter("surface_mask", mask_view.get_texture())
	layer.material = air
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(layer)


func set_geometry(cells: Dictionary, area: Rect2i, layers: int, z: int, seed: int, season := "spring") -> void:
	var geometry := Geometry.encode(cells, area, layers)
	solar.set_shader_parameter("geometry", geometry)
	solar.set_shader_parameter("map_size", area.size)
	solar.set_shader_parameter("layer_count", layers)
	solar_near.set_shader_parameter("geometry", geometry)
	solar_near.set_shader_parameter("map_size", area.size)
	solar_near.set_shader_parameter("layer_count", layers)
	volume.set_shader_parameter("geometry", geometry)
	volume.set_shader_parameter("map_size", area.size)
	volume.set_shader_parameter("layer_count", layers)
	bounce.set_shader_parameter("geometry", geometry)
	bounce.set_shader_parameter("map_size", area.size)
	bounce_source.set_shader_parameter("geometry", geometry)
	bounce_source.set_shader_parameter("map_size", area.size)
	bounce_source.set_shader_parameter("materials", Geometry.bounce_materials(cells, area, season))
	air.set_shader_parameter("geometry", geometry)
	air.set_shader_parameter("sky_transport", SkyTransport.bake(cells, area, z))
	air.set_shader_parameter("map_size", area.size)
	var river := Geometry.river_field(cells, area, z)
	air.set_shader_parameter("river_field", river)
	solar.set_shader_parameter("river_field", river)
	solar_near.set_shader_parameter("river_field", river)
	air.set_shader_parameter("below_ground", z < 0)
	air.set_shader_parameter("noise_seed", float(seed % 193))


func update_surfaces(cells: Dictionary, props: Rect2i, origin: Vector2i, cam_px_offset: Vector2, screen: Vector2,
		cell: int, seed: int, season: String = "spring", characters: Array = []) -> void:
	var resolution := Vector2i(screen.ceil()).max(Vector2i(2, 2))
	if mask_view.size != resolution:
		mask_view.size = resolution
	air.set_shader_parameter("mask_sample_scale", screen / Vector2(resolution))
	surface_mask.view_origin = origin
	surface_mask.cam_px_offset = cam_px_offset
	surface_mask.cell = cell
	surface_mask.cells = cells
	surface_mask.props = props
	surface_mask.seed = seed
	surface_mask.season = season
	surface_mask.characters = characters
	surface_mask.queue_redraw()
	mask_view.render_target_update_mode = SubViewport.UPDATE_ONCE


func update_emitters(cells: Dictionary, area: Rect2i, region: Rect2i, sites: Dictionary = {}, seed: int = 0) -> void:
	var data := PointLighting.bake(cells, area, region, sites, seed)
	air.set_shader_parameter("lamp_slots", data[0])
	air.set_shader_parameter("lamp_sources", data[1])
	active_emitters = data[2]


func update_weather_visual(weather: RefCounted) -> void:
	if weather == null:
		return
	air.set_shader_parameter("rain_level", float(weather.rain))
	air.set_shader_parameter("wetness", float(weather.wetness))
	air.set_shader_parameter("snow_cover", float(weather.snow_cover))
	air.set_shader_parameter("cloud_cover", float(weather.cloud))
	air.set_shader_parameter("puddle_phase", float(weather.puddle_phase))


func tick_near_cascade(area: Rect2i, player_visual: Vector2, wind_time: float, delta: float, force := false) -> void:
	if not (_sunlight_enabled or _moon_active):
		return
	var target_origin := (player_visual + Vector2(0.5, 0.5) - Vector2(area.position) - Vector2.ONE * (float(NEAR_SPAN) * 0.5)).floor()
	_near_wind_accum += delta
	if force or target_origin.distance_squared_to(_near_origin) > 0.25 or _near_wind_accum >= 0.08:
		_near_origin = target_origin
		_near_wind_accum = 0.0
		solar_near.set_shader_parameter("view_offset", _near_origin)
		solar_near.set_shader_parameter("wind_time", wind_time)
		air.set_shader_parameter("near_offset", _near_origin)
		solar_near_view.render_target_update_mode = SubViewport.UPDATE_ONCE


func update_light(tints: Dictionary, area: Rect2i, visible: Rect2i, sky: Dictionary, z: int, weather: RefCounted = null,
		player_visual := Vector2.ZERO, wind_time := 0.0) -> void:
	var rain_level := float(weather.rain) if weather != null else 0.0
	var snow_level := float(weather.snow) if weather != null else 0.0
	var cloud_cover := float(weather.cloud) if weather != null else 0.0
	var wetness := float(weather.wetness) if weather != null else 0.0
	var snow_cover := float(weather.snow_cover) if weather != null else 0.0
	var puddle_phase := float(weather.puddle_phase) if weather != null else 0.0

	var image := Image.create_empty(area.size.x, area.size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for p: Vector2i in tints:
		var local := p - area.position
		image.set_pixelv(local, tints[p])
	air.set_shader_parameter("ambient_map", ImageTexture.create_from_image(image))
	var altitude: float = sky.sun_altitude
	var direction: Vector2 = sky.sun_direction
	if direction.length_squared() < 0.01:
		direction = Vector2.DOWN
	var strength := smoothstep(0.0, deg_to_rad(6.0), altitude) * (0.40 + 0.26 * sin(maxf(altitude, 0.0)))
	strength *= 1.0 - cloud_cover * 0.78
	if z < 0:
		strength = 0.0
	_sunlight_enabled = strength > 0.0001
	var rise := maxf(0.016, tan(clampf(altitude, 0.0, deg_to_rad(89.0))))
	var sun_color := Vector3(1.0, 0.94, 0.83).lerp(Vector3(1.0, 0.56, 0.26), 1.0 - smoothstep(0.0, deg_to_rad(30.0), altitude))
	var hours: float = sky.hour
	var sunrise: float = sky.sunrise
	var sunset: float = sky.sunset
	var morning := 1.0 - smoothstep(0.0, 4.5, absf(hours - sunrise))
	var evening := 1.0 - smoothstep(0.0, 3.5, absf(hours - sunset))
	var span := visible.size + Vector2i.ONE * (LIGHT_MARGIN * 2)
	var resolution := span * SAMPLES_PER_TILE
	if solar_view.size != resolution:
		solar_view.size = resolution
		solar_rect.size = Vector2(resolution)
	var volume_resolution := span * VOLUME_SAMPLES_PER_TILE
	if volume_view.size != volume_resolution:
		volume_view.size = volume_resolution
		volume_rect.size = Vector2(volume_resolution)
	var bounce_resolution := span * BOUNCE_SAMPLES_PER_TILE
	if bounce_view.size != bounce_resolution:
		bounce_view.size = bounce_resolution
		bounce_rect.size = Vector2(bounce_resolution)
	if bounce_source_view.size != span:
		bounce_source_view.size = span
		bounce_source_rect.size = Vector2(span)
	var offset := Vector2(visible.position - area.position - Vector2i.ONE * LIGHT_MARGIN)
	solar.set_shader_parameter("view_offset", offset)
	solar.set_shader_parameter("wind_time", wind_time)
	bounce.set_shader_parameter("view_offset", offset)
	bounce.set_shader_parameter("light_size", Vector2(span))
	bounce.set_shader_parameter("sunlight_enabled", _sunlight_enabled)
	bounce_source.set_shader_parameter("view_offset", offset)
	bounce_source.set_shader_parameter("light_size", Vector2(span))
	bounce_source.set_shader_parameter("sunlight_enabled", _sunlight_enabled)
	var sun_ray := Vector3(direction.x, direction.y, rise).normalized()
	bounce_source.set_shader_parameter("sun_ray", sun_ray)
	solar.set_shader_parameter("light_size", Vector2(span))
	var moon_altitude: float = sky.moon_altitude
	var moon_direction: Vector2 = sky.moon_direction
	var moon_rise := maxf(0.016, tan(clampf(moon_altitude, 0.0, deg_to_rad(89.0))))
	var moon_energy := float(sky.moonlight) * 1.35 * smoothstep(0.0, deg_to_rad(7.0), moon_altitude)
	moon_energy *= (1.0 - smoothstep(deg_to_rad(-6.0), 0.0, altitude)) * (1.0 - cloud_cover * 0.65)
	if z != 0:
		moon_energy = 0.0
	_moon_active = moon_energy > 0.0001 and not _sunlight_enabled
	var active_dir := moon_direction if _moon_active else direction
	var active_rise := moon_rise if _moon_active else rise
	solar.set_shader_parameter("toward_sun", active_dir)
	solar.set_shader_parameter("rise", active_rise)
	solar.set_shader_parameter("sample_moon", _moon_active)
	solar.set_shader_parameter("sunlight_enabled", _sunlight_enabled)
	solar_near.set_shader_parameter("toward_sun", active_dir)
	solar_near.set_shader_parameter("rise", active_rise)
	solar_near.set_shader_parameter("sample_moon", _moon_active)
	solar_near.set_shader_parameter("sunlight_enabled", _sunlight_enabled)
	volume.set_shader_parameter("view_offset", offset)
	volume.set_shader_parameter("light_size", Vector2(span))
	volume.set_shader_parameter("toward_sun", direction)
	volume.set_shader_parameter("rise", rise)
	volume.set_shader_parameter("sunlight_enabled", _sunlight_enabled)
	var daylight_update := SubViewport.UPDATE_ONCE if _sunlight_enabled else SubViewport.UPDATE_DISABLED
	volume_view.render_target_update_mode = daylight_update
	solar_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	bounce_source_view.render_target_update_mode = daylight_update
	bounce_view.render_target_update_mode = daylight_update
	air.set_shader_parameter("far_offset", offset)
	air.set_shader_parameter("light_span", Vector2(span))
	air.set_shader_parameter("light_margin", float(LIGHT_MARGIN))
	var sky_level := Lighting._natural_light(sky)
	var sky_strength := smoothstep(4.3, 85.0, sky_level) * (0.86 - 0.16 * cloud_cover) if z >= 0 else 0.0
	current_daylight = clampf(sky_strength * 1.35, 0.0, 1.0)
	air.set_shader_parameter("sky_energy", sky_strength)
	air.set_shader_parameter("indoor_daylight", sky_strength * smoothstep(deg_to_rad(-6.0), deg_to_rad(2.0), altitude))
	var base_sky := Vector3(0.80, 0.90, 1.0).lerp(Vector3(1.0, 0.78, 0.57), float(sky.sun_warmth) * 0.40 * (1.0 - cloud_cover * 0.7))
	base_sky = base_sky.lerp(Vector3(0.74, 0.83, 0.88), rain_level * 0.55)
	base_sky = base_sky.lerp(Vector3(0.86, 0.92, 0.98), snow_level * 0.50)
	air.set_shader_parameter("sky_color", base_sky)
	var out_level := maxf(sky_level - Lighting.AMBIENT_LOW, 0.0)
	var out_day := 1.0 - exp(-out_level / 56.0)
	var out_twilight := 1.0 - exp(-out_level / 9.0)
	var daylight_tint := Color.WHITE.lerp(Color(1.0, 0.78, 0.57), float(sky.sun_warmth) * 0.75 * (1.0 - cloud_cover * 0.7))
	var out_hue := Color(0.74, 0.81, 1.0).lerp(daylight_tint, out_twilight)
	var out_bright := (0.23 + out_twilight * 0.17 + out_day * 0.42) * (1.0 - cloud_cover * 0.14)
	var out_amb := Vector3(out_hue.r * out_bright, out_hue.g * out_bright, out_hue.b * out_bright)
	air.set_shader_parameter("outdoor_ambient", out_amb)
	var roof_exp := out_amb + sun_color * strength * 0.78 + Vector3(0.55, 0.70, 0.92) * (moon_energy if _moon_active else 0.0) * 0.50
	current_roof_light = Color(minf(roof_exp.x, 1.05), minf(roof_exp.y, 1.05), minf(roof_exp.z, 1.05), 1.0)
	current_lamp_power = 1.0 if z < 0 else clampf((1.0 - smoothstep(5.0, 18.0 + cloud_cover * 18.0, sky_level)) + rain_level * 0.18, 0.0, 1.0)
	air.set_shader_parameter("lamp_power", current_lamp_power)
	air.set_shader_parameter("sun_ray", sun_ray)
	air.set_shader_parameter("sun_color", sun_color)
	air.set_shader_parameter("sun_energy", strength)
	air.set_shader_parameter("moon_ray", Vector3(moon_direction.x, moon_direction.y, moon_rise).normalized())
	air.set_shader_parameter("moon_energy", moon_energy if _moon_active else 0.0)
	var season_mist := 1.15 if sky.season == "春" else 0.82 if sky.season == "夏" else 1.05 if sky.season == "秋" else 0.92
	var season_tint := Vector3(0.98, 1.02, 0.99) if sky.season == "春" else Vector3(1.01, 1.01, 0.97) if sky.season == "夏" else Vector3(1.05, 0.98, 0.90) if sky.season == "秋" else Vector3(0.92, 0.97, 1.05)
	season_tint = season_tint.lerp(Vector3(0.91, 0.96, 1.02), rain_level * 0.45)
	season_tint = season_tint.lerp(Vector3(0.93, 0.97, 1.04), snow_cover * 0.45)
	air.set_shader_parameter("season_tint", season_tint)
	air.set_shader_parameter("mist_time", ((0.28 + 0.68 * morning + 0.37 * evening) * season_mist + 0.48 * rain_level + 0.22 * snow_level) if z == 0 else 0.0)
	air.set_shader_parameter("rain_level", rain_level)
	air.set_shader_parameter("wetness", wetness)
	air.set_shader_parameter("snow_cover", snow_cover)
	air.set_shader_parameter("cloud_cover", cloud_cover)
	air.set_shader_parameter("puddle_phase", puddle_phase)
	tick_near_cascade(area, player_visual, wind_time, 0.0, true)


func set_view(area: Rect2i, view_world_exact: Vector2, screen: Vector2, cell: int, player_visual: Vector2) -> void:
	layer.size = screen
	air.set_shader_parameter("view_world", view_world_exact)
	air.set_shader_parameter("map_offset", view_world_exact - Vector2(area.position))
	air.set_shader_parameter("view_span", screen / float(cell))
	air.set_shader_parameter("player_feet", player_visual + Vector2(0.5, 0.84))
