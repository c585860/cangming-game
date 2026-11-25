extends RefCounted

# Double-Buffered Frame-Sliced GPU World Cache.
# - Front SubViewport displays the active cached region (zero CPU redraw while panning inside margin).
# - When the player approaches within PRELOAD_TRIGGER tiles of the front edge, an incremental
#   background build streams into the Back SubViewport at ~10 rows per frame (~4 ms/frame),
#   then swaps atomically in 0.01 ms — eliminating 100+ ms single-frame hitches at wide FOV!

const Art = preload("res://scripts/street_art.gd")
const CACHE_MARGIN := 8
const WIDE_FOV_MARGIN := 12
const SLICE_ROWS := 6

var view: SubViewport
var canvas: WorldCanvas
var back_view: SubViewport
var back_canvas: WorldCanvas

var cache_rect := Rect2i()
var cache_key: Array = []
var dirty := true

# Incremental double-buffered preload state
var preloading := false
var pending_rect := Rect2i()
var pending_props := Rect2i()
var pending_key: Array = []
var _stage := 0 # 0=ground slices, 1=props slices, 2=ready for atomic swap
var _cursor_y := 0
var _first_slice := true


static func margin_for_cell(cell_size: int) -> int:
	return WIDE_FOV_MARGIN if cell_size <= 25 else CACHE_MARGIN


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
	var props_map: Dictionary = {}
	var sites_map: Dictionary = {}

	# Row-slice mode: mode -1 = full synchronous draw; 0 = ground rows; 1 = props rows + sites
	var slice_mode := -1
	var slice_y0 := 0
	var slice_y1 := 0
	var slice_is_first := true
	var slice_is_last := true

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if world == null or not draw_rect_tiles.has_area():
			return
		if slice_mode == -1 or (slice_mode == 0 and slice_is_first):
			draw_rect(Rect2(Vector2.ZERO, size), Color("090d0b"))
		if slice_mode == -1 or slice_mode == 0:
			var y0 := draw_rect_tiles.position.y if slice_mode == -1 else slice_y0
			var y1 := draw_rect_tiles.end.y if slice_mode == -1 else slice_y1
			if floor_z > 0 and not below_cells.is_empty():
				var sky_factor := clampf(1.0 - lit_strength * 0.72, 0.22, 1.0)
				var depth_tint := Color(0.35 * sky_factor, 0.42 * sky_factor, 0.48 * sky_factor, 1.0)
				for y in range(y0, y1):
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
			for y in range(y0, y1):
				for x in range(draw_rect_tiles.position.x, draw_rect_tiles.end.x):
					var p := Vector2i(x, y)
					if cells.has(p):
						Art.ground(self, cells, p, seed, current_season)
		if slice_mode == -1 or slice_mode == 1:
			var y0 := props_rect.position.y if slice_mode == -1 else slice_y0
			var y1 := props_rect.end.y if slice_mode == -1 else slice_y1
			for y in range(y0, y1):
				for x in range(props_rect.position.x, props_rect.end.x):
					var p := Vector2i(x, y)
					if cells.has(p):
						Art.walls(self, cells, p, seed, current_season, lit_strength)
						Art.detail(self, world, cells, p, seed, current_season, emitters, lit_strength, props_map, true)
			if (slice_mode == -1 or slice_is_last) and floor_z == 0 and not sites_map.is_empty():
				for p: Vector2i in sites_map:
					if draw_rect_tiles.has_point(p):
						Art.site_landmark(self, p, sites_map[p], lit_strength)


func build(parent: Control) -> void:
	view = SubViewport.new()
	view.disable_3d = true
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(view)
	canvas = WorldCanvas.new()
	view.add_child(canvas)

	back_view = SubViewport.new()
	back_view.disable_3d = true
	back_view.transparent_bg = false
	back_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(back_view)
	back_canvas = WorldCanvas.new()
	back_view.add_child(back_canvas)


func invalidate() -> void:
	dirty = true
	cache_key.clear()
	cancel_preload()


func cancel_preload() -> void:
	preloading = false
	pending_rect = Rect2i()
	pending_props = Rect2i()
	pending_key.clear()
	_stage = 0


func get_texture() -> ViewportTexture:
	return view.get_texture()


func _make_key(world: Object, cell: int, season: String, lit_strength: float, _emitters: Dictionary) -> Array:
	var lit_bucket := int(round(lit_strength * 2.0))
	return [world.seed, world.floor, cell, season, lit_bucket, world.herbs]


