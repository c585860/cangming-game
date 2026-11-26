extends Control

signal cell_clicked(cell: Vector2i)
signal context_requested(cell: Vector2i)

const World = preload("res://scripts/world.gd")
const CanglingCalendar = preload("res://scripts/cangling_calendar.gd")
const Tiles = preload("res://scripts/undead_tiles.gd")
const Lighting = preload("res://scripts/lighting.gd")
const LightGeometry = preload("res://scripts/light_geometry.gd")
const SceneLighting = preload("res://scripts/scene_lighting.gd")
const WorldCache = preload("res://scripts/world_cache.gd")
const Weather = preload("res://scripts/weather.gd")
const WeatherFx = preload("res://scripts/weather_fx.gd")
const FootprintTrail = preload("res://scripts/footprints.gd")
const CharacterMotion = preload("res://scripts/character_motion.gd")
const RoofSystem = preload("res://scripts/roof_system.gd")
const AmbientLife = preload("res://scripts/ambient_life.gd")
const ZOOMS := [20, 25, 32, 40, 48]
const SITE_NAMES := {
	&"innkeeper": "冼老板 (醉仙楼掌柜)",
	&"blacksmith": "王铁匠 (王记铁匠铺)",
	&"herbalist": "平大夫 (回春堂药铺)",
	&"martial_master": "陈馆主 (扬威武馆)",
	&"weapon_coach": "周教头 (扬威武馆教头)",
	&"scholar": "顾夫子 (文昌书院山长)",
	&"pawnbroker": "唐掌柜 (利源当铺)",
	&"boatman": "老船夫 (水埠码头)",
	&"storyteller": "说书先生 (春风茶馆)",
	&"grocer": "福兴掌柜 (福兴杂货铺)",
	&"banker": "钱庄掌柜 (通济钱庄)",
	&"waiter": "客栈店小二 (悦来客栈)",
	&"sparring_disciple": "武馆陪练弟子 (扬威武馆)",
	&"notice_board": "沧灵告示牌 (江湖委托)",
	&"door": "门",
}
const NPC_SITES := [
	&"innkeeper", &"blacksmith", &"herbalist", &"martial_master",
	&"weapon_coach", &"scholar", &"pawnbroker", &"boatman", &"storyteller",
	&"grocer", &"banker", &"waiter", &"sparring_disciple",
]
const SEASON_KEYS := {"春": "spring", "夏": "summer", "秋": "autumn", "冬": "winter"}
const NONE := Vector2i(-1, -1)

static var _ascii_chars: PackedStringArray = PackedStringArray()
static var _empty_upper := PackedStringArray()

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

var world_cache := WorldCache.new()
var scene_lighting := SceneLighting.new()
var roof_system := RoofSystem.new()
var footprints := FootprintTrail.new()
var motion := CharacterMotion.new()
var ambient_life := AmbientLife.new()
var water_life_layer := Control.new()
var roof_layer := Control.new()
var player_layer := Control.new()
var markers := Control.new()
var sky_life_layer := Control.new()
var weather_fx := WeatherFx.new()

var lighting_key: Array = []
var baked_light_area := Rect2i()
var baked_light_minutes := -99999
var baked_ray_minutes := -99999
var geometry_key: Array = []
var surface_key: Array = []
var emitter_area := Rect2i()
var emitter_herbs := -1
var geometry_area := Rect2i()
var cells_area := Rect2i()
var _last_baked_region: Dictionary = {}
var _last_baked_area := Rect2i()
var _last_baked_z := -999
var _preload_phase := 0 # 0=idle, 1=world_slices, 2=mask_slices, 3=commit_swap
var _preload_rect := Rect2i()
var _preload_props := Rect2i()
var cells: Dictionary = {}
var below_cells: Dictionary = {}
var current_season := "spring"
var can_read_upper_levels := false
var visual_time := 0.0
var work_progress := 0.0 # 0.0..1.0 active 2.5s workstation progress bar
var work_label := ""
var _last_player_pos := NONE
var _camera_initialized := false


var roofs_enabled: bool:
	get: return roof_system.enabled
	set(v): roof_system.enabled = v


