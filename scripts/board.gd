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
const ZOOMS := [20, 25, 32, 40, 48]
const SITE_NAMES := {&"merchant": "药商沈青", &"ferryman": "渡夫", &"altar": "吐纳石台", &"herb": "清露草", &"door": "门"}
const SEASON_KEYS := {"春": "spring", "夏": "summer", "秋": "autumn", "冬": "winter"}
const NONE := Vector2i(-1, -1)

var world: World
var route: Array = []
var route_head := 0
var bounds: Rect2i
var hovered := NONE
var view_center := Vector2i.ZERO
var view_origin := Vector2i.ZERO
var view_size := Vector2i.ONE
var zoom := 2
var cell := 32
var scene_lighting := SceneLighting.new()
var markers := Control.new()
var lighting_key: Array = []
var geometry_key: Array = []
var surface_key: Array = []
var emitter_area := Rect2i()
var emitter_herbs := -1
var geometry_area := Rect2i()
var cells: Dictionary = {}
var below_cells: Dictionary = {}
var current_season := "spring"
var can_read_upper_levels := false


func build(model: World) -> void:
	world = model
	can_read_upper_levels = world.has_method("terrain_at_level")
	invalidate_lightmap()
	bounds = Rect2i(Vector2i.ZERO, world.city_size)
	view_center = world.pos
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	scene_lighting.build(self)
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(markers)
	markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	markers.draw.connect(_draw_markers)
	mouse_exited.connect(_clear_hover)
	resized.connect(_update_view)


func follow(p: Vector2i) -> void:
	if view_center != p:
		hovered = NONE
	view_center = p
	_update_view()


func _update_view() -> void:
	cell = ZOOMS[zoom]
	view_size = Vector2i((size / float(cell)).ceil()).max(Vector2i.ONE)
	var max_origin := (world.city_size - view_size).max(Vector2i.ZERO)
	view_origin = (view_center - Vector2i(Vector2(view_size) / 2.0)).clamp(Vector2i.ZERO, max_origin)
	queue_redraw()


func _clear_hover() -> void:
	hovered = NONE
	queue_redraw()


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
		hovered = p
		queue_redraw()
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			cell_clicked.emit(p)
			accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			context_requested.emit(p)
			accept_event()


func _tile_at(screen: Vector2) -> Vector2i:
	return view_origin + Vector2i((screen / float(cell)).floor())


func _get_tooltip(at_position: Vector2) -> String:
	var p := _tile_at(at_position)
	if not bounds.has_point(p):
		return ""
	return SITE_NAMES.get(world.site_at(p), "")


func invalidate_lightmap() -> void:
	lighting_key.clear()
	geometry_key.clear()
	surface_key.clear()
	emitter_area = Rect2i()
	emitter_herbs = -1


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


func _collect_characters(visible: Rect2i) -> Array:
	var list: Array = []
	if world.floor == 0:
		for y in range(visible.position.y, visible.end.y):
			for x in range(visible.position.x, visible.end.x):
				var p := Vector2i(x, y)
				var site: StringName = world.site_at(p)
				if site == &"merchant" or site == &"ferryman":
					list.append([p, site])
	if visible.has_point(world.pos):
		list.append([world.pos, &"player"])
	return list