func _configure_canvas(vp: SubViewport, cv: WorldCanvas, world: Object, cells: Dictionary,
		below_cells: Dictionary, rect: Rect2i, props: Rect2i, cell: int, season: String,
		emitters: Dictionary, lit_strength: float) -> void:
	var px_size := (rect.size * cell).max(Vector2i(2, 2))
	if vp.size != px_size:
		vp.size = px_size
		cv.size = Vector2(px_size)
	# Pre-size back_view eagerly during sync rebuilds so async preload never allocates an FBO mid-walk!
	if vp == view and back_view != null and back_view.size != px_size:
		back_view.size = px_size
		back_canvas.size = Vector2(px_size)
	cv.world = world
	cv.cells = cells
	cv.below_cells = below_cells
	cv.view_origin = rect.position
	cv.cam_px_offset = Vector2.ZERO
	cv.cell = cell
	cv.draw_rect_tiles = rect
	cv.props_rect = props
	cv.seed = world.seed ^ (world.floor * 0x65bd4e97)
	cv.current_season = season
	cv.floor_z = world.floor
	cv.lit_strength = lit_strength
	cv.emitters = emitters
	cv.props_map = world.props_in_rect(props)
	cv.sites_map = world.active_sites_in_rect(rect) if world.floor == 0 else {}


func ensure_updated(world: Object, cells: Dictionary, below_cells: Dictionary, visible: Rect2i,
		bounds: Rect2i, cell: int, season: String, emitters: Dictionary, lit_strength: float) -> bool:
	var key := _make_key(world, cell, season, lit_strength, emitters)
	var needs_sync := dirty or (key != cache_key) or (not cache_rect.has_area()) or (not cache_rect.encloses(visible))
	if not needs_sync:
		return false

	cancel_preload()
	var margin := margin_for_cell(cell)
	cache_rect = visible.grow(margin).intersection(bounds)
	if not cache_rect.has_area():
		return false
	var props := cache_rect.grow_individual(1, 0, 1, 2).intersection(bounds)
	_configure_canvas(view, canvas, world, cells, below_cells, cache_rect, props, cell, season, emitters, lit_strength)
	canvas.slice_mode = -1
	view.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	canvas.queue_redraw()
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	cache_key = key
	dirty = false
	return true


func needs_preload(visible: Rect2i, cell: int) -> bool:
	if preloading or dirty or not cache_rect.has_area():
		return false
	var trigger := maxi(4, margin_for_cell(cell) / 2)
	var safe_inner := cache_rect.grow(-trigger)
	if not safe_inner.has_area():
		return false
	return not safe_inner.encloses(visible)


func begin_preload(world: Object, cells: Dictionary, below_cells: Dictionary, visible: Rect2i,
		bounds: Rect2i, cell: int, season: String, emitters: Dictionary, lit_strength: float) -> Rect2i:
	var margin := margin_for_cell(cell)
	pending_rect = visible.grow(margin).intersection(bounds)
	if not pending_rect.has_area():
		return Rect2i()
	pending_props = pending_rect.grow_individual(1, 0, 1, 2).intersection(bounds)
	pending_key = _make_key(world, cell, season, lit_strength, emitters)
	_configure_canvas(back_view, back_canvas, world, cells, below_cells, pending_rect, pending_props,
		cell, season, emitters, lit_strength)
	preloading = true
	_stage = 0
	_cursor_y = pending_rect.position.y
	_first_slice = true
	return pending_rect


func step_preload_slice() -> bool:
	# Advances back_view by SLICE_ROWS tiles (~4-5ms). Returns true when WorldCache back buffer is complete!
	if not preloading or _stage >= 2:
		return true
	if _stage == 0:
		var y1 := mini(_cursor_y + SLICE_ROWS, pending_rect.end.y)
		back_canvas.slice_mode = 0
		back_canvas.slice_y0 = _cursor_y
		back_canvas.slice_y1 = y1
		back_canvas.slice_is_first = _first_slice
		back_canvas.slice_is_last = (y1 >= pending_rect.end.y)
		back_view.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE if _first_slice else SubViewport.CLEAR_MODE_NEVER
		back_canvas.queue_redraw()
		back_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		_first_slice = false
		_cursor_y = y1
		if _cursor_y >= pending_rect.end.y:
			_stage = 1
			_cursor_y = pending_props.position.y
		return false
	else:
		var y1 := mini(_cursor_y + SLICE_ROWS, pending_props.end.y)
		back_canvas.slice_mode = 1
		back_canvas.slice_y0 = _cursor_y
		back_canvas.slice_y1 = y1
		back_canvas.slice_is_first = false
		back_canvas.slice_is_last = (y1 >= pending_props.end.y)
		back_view.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		back_canvas.queue_redraw()
		back_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		_cursor_y = y1
		if _cursor_y >= pending_props.end.y:
			_stage = 2
			return true
		return false


func commit_preload() -> void:
	if not preloading:
		return
	var tmp_vp := view
	view = back_view
	back_view = tmp_vp
	var tmp_cv := canvas
	canvas = back_canvas
	back_canvas = tmp_cv
	cache_rect = pending_rect
	cache_key = pending_key
	preloading = false
	_stage = 0
	dirty = false
