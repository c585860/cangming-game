extends RefCounted

# Traditional Jiangnan / Huizhou multi-story Chinese tiered roof system:
# - Indexes connected buildings and computes exact story counts (1, 2, or 3 stories) from lighting column flags
# - Renders 1-story pitched clay-tile roofs with horse-head gables (马头墙) & upturned flying eaves (飞檐翘角)
# - Renders 2-story & 3-story tiered pavilions (重檐楼阁) with visible upper-story white-plaster/timber facades,
#   carved upper lattice windows, vermilion railings, waist eaves (腰檐), main ridges, and chiwen finials (鸱吻/宝顶)
# - Smoothly fades out based on continuous distance to the player (6.4 -> 1.6 tiles)

const Lighting = preload("res://scripts/lighting.gd")
const ROOF_FADE_NEAR := 1.4
const ROOF_FADE_FAR := 4.8

var enabled := true
var buildings: Dictionary = {} # anchor: Vector2i -> Array[Vector2i]
var building_roof_tiles: Dictionary = {} # anchor: Vector2i -> Dictionary[Vector2i, Vector3i(north_d, south_d, edge_mask)]
var building_bounds: Dictionary = {} # anchor: Vector2i -> Rect2i (largest inscribed rect)
var building_bbox: Dictionary = {} # anchor: Vector2i -> Rect2i (full bounding box for O(1) distance cull)
var building_stories: Dictionary = {} # anchor: Vector2i -> int (1, 2, or 3)
var building_style: Dictionary = {} # anchor: Vector2i -> String ("H", "N", "B")
var building_variant: Dictionary = {} # anchor: Vector2i -> int (0=黛青小青瓦, 1=古窑青灰瓦, 2=琥珀暖陶瓦, 3=翠琉璃官瓦)
var building_vertical_ridge: Dictionary = {} # anchor: Vector2i -> bool (true = N-S ridge, false = E-W ridge)
var tile_to_anchor: Dictionary = {} # Vector2i -> anchor: Vector2i (O(1) lookup for plaques/nameplates)
var building_alpha: Dictionary = {} # anchor: Vector2i -> float
var building_target: Dictionary = {} # anchor: Vector2i -> float
var revealed_interior: Dictionary = {} # Vector2i -> bool
var _revealed_anchors: Dictionary = {} # anchor: Vector2i -> bool

# Single GPU SubViewport caching all opaque static roofs (alpha >= 0.995) over cache_rect at Color.WHITE!
var _cache_view: SubViewport
var _cache_canvas: RoofCacheCanvas
var _cache_rect := Rect2i()
var _cache_key: Array = []
var _cache_opaque_sig := 0
var _cache_dirty := true
var _index_version := 0


class RoofCacheCanvas extends Control:
	var owner_sys: RefCounted
	var view_origin := Vector2i.ZERO
	var cam_px_offset := Vector2.ZERO
	var cell := 32
	var draw_rect_tiles := Rect2i()
	var seed := 0
	var wetness := 0.0
	var snow_cover := 0.0
	var night_warmth := 0.0

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if owner_sys == null or not draw_rect_tiles.has_area():
			return
		owner_sys._draw_opaque_into_cache(self, draw_rect_tiles, seed, wetness, snow_cover, night_warmth)


func build_cache(parent: Control) -> void:
	if _cache_view != null:
		return
	_cache_view = SubViewport.new()
	_cache_view.disable_3d = true
	_cache_view.transparent_bg = true
	_cache_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(_cache_view)
	_cache_canvas = RoofCacheCanvas.new()
	_cache_canvas.owner_sys = self
	_cache_view.add_child(_cache_canvas)


func invalidate_cache() -> void:
	_cache_dirty = true
	_cache_key.clear()


static func _hash(p: Vector2i, seed: int) -> int:
	var n := ((p.x * 0x9e3779b9) ^ (p.y * 0x85ebca6b) ^ seed) & 0xffffffff
	n = ((n ^ (n >> 16)) * 0x7feb352d) & 0xffffffff
	return n ^ (n >> 15)


static func _style_group(sf: String) -> String:
	# Partition contiguous wall-to-wall Northern Song row-houses by style (H / B / N)
	# so neighboring houses sharing a wall get separate pitched roofs & stepped 马头墙!
	if sf == "H" or sf == "B" or sf == "N":
		return sf
	return ""