static func _ensure_ascii_table() -> void:
	if not _ascii_chars.is_empty():
		return
	_ascii_chars.resize(128)
	_ascii_chars[0] = ""
	for i in range(1, 128):
		_ascii_chars[i] = char(i)


func build(model: World, weather_model: Weather = null) -> void:
	_ensure_ascii_table()
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

	world_cache.build(self)
	roof_system.build_cache(self)
	scene_lighting.build(self)
	scene_lighting.set_world_texture(world_cache.get_texture())

	# Layer order above GPU-lit scene: canal boats -> roofs -> animated player -> footprints/markers -> banners/geese/motes -> GPU rain/snow
	water_life_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(water_life_layer)
	water_life_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	water_life_layer.draw.connect(_draw_water_life)

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

	sky_life_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky_life_layer)
	sky_life_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_life_layer.draw.connect(_draw_sky_life)

	add_child(weather_fx)
	weather_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_exited.connect(_clear_hover)
	resized.connect(_update_view)
	set_process(true)


func _process(delta: float) -> void:
	if world == null:
		return
	visual_time += delta

	# Automatic C++ memory management + cold sprite atlas page reclamation.
	if world.tick_memory(delta):
		Tiles.trim_unused_pages()

	# 1. Decoupled FPS weather evolution (dynamic puddles & snow) + Jiangnan ambient life (boats/birds/banners/sparks)
	if weather != null:
		weather.tick_visual(delta)
		scene_lighting.update_weather_visual(weather)
	ambient_life.tick(delta, motion.visual_pos, world)
	water_life_layer.queue_redraw()
	sky_life_layer.queue_redraw()

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

	# 4. High-res near shadow cascade, smooth dawn/dusk interpolation & live 60 FPS moving firelight
	if scene_lighting.tick_smooth_light(delta):
		roof_layer.queue_redraw()
		player_layer.queue_redraw()
	if geometry_area.has_area():
		scene_lighting.tick_near_cascade(geometry_area, motion.visual_pos, visual_time, delta)
		var st_live: Dictionary = world.character_status()
		var live_ls: int = int(st_live.get("light_source", 0))
		scene_lighting.set_player_light(geometry_area, motion.visual_pos, live_ls, motion.facing_x)
		if live_ls > 0:
			player_layer.queue_redraw()

	# 4.5. Double-buffered frame-sliced background preload (~4-5ms/frame) so wide-FOV walking NEVER stutters!
	if geometry_area.has_area():
		_tick_incremental_preload()

	# 5. Pure GPU pan inside world_cache margin (0 CPU tile/mask redraws!)
	if cam_moved:
		_recompute_camera_window()
		var visible := Rect2i(view_origin, view_size).intersection(bounds)
		if not world_cache.cache_rect.encloses(visible) \
				or not baked_light_area.encloses(visible) \
				or not geometry_area.has_area():
			_sync_render_state()
		else:
			scene_lighting.set_view(geometry_area, view_world_exact, size, cell, motion.visual_pos)
			weather_fx.set_view(view_world_exact, size / float(cell), size)
		roof_layer.queue_redraw()
		player_layer.queue_redraw()
		markers.queue_redraw()
	else:
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
		var z: int = world.floor
		weather_fx.configure(weather.rain if z == 0 else 0.0,
			weather.snow if z == 0 else 0.0,
			scene_lighting.current_daylight, view_world_exact, size / float(cell), size,
			view_origin, view_size, roof_system.revealed_interior)
	Tiles.finish_frame()


