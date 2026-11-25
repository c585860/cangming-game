extends Control

signal cell_clicked(cell: Vector2i)
signal context_requested(cell: Vector2i)

const World = preload("res://scripts/world.gd")
const Art = preload("res://scripts/street_art.gd")
const CanglingCalendar = preload("res://scripts/cangling_calendar.gd")
const Tiles = preload("res://scripts/undead_tiles.gd")
const Lighting = preload("res://scripts/lighting.gd")
const LightGeometry = preload("res://scripts/light_geometry.gd")
const SceneLighting = preload("res://scripts/scene_lighting.gd")
const Weather = preload("res://scripts/weather.gd")
const WeatherFx = preload("res://scripts/weather_fx.gd")
const FootprintTrail = preload("res://scripts/footprints.gd")
const CharacterMotion = preload("res://scripts/character_motion.gd")
const RoofSystem = preload("res://scripts/roof_system.gd")
const ZOOMS := [20, 25, 32, 40, 48]
const SITE_NAMES := {&"merchant": "药商沈青", &"ferryman": "渡夫", &"altar": "吐纳石台", &"herb": "清露草", &"door": "门"}
const SEASON_KEYS := {"春": "spring", "夏": "summer", "秋": "autumn", "冬": "winter"}
const NONE := Vector2i(-1, -1)

var world: World
var weather: Weather
var route: Array = []
var route_head := 0
var bounds: Rect2i
var hovered := NONE
var view_center := Vector2i.ZERO
var camera_world := Vector2.ZERO
var camera_target := Vector2.ZERO
var view_world_exact := Vector2.ZERO
var view_origin := Vector2i.ZERO
var cam_px_offset := Vector2.ZERO
var view_size := Vector2i.ONE
var zoom := 2
var cell := 32

var scene_lighting := SceneLighting.new()
var roof_system := RoofSystem.new()
var footprints := FootprintTrail.new()
var motion := CharacterMotion.new()
var roof_layer := Control.new()
var player_layer := Control.new()
var markers := Control.new()
var weather_fx := WeatherFx.new()

var lighting_key: Array = []
var baked_light_area := Rect2i()
var baked_light_minutes := -99999
var geometry_key: Array = []
var surface_key: Array = []
var emitter_area := Rect2i()
var emitter_herbs := -1
var geometry_area := Rect2i()
var cells: Dictionary = {}
var below_cells: Dictionary = {}
var current_season := "spring"
var can_read_upper_levels := false
var visual_time := 0.0
var _last_player_pos := NONE
var _camera_initialized := false


var roofs_enabled: bool:
	get: return roof_system.enabled
	set(v): roof_system.enabled = v


func build(model: World, weather_model: Weather = null) -> void:
	world = model
	weather = weather_model if weather_model != null else Weather.new()
	can_read_upper_levels = world.has_method("terrain_at_level")
	invalidate_lightmap()
	bounds = Rect2i(Vector2i.ZERO, world.city_size)
	view_center = world.pos
	camera_world = Vector2(world.pos) + Vector2(0.5, 0.5)
	camera_target = camera_world
	_camera_initialized = true
	_last_player_pos = world.pos
	motion.snap_to(world.pos)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	scene_lighting.build(self)

	# Layer order above lit scene: roofs -> animated player -> footprints/markers -> rain/snow
	roof_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roof_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(roof_layer)
	roof_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	roof_layer.draw.connect(_draw_roofs)

	player_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(player_layer)
	player_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_layer.draw.connect(_draw_player)

	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(markers)
	markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	markers.draw.connect(_draw_markers)

	add_child(weather_fx)
	weather_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_exited.connect(_clear_hover)
	resized.connect(_update_view)
	set_process(true)