func index_buildings(cells: Dictionary, area: Rect2i) -> void:
	buildings.clear()
	building_roof_tiles.clear()
	building_bounds.clear()
	building_bbox.clear()
	building_stories.clear()
	building_style.clear()
	building_variant.clear()
	building_vertical_ridge.clear()
	tile_to_anchor.clear()
	_revealed_anchors.clear()
	_index_version += 1
	_cache_dirty = true
	var visited := {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var start := Vector2i(x, y)
			if visited.has(start) or not cells.has(start) or not Lighting.enclosed(cells[start]):
				continue
			var seed_grp := _style_group(String(cells[start][1]))
			var queue: Array[Vector2i] = [start]
			var members: Array[Vector2i] = []
			var anchor := start
			visited[start] = true
			var head := 0
			var max_stories := 1
			var style_counts := {"H": 0, "N": 0, "B": 0}
			while head < queue.size():
				var cur := queue[head]
				head += 1
				members.append(cur)
				if cur.y < anchor.y or (cur.y == anchor.y and cur.x < anchor.x):
					anchor = cur
				var d: Array = cells[cur]
				var fl: int = int(d[3])
				if (fl & 16) != 0:
					max_stories = maxi(max_stories, 3)
				elif (fl & 4) != 0:
					max_stories = maxi(max_stories, 2)
				var sf: String = d[1]
				if style_counts.has(sf):
					style_counts[sf] = int(style_counts[sf]) + 1
				for step: Vector2i in Lighting.CARDINAL:
					var nxt := cur + step
					if visited.has(nxt) or not cells.has(nxt):
						continue
					if Lighting.enclosed(cells[nxt]):
						var ng := _style_group(String(cells[nxt][1]))
						if seed_grp.is_empty() or ng.is_empty() or ng == seed_grp:
							if seed_grp.is_empty() and not ng.is_empty():
								seed_grp = ng
							visited[nxt] = true
							queue.append(nxt)
			var roof_set := {}
			var min_p := Vector2i(999999, 999999)
			var max_p := Vector2i(-999999, -999999)
			for p: Vector2i in members:
				var tile: String = cells[p][0]
				var south_out := not Lighting.enclosed(cells.get(p + Vector2i.DOWN, []))
				if south_out and tile in ["#", "w", "O", "%", "D", "o"]:
					continue
				roof_set[p] = true
				min_p.x = mini(min_p.x, p.x)
				min_p.y = mini(min_p.y, p.y)
				max_p.x = maxi(max_p.x, p.x)
				max_p.y = maxi(max_p.y, p.y)
			if roof_set.is_empty():
				continue
			var full_box := Rect2i(min_p, max_p - min_p + Vector2i.ONE)
			var ah := _hash(anchor, 0x71b3)
			var vertical_ridge := max_stories == 1 and (full_box.size.y > full_box.size.x or (full_box.size.y == full_box.size.x and (ah % 3 == 0)))
			# Precompute slope distances (north/south for E-W ridge, west/east for N-S ridge) & edge bitmask!
			var roof_meta := {}
			for p: Vector2i in roof_set:
				var d1 := 0
				var d2 := 0
				if vertical_ridge:
					while d1 < 12 and roof_set.has(p + Vector2i(-(d1 + 1), 0)):
						d1 += 1
					while d2 < 12 and roof_set.has(p + Vector2i(d2 + 1, 0)):
						d2 += 1
				else:
					while d1 < 12 and roof_set.has(p + Vector2i(0, -(d1 + 1))):
						d1 += 1
					while d2 < 12 and roof_set.has(p + Vector2i(0, d2 + 1)):
						d2 += 1
				var em := 0
				if not roof_set.has(p + Vector2i.UP): em |= 1
				if not roof_set.has(p + Vector2i.DOWN): em |= 2
				if not roof_set.has(p + Vector2i.LEFT): em |= 4
				if not roof_set.has(p + Vector2i.RIGHT): em |= 8
				roof_meta[p] = Vector3i(d1, d2, em)
			var dom_style := "H"
			if int(style_counts["N"]) > int(style_counts["H"]) and int(style_counts["N"]) >= int(style_counts["B"]):
				dom_style = "N"
			elif int(style_counts["B"]) > int(style_counts["H"]):
				dom_style = "B"
			buildings[anchor] = members
			building_roof_tiles[anchor] = roof_meta
			building_bbox[anchor] = full_box
			building_bounds[anchor] = _largest_inscribed_rect(roof_set, full_box)
			building_stories[anchor] = max_stories
			building_style[anchor] = dom_style
			building_vertical_ridge[anchor] = vertical_ridge
			var roof_var := 0
			if dom_style == "N":
				roof_var = 3 if max_stories >= 3 and (ah % 2 == 0) else 2 # 琥珀暖陶瓦 / 翠琉璃官瓦
			elif dom_style == "B":
				roof_var = 1 # 古窑青灰瓦
			else:
				roof_var = 0 if (ah % 3 != 0) else 1 # 黛青小青瓦 + 古窑青灰瓦交错
			building_variant[anchor] = roof_var
			for mp: Vector2i in members:
				tile_to_anchor[mp] = anchor


func has_roof_at(p: Vector2i) -> bool:
	return tile_to_anchor.has(p)


func alpha_at(p: Vector2i) -> float:
	if not enabled:
		return 0.0
	if not tile_to_anchor.has(p):
		return 1.0
	var anchor: Vector2i = tile_to_anchor[p]
	return float(building_alpha.get(anchor, 1.0))


static func _largest_inscribed_rect(roof_set: Dictionary, bbox: Rect2i) -> Rect2i:
	# Finds the largest solid rectangle fully contained in roof_set so L-shaped buildings
	# never have upper-story pavilion tiers overhanging an empty courtyard notch!
	var w := bbox.size.x
	var h := bbox.size.y
	if w <= 0 or h <= 0:
		return bbox
	var heights := PackedInt32Array()
	heights.resize(w)
	var best_area := 0
	var best := bbox
	for y in range(h):
		for x in range(w):
			var p := Vector2i(bbox.position.x + x, bbox.position.y + y)
			heights[x] = (heights[x] + 1) if roof_set.has(p) else 0
		for x0 in range(w):
			var min_h := heights[x0]
			if min_h <= 0:
				continue
			for x1 in range(x0, w):
				min_h = mini(min_h, heights[x1])
				if min_h <= 0:
					break
				var area := (x1 - x0 + 1) * min_h
				if area > best_area:
					best_area = area
					best = Rect2i(bbox.position.x + x0, bbox.position.y + y - min_h + 1, x1 - x0 + 1, min_h)
	return best


func update_targets(player_pos: Vector2, floor_z: int, instant := false) -> void:
	building_target.clear()
	if not enabled or floor_z != 0:
		building_alpha.clear()
		refresh_revealed(floor_z, true)
		return
	var far_pad := ROOF_FADE_FAR + 1.5
	var revealed_changed := instant
	for anchor: Vector2i in buildings:
		var bbox: Rect2i = building_bbox[anchor]
		# O(1) AABB cull: skip tile loop completely for buildings outside fade radius!
		var dx := maxf(float(bbox.position.x) - player_pos.x, maxf(0.0, player_pos.x - float(bbox.end.x)))
		var dy := maxf(float(bbox.position.y) - player_pos.y, maxf(0.0, player_pos.y - float(bbox.end.y)))
		var target := 1.0
		if dx * dx + dy * dy <= far_pad * far_pad:
			var members: Array = buildings[anchor]
			var min_d2 := 999999.0
			for p: Vector2i in members:
				var d2 := (Vector2(p) - player_pos).length_squared()
				if d2 < min_d2:
					min_d2 = d2
					if min_d2 <= 0.01:
						break
			target = smoothstep(ROOF_FADE_NEAR, ROOF_FADE_FAR, sqrt(min_d2))
		building_target[anchor] = target
		if instant or not building_alpha.has(anchor):
			building_alpha[anchor] = target
			var now_rev := target < 0.40
			if bool(_revealed_anchors.get(anchor, false)) != now_rev:
				revealed_changed = true
	if revealed_changed:
		refresh_revealed(floor_z)


func tick(delta: float, floor_z: int) -> bool:
	if building_target.is_empty():
		return false
	var changed := false
	var revealed_changed := false
	var speed := 7.5 * delta
	for key: Vector2i in building_target:
		var target := float(building_target[key])
		var cur := float(building_alpha.get(key, target))
		if absf(cur - target) > 0.004:
			var nxt := move_toward(cur, target, speed)
			building_alpha[key] = nxt
			changed = true
			if (cur < 0.40) != (nxt < 0.40):
				revealed_changed = true
		elif cur != target:
			building_alpha[key] = target
			changed = true
			if (cur < 0.40) != (target < 0.40):
				revealed_changed = true
	if revealed_changed:
		refresh_revealed(floor_z)
	return changed


func snap(floor_z: int) -> void:
	for key: Vector2i in building_target:
		building_alpha[key] = building_target[key]
	refresh_revealed(floor_z, true)
	_cache_dirty = true


func refresh_revealed(floor_z: int, force := false) -> void:
	var next_anchors := {}
	if not enabled or floor_z != 0:
		for anchor: Vector2i in buildings:
			next_anchors[anchor] = true
	else:
		for anchor: Vector2i in buildings:
			if float(building_alpha.get(anchor, 1.0)) < 0.40:
				next_anchors[anchor] = true
	if not force and next_anchors == _revealed_anchors:
		return
	_revealed_anchors = next_anchors
	revealed_interior.clear()
	for anchor: Vector2i in _revealed_anchors:
		for p: Vector2i in buildings[anchor]:
			revealed_interior[p] = true


func _opaque_signature(area: Rect2i) -> int:
	var sig := 17
	for anchor: Vector2i in buildings:
		var b_rect: Rect2i = building_bbox[anchor]
		if not b_rect.grow(2).intersects(area):
			continue
		if float(building_alpha.get(anchor, 1.0)) >= 0.995:
			sig = (sig * 31 + anchor.x * 73856093 + anchor.y * 19349663) & 0x7fffffff
	return sig


func _draw_opaque_into_cache(canvas: Control, area: Rect2i, seed: int,
		wetness: float, snow_cover: float, night_warmth: float) -> void:
	for anchor: Vector2i in buildings:
		if float(building_alpha.get(anchor, 1.0)) < 0.995:
			continue
		var b_box: Rect2i = building_bbox[anchor]
		if not b_box.grow(3).intersects(area):
			continue
		_draw_building(canvas, canvas, anchor, area, seed, 1.0, Color.WHITE, wetness, snow_cover, night_warmth)


func _draw_building(canvas: Control, board: Control, anchor: Vector2i, visible: Rect2i, seed: int,
		alpha: float, light_tint: Color, wetness: float, snow_cover: float, night_warmth: float) -> void:
	var b_rect: Rect2i = building_bounds[anchor]
	var roof_meta: Dictionary = building_roof_tiles[anchor]
	var stories: int = int(building_stories.get(anchor, 1))
	var style: String = String(building_style.get(anchor, "H"))
	var roof_var: int = int(building_variant.get(anchor, 0))
	var vertical_ridge: bool = bool(building_vertical_ridge.get(anchor, false))

	for p: Vector2i in roof_meta:
		if visible.has_point(p):
			_draw_base_tile(canvas, board, roof_meta[p], p, seed, alpha, light_tint, wetness, snow_cover, stories, roof_var, night_warmth, vertical_ridge)

	if stories == 1:
		_draw_corner_finials(canvas, board, b_rect, alpha, light_tint, false, vertical_ridge)
		return

	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	var s := float(board.cell)
	var base_px := Rect2(Vector2((b_rect.position - board.view_origin) * board.cell) + cam_offset,
		Vector2(b_rect.size) * s)
	if base_px.size.x < s * 4.5 or base_px.size.y < s * 4.5:
		_draw_corner_finials(canvas, board, b_rect, alpha, light_tint, false)
		return

	var t2_inset_x := minf(s * 0.95, base_px.size.x * 0.12)
	var t2_inset_top := minf(s * 0.72, base_px.size.y * 0.11)
	var t2_inset_bot := minf(s * 1.15, base_px.size.y * 0.16)
	var t2_rect := Rect2(
		base_px.position.x + t2_inset_x,
		base_px.position.y + t2_inset_top,
		base_px.size.x - t2_inset_x * 2.0,
		base_px.size.y - t2_inset_top - t2_inset_bot
	)
	_draw_upper_story_tier(canvas, t2_rect, s, 2, stories == 2, style, alpha, light_tint, wetness, snow_cover, night_warmth, roof_var)

	if stories >= 3 and t2_rect.size.x >= s * 5.0 and t2_rect.size.y >= s * 4.2:
		var t3_inset_x := minf(s * 1.05, t2_rect.size.x * 0.16)
		var t3_inset_top := minf(s * 0.65, t2_rect.size.y * 0.14)
		var t3_inset_bot := minf(s * 1.35, t2_rect.size.y * 0.25)
		var t3_rect := Rect2(
			t2_rect.position.x + t3_inset_x,
			t2_rect.position.y + t3_inset_top,
			t2_rect.size.x - t3_inset_x * 2.0,
			t2_rect.size.y - t3_inset_top - t3_inset_bot
		)
		if t3_rect.size.x >= s * 2.6 and t3_rect.size.y >= s * 2.2:
			_draw_upper_story_tier(canvas, t3_rect, s, 3, true, style, alpha, light_tint, wetness, snow_cover, night_warmth, roof_var)


func draw_all(canvas: Control, board: Control, _cells: Dictionary, visible: Rect2i, seed: int,
		light_tint: Color, wetness: float, snow_cover: float, night_warmth := 0.0) -> void:
	if not enabled or buildings.is_empty():
		return
	var target_rect: Rect2i = board.world_cache.cache_rect if board.world_cache.cache_rect.has_area() else visible
	if _cache_view != null and target_rect.has_area():
		var wet_b := int(round(wetness * 4.0))
		var snow_b := int(round(snow_cover * 4.0))
		var night_b := int(round(night_warmth * 2.0))
		var sig := _opaque_signature(target_rect)
		var cell_i: int = int(board.cell)
		var key: Array = [cell_i, seed, _index_version, wet_b, snow_b, night_b, sig]
		if _cache_dirty or key != _cache_key or not _cache_rect.encloses(visible):
			_cache_rect = target_rect
			var px_size: Vector2i = (_cache_rect.size * cell_i).max(Vector2i(2, 2))
			if _cache_view.size != px_size:
				_cache_view.size = px_size
				_cache_canvas.size = Vector2(px_size)
			_cache_canvas.view_origin = _cache_rect.position
			_cache_canvas.cam_px_offset = Vector2.ZERO
			_cache_canvas.cell = cell_i
			_cache_canvas.draw_rect_tiles = _cache_rect
			_cache_canvas.seed = seed
			_cache_canvas.wetness = wetness
			_cache_canvas.snow_cover = snow_cover
			_cache_canvas.night_warmth = night_warmth
			_cache_canvas.queue_redraw()
			_cache_view.render_target_update_mode = SubViewport.UPDATE_ONCE
			_cache_key = key
			_cache_dirty = false
		# 1 single GPU textured quad draws ALL opaque static multi-story roofs across the entire wide FOV!
		var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
		var dest := Rect2(Vector2((_cache_rect.position - board.view_origin) * cell_i) + cam_offset,
			Vector2(_cache_rect.size * cell_i))
		canvas.draw_texture_rect(_cache_view.get_texture(), dest, false, light_tint)
		# Only draw the 0-1 nearby fading building(s) dynamically!
		for anchor: Vector2i in buildings:
			var alpha := float(building_alpha.get(anchor, 1.0))
			if alpha <= 0.01 or alpha >= 0.995:
				continue
			var b_box: Rect2i = building_bbox[anchor]
			if not b_box.grow(3).intersects(visible):
				continue
			_draw_building(canvas, board, anchor, visible, seed, alpha, light_tint, wetness, snow_cover, night_warmth)
		return

	# Fallback when cache SubViewport is not attached
	for anchor: Vector2i in buildings:
		var alpha := float(building_alpha.get(anchor, 1.0))
		if alpha <= 0.01:
			continue
		var b_box: Rect2i = building_bbox[anchor]
		if not b_box.grow(3).intersects(visible):
			continue
		_draw_building(canvas, board, anchor, visible, seed, alpha, light_tint, wetness, snow_cover, night_warmth)


static func _draw_upper_story_tier(canvas: Control, r: Rect2, s: float, story_num: int, is_top: bool,
		style: String, alpha: float, light_tint: Color, wetness: float, snow_cover: float, night_warmth: float,
		roof_var := 0) -> void:
	# Drop shadow cast onto the lower roof eaves beneath this upper story!
	var sh_col := Color(0.03, 0.04, 0.06, 0.44 * alpha)
	canvas.draw_rect(Rect2(r.position.x + 3.0, r.end.y, r.size.x + 2.0, maxf(5.0, s * 0.26)), sh_col)
	canvas.draw_rect(Rect2(r.end.x, r.position.y + 4.0, maxf(4.0, s * 0.18), r.size.y), sh_col)

	# Upper-story visible south facade (粉墙/朱木立面 + 雕花木窗 + 朱漆栏杆)
	var wall_h := clampf(s * (0.76 if story_num == 2 else 0.68), 14.0, r.size.y * 0.34)
	var roof_h := r.size.y - wall_h
	var facade_r := Rect2(r.position.x, r.position.y + roof_h, r.size.x, wall_h)
	var roof_r := Rect2(r.position.x, r.position.y, r.size.x, roof_h)

	var plaster := Color("dfd7c6") if style == "H" else Color("8c593b") if style == "N" else Color("878c8f")
	var wall_col := Color(plaster.r * light_tint.r, plaster.g * light_tint.g, plaster.b * light_tint.b, alpha)
	var beam_col := Color(0.36 * light_tint.r, 0.18 * light_tint.g, 0.13 * light_tint.b, alpha)
	var rail_col := Color(0.54 * light_tint.r, 0.22 * light_tint.g, 0.17 * light_tint.b, alpha)
	var gold_col := Color(0.86 * light_tint.r, 0.72 * light_tint.g, 0.38 * light_tint.b, alpha)
	var win_paper := Color("e2d8c0").lerp(Color("ffd072"), clampf(night_warmth, 0.0, 1.0) * 0.88)
	var win_col := Color(win_paper.r * maxf(0.55, light_tint.r), win_paper.g * maxf(0.55, light_tint.g), win_paper.b * maxf(0.55, light_tint.b), alpha)

	# Facade body + eave shadow along top of upper wall
	canvas.draw_rect(facade_r, wall_col)
	canvas.draw_rect(Rect2(facade_r.position.x, facade_r.position.y, facade_r.size.x, maxf(3.0, wall_h * 0.22)), Color(0.04, 0.05, 0.07, 0.40 * alpha))

	# Vermilion timber columns & upper-story Chinese lattice windows
	var bays := maxi(2, int(round(facade_r.size.x / (s * 1.9))))
	var bay_w := facade_r.size.x / float(bays)
	var col_w := maxf(2.5, s * 0.11)
	for i in range(bays + 1):
		var cx := facade_r.position.x + float(i) * bay_w
		canvas.draw_rect(Rect2(cx - col_w * 0.5, facade_r.position.y, col_w, facade_r.size.y), beam_col)
		if i < bays:
			var ww := minf(bay_w * 0.52, s * 0.74)
			var wh := wall_h * 0.52
			var wx := cx + (bay_w - ww) * 0.5
			var wy := facade_r.position.y + wall_h * 0.22
			var wr := Rect2(wx, wy, ww, wh)
			canvas.draw_rect(wr.grow(1.2), beam_col)
			canvas.draw_rect(wr, win_col)
			# Delicate lattice muntin cross
			canvas.draw_line(Vector2(wx + ww * 0.5, wy), Vector2(wx + ww * 0.5, wy + wh), beam_col, 1.0)
			canvas.draw_line(Vector2(wx, wy + wh * 0.5), Vector2(wx + ww, wy + wh * 0.5), beam_col, 1.0)

	# Upper-story vermilion veranda balustrade (凭栏) along bottom of facade
	var rail_h := maxf(3.0, wall_h * 0.22)
	var rail_y := facade_r.end.y - rail_h
	canvas.draw_rect(Rect2(facade_r.position.x, rail_y, facade_r.size.x, maxf(1.5, rail_h * 0.35)), rail_col)
	canvas.draw_rect(Rect2(facade_r.position.x, facade_r.end.y - maxf(1.5, rail_h * 0.30), facade_r.size.x, maxf(1.5, rail_h * 0.30)), beam_col)
	var balusters := maxi(6, int(round(facade_r.size.x / (s * 0.45))))
	for b in range(1, balusters):
		var bx := facade_r.position.x + facade_r.size.x * float(b) / float(balusters)
		canvas.draw_line(Vector2(bx, rail_y), Vector2(bx, facade_r.end.y), rail_col, 1.0)

	# Upper-story pitched Chinese barrel-tile roof (歇山瓦顶)
	var eave_pad := maxf(3.0, s * 0.16)
	var roof_draw := Rect2(roof_r.position.x - eave_pad, roof_r.position.y - eave_pad * 0.4,
		roof_r.size.x + eave_pad * 2.0, roof_r.size.y + eave_pad * 0.7)
	var dark_shift := 0.03 if story_num == 2 else 0.06
	var north_base := _roof_palette(roof_var, true, -dark_shift * 0.5)
	var south_base := _roof_palette(roof_var, false, -dark_shift * 0.4)
	if wetness > 0.01:
		north_base = north_base.darkened(0.16 * wetness)
		south_base = south_base.darkened(0.16 * wetness)
	var c_north := Color(north_base.r * light_tint.r, north_base.g * light_tint.g, north_base.b * light_tint.b, alpha)
	var c_south := Color(south_base.r * light_tint.r, south_base.g * light_tint.g, south_base.b * light_tint.b, alpha)
	var c_dark := Color(c_south.r * 0.60, c_south.g * 0.62, c_south.b * 0.66, alpha)
	var c_hi := Color(minf(c_south.r * 1.24, 1.0), minf(c_south.g * 1.24, 1.0), minf(c_south.b * 1.26, 1.0), alpha * 0.75)
	var ridge_col := Color(0.48 * light_tint.r, 0.54 * light_tint.g, 0.58 * light_tint.b, alpha)
	var ridge_hi := Color(minf(0.72 * light_tint.r, 1.0), minf(0.77 * light_tint.g, 1.0), minf(0.81 * light_tint.b, 1.0), alpha)

	var ridge_y := roof_draw.position.y + roof_draw.size.y * 0.44
	canvas.draw_rect(Rect2(roof_draw.position.x, roof_draw.position.y, roof_draw.size.x, ridge_y - roof_draw.position.y), c_north)
	canvas.draw_rect(Rect2(roof_draw.position.x, ridge_y, roof_draw.size.x, roof_draw.end.y - ridge_y), c_south)

	# Chinese clay barrel-tile courses & ribs across the upper roof
	var tile_rows := maxi(4, int(round(roof_draw.size.y / (s * 0.26))))
	var tile_cols := maxi(6, int(round(roof_draw.size.x / (s * 0.25))))
	var rh := roof_draw.size.y / float(tile_rows)
	var cw := roof_draw.size.x / float(tile_cols)
	for rr in range(tile_rows):
		var ry := roof_draw.position.y + float(rr) * rh
		canvas.draw_line(Vector2(roof_draw.position.x, ry), Vector2(roof_draw.end.x, ry), c_dark, 1.0)
	for cc in range(1, tile_cols):
		var tx := roof_draw.position.x + float(cc) * cw
		canvas.draw_line(Vector2(tx, roof_draw.position.y), Vector2(tx, roof_draw.end.y), c_dark, 1.0)
		if cw >= 6.0:
			canvas.draw_line(Vector2(tx + cw * 0.42, roof_draw.position.y + 1.0), Vector2(tx + cw * 0.42, roof_draw.end.y - 1.0), c_hi, 1.0)

	# Snow dusting on upper-story roof
	if snow_cover > 0.04:
		var sa := clampf(snow_cover * 0.78, 0.0, 0.84) * alpha
		var snow_col := Color(minf(0.92 * light_tint.r + 0.06, 1.0), minf(0.95 * light_tint.g + 0.08, 1.0), minf(1.0 * light_tint.b + 0.10, 1.0), sa)
		canvas.draw_rect(roof_draw.grow(-1.0), snow_col)

	# Stepped Huizhou white-plaster gable side trims (马头墙侧檐)
	var g_w := maxf(3.0, s * 0.14)
	var gable_col := Color(0.84 * light_tint.r, 0.80 * light_tint.g, 0.72 * light_tint.b, alpha)
	canvas.draw_rect(Rect2(roof_draw.position.x, roof_draw.position.y, g_w, roof_draw.size.y), gable_col)
	canvas.draw_rect(Rect2(roof_draw.end.x - g_w, roof_draw.position.y, g_w, roof_draw.size.y), gable_col.darkened(0.10))
	canvas.draw_rect(Rect2(roof_draw.position.x, roof_draw.position.y, roof_draw.size.x, maxf(2.5, s * 0.10)), ridge_col)
	canvas.draw_rect(Rect2(roof_draw.position.x, roof_draw.end.y - maxf(2.5, s * 0.11), roof_draw.size.x, maxf(2.5, s * 0.11)), c_dark)

	# Upturned flying-eave corner horns (四角飞檐翘角)
	var horn_dx := maxf(4.0, s * 0.22)
	var horn_dy := maxf(3.0, s * 0.16)
	for corner in [
		[Vector2(roof_draw.position.x, roof_draw.position.y), Vector2(-horn_dx, -horn_dy)],
		[Vector2(roof_draw.end.x, roof_draw.position.y), Vector2(horn_dx, -horn_dy)],
		[Vector2(roof_draw.position.x, roof_draw.end.y), Vector2(-horn_dx, -horn_dy * 0.7)],
		[Vector2(roof_draw.end.x, roof_draw.end.y), Vector2(horn_dx, -horn_dy * 0.7)],
	]:
		var base_pt: Vector2 = corner[0]
		var tip_pt: Vector2 = base_pt + corner[1]
		var poly := PackedVector2Array([base_pt, tip_pt, base_pt + Vector2(-signf(corner[1].x) * g_w, 0.0)])
		canvas.draw_colored_polygon(poly, ridge_col)
		canvas.draw_circle(tip_pt, maxf(1.6, s * 0.06), ridge_hi)

	# Hip diagonal ridges (歇山垂脊) + main crown ridge (正脊 + 鸱吻 + 宝顶)
	if is_top:
		var bh := maxf(4.0, s * 0.20)
		var inset_r := minf(roof_draw.size.x * 0.18, s * 1.1)
		var rx0 := roof_draw.position.x + inset_r
		var rx1 := roof_draw.end.x - inset_r
		# Four diagonal hip ridges meeting the main ridge ends
		canvas.draw_line(Vector2(rx0, ridge_y), Vector2(roof_draw.position.x - horn_dx * 0.6, roof_draw.position.y - horn_dy * 0.6), ridge_col, 2.2)
		canvas.draw_line(Vector2(rx0, ridge_y), Vector2(roof_draw.position.x - horn_dx * 0.6, roof_draw.end.y - horn_dy * 0.3), ridge_col, 2.2)
		canvas.draw_line(Vector2(rx1, ridge_y), Vector2(roof_draw.end.x + horn_dx * 0.6, roof_draw.position.y - horn_dy * 0.6), ridge_col, 2.2)
		canvas.draw_line(Vector2(rx1, ridge_y), Vector2(roof_draw.end.x + horn_dx * 0.6, roof_draw.end.y - horn_dy * 0.3), ridge_col, 2.2)
		# Main horizontal ridge beam
		canvas.draw_rect(Rect2(rx0, ridge_y - bh * 0.5, rx1 - rx0, bh), ridge_col)
		canvas.draw_rect(Rect2(rx0, ridge_y - bh * 0.5, rx1 - rx0, maxf(1.5, bh * 0.32)), ridge_hi)
		canvas.draw_rect(Rect2(rx0, ridge_y + bh * 0.5, rx1 - rx0, maxf(2.0, s * 0.08)), Color(0.04, 0.06, 0.08, 0.42 * alpha))
		# Chiwen dragon-tail finials (鸱吻) at both ridge ends
		var fin_r := maxf(2.8, s * 0.12)
		canvas.draw_circle(Vector2(rx0, ridge_y - bh * 0.35), fin_r, ridge_hi)
		canvas.draw_circle(Vector2(rx1, ridge_y - bh * 0.35), fin_r, ridge_hi)
		# Gilded bronze lotus roof finial (宝顶) at center of 3-story pavilion!
		if story_num >= 3:
			var mid_x := (rx0 + rx1) * 0.5
			canvas.draw_circle(Vector2(mid_x, ridge_y - bh * 0.45), maxf(3.2, s * 0.14), gold_col)
			canvas.draw_circle(Vector2(mid_x, ridge_y - bh * 0.72), maxf(1.8, s * 0.075), ridge_hi)


static func _draw_corner_finials(canvas: Control, board: Control, b_rect: Rect2i,
		alpha: float, light_tint: Color, with_gold: bool, vertical_ridge := false) -> void:
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	var s := float(board.cell)
	var px := Rect2(Vector2((b_rect.position - board.view_origin) * board.cell) + cam_offset,
		Vector2(b_rect.size) * s)
	var ridge_col := Color(0.46 * light_tint.r, 0.52 * light_tint.g, 0.56 * light_tint.b, alpha)
	var ridge_hi := Color(minf(0.72 * light_tint.r, 1.0), minf(0.77 * light_tint.g, 1.0), minf(0.81 * light_tint.b, 1.0), alpha)
	var dx := maxf(4.0, s * 0.22)
	var dy := maxf(3.0, s * 0.15)
	for corner in [
		[px.position, Vector2(-dx, -dy)],
		[Vector2(px.end.x, px.position.y), Vector2(dx, -dy)],
		[Vector2(px.position.x, px.end.y), Vector2(-dx, -dy * 0.6)],
		[px.end, Vector2(dx, -dy * 0.6)],
	]:
		var bp: Vector2 = corner[0]
		var tp: Vector2 = bp + corner[1]
		canvas.draw_line(bp, tp, ridge_col, maxf(2.0, s * 0.08))
		canvas.draw_circle(tp, maxf(1.8, s * 0.07), ridge_hi)
	# Ridge chiwen ends at gable ends of 1-story roof
	if vertical_ridge:
		var rx := px.position.x + px.size.x * 0.46
		canvas.draw_circle(Vector2(rx, px.position.y + s * 0.14), maxf(2.4, s * 0.10), ridge_hi)
		canvas.draw_circle(Vector2(rx, px.end.y - s * 0.14), maxf(2.4, s * 0.10), ridge_hi)
	else:
		var ry := px.position.y + px.size.y * 0.46
		canvas.draw_circle(Vector2(px.position.x + s * 0.14, ry), maxf(2.4, s * 0.10), ridge_hi)
		canvas.draw_circle(Vector2(px.end.x - s * 0.14, ry), maxf(2.4, s * 0.10), ridge_hi)
		if with_gold:
			canvas.draw_circle(Vector2(px.position.x + px.size.x * 0.5, ry - s * 0.06), maxf(2.6, s * 0.11),
				Color(0.88 * light_tint.r, 0.74 * light_tint.g, 0.40 * light_tint.b, alpha))


static func _roof_palette(roof_var: int, north_slope: bool, jitter: float) -> Color:
	# 4 distinct realistic historic Chinese roof materials (never identical flat tiles!)
	match roof_var:
		1: # 古窑青灰瓦 (Weathered Ash-Grey Ceramic Tiles)
			return Color(0.26 + jitter, 0.27 + jitter, 0.28 + jitter) if north_slope \
				else Color(0.35 + jitter, 0.36 + jitter, 0.36 + jitter)
		2: # 琥珀暖陶瓦 (Warm Dark-Chestnut Timber Tavern & Inn Tiles)
			return Color(0.28 + jitter, 0.21 + jitter, 0.18 + jitter) if north_slope \
				else Color(0.38 + jitter, 0.29 + jitter, 0.24 + jitter)
		3: # 翠琉璃官瓦 (Deep Muted Jade Glazed Pavilion Tiles)
			return Color(0.16 + jitter, 0.28 + jitter, 0.26 + jitter) if north_slope \
				else Color(0.22 + jitter, 0.38 + jitter, 0.34 + jitter)
		_: # 黛青小青瓦 (Classic Ink-Slate Jiangnan Clay Tiles — Photo 1!)
			return Color(0.19 + jitter, 0.23 + jitter, 0.27 + jitter) if north_slope \
				else Color(0.26 + jitter, 0.31 + jitter, 0.36 + jitter)


static func _draw_base_tile(canvas: Control, board: Control, meta: Vector3i, p: Vector2i,
		seed: int, alpha: float, light_tint: Color, wetness: float, snow_cover: float, stories: int,
		roof_var := 0, night_warmth := 0.0, vertical_ridge := false) -> void:
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	var o := Vector2((p - board.view_origin) * board.cell) + cam_offset
	var s := float(board.cell)
	var d1 := meta.x # north_d (E-W ridge) or west_d (N-S ridge)
	var d2 := meta.y # south_d (E-W ridge) or east_d (N-S ridge)
	var edge_mask := meta.z
	var rel := d1 - d2
	var is_ridge := stories == 1 and absi(rel) <= 1 and (d1 + d2) >= 2
	var shaded_slope := rel < -1
	var roll := _hash(p, seed ^ 0x29c71)
	var jitter := (float(roll % 9) - 4.0) * 0.009

	var base := _roof_palette(roof_var, shaded_slope, jitter)
	if stories >= 2:
		base = base.darkened(0.05)
	if wetness > 0.01:
		base = base.darkened(0.18 * wetness)
	var lit_base := Color(base.r * light_tint.r, base.g * light_tint.g, base.b * light_tint.b, alpha)
	if wetness > 0.05:
		var sheen := (0.06 if shaded_slope else 0.11) * wetness * light_tint.b
		lit_base = Color(minf(lit_base.r + sheen * 0.7, 1.0), minf(lit_base.g + sheen * 0.85, 1.0), minf(lit_base.b + sheen, 1.0), alpha)

	var tile_dark := Color(lit_base.r * 0.58, lit_base.g * 0.60, lit_base.b * 0.64, alpha)
	var tile_hi := Color(minf(lit_base.r * 1.28, 1.0), minf(lit_base.g * 1.28, 1.0), minf(lit_base.b * 1.30, 1.0), alpha * 0.76)
	var ridge_col := Color(0.46 * light_tint.r, 0.50 * light_tint.g, 0.54 * light_tint.b, alpha)
	var ridge_hi := Color(minf(0.72 * light_tint.r, 1.0), minf(0.75 * light_tint.g, 1.0), minf(0.78 * light_tint.b, 1.0), alpha)

	canvas.draw_rect(Rect2(o, Vector2(s, s)), lit_base)

	var cols := 2 if s <= 24.0 else maxi(3, int(round(s / 8.0)))
	var rows := 2 if s <= 24.0 else 4
	var cw := s / float(cols)
	var rh := s / float(rows)
	if vertical_ridge:
		# N-S ridge: clay barrel tiles slope West & East (vertical courses, horizontal ribs!)
		for c in range(rows):
			var tx := o.x + float(c) * rh
			var col_shade := 0.90 + 0.16 * (float(c) / float(rows))
			if shaded_slope:
				col_shade = 1.08 - 0.16 * (float(c) / float(rows))
			var col_c := Color(lit_base.r * col_shade, lit_base.g * col_shade, lit_base.b * col_shade, alpha)
			canvas.draw_rect(Rect2(tx, o.y, rh * 0.72, s), col_c)
			canvas.draw_line(Vector2(tx + rh - 1.0, o.y), Vector2(tx + rh - 1.0, o.y + s), tile_dark, 1.0)
		for r in range(cols):
			var ty := o.y + float(r) * cw
			canvas.draw_line(Vector2(o.x, ty), Vector2(o.x + s, ty), tile_dark, 1.0)
			if cw >= 6.5:
				canvas.draw_line(Vector2(o.x + 1.0, ty + cw * 0.45), Vector2(o.x + s - 1.0, ty + cw * 0.45), tile_hi, 1.0)
	else:
		# E-W ridge: clay barrel tiles slope North & South
		for r in range(rows):
			var ry := o.y + float(r) * rh
			var row_shade := 0.90 + 0.16 * (float(r) / float(rows))
			if shaded_slope:
				row_shade = 1.08 - 0.16 * (float(r) / float(rows))
			var row_col := Color(lit_base.r * row_shade, lit_base.g * row_shade, lit_base.b * row_shade, alpha)
			canvas.draw_rect(Rect2(o.x, ry, s, rh * 0.72), row_col)
			canvas.draw_line(Vector2(o.x, ry + rh - 1.0), Vector2(o.x + s, ry + rh - 1.0), tile_dark, 1.0)
		for c in range(cols):
			var tx := o.x + float(c) * cw
			canvas.draw_line(Vector2(tx, o.y), Vector2(tx, o.y + s), tile_dark, 1.0)
			if cw >= 6.5:
				canvas.draw_line(Vector2(tx + cw * 0.45, o.y + 1.0), Vector2(tx + cw * 0.45, o.y + s - 1.0), tile_hi, 1.0)
	# Subtle weathered moss/lichen patina on aged clay roofs
	if roof_var <= 1 and (roll % 19 == 0) and snow_cover < 0.1:
		canvas.draw_rect(Rect2(o.x + s * 0.22, o.y + s * 0.30, s * 0.34, s * 0.24),
			Color(0.24 * light_tint.r, 0.33 * light_tint.g, 0.22 * light_tint.b, 0.26 * alpha))

	if snow_cover > 0.04:
		var snow_patch := 0.78 + 0.22 * (float(roll % 17) / 16.0)
		var sa := clampf(snow_cover * 0.78 * snow_patch, 0.0, 0.84) * alpha
		var snow_col := Color(minf(0.92 * light_tint.r + 0.06, 1.0), minf(0.95 * light_tint.g + 0.08, 1.0), minf(1.0 * light_tint.b + 0.10, 1.0), sa)
		canvas.draw_rect(Rect2(o.x, o.y, s, s * 0.86), snow_col)

	if is_ridge:
		var bh := maxf(3.0, s * 0.22)
		if vertical_ridge:
			var rx := o.x + s * 0.36 if rel <= 0 else o.x + s * 0.12
			canvas.draw_rect(Rect2(rx, o.y, bh, s), ridge_col)
			canvas.draw_rect(Rect2(rx, o.y, maxf(1.5, bh * 0.32), s), ridge_hi)
			canvas.draw_rect(Rect2(rx + bh, o.y, maxf(2.0, s * 0.08), s), Color(0.04, 0.06, 0.08, 0.40 * alpha))
		else:
			var ry := o.y + s * 0.36 if rel <= 0 else o.y + s * 0.12
			canvas.draw_rect(Rect2(o.x, ry, s, bh), ridge_col)
			canvas.draw_rect(Rect2(o.x, ry, s, maxf(1.5, bh * 0.32)), ridge_hi)
			canvas.draw_rect(Rect2(o.x, ry + bh, s, maxf(2.0, s * 0.08)), Color(0.04, 0.06, 0.08, 0.44 * alpha))

	var n_edge := (edge_mask & 1) != 0
	var s_edge := (edge_mask & 2) != 0
	var w_edge := (edge_mask & 4) != 0
	var e_edge := (edge_mask & 8) != 0
	var trim := maxf(3.2, s * 0.15)
	var gable_light := Color(0.88 * light_tint.r, 0.85 * light_tint.g, 0.79 * light_tint.b, alpha)
	var gable_dark := Color(0.72 * light_tint.r, 0.70 * light_tint.g, 0.64 * light_tint.b, alpha)

	if vertical_ridge:
		# N & S edges = stepped white-plaster horse-head gables (南北马头墙!)
		if n_edge:
			canvas.draw_rect(Rect2(o.x, o.y, s, trim * 1.15), gable_light)
			canvas.draw_rect(Rect2(o.x, o.y, s, maxf(1.5, trim * 0.42)), ridge_col)
			if (d1 % 2 == 0):
				canvas.draw_rect(Rect2(o.x, o.y - 1.5, maxf(2.4, s * 0.14), trim * 1.35), tile_dark)
		if s_edge:
			canvas.draw_rect(Rect2(o.x, o.y + s - trim * 1.15, s, trim * 1.15), gable_dark)
			canvas.draw_rect(Rect2(o.x, o.y + s - maxf(1.5, trim * 0.42), s, maxf(1.5, trim * 0.42)), tile_dark)
			canvas.draw_rect(Rect2(o.x, o.y + s, s, maxf(2.8, s * 0.16)), Color(0.03, 0.05, 0.07, 0.46 * alpha))
		# W & E edges = drip-tile eaves + hanging crimson lanterns!
		if w_edge:
			canvas.draw_rect(Rect2(o.x, o.y, trim * 0.85, s), tile_dark)
			for r in range(cols):
				canvas.draw_circle(Vector2(o.x + 1.2, o.y + (float(r) + 0.5) * cw), maxf(1.1, cw * 0.20), ridge_hi)
		if e_edge:
			canvas.draw_rect(Rect2(o.x + s - trim * 0.85, o.y, trim * 0.85, s), tile_dark)
			for r in range(cols):
				canvas.draw_circle(Vector2(o.x + s - 1.2, o.y + (float(r) + 0.5) * cw), maxf(1.1, cw * 0.20), ridge_hi)
			canvas.draw_rect(Rect2(o.x + s, o.y, maxf(2.4, s * 0.13), s), Color(0.03, 0.05, 0.07, 0.38 * alpha))
			if posmod(p.y, 3) == 1 and s >= 20.0:
				var lx := o.x + s + s * 0.04
				var ly := o.y + s * 0.50
				var lr := maxf(2.2, s * 0.11)
				var l_glow := clampf(night_warmth, 0.0, 1.0)
				if l_glow > 0.12:
					canvas.draw_circle(Vector2(lx, ly), lr * 2.8, Color(1.0, 0.42, 0.16, 0.24 * l_glow * alpha))
				var l_col := Color("b8221a").lerp(Color("ff6e3a"), l_glow * 0.72)
				l_col = Color(l_col.r * maxf(0.65, light_tint.r), l_col.g * maxf(0.55, light_tint.g), l_col.b * maxf(0.45, light_tint.b), alpha)
				canvas.draw_rect(Rect2(lx - lr * 0.75, ly - lr * 0.9, lr * 1.5, lr * 1.8), l_col)
	else:
		if n_edge:
			canvas.draw_rect(Rect2(o.x, o.y, s, trim), ridge_col)
			canvas.draw_rect(Rect2(o.x, o.y, s, maxf(1.0, trim * 0.35)), ridge_hi)
		if s_edge:
			canvas.draw_rect(Rect2(o.x, o.y + s - trim * 0.85, s, trim * 0.85), tile_dark)
			for c in range(cols):
				var tx := o.x + (float(c) + 0.5) * cw
				canvas.draw_circle(Vector2(tx, o.y + s - 1.0), maxf(1.2, cw * 0.22), ridge_hi)
			canvas.draw_rect(Rect2(o.x, o.y + s, s, maxf(2.8, s * 0.16)), Color(0.03, 0.05, 0.07, 0.46 * alpha))
			if posmod(p.x, 3) == 1 and s >= 20.0:
				var lx := o.x + s * 0.50
				var ly := o.y + s + s * 0.04
				var lr := maxf(2.2, s * 0.11)
				var l_glow := clampf(night_warmth, 0.0, 1.0)
				if l_glow > 0.12:
					canvas.draw_circle(Vector2(lx, ly), lr * 2.8, Color(1.0, 0.42, 0.16, 0.24 * l_glow * alpha))
				var l_col := Color("b8221a").lerp(Color("ff6e3a"), l_glow * 0.72)
				l_col = Color(l_col.r * maxf(0.65, light_tint.r), l_col.g * maxf(0.55, light_tint.g), l_col.b * maxf(0.45, light_tint.b), alpha)
				canvas.draw_rect(Rect2(lx - lr * 0.75, ly - lr * 0.9, lr * 1.5, lr * 1.8), l_col)
				canvas.draw_line(Vector2(lx, ly + lr * 0.9), Vector2(lx, ly + lr * 1.5), Color("d9a244", alpha), 1.0)
		if w_edge:
			canvas.draw_rect(Rect2(o.x, o.y, trim * 1.15, s), gable_light)
			canvas.draw_rect(Rect2(o.x, o.y, maxf(1.5, trim * 0.42), s), ridge_col)
			if (d1 % 2 == 0):
				canvas.draw_rect(Rect2(o.x - 1.5, o.y, trim * 1.35, maxf(2.4, s * 0.14)), tile_dark)
		if e_edge:
			canvas.draw_rect(Rect2(o.x + s - trim * 1.15, o.y, trim * 1.15, s), gable_dark)
			canvas.draw_rect(Rect2(o.x + s - maxf(1.5, trim * 0.42), o.y, maxf(1.5, trim * 0.42), s), tile_dark)
			if (d1 % 2 == 0):
				canvas.draw_rect(Rect2(o.x + s - trim * 1.20, o.y, trim * 1.35, maxf(2.4, s * 0.14)), tile_dark)
			canvas.draw_rect(Rect2(o.x + s, o.y, maxf(2.0, s * 0.10), s), Color(0.03, 0.05, 0.07, 0.34 * alpha))