func _update_lightmap(visible: Rect2i, props: Rect2i) -> void:
	var sky := CanglingCalendar.at_minute(world.minutes)
	current_season = SEASON_KEYS.get(sky.season, "spring")
	var z: int = world.floor
	var layers := maxi(1, 3 - z) if can_read_upper_levels and z >= 0 else 1
	var reach := LightGeometry.REACH + SceneLighting.LIGHT_MARGIN + 1
	var required := props.grow(reach).intersection(bounds)
	var static_key: Array = [world.seed, z]
	if static_key != geometry_key or not geometry_area.encloses(required):
		geometry_area = props.grow(reach + 5).intersection(bounds)
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
		scene_lighting.set_geometry(cells, geometry_area, layers, z, world.seed)
		geometry_key = static_key
		lighting_key.clear()
		surface_key.clear()
		emitter_area = Rect2i()
	var characters := _collect_characters(visible)
	var mask_key: Array = [props, visible.position, size, cell, current_season, world.pos, characters.size()]
	if mask_key != surface_key:
		scene_lighting.update_surfaces(cells, props, visible.position, size, cell,
			world.seed ^ (z * 0x65bd4e97), current_season, characters)
		surface_key = mask_key
	if not emitter_area.encloses(props) or emitter_herbs != world.herbs:
		emitter_area = geometry_area.grow(-SceneLighting.PointLighting.REACH).merge(props).intersection(geometry_area)
		var sites := _collect_sites(emitter_area.grow(SceneLighting.PointLighting.REACH).intersection(geometry_area))
		scene_lighting.update_emitters(cells, geometry_area, emitter_area, sites, world.seed ^ (z * 0x65bd4e97))
		emitter_herbs = world.herbs
	var key: Array = [visible, world.minutes]
	if key != lighting_key:
		var tints := Lighting.calculate_ambient(cells, props.grow(1).intersection(bounds), sky, z)
		scene_lighting.update_light(tints, geometry_area, visible, sky, z)
		lighting_key = key
	scene_lighting.set_view(geometry_area, visible, size, cell, world.pos)


func _draw() -> void:
	if world == null:
		return
	var visible := Rect2i(view_origin, view_size).intersection(bounds)
	# Taller sprites can start below the viewport and extend into it.
	var props := visible.grow_individual(1, 0, 1, 2).intersection(bounds)
	_update_lightmap(visible, props)
	var seed: int = world.seed ^ (world.floor * 0x65bd4e97)
	var lit_strength: float = scene_lighting.current_lamp_power
	var emitters: Dictionary = scene_lighting.active_emitters
	# Multi-floor context: softly show ground level outside upper-floor buildings with elevation drop shadow.
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
						var o := Vector2((p - view_origin) * cell)
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
	if visible.has_point(world.pos):
		Art.character(self, world.pos, &"player")
	markers.queue_redraw()


func _draw_markers() -> void:
	var visible := Rect2i(view_origin, view_size).intersection(bounds)
	for i in range(route_head, mini(route_head + 150, route.size())):
		var p: Vector2i = route[i]
		if visible.has_point(p):
			var pt := Vector2((p - view_origin) * cell) + Vector2.ONE * cell * 0.5
			markers.draw_circle(pt, 2.8, Color(0.08, 0.12, 0.10, 0.65))
			markers.draw_circle(pt, 2.0, Color("e8cf86"))
	if visible.has_point(hovered):
		var rect := Rect2(Vector2((hovered - view_origin) * cell), Vector2.ONE * cell)
		markers.draw_rect(rect, Color(0.86, 0.93, 0.84, 0.45), false, 1.2)
		var c := maxf(3.0, cell * 0.16)
		var accent := Color("e6c87a")
		markers.draw_line(rect.position, rect.position + Vector2(c, 0), accent, 1.5)
		markers.draw_line(rect.position, rect.position + Vector2(0, c), accent, 1.5)
		markers.draw_line(rect.end, rect.end - Vector2(c, 0), accent, 1.5)
		markers.draw_line(rect.end, rect.end - Vector2(0, c), accent, 1.5)
	if visible.has_point(world.pos):
		var center := Vector2((world.pos - view_origin) * cell) + Vector2(cell * 0.5, cell * 0.86)
		markers.draw_set_transform(center, 0, Vector2(1.0, 0.34))
		markers.draw_arc(Vector2.ZERO, cell * 0.40, 0, TAU, 24, Color(0.92, 0.82, 0.56, 0.72), 1.2, true)
		markers.draw_set_transform(Vector2.ZERO)
	Tiles.finish_frame()