func snap_visuals() -> void:
	if world == null:
		return
	motion.snap_to(world.pos)
	camera_world = Vector2(view_center) + Vector2(0.5, 0.5)
	_recompute_camera_window()
	roof_system.update_targets(motion.visual_pos, world.floor, true)
	roof_system.snap(world.floor)
	_sync_render_state()
	scene_lighting.snap_smooth_light()
	roof_layer.queue_redraw()
	player_layer.queue_redraw()
	markers.queue_redraw()


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
		return
	# Fast path: if all GPU caches already enclose visible area and time hasn't hit the next light step,
	# skip heavy _sync_render_state() — 60 FPS _process() handles smooth pan & lighting seamlessly!
	if size.x >= 2.0 and size.y >= 2.0 and geometry_area.has_area():
		_recompute_camera_window()
		var visible := Rect2i(view_origin, view_size).intersection(bounds)
		var sky := CanglingCalendar.at_minute(world.minutes)
		var min_step := 1 if absf(float(sky.sun_altitude)) < deg_to_rad(18.0) else 5
		if world_cache.cache_rect.encloses(visible) \
				and baked_light_area.encloses(visible) \
				and cells_area.encloses(visible.grow(2).intersection(bounds)) \
				and absi(world.minutes - baked_light_minutes) < min_step \
				and emitter_herbs == world.herbs:
			roof_layer.queue_redraw()
			player_layer.queue_redraw()
			markers.queue_redraw()
			return
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
	if world == null or size.x < 2.0 or size.y < 2.0:
		return
	_recompute_camera_window()
	_sync_render_state()
	roof_layer.queue_redraw()
	player_layer.queue_redraw()
	markers.queue_redraw()


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


func _tick_incremental_preload() -> void:
	var visible := Rect2i(view_origin, view_size).intersection(bounds)
	if not visible.has_area():
		return
	if _preload_phase == 0:
		if not world_cache.needs_preload(visible, cell):
			return
		var margin := WorldCache.margin_for_cell(cell)
		var target_rect := visible.grow(margin).intersection(bounds)
		var target_props := target_rect.grow_individual(1, 0, 1, 2).intersection(bounds)
		# Only start async preload if our geometry & cells already cover the target rect!
		if not geometry_area.encloses(target_props):
			return
		if not cells_area.encloses(target_props):
			if not _last_baked_region.is_empty() and _last_baked_z == world.floor and _last_baked_area == geometry_area:
				cells_area = target_props.grow(8).intersection(geometry_area)
				_populate_cells_from_baked(_last_baked_region, geometry_area, cells_area, world.floor)
				roof_system.index_buildings(cells, cells_area)
			else:
				return
		var prect := world_cache.begin_preload(world, cells, below_cells, visible, bounds, cell,
			current_season, scene_lighting.active_emitters, scene_lighting.current_lamp_power)
		if prect.has_area():
			_preload_rect = prect
			_preload_props = prect.grow_individual(1, 0, 1, 2).intersection(bounds)
			_preload_phase = 1
	elif _preload_phase == 1:
		if world_cache.step_preload_slice():
			var npcs := _collect_npc_characters(_preload_rect)
			scene_lighting.begin_surface_preload(cells, _preload_rect, _preload_props, cell,
				world.seed ^ (world.floor * 0x65bd4e97), current_season, npcs)
			_preload_phase = 2
	elif _preload_phase == 2:
		if scene_lighting.step_surface_preload_slice(12):
			_preload_phase = 3
	elif _preload_phase == 3:
		# Atomic 0.01ms GPU pointer swap — back buffer is 100% rendered on GPU!
		world_cache.commit_preload()
		scene_lighting.set_world_texture(world_cache.get_texture())
		scene_lighting.commit_surface_preload()
		scene_lighting.set_cache_window(geometry_area, world_cache.cache_rect)
		var npcs := _collect_npc_characters(world_cache.cache_rect)
		surface_key = [world_cache.cache_rect, cell, current_season, world.floor, npcs.size()]
		_preload_phase = 0
		roof_layer.queue_redraw()


func invalidate_lightmap() -> void:
	_preload_phase = 0
	lighting_key.clear()
	baked_light_area = Rect2i()
	baked_light_minutes = -99999
	baked_ray_minutes = -99999
	geometry_key.clear()
	cells_area = Rect2i()
	_last_baked_region.clear()
	surface_key.clear()
	emitter_area = Rect2i()
	emitter_herbs = -1
	world_cache.invalidate()
	roof_system.invalidate_cache()


func invalidate_world_cache() -> void:
	_preload_phase = 0
	world_cache.invalidate()
	roof_system.invalidate_cache()
	surface_key.clear()
	if world != null and size.x >= 2.0 and size.y >= 2.0:
		_sync_render_state()


func invalidate_weather() -> void:
	lighting_key.clear()
	baked_light_area = Rect2i()
	baked_light_minutes = -99999
	baked_ray_minutes = -99999
	surface_key.clear()
	world_cache.invalidate()
	roof_system.invalidate_cache()
	_update_view()