func _process(delta: float) -> void:
	if world == null:
		return
	visual_time += delta

	# 1. Decoupled FPS weather evolution (dynamic puddles & snow)
	if weather != null:
		weather.tick_visual(delta)
		scene_lighting.update_weather_visual(weather)

	# 2. Smooth 60 FPS character stride & sub-tile camera tracking
	var player_moved := motion.tick(delta)
	var look_following_player := view_center == world.pos
	var desired_cam := (motion.visual_pos + Vector2(0.5, 0.5)) if look_following_player else (Vector2(view_center) + Vector2(0.5, 0.5))
	var cam_moved := false
	if camera_world.distance_squared_to(desired_cam) > 0.0001:
		var smooth := 1.0 - exp(-11.0 * delta)
		camera_world = camera_world.lerp(desired_cam, smooth)
		if camera_world.distance_squared_to(desired_cam) < 0.0002:
			camera_world = desired_cam
		cam_moved = true

	# 3. Proximity-fading roofs & footprint drying / puddle splashes
	roof_system.update_targets(motion.visual_pos, world.floor, false)
	var roofs_changed := roof_system.tick(delta, world.floor)
	var marks_changed := footprints.tick(delta, weather)

	# 4. High-res near shadow cascade follows smooth player & wind-swaying tree canopies
	if geometry_area.has_area():
		scene_lighting.tick_near_cascade(geometry_area, motion.visual_pos, visual_time, delta)

	if cam_moved:
		_recompute_camera_window()
		if geometry_area.has_area():
			scene_lighting.set_view(geometry_area, view_world_exact, size, cell, motion.visual_pos)
		queue_redraw()
	else:
		# Player walking without camera shift only needs cheap player_layer + view uniform update!
		if player_moved:
			if geometry_area.has_area():
				scene_lighting.set_view(geometry_area, view_world_exact, size, cell, motion.visual_pos)
			player_layer.queue_redraw()
			markers.queue_redraw()
		if roofs_changed:
			roof_layer.queue_redraw()
		if marks_changed:
			markers.queue_redraw()
	if roofs_changed or cam_moved:
		weather_fx.configure(weather.rain if world.floor == 0 else 0.0,
			weather.snow if world.floor == 0 else 0.0,
			scene_lighting.current_daylight, view_origin, cell, roof_system.revealed_interior)


func snap_visuals() -> void:
	if world == null:
		return
	motion.snap_to(world.pos)
	camera_world = Vector2(view_center) + Vector2(0.5, 0.5)
	_recompute_camera_window()
	roof_system.update_targets(motion.visual_pos, world.floor, true)
	roof_system.snap(world.floor)
	queue_redraw()


func snap_roof_alphas() -> void:
	if world == null:
		return
	roof_system.update_targets(motion.visual_pos, world.floor, true)
	roof_system.snap(world.floor)
	roof_layer.queue_redraw()


func clear_footprints() -> void:
	footprints.clear()
	_last_player_pos = world.pos if world != null else NONE


func follow(p: Vector2i) -> void:
	if world != null and world.pos != _last_player_pos:
		if _last_player_pos != NONE:
			footprints.record_step(_last_player_pos, world.pos, world, weather, cells)
		motion.set_target(world.pos)
		_last_player_pos = world.pos
	var big_jump := (p - view_center).length_squared() > 25
	if view_center != p:
		hovered = NONE
	view_center = p
	camera_target = Vector2(p) + Vector2(0.5, 0.5)
	if not _camera_initialized or big_jump:
		camera_world = camera_target
		_camera_initialized = true
	_update_view()


func _recompute_camera_window() -> void:
	cell = ZOOMS[zoom]
	var exact_span := size / float(cell)
	var max_world := (Vector2(world.city_size) - exact_span).max(Vector2.ZERO)
	view_world_exact = (camera_world - exact_span * 0.5).clamp(Vector2.ZERO, max_world)
	view_origin = Vector2i(floori(view_world_exact.x), floori(view_world_exact.y))
	var frac := view_world_exact - Vector2(view_origin)
	cam_px_offset = -frac * float(cell)
	view_size = Vector2i(exact_span.ceil()).max(Vector2i.ONE) + Vector2i.ONE


