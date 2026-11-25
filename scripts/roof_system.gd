extends RefCounted

# Dedicated outdoor pitched Jiangnan clay-tile roof system:
# - Indexes connected buildings in the active region
# - Smoothly fades each building's roof based on continuous distance to the player (6.4 -> 1.6 tiles)
# - Renders overlapping Jiangnan clay tiles, ridge beams, pale-plaster gable walls, wet sheen & snow cover

const Lighting = preload("res://scripts/lighting.gd")
const ROOF_FADE_NEAR := 1.6
const ROOF_FADE_FAR := 6.4

var enabled := true
var buildings: Dictionary = {} # anchor: Vector2i -> Array[Vector2i]
var building_roof_tiles: Dictionary = {} # anchor: Vector2i -> Dictionary[Vector2i, bool]
var building_alpha: Dictionary = {} # anchor: Vector2i -> float
var building_target: Dictionary = {} # anchor: Vector2i -> float
var revealed_interior: Dictionary = {} # Vector2i -> bool (tiles inside buildings whose roof has faded open)


static func _hash(p: Vector2i, seed: int) -> int:
	var n := ((p.x * 0x9e3779b9) ^ (p.y * 0x85ebca6b) ^ seed) & 0xffffffff
	n = ((n ^ (n >> 16)) * 0x7feb352d) & 0xffffffff
	return n ^ (n >> 15)