func _collect_sites(region: Rect2i) -> Dictionary:
	if world.floor != 0:
		return {}
	return world.active_sites_in_rect(region)


func _collect_npc_characters(region: Rect2i) -> Array:
	var list: Array = []
	if world.floor == 0:
		var sites: Dictionary = world.active_sites_in_rect(region)
		for p: Vector2i in sites:
			var site: StringName = sites[p]
			if site in NPC_SITES:
				list.append([Vector2(p), site, false, p, null])
	return list


func _populate_cells_from_baked(baked: Dictionary, baked_area: Rect2i, sub_area: Rect2i, z: int) -> void:
	cells.clear()
	below_cells.clear()
	var tiles_buf: PackedByteArray = baked["tiles"]
	var surf_buf: PackedByteArray = baked["surfaces"]
	var flags_buf: PackedByteArray = baked["flags"]
	var has_below := z > 0 and baked.has("below_tiles")
	var bt_buf: PackedByteArray = baked["below_tiles"] if has_below else PackedByteArray()
	var bs_buf: PackedByteArray = baked["below_surfaces"] if has_below else PackedByteArray()
	var bw := baked_area.size.x
	var bx0 := baked_area.position.x
	var by0 := baked_area.position.y
	var sx0 := maxi(sub_area.position.x, bx0)
	var sy0 := maxi(sub_area.position.y, by0)
	var sx1 := mini(sub_area.end.x, baked_area.end.x)
	var sy1 := mini(sub_area.end.y, baked_area.end.y)
	var chars := _ascii_chars
	var empty_up := _empty_upper
	for wy in range(sy0, sy1):
		var row_off := (wy - by0) * bw - bx0
		for wx in range(sx0, sx1):
			var idx := row_off + wx
			var p := Vector2i(wx, wy)
			var tb := tiles_buf[idx]
			var sb := surf_buf[idx]
			var t_str := chars[tb] if tb < 128 else " "
			var s_str := chars[sb] if sb < 128 else ""
			cells[p] = [t_str, s_str, empty_up, flags_buf[idx]]
			if has_below and tb == 32:
				var btb := bt_buf[idx]
				var bsb := bs_buf[idx]
				below_cells[p] = [chars[btb] if btb < 128 else " ", chars[bsb] if bsb < 128 else ""]