func _update_view() -> void:
	_recompute_camera_window()
	queue_redraw()


func _clear_hover() -> void:
	hovered = NONE
	markers.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampi(zoom + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, ZOOMS.size() - 1)
			_clear_hover()
			_update_view()
			accept_event()
			return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var p := _tile_at(event.position)
		if not bounds.has_point(p):
			return
		if hovered != p:
			hovered = p
			markers.queue_redraw()
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			cell_clicked.emit(p)
			accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			context_requested.emit(p)
			accept_event()


func _tile_at(screen: Vector2) -> Vector2i:
	return view_origin + Vector2i(((screen - cam_px_offset) / float(cell)).floor())


func _get_tooltip(at_position: Vector2) -> String:
	var p := _tile_at(at_position)
	if not bounds.has_point(p):
		return ""
	return SITE_NAMES.get(world.site_at(p), "")


func invalidate_lightmap() -> void:
	lighting_key.clear()
	baked_light_area = Rect2i()
	baked_light_minutes = -99999
	geometry_key.clear()
	surface_key.clear()
	emitter_area = Rect2i()
	emitter_herbs = -1


func invalidate_weather() -> void:
	lighting_key.clear()
	baked_light_area = Rect2i()
	baked_light_minutes = -99999
	surface_key.clear()
	queue_redraw()


func _collect_sites(region: Rect2i) -> Dictionary:
	var sites := {}
	if world.floor != 0:
		return sites
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var p := Vector2i(x, y)
			var site: StringName = world.site_at(p)
			if site in [&"merchant", &"ferryman", &"altar", &"herb"]:
				sites[p] = site
	return sites


func _collect_npc_characters(visible: Rect2i) -> Array:
	var list: Array = []
	if world.floor == 0:
		for y in range(visible.position.y, visible.end.y):
			for x in range(visible.position.x, visible.end.x):
				var p := Vector2i(x, y)
				var site: StringName = world.site_at(p)
				if site == &"merchant" or site == &"ferryman":
					list.append([Vector2(p), site, false, p, null])
	return list


