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
const VOLUME_SAMPLES_PER_TILE := 3
const BOUNCE_SAMPLES_PER_TILE := 2
const LIGHT_MARGIN := 5

var solar_view: SubViewport
var solar_rect: ColorRect
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
var volume := ShaderMaterial.new()
var air := ShaderMaterial.new()
var layer := ColorRect.new()
var active_emitters: Dictionary = {}
var current_lamp_power := 0.0


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
	# A viewport renders its child viewports before sampling their textures.
	bounce_source_view.add_child(solar_view)
	solar.shader = SolarShader
	solar_rect = ColorRect.new()
	solar_rect.material = solar
	solar_view.add_child(solar_rect)
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
	air.set_shader_parameter("volume_map", volume_view.get_texture())
	air.set_shader_parameter("volume_sample_inset", 0.5 / float(VOLUME_SAMPLES_PER_TILE))
	air.set_shader_parameter("bounce_map", bounce_view.get_texture())
	air.set_shader_parameter("bounce_sample_inset", 0.5 / float(BOUNCE_SAMPLES_PER_TILE))
	air.set_shader_parameter("surface_mask", mask_view.get_texture())
	layer.material = air
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(layer)


func set_geometry(cells: Dictionary, area: Rect2i, layers: int, z: int, seed: int) -> void:
	var geometry := Geometry.encode(cells, area, layers)
	solar.set_shader_parameter("geometry", geometry)
	solar.set_shader_parameter("map_size", area.size)
	solar.set_shader_parameter("layer_count", layers)
	volume.set_shader_parameter("geometry", geometry)
	volume.set_shader_parameter("map_size", area.size)
	volume.set_shader_parameter("layer_count", layers)
	bounce.set_shader_parameter("geometry", geometry)
	bounce.set_shader_parameter("map_size", area.size)
	bounce_source.set_shader_parameter("geometry", geometry)
	bounce_source.set_shader_parameter("map_size", area.size)
	bounce_source.set_shader_parameter("materials", Geometry.bounce_materials(cells, area))
	air.set_shader_parameter("geometry", geometry)
	air.set_shader_parameter("sky_transport", SkyTransport.bake(cells, area, z))
	air.set_shader_parameter("map_size", area.size)
	var river := Geometry.river_field(cells, area, z)
	air.set_shader_parameter("river_field", river)
	solar.set_shader_parameter("river_field", river)
	air.set_shader_parameter("below_ground", z < 0)
	air.set_shader_parameter("noise_seed", float(seed % 193))


func update_surfaces(cells: Dictionary, props: Rect2i, origin: Vector2i, screen: Vector2, cell: int, seed: int,
		season: String = "spring", characters: Array = []) -> void:
	var resolution := Vector2i(screen.ceil()).max(Vector2i(2, 2))
	if mask_view.size != resolution:
		mask_view.size = resolution
	air.set_shader_parameter("mask_sample_scale", screen / Vector2(resolution))
	surface_mask.view_origin = origin
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