func _sync_render_state() -> void:
	if world == null or size.x < 2.0 or size.y < 2.0:
		return
	var visible := Rect2i(view_origin, view_size).intersection(bounds)
	if not visible.has_area():
		return
	var cache_margin := WorldCache.margin_for_cell(cell)
	var cached_needed := visible.grow(cache_margin + 2).intersection(bounds)
	var props := cached_needed.grow_individual(1, 0, 1, 2).intersection(bounds)

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
		var static_changed := (static_key != geometry_key)
		# Large +18 tile geometry margin + background C++ multi-core sector prewarm eliminate frequent hitches!
		geometry_area = props.grow(reach + 18).intersection(bounds)
		world.prewarm_area(geometry_area.grow(24))
		var baked: Dictionary = world.bake_region_data(geometry_area, z, layers, current_season)
		_last_baked_region = baked
		_last_baked_area = geometry_area
		_last_baked_z = z
		cells_area = props.grow(10).intersection(geometry_area)
		_populate_cells_from_baked(baked, geometry_area, cells_area, z)
		scene_lighting.set_geometry_baked(baked, geometry_area, layers, z, world.seed)
		roof_system.index_buildings(cells, cells_area)
		geometry_key = static_key
		lighting_key.clear()
		baked_light_area = Rect2i()
		emitter_area = Rect2i()
		if static_changed:
			surface_key.clear()
			world_cache.invalidate()
			roof_system.invalidate_cache()
		rebuilt_geom = true
	elif not cells_area.encloses(props) and not _last_baked_region.is_empty() and _last_baked_z == z and _last_baked_area == geometry_area:
		cells_area = props.grow(10).intersection(geometry_area)
		_populate_cells_from_baked(_last_baked_region, geometry_area, cells_area, z)
		roof_system.index_buildings(cells, cells_area)
	roof_system.update_targets(motion.visual_pos, z, rebuilt_geom)

	if not emitter_area.encloses(props) or emitter_herbs != world.herbs:
		emitter_area = geometry_area.grow(-SceneLighting.PointLighting.REACH).merge(props).intersection(geometry_area)
		var sites := _collect_sites(emitter_area.grow(SceneLighting.PointLighting.REACH).intersection(geometry_area))
		var point_baked: Dictionary = world.bake_point_lights_data(geometry_area, emitter_area, z, sites, world.seed ^ (z * 0x65bd4e97))
		scene_lighting.update_emitters_baked(point_baked, geometry_area)
		emitter_herbs = world.herbs

	# Smooth twilight: update ambient + scalars every 1 min (fast ~0.3ms), while heavy 4x4 raymarched solar/volume/bounce
	# only re-bakes every 4 min or when moving outside baked_light_area!
	var in_twilight := absf(float(sky.sun_altitude)) < deg_to_rad(18.0)
	var min_step := 1 if in_twilight else 5
	var ray_step := 4 if in_twilight else 10
	var weather_key: Array = [z, weather.current_kind, int(round(weather.wetness * 20.0)),
		int(round(weather.snow_cover * 20.0)), int(round(weather.rain * 20.0)), int(round(weather.snow * 20.0)), visible.size]
	var need_rays := (weather_key != lighting_key) \
		or (not baked_light_area.encloses(visible)) \
		or (absi(world.minutes - baked_ray_minutes) >= ray_step)
	var needs_light_bake := need_rays or (absi(world.minutes - baked_light_minutes) >= min_step)
	if needs_light_bake:
		var ambient_region := props.grow(SceneLighting.LIGHT_MARGIN).intersection(geometry_area)
		var ambient_bytes: PackedByteArray = world.bake_ambient_data(geometry_area, ambient_region, z,
			Lighting._natural_light(sky), float(sky.sun_warmth))
		scene_lighting.update_light_baked(ambient_bytes, geometry_area, visible, sky, z, weather, motion.visual_pos, visual_time, need_rays)
		if need_rays:
			baked_light_area = visible.grow(maxi(1, SceneLighting.LIGHT_MARGIN - 2)).intersection(bounds)
			baked_ray_minutes = world.minutes
		baked_light_minutes = world.minutes
		lighting_key = weather_key

	# GPU-cached static world & surface mask (synchronous fallback on zoom/teleport/edit; normal walking uses double-buffered preload!)
	var cache_rebuilt := world_cache.ensure_updated(world, cells, below_cells, visible, bounds, cell,
		current_season, scene_lighting.active_emitters, scene_lighting.current_lamp_power)
	if cache_rebuilt:
		_preload_phase = 0
		scene_lighting.set_world_texture(world_cache.get_texture())
	var crect := world_cache.cache_rect
	if crect.has_area():
		scene_lighting.set_cache_window(geometry_area, crect)
		var mask_props := crect.grow_individual(1, 0, 1, 2).intersection(bounds)
		var npcs := _collect_npc_characters(crect)
		var mask_key: Array = [crect, cell, current_season, z, npcs.size()]
		if cache_rebuilt or mask_key != surface_key:
			scene_lighting.update_surfaces_cached(cells, crect, mask_props, cell,
				world.seed ^ (z * 0x65bd4e97), current_season, npcs)
			surface_key = mask_key

	weather_fx.configure(weather.rain if z == 0 else 0.0, weather.snow if z == 0 else 0.0,
		scene_lighting.current_daylight, view_world_exact, size / float(cell), size,
		view_origin, view_size, roof_system.revealed_interior)
	scene_lighting.set_view(geometry_area, view_world_exact, size, cell, motion.visual_pos)
	var st_sync: Dictionary = world.character_status()
	scene_lighting.set_player_light(geometry_area, motion.visual_pos, int(st_sync.get("light_source", 0)), motion.facing_x)


func _draw() -> void:
	if world == null:
		return
	_sync_render_state()
	roof_layer.queue_redraw()
	player_layer.queue_redraw()
	markers.queue_redraw()