func _update_lightmap(visible: Rect2i, props: Rect2i) -> void:
	var sky := CanglingCalendar.at_minute(world.minutes)
	current_season = SEASON_KEYS.get(sky.season, "spring")
	weather.sync(sky, world.seed, false, world.minutes)
	var z: int = world.floor
	var layers := maxi(1, 3 - z) if can_read_upper_levels and z >= 0 else 1
	var reach := LightGeometry.REACH + SceneLighting.LIGHT_MARGIN + 2
	var required := props.grow(reach).intersection(bounds)
	var static_key: Array = [world.seed, z, current_season]
	var rebuilt_geom := false
	if static_key != geometry_key or not geometry_area.encloses(required):
		geometry_area = props.grow(reach + 6).intersection(bounds)
		cells.clear()
		below_cells.clear()
		for y in range(geometry_area.position.y, geometry_area.end.y):
			for x in range(geometry_area.position.x, geometry_area.end.x):
				var p := Vector2i(x, y)
				var upper := PackedStringArray()
				if can_read_upper_levels and z >= 0 and z < 2147483647:
					for level in range(1, layers + 1):
						upper.append(world.call("terrain_at_level", p, z + level))
				var t: String = world.terrain_at(p)
				cells[p] = [t, world.surface_at(p), upper, world.lighting_column(p, z, layers)]
				if z > 0 and t == " " and can_read_upper_levels:
					below_cells[p] = [world.call("terrain_at_level", p, 0), world.call("surface_at_level", p, 0)]
		scene_lighting.set_geometry(cells, geometry_area, layers, z, world.seed, current_season)
		roof_system.index_buildings(cells, geometry_area)
		geometry_key = static_key
		lighting_key.clear()
		baked_light_area = Rect2i()
		surface_key.clear()
		emitter_area = Rect2i()
		rebuilt_geom = true
	roof_system.update_targets(motion.visual_pos, z, rebuilt_geom)

	# Surface mask only tracks static world + NPCs (player is rendered on player_layer above atmosphere!)
	var npcs := _collect_npc_characters(visible)
	var mask_key: Array = [props, visible.position, cam_px_offset.snapped(Vector2(1.0, 1.0)), size, cell, current_season, npcs.size()]
	if mask_key != surface_key:
		scene_lighting.update_surfaces(cells, props, visible.position, cam_px_offset, size, cell,
			world.seed ^ (z * 0x65bd4e97), current_season, npcs)
		surface_key = mask_key

	if not emitter_area.encloses(props) or emitter_herbs != world.herbs:
		emitter_area = geometry_area.grow(-SceneLighting.PointLighting.REACH).merge(props).intersection(geometry_area)
		var sites := _collect_sites(emitter_area.grow(SceneLighting.PointLighting.REACH).intersection(geometry_area))
		scene_lighting.update_emitters(cells, geometry_area, emitter_area, sites, world.seed ^ (z * 0x65bd4e97))
		emitter_herbs = world.herbs

	# Cache far-field solar/bounce/volume/ambient across multiple walking steps inside LIGHT_MARGIN!
	var weather_key: Array = [z, weather.current_kind, int(round(weather.wetness * 20.0)),
		int(round(weather.snow_cover * 20.0)), int(round(weather.rain * 20.0)), int(round(weather.snow * 20.0)), visible.size]
	var needs_light_bake := (weather_key != lighting_key) \
		or (not baked_light_area.encloses(visible)) \
		or (absi(world.minutes - baked_light_minutes) >= 5)
	if needs_light_bake:
		var ambient_region := props.grow(SceneLighting.LIGHT_MARGIN).intersection(geometry_area)
		var tints := Lighting.calculate_ambient(cells, ambient_region, sky, z)
		scene_lighting.update_light(tints, geometry_area, visible, sky, z, weather, motion.visual_pos, visual_time)
		baked_light_area = visible.grow(maxi(1, SceneLighting.LIGHT_MARGIN - 2)).intersection(bounds)
		baked_light_minutes = world.minutes
		lighting_key = weather_key

	weather_fx.configure(weather.rain if z == 0 else 0.0, weather.snow if z == 0 else 0.0,
		scene_lighting.current_daylight, view_origin, cell, roof_system.revealed_interior)
	scene_lighting.set_view(geometry_area, view_world_exact, size, cell, motion.visual_pos)


func _draw() -> void:
	if world == null:
		return
	var visible := Rect2i(view_origin, view_size).intersection(bounds)
	var props := visible.grow_individual(1, 0, 1, 2).intersection(bounds)
	_update_lightmap(visible, props)
	var seed: int = world.seed ^ (world.floor * 0x65bd4e97)
	var lit_strength: float = scene_lighting.current_lamp_power
	var emitters: Dictionary = scene_lighting.active_emitters
	if world.floor > 0 and not below_cells.is_empty():
		var sky_factor := clampf(1.0 - lit_strength * 0.72, 0.22, 1.0)
		var depth_tint := Color(0.35 * sky_factor, 0.42 * sky_factor, 0.48 * sky_factor, 1.0)
		for y in range(visible.position.y, visible.end.y):
			for x in range(visible.position.x, visible.end.x):
				var p := Vector2i(x, y)
				if below_cells.has(p):
					Art.ground(self, below_cells, p, world.seed, current_season, depth_tint)
					var north_solid: bool = cells.get(p + Vector2i.UP, [" "])[0] != " "
					var west_solid: bool = cells.get(p + Vector2i.LEFT, [" "])[0] != " "
					if north_solid or west_solid:
						var o := Vector2((p - view_origin) * cell) + cam_px_offset
						if north_solid:
							draw_rect(Rect2(o, Vector2(cell, cell * 0.42)), Color(0.02, 0.04, 0.05, 0.42))
						if west_solid:
							draw_rect(Rect2(o, Vector2(cell * 0.35, cell)), Color(0.02, 0.04, 0.05, 0.32))
	for y in range(visible.position.y, visible.end.y):
		for x in range(visible.position.x, visible.end.x):
			Art.ground(self, cells, Vector2i(x, y), seed, current_season)
	for y in range(props.position.y, props.end.y):
		for x in range(props.position.x, props.end.x):
			var p := Vector2i(x, y)
			Art.walls(self, cells, p, seed, current_season, lit_strength)
			Art.detail(self, world, cells, p, seed, current_season, emitters, lit_strength)
	if world.floor == 0:
		for y in range(visible.position.y, visible.end.y):
			for x in range(visible.position.x, visible.end.x):
				var p := Vector2i(x, y)
				var site: StringName = world.site_at(p)
				if site in [&"merchant", &"ferryman", &"altar", &"herb"]:
					Art.site_landmark(self, p, site, lit_strength)
	roof_layer.queue_redraw()
	player_layer.queue_redraw()
	markers.queue_redraw()


