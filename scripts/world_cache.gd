extends RefCounted

# GPU-cached static world renderer.
# Draws ground, walls, details, and static landmarks into an oversized SubViewport
# (visible viewport + CACHE_MARGIN tiles on all sides) with UPDATE_ONCE.
# During smooth 60/144 FPS camera panning inside the margin, atmosphere.gdshader
# pans the cached texture directly on the GPU with ZERO CPU tile redraws!

const Art = preload("res://scripts/street_art.gd")
const CACHE_MARGIN := 4

var view: SubViewport
var canvas: WorldCanvas
var cache_rect := Rect2i()
var cache_key: Array = []
var dirty := true


class WorldCanvas extends Control:
	var world: Object
	var cells: Dictionary = {}
	var below_cells: Dictionary = {}
	var view_origin := Vector2i.ZERO
	var cam_px_offset := Vector2.ZERO
	var cell := 32
	var draw_rect_tiles := Rect2i()
	var props_rect := Rect2i()
	var seed := 0
	var current_season := "spring"
	var floor_z := 0
	var lit_strength := 0.0
	var emitters: Dictionary = {}

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if world == null or not draw_rect_tiles.has_area():
			return
		# Dark ink backdrop so any out-of-bounds area stays clean.
		draw_rect(Rect2(Vector2.ZERO, size), Color("090d0b"))
		if floor_z > 0 and not below_cells.is_empty():
			var sky_factor := clampf(1.0 - lit_strength * 0.72, 0.22, 1.0)
			var depth_tint := Color(0.35 * sky_factor, 0.42 * sky_factor, 0.48 * sky_factor, 1.0)
			for y in range(draw_rect_tiles.position.y, draw_rect_tiles.end.y):
				for x in range(draw_rect_tiles.position.x, draw_rect_tiles.end.x):
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
		for y in range(draw_rect_tiles.position.y, draw_rect_tiles.end.y):
			for x in range(draw_rect_tiles.position.x, draw_rect_tiles.end.x):
				Art.ground(self, cells, Vector2i(x, y), seed, current_season)
		for y in range(props_rect.position.y, props_rect.end.y):
			for x in range(props_rect.position.x, props_rect.end.x):
				var p := Vector2i(x, y)
				Art.walls(self, cells, p, seed, current_season, lit_strength)
				Art.detail(self, world, cells, p, seed, current_season, emitters, lit_strength)
		if floor_z == 0:
			for y in range(draw_rect_tiles.position.y, draw_rect_tiles.end.y):
				for x in range(draw_rect_tiles.position.x, draw_rect_tiles.end.x):
					var p := Vector2i(x, y)
					var site: StringName = world.site_at(p)
					if site in [&"merchant", &"ferryman", &"altar", &"herb"]:
						Art.site_landmark(self, p, site, lit_strength)


func build(parent: Control) -> void:
	view = SubViewport.new()
	view.disable_3d = true
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(view)
	canvas = WorldCanvas.new()
	view.add_child(canvas)


func invalidate() -> void:
	dirty = true
	cache_key.clear()


func get_texture() -> ViewportTexture:
	return view.get_texture()


func ensure_updated(world: Object, cells: Dictionary, below_cells: Dictionary, visible: Rect2i,
		bounds: Rect2i, cell: int, season: String, emitters: Dictionary, lit_strength: float) -> bool:
	var lit_bucket := int(round(lit_strength * 6.0))
	var key: Array = [world.seed, world.floor, cell, season, lit_bucket, world.herbs, emitters.size()]
	var needs_rebuild := dirty or (key != cache_key) or (not cache_rect.has_area()) or (not cache_rect.encloses(visible))
	if not needs_rebuild:
		return false

	cache_rect = visible.grow(CACHE_MARGIN).intersection(bounds)
	if not cache_rect.has_area():
		return false
	var props := cache_rect.grow_individual(1, 0, 1, 2).intersection(bounds)
	var px_size := (cache_rect.size * cell).max(Vector2i(2, 2))
	if view.size != px_size:
		view.size = px_size
		canvas.size = Vector2(px_size)

	canvas.world = world
	canvas.cells = cells
	canvas.below_cells = below_cells
	canvas.view_origin = cache_rect.position
	canvas.cam_px_offset = Vector2.ZERO
	canvas.cell = cell
	canvas.draw_rect_tiles = cache_rect
	canvas.props_rect = props
	canvas.seed = world.seed ^ (world.floor * 0x65bd4e97)
	canvas.current_season = season
	canvas.floor_z = world.floor
	canvas.lit_strength = lit_strength
	canvas.emitters = emitters
	canvas.queue_redraw()
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	cache_key = key
	dirty = false
	return true