func enter_posture(kind: StringName, furniture_tile: Vector2i) -> void:
	if world == null:
		return
	motion.enter_posture(kind, furniture_tile, cells, world.seed ^ (world.floor * 0x65bd4e97))
	player_layer.queue_redraw()
	markers.queue_redraw()


func exit_posture() -> void:
	if world == null or not motion.is_resting():
		return
	motion.exit_posture(world.pos)
	player_layer.queue_redraw()
	markers.queue_redraw()


func _draw_water_life() -> void:
	if world == null:
		return
	ambient_life.draw_water_layer(water_life_layer, self, scene_lighting.current_daylight, scene_lighting.current_lamp_power)


func _draw_sky_life() -> void:
	if world == null:
		return
	ambient_life.draw_sky_layer(sky_life_layer, self, current_season, scene_lighting.current_daylight, scene_lighting.current_lamp_power)


func _draw_roofs() -> void:
	if world == null or world.floor != 0:
		return
	var visible := Rect2i(view_origin, view_size).intersection(bounds).grow(1).intersection(bounds)
	var seed: int = world.seed ^ (world.floor * 0x65bd4e97)
	roof_system.draw_all(roof_layer, self, cells, visible, seed,
		scene_lighting.current_roof_light,
		weather.wetness if weather != null else 0.0,
		weather.snow_cover if weather != null else 0.0,
		scene_lighting.current_lamp_power)