func _draw_roofs() -> void:
	if world == null or world.floor != 0:
		return
	var visible := Rect2i(view_origin, view_size).intersection(bounds).grow(1).intersection(bounds)
	var seed: int = world.seed ^ (world.floor * 0x65bd4e97)
	roof_system.draw_all(roof_layer, self, cells, visible, seed,
		scene_lighting.current_roof_light,
		weather.wetness if weather != null else 0.0,
		weather.snow_cover if weather != null else 0.0)


func _draw_player() -> void:
	if world == null:
		return
	var visible := Rect2i(view_origin, view_size).intersection(bounds)
	var pcell := Vector2i(roundi(motion.visual_pos.x), roundi(motion.visual_pos.y))
	if not visible.grow(1).has_point(pcell):
		return
	var tint := motion.compute_player_tint(cells, scene_lighting, weather)
	motion.draw_character(self, player_layer, &"player", motion.visual_pos, true, world.pos, tint)


func _draw_markers() -> void:
	var visible := Rect2i(view_origin, view_size).intersection(bounds)
	footprints.draw(markers, self, world, weather, scene_lighting.current_daylight, visible)
	for i in range(route_head, mini(route_head + 150, route.size())):
		var p: Vector2i = route[i]
		if visible.has_point(p):
			var pt := Vector2((p - view_origin) * cell) + cam_px_offset + Vector2.ONE * cell * 0.5
			markers.draw_circle(pt, 2.8, Color(0.08, 0.12, 0.10, 0.65))
			markers.draw_circle(pt, 2.0, Color("e8cf86"))
	if visible.has_point(hovered):
		var rect := Rect2(Vector2((hovered - view_origin) * cell) + cam_px_offset, Vector2.ONE * cell)
		markers.draw_rect(rect, Color(0.86, 0.93, 0.84, 0.45), false, 1.2)
		var c := maxf(3.0, cell * 0.16)
		var accent := Color("e6c87a")
		markers.draw_line(rect.position, rect.position + Vector2(c, 0), accent, 1.5)
		markers.draw_line(rect.position, rect.position + Vector2(0, c), accent, 1.5)
		markers.draw_line(rect.end, rect.end - Vector2(c, 0), accent, 1.5)
		markers.draw_line(rect.end, rect.end - Vector2(0, c), accent, 1.5)
	var pcell := Vector2i(roundi(motion.visual_pos.x), roundi(motion.visual_pos.y))
	if visible.grow(1).has_point(pcell):
		var center := (motion.visual_pos - Vector2(view_origin)) * float(cell) + cam_px_offset + Vector2(cell * 0.5, cell * 0.86)
		markers.draw_set_transform(center, 0, Vector2(1.0, 0.34))
		markers.draw_arc(Vector2.ZERO, cell * 0.40, 0, TAU, 24, Color(0.92, 0.82, 0.56, 0.65), 1.2, true)
		markers.draw_set_transform(Vector2.ZERO)
	Tiles.finish_frame()