func update_light(tints: Dictionary, area: Rect2i, visible: Rect2i, sky: Dictionary, z: int) -> void:
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
	if z < 0:
		strength = 0.0
	var sunlight_enabled := strength > 0.0001
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
	bounce.set_shader_parameter("view_offset", offset)
	bounce.set_shader_parameter("light_size", Vector2(span))
	bounce.set_shader_parameter("sunlight_enabled", sunlight_enabled)
	bounce_source.set_shader_parameter("view_offset", offset)
	bounce_source.set_shader_parameter("light_size", Vector2(span))
	bounce_source.set_shader_parameter("sunlight_enabled", sunlight_enabled)
	var sun_ray := Vector3(direction.x, direction.y, rise).normalized()
	bounce_source.set_shader_parameter("sun_ray", sun_ray)
	solar.set_shader_parameter("light_size", Vector2(span))
	var moon_altitude: float = sky.moon_altitude
	var moon_direction: Vector2 = sky.moon_direction
	var moon_rise := maxf(0.016, tan(clampf(moon_altitude, 0.0, deg_to_rad(89.0))))
	var moon_energy := float(sky.moonlight) * 1.35 * smoothstep(0.0, deg_to_rad(7.0), moon_altitude)
	moon_energy *= 1.0 - smoothstep(deg_to_rad(-6.0), 0.0, altitude)
	if z != 0:
		moon_energy = 0.0
	var moon_active := moon_energy > 0.0001 && not sunlight_enabled
	solar.set_shader_parameter("toward_sun", moon_direction if moon_active else direction)
	solar.set_shader_parameter("rise", moon_rise if moon_active else rise)
	solar.set_shader_parameter("sample_moon", moon_active)
	solar.set_shader_parameter("sunlight_enabled", sunlight_enabled)
	volume.set_shader_parameter("view_offset", offset)
	volume.set_shader_parameter("light_size", Vector2(span))
	volume.set_shader_parameter("toward_sun", direction)
	volume.set_shader_parameter("rise", rise)
	volume.set_shader_parameter("sunlight_enabled", sunlight_enabled)
	var daylight_update := SubViewport.UPDATE_ONCE if sunlight_enabled else SubViewport.UPDATE_DISABLED
	volume_view.render_target_update_mode = daylight_update
	solar_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	bounce_source_view.render_target_update_mode = daylight_update
	bounce_view.render_target_update_mode = daylight_update
	air.set_shader_parameter("light_span", Vector2(span))
	air.set_shader_parameter("light_margin", float(LIGHT_MARGIN))
	var sky_level := Lighting._natural_light(sky)
	var sky_strength := smoothstep(4.3, 85.0, sky_level) * 0.86 if z >= 0 else 0.0
	air.set_shader_parameter("sky_energy", sky_strength)
	air.set_shader_parameter("indoor_daylight", sky_strength * smoothstep(deg_to_rad(-6.0), deg_to_rad(2.0), altitude))
	air.set_shader_parameter("sky_color", Vector3(0.80, 0.90, 1.0).lerp(Vector3(1.0, 0.78, 0.57), float(sky.sun_warmth) * 0.40))
	current_lamp_power = 1.0 if z < 0 else 1.0 - smoothstep(5.0, 18.0, sky_level)
	air.set_shader_parameter("lamp_power", current_lamp_power)
	air.set_shader_parameter("sun_ray", sun_ray)
	air.set_shader_parameter("sun_color", sun_color)
	air.set_shader_parameter("sun_energy", strength)
	air.set_shader_parameter("moon_ray", Vector3(moon_direction.x, moon_direction.y, moon_rise).normalized())
	air.set_shader_parameter("moon_energy", moon_energy if moon_active else 0.0)
	var season_mist := 1.15 if sky.season == "春" else 0.82 if sky.season == "夏" else 1.05 if sky.season == "秋" else 0.92
	var season_tint := Vector3(0.98, 1.02, 0.99) if sky.season == "春" else Vector3(1.01, 1.01, 0.97) if sky.season == "夏" else Vector3(1.05, 0.98, 0.90) if sky.season == "秋" else Vector3(0.92, 0.97, 1.05)
	air.set_shader_parameter("season_tint", season_tint)
	air.set_shader_parameter("mist_time", (0.28 + 0.68 * morning + 0.37 * evening) * season_mist if z == 0 else 0.0)


func set_view(area: Rect2i, visible: Rect2i, screen: Vector2, cell: int, player: Vector2i) -> void:
	layer.size = screen
	air.set_shader_parameter("view_world", Vector2(visible.position))
	air.set_shader_parameter("map_offset", Vector2(visible.position - area.position))
	air.set_shader_parameter("view_span", screen / float(cell))
	air.set_shader_parameter("player_feet", Vector2(player) + Vector2(0.5, 0.84))