func _draw_player() -> void:
	if world == null:
		return
	var visible := Rect2i(view_origin, view_size).intersection(bounds)
	var pcell := Vector2i(roundi(motion.visual_pos.x), roundi(motion.visual_pos.y))
	if not visible.grow(1).has_point(pcell):
		return
	var st: Dictionary = world.character_status()
	var ls: int = int(st.get("light_source", 0))
	var tint := motion.compute_player_tint(cells, scene_lighting, weather)
	if ls > 0:
		var flicker := 0.92 + 0.08 * sin(visual_time * 13.7) + 0.05 * sin(visual_time * 23.1)
		var warm := Color(1.06, 0.80, 0.56) if ls == 1 else (Color(1.08, 0.88, 0.64) if ls == 2 else Color(1.10, 0.95, 0.74))
		tint = tint.lerp(warm * flicker, 0.58 if ls == 1 else 0.68)
	motion.draw_character(self, player_layer, &"player", motion.visual_pos, true, world.pos, tint, world.worn_overlays())
	# Multiplayer Hook: Render synced remote players on the same floor (zero cost in single-player!)
	if world.remote_player_count() > 0:
		var remotes: Array = world.remote_players_in_rect(visible.grow(1))
		var rfont := get_theme_default_font()
		for rp: Dictionary in remotes:
			var rpos: Vector2i = rp.get("pos", Vector2i.ZERO)
			var rname: String = str(rp.get("name", "同道"))
			var rov: PackedStringArray = rp.get("worn_overlays", PackedStringArray())
			var rtint := Color(0.88, 0.98, 0.96, 1.0) * scene_lighting.current_roof_light.clamp(Color(0.45, 0.45, 0.50), Color.WHITE)
			motion.draw_character(self, player_layer, &"remote_player", Vector2(rpos), false, rpos, rtint, rov)
			var rpx := Vector2((rpos - view_origin) * cell) + cam_px_offset
			var ring_c := rpx + Vector2(cell * 0.5, cell * 0.86)
			player_layer.draw_set_transform(ring_c, 0, Vector2(1.0, 0.34))
			player_layer.draw_arc(Vector2.ZERO, cell * 0.40, 0, TAU, 20, Color("66e0c2", 0.82), 1.4, true)
			player_layer.draw_set_transform(Vector2.ZERO)
			if rfont != null and cell >= 20:
				var tw := rfont.get_string_size(rname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				var tag := Rect2(rpx + Vector2((cell - tw - 8.0) * 0.5, -15.0), Vector2(tw + 8.0, 15.0))
				player_layer.draw_rect(tag, Color(0.06, 0.14, 0.13, 0.86))
				player_layer.draw_rect(tag, Color(0.40, 0.85, 0.74, 0.82), false, 1.0)
				player_layer.draw_string(rfont, tag.position + Vector2(4.0, 12.0), rname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b4f5e4"))
	# Tiny physical flame tip held in character's hand (real wall-occluded light is rendered by GPU atmosphere.gdshader!)
	if ls > 0 and not motion.is_resting():
		var f_sway := Vector2(sin(visual_time * 9.5) * 0.7, -absf(cos(visual_time * 15.2)) * 0.8)
		var hand_off := Vector2(0.68 if motion.facing_x >= 0 else 0.32, 0.56)
		var tip := (motion.visual_pos - Vector2(view_origin)) * float(cell) + cam_px_offset + hand_off * float(cell) + f_sway
		var fcol := Color(1.0, 0.52, 0.16, 0.88) if ls == 1 else (Color(1.0, 0.72, 0.28, 0.90) if ls == 2 else Color(1.0, 0.84, 0.45, 0.92))
		var r := maxf(1.6, float(cell) * (0.065 if ls == 1 else 0.08))
		player_layer.draw_circle(tip, r * 1.9, Color(fcol.r, fcol.g, fcol.b, 0.24))
		player_layer.draw_circle(tip, r, fcol)
		player_layer.draw_circle(tip + Vector2(0.0, -r * 0.25), r * 0.48, Color(1.0, 0.96, 0.82, 0.95))


func _draw_markers() -> void:
	var visible := Rect2i(view_origin, view_size).intersection(bounds)
	footprints.draw(markers, self, world, weather, scene_lighting.current_daylight, visible)
	# Subtle workstation markers when interior/yard is visible (emerald = unlocked, warm amber = learn prereq)
	if world != null and world.floor == 0 and cell >= 24:
		var stations: Array = world.workstations_in_rect(visible)
		for ws: Dictionary in stations:
			var wp: Vector2i = ws.get("pos", Vector2i.ZERO)
			if roof_system.has_roof_at(wp) and roof_system.alpha_at(wp) >= 0.55:
				continue
			var unlocked: bool = bool(ws.get("unlocked", false))
			var center := Vector2((wp - view_origin) * cell) + cam_px_offset + Vector2(cell * 0.82, cell * 0.20)
			var r := maxf(2.6, float(cell) * 0.11)
			var col := Color("5be2a8", 0.90) if unlocked else Color("e0a94c", 0.72)
			var poly := PackedVector2Array([
				center + Vector2(0, -r), center + Vector2(r, 0),
				center + Vector2(0, r), center + Vector2(-r, 0),
			])
			markers.draw_colored_polygon(poly, Color(0.06, 0.09, 0.08, 0.85))
			markers.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -r * 0.72), center + Vector2(r * 0.72, 0),
				center + Vector2(0, r * 0.72), center + Vector2(-r * 0.72, 0),
			]), col)
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
	if world != null and world.is_grabbing():
		var gp: Vector2i = world.pos + world.get_grab_offset()
		if visible.grow(1).has_point(gp):
			var grect := Rect2(Vector2((gp - view_origin) * cell) + cam_px_offset, Vector2.ONE * cell)
			markers.draw_rect(grect.grow(-1.0), Color(0.95, 0.78, 0.36, 0.85), false, 2.0)
			var p_mid := (motion.visual_pos - Vector2(view_origin)) * float(cell) + cam_px_offset + Vector2.ONE * (cell * 0.5)
			var g_mid := grect.position + grect.size * 0.5
			markers.draw_line(p_mid, g_mid, Color(0.95, 0.78, 0.36, 0.65), 1.6, true)
	var pcell := Vector2i(roundi(motion.visual_pos.x), roundi(motion.visual_pos.y))
	if visible.grow(1).has_point(pcell) and not motion.is_resting():
		var st: Dictionary = world.character_status()
		var mmode: int = int(st.get("move_mode", 0))
		var hauling: bool = bool(st.get("hauling", false))
		var ring_col := Color(0.92, 0.82, 0.56, 0.65)
		if hauling:
			ring_col = Color(0.36, 0.84, 0.84, 0.82)
		elif mmode == 1:
			ring_col = Color(0.95, 0.72, 0.28, 0.82)
		elif mmode == 2:
			ring_col = Color(0.55, 0.72, 0.88, 0.72)
		elif mmode == 3:
			ring_col = Color(0.55, 0.55, 0.58, 0.68)
		var center := (motion.visual_pos - Vector2(view_origin)) * float(cell) + cam_px_offset + Vector2(cell * 0.5, cell * 0.86)
		markers.draw_set_transform(center, 0, Vector2(1.0, 0.34))
		markers.draw_arc(Vector2.ZERO, cell * 0.40, 0, TAU, 24, ring_col, 1.3, true)
		markers.draw_set_transform(Vector2.ZERO)
	# Central Square Notice Board ('榜') wooden stand marker
	if world != null and world.floor == 0 and cell >= 20:
		var nb: Vector2i = world.notice_board_pos()
		if visible.has_point(nb):
			var nbo := Vector2((nb - view_origin) * cell) + cam_px_offset
			var br := Rect2(nbo.x + cell * 0.16, nbo.y + cell * 0.12, cell * 0.68, cell * 0.52)
			markers.draw_rect(Rect2(nbo.x + cell * 0.44, nbo.y + cell * 0.58, cell * 0.12, cell * 0.34), Color("4e2e1b"))
			markers.draw_rect(br, Color("7b4c2a"))
			markers.draw_rect(br.grow(-2.0), Color("e7dbb8"))
			markers.draw_rect(br, Color("3c2112"), false, 1.4)
			var nbf := get_theme_default_font()
			if nbf != null:
				markers.draw_string(nbf, Vector2(br.position.x + br.size.x * 0.24, br.position.y + br.size.y * 0.78), "榜", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(cell * 0.38)), Color("8f251c"))
	# Active Wuxia Sparring opponent HP banner
	if world != null and world.floor == 0:
		var sp: Dictionary = world.spar_status()
		if bool(sp.get("active", false)):
			var opp_p: Vector2i = sp.get("npc_pos", Vector2i.ZERO)
			if visible.grow(1).has_point(opp_p):
				var op_top := Vector2((opp_p - view_origin) * cell) + cam_px_offset + Vector2(cell * 0.5, -14.0)
				var ohp: float = float(sp.get("opp_hp", 1))
				var omax: float = maxf(1.0, float(sp.get("opp_max_hp", 100)))
				var bw := 84.0
				var bar_r := Rect2(op_top - Vector2(bw * 0.5, 0.0), Vector2(bw, 8.0))
				markers.draw_rect(bar_r.grow(1.5), Color(0.06, 0.04, 0.04, 0.90))
				markers.draw_rect(Rect2(bar_r.position, Vector2(bw * clampf(ohp / omax, 0.0, 1.0), 8.0)), Color("e35d4f"))
				markers.draw_rect(bar_r.grow(1.5), Color("e6c87a"), false, 1.0)
	# 2.5s Real-Time Workstation / Craft / Study / Dazuo Progress Bar right above player!
	if work_progress > 0.001:
		var p_top := (motion.visual_pos - Vector2(view_origin)) * float(cell) + cam_px_offset + Vector2(cell * 0.5, -18.0)
		var bw := 112.0
		var bh := 10.0
		var bar_r := Rect2(p_top - Vector2(bw * 0.5, 0.0), Vector2(bw, bh))
		markers.draw_rect(bar_r.grow(2.0), Color(0.05, 0.08, 0.07, 0.92))
		markers.draw_rect(bar_r, Color(0.16, 0.20, 0.19, 0.95))
		markers.draw_rect(Rect2(bar_r.position, Vector2(bw * clampf(work_progress, 0.0, 1.0), bh)), Color("5be2a8"))
		markers.draw_rect(bar_r.grow(2.0), Color("d9be72"), false, 1.0)
		var wf := get_theme_default_font()
		if wf != null:
			var cap := "%s %d%%" % [work_label, int(round(work_progress * 100.0))]
			var tw := wf.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			markers.draw_rect(Rect2(p_top.x - tw * 0.5 - 4.0, p_top.y - 16.0, tw + 8.0, 14.0), Color(0.05, 0.08, 0.07, 0.88))
			markers.draw_string(wf, Vector2(p_top.x - tw * 0.5, p_top.y - 5.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f3dca0"))
	Tiles.finish_frame()