func index_buildings(cells: Dictionary, area: Rect2i) -> void:
	buildings.clear()
	building_roof_tiles.clear()
	var visited := {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var start := Vector2i(x, y)
			if visited.has(start) or not cells.has(start) or not Lighting.enclosed(cells[start]):
				continue
			var queue: Array[Vector2i] = [start]
			var members: Array[Vector2i] = []
			var anchor := start
			visited[start] = true
			var head := 0
			while head < queue.size():
				var cur := queue[head]
				head += 1
				members.append(cur)
				if cur.y < anchor.y or (cur.y == anchor.y and cur.x < anchor.x):
					anchor = cur
				for step: Vector2i in Lighting.CARDINAL:
					var nxt := cur + step
					if visited.has(nxt) or not cells.has(nxt):
						continue
					if Lighting.enclosed(cells[nxt]):
						visited[nxt] = true
						queue.append(nxt)
			var roof_set := {}
			for p: Vector2i in members:
				var tile: String = cells[p][0]
				var south_out := not Lighting.enclosed(cells.get(p + Vector2i.DOWN, []))
				if south_out and tile in ["#", "w", "O", "D", "o"]:
					continue
				roof_set[p] = true
			buildings[anchor] = members
			building_roof_tiles[anchor] = roof_set


func update_targets(player_pos: Vector2, floor_z: int, instant := false) -> void:
	building_target.clear()
	if not enabled or floor_z != 0:
		building_alpha.clear()
		refresh_revealed(floor_z)
		return
	for anchor: Vector2i in buildings:
		var members: Array = buildings[anchor]
		var min_d2 := 999999.0
		for p: Vector2i in members:
			var d2 := (Vector2(p) - player_pos).length_squared()
			if d2 < min_d2:
				min_d2 = d2
				if min_d2 <= 0.01:
					break
		var dist := sqrt(min_d2)
		var target := smoothstep(ROOF_FADE_NEAR, ROOF_FADE_FAR, dist)
		building_target[anchor] = target
		if instant or not building_alpha.has(anchor):
			building_alpha[anchor] = target
	refresh_revealed(floor_z)


func tick(delta: float, floor_z: int) -> bool:
	if building_target.is_empty():
		return false
	var changed := false
	var speed := 7.5 * delta
	for key: Vector2i in building_target:
		var target := float(building_target[key])
		var cur := float(building_alpha.get(key, target))
		if absf(cur - target) > 0.004:
			building_alpha[key] = move_toward(cur, target, speed)
			changed = true
		elif cur != target:
			building_alpha[key] = target
			changed = true
	if changed:
		refresh_revealed(floor_z)
	return changed


func snap(floor_z: int) -> void:
	for key: Vector2i in building_target:
		building_alpha[key] = building_target[key]
	refresh_revealed(floor_z)


func refresh_revealed(floor_z: int) -> void:
	revealed_interior.clear()
	if not enabled or floor_z != 0:
		for anchor: Vector2i in buildings:
			for p: Vector2i in buildings[anchor]:
				revealed_interior[p] = true
		return
	for anchor: Vector2i in buildings:
		if float(building_alpha.get(anchor, 1.0)) < 0.40:
			for p: Vector2i in buildings[anchor]:
				revealed_interior[p] = true


func draw_all(canvas: Control, board: Control, cells: Dictionary, visible: Rect2i, seed: int,
		light_tint: Color, wetness: float, snow_cover: float) -> void:
	if not enabled or buildings.is_empty():
		return
	for anchor: Vector2i in buildings:
		var alpha := float(building_alpha.get(anchor, 1.0))
		if alpha <= 0.01:
			continue
		var roof_set: Dictionary = building_roof_tiles[anchor]
		for p: Vector2i in roof_set:
			if visible.has_point(p):
				_draw_tile(canvas, board, cells, roof_set, p, seed, alpha, light_tint, wetness, snow_cover)


static func _draw_tile(canvas: Control, board: Control, cells: Dictionary, roof_tiles: Dictionary, p: Vector2i,
		seed: int, alpha: float, light_tint: Color, wetness: float, snow_cover: float) -> void:
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	var o := Vector2((p - board.view_origin) * board.cell) + cam_offset
	var s := float(board.cell)
	var data: Array = cells[p]
	var multi_story := (int(data[3]) & 4) != 0
	var north_d := 0
	while north_d < 12 and roof_tiles.has(p + Vector2i(0, -(north_d + 1))):
		north_d += 1
	var south_d := 0
	while south_d < 12 and roof_tiles.has(p + Vector2i(0, south_d + 1)):
		south_d += 1
	var rel := north_d - south_d
	var is_ridge := absi(rel) <= 1 and (north_d + south_d) >= 2
	var north_slope := rel < -1
	var roll := _hash(p, seed ^ 0x29c71)
	var jitter := (float(roll % 9) - 4.0) * 0.008

	var base := Color(0.21 + jitter, 0.27 + jitter, 0.31 + jitter) if north_slope else Color(0.28 + jitter, 0.35 + jitter, 0.40 + jitter)
	if multi_story:
		base = base.darkened(0.08)
	if wetness > 0.01:
		base = base.darkened(0.18 * wetness)
	var lit_base := Color(base.r * light_tint.r, base.g * light_tint.g, base.b * light_tint.b, alpha)
	if wetness > 0.05:
		var sheen := (0.06 if north_slope else 0.11) * wetness * light_tint.b
		lit_base = Color(minf(lit_base.r + sheen * 0.7, 1.0), minf(lit_base.g + sheen * 0.85, 1.0), minf(lit_base.b + sheen, 1.0), alpha)

	var tile_dark := Color(lit_base.r * 0.62, lit_base.g * 0.64, lit_base.b * 0.68, alpha)
	var tile_hi := Color(minf(lit_base.r * 1.24, 1.0), minf(lit_base.g * 1.24, 1.0), minf(lit_base.b * 1.26, 1.0), alpha * 0.72)
	var ridge_col := Color(0.46 * light_tint.r, 0.52 * light_tint.g, 0.56 * light_tint.b, alpha)
	var ridge_hi := Color(minf(0.68 * light_tint.r, 1.0), minf(0.74 * light_tint.g, 1.0), minf(0.78 * light_tint.b, 1.0), alpha)

	canvas.draw_rect(Rect2(o, Vector2(s, s)), lit_base)

	var cols := maxi(4, int(round(s / 8.0)))
	var rows := 4
	var cw := s / float(cols)
	var rh := s / float(rows)
	for r in range(rows):
		var ry := o.y + float(r) * rh
		var row_shade := 0.92 + 0.14 * (float(r) / float(rows))
		if north_slope:
			row_shade = 1.06 - 0.14 * (float(r) / float(rows))
		var row_col := Color(lit_base.r * row_shade, lit_base.g * row_shade, lit_base.b * row_shade, alpha)
		canvas.draw_rect(Rect2(o.x, ry, s, rh * 0.72), row_col)
		canvas.draw_line(Vector2(o.x, ry + rh - 1.0), Vector2(o.x + s, ry + rh - 1.0), tile_dark, 1.0)
		for c in range(cols):
			var tx := o.x + float(c) * cw
			canvas.draw_line(Vector2(tx, ry), Vector2(tx, ry + rh), tile_dark, 1.0)
			if cw >= 6.0:
				canvas.draw_line(Vector2(tx + cw * 0.45, ry + 1.0), Vector2(tx + cw * 0.45, ry + rh - 1.5), tile_hi, 1.0)
			var cell_roll := _hash(Vector2i(p.x * 7 + c, p.y * 11 + r), seed)
			if cell_roll % 11 == 0:
				canvas.draw_rect(Rect2(tx + 1.0, ry + 1.0, maxf(1.0, cw - 2.0), maxf(1.0, rh - 2.0)),
					Color(tile_dark.r, tile_dark.g, tile_dark.b, alpha * 0.35))

	if snow_cover > 0.04:
		var snow_patch := 0.78 + 0.22 * (float(roll % 17) / 16.0)
		var sa := clampf(snow_cover * 0.78 * snow_patch, 0.0, 0.84) * alpha
		var snow_col := Color(minf(0.92 * light_tint.r + 0.06, 1.0), minf(0.95 * light_tint.g + 0.08, 1.0), minf(1.0 * light_tint.b + 0.10, 1.0), sa)
		for r in range(rows):
			var ry := o.y + float(r) * rh
			canvas.draw_rect(Rect2(o.x, ry, s, rh * 0.76), snow_col)

	if is_ridge:
		var ry := o.y + s * 0.36 if rel <= 0 else o.y + s * 0.12
		var bh := maxf(3.0, s * 0.22)
		canvas.draw_rect(Rect2(o.x, ry, s, bh), ridge_col)
		canvas.draw_rect(Rect2(o.x, ry, s, maxf(1.5, bh * 0.32)), ridge_hi)
		canvas.draw_rect(Rect2(o.x, ry + bh, s, maxf(2.0, s * 0.08)), Color(0.04, 0.06, 0.08, 0.44 * alpha))

	var n_edge := not roof_tiles.has(p + Vector2i.UP)
	var s_edge := not roof_tiles.has(p + Vector2i.DOWN)
	var w_edge := not roof_tiles.has(p + Vector2i.LEFT)
	var e_edge := not roof_tiles.has(p + Vector2i.RIGHT)
	var trim := maxf(2.5, s * 0.12)
	var gable_light := Color(0.80 * light_tint.r, 0.77 * light_tint.g, 0.69 * light_tint.b, alpha)
	var gable_dark := Color(0.68 * light_tint.r, 0.65 * light_tint.g, 0.58 * light_tint.b, alpha)
	if n_edge:
		canvas.draw_rect(Rect2(o.x, o.y, s, trim), ridge_col)
		canvas.draw_rect(Rect2(o.x, o.y, s, maxf(1.0, trim * 0.35)), ridge_hi)
	if s_edge:
		canvas.draw_rect(Rect2(o.x, o.y + s - trim * 0.9, s, trim * 0.9), tile_dark)
		canvas.draw_rect(Rect2(o.x, o.y + s, s, maxf(2.5, s * 0.14)), Color(0.03, 0.05, 0.07, 0.45 * alpha))
	if w_edge:
		canvas.draw_rect(Rect2(o.x, o.y, trim, s), gable_light)
		canvas.draw_rect(Rect2(o.x, o.y, maxf(1.2, trim * 0.38), s), ridge_col)
	if e_edge:
		canvas.draw_rect(Rect2(o.x + s - trim, o.y, trim, s), gable_dark)
		canvas.draw_rect(Rect2(o.x + s - maxf(1.2, trim * 0.38), o.y, maxf(1.2, trim * 0.38), s), tile_dark)
		canvas.draw_rect(Rect2(o.x + s, o.y, maxf(2.0, s * 0.10), s), Color(0.03, 0.05, 0.07, 0.34 * alpha))
