extends RefCounted

# Organic rounded road-edge & corner blending (eliminates harsh 90-degree square tile stairs).
# Drawn into the GPU WorldCache (UPDATE_ONCE), so it adds 0.0 ms CPU cost during gameplay!

const ROAD_SURFACES := ["m", "p", "G"]
const ROAD_TILES := ["+", ":"]
const GRASS_TILES := [".", "g", "Y", "L", "f", "s"]

const SEASON_GRASS_BASE := {
	"spring": Color("54683b"),
	"summer": Color("486234"),
	"autumn": Color("7d683b"),
	"winter": Color("828c90"),
}
const SEASON_SOIL_BASE := {
	"spring": Color("655941"),
	"summer": Color("635740"),
	"autumn": Color("705e42"),
	"winter": Color("75787a"),
}


static func _origin(board: Control, p: Vector2i) -> Vector2:
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	return Vector2((p - board.view_origin) * board.cell) + cam_offset


static func _hash(p: Vector2i, seed: int) -> int:
	var n := ((p.x * 0x9e3779b9) ^ (p.y * 0x85ebca6b) ^ seed) & 0xffffffff
	n = ((n ^ (n >> 16)) * 0x7feb352d) & 0xffffffff
	return n ^ (n >> 15)


static func is_road(cells: Dictionary, p: Vector2i) -> bool:
	var d: Array = cells.get(p, [])
	if d.is_empty():
		return false
	var t: String = d[0]
	var sf: String = d[1]
	if t in ["#", "w", "O", "D", "o", " ", "W", "~", "="]:
		return false
	return sf in ROAD_SURFACES or (sf.is_empty() and t in ROAD_TILES)


static func is_soft_ground(cells: Dictionary, p: Vector2i) -> bool:
	var d: Array = cells.get(p, [])
	if d.is_empty():
		return false
	var t: String = d[0]
	var sf: String = d[1]
	return sf.is_empty() and t in GRASS_TILES


static func _road_color(cells: Dictionary, p: Vector2i, season: String) -> Color:
	var d: Array = cells.get(p, ["+", ""])
	var sf: String = d[1]
	var t: String = d[0]
	if sf == "m":
		return Color("707170") if season != "winter" else Color("7b8084")
	if sf == "p" or sf == "G":
		return Color("8c8270")
	if t == ":":
		return Color("8d7a5e")
	return Color("76736c")


static func _arc_corner_poly(corner: Vector2, p_a: Vector2, p_b: Vector2, arc_center: Vector2,
		radius: float, steps := 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(corner)
	var a0 := (p_a - arc_center).angle()
	var a1 := (p_b - arc_center).angle()
	var diff := wrapf(a1 - a0, -PI, PI)
	for i in range(steps + 1):
		var a := a0 + diff * (float(i) / float(steps))
		pts.append(arc_center + Vector2(cos(a), sin(a)) * radius)
	return pts


static func blend_tile(board: Control, cells: Dictionary, p: Vector2i, seed: int, season := "spring",
		tint_override := Color.WHITE) -> void:
	if board.has_method("surface_id"):
		return
	var self_road := is_road(cells, p)
	var self_soft := (not self_road) and is_soft_ground(cells, p)
	if not self_road and not self_soft:
		return
	var o := _origin(board, p)
	var s := float(board.cell)
	var roll := _hash(p, seed ^ 0x41d73)
	var grass_col: Color = SEASON_GRASS_BASE.get(season, Color("54683b")) * tint_override
	var soil_col: Color = SEASON_SOIL_BASE.get(season, Color("655941")) * tint_override

	if self_road:
		var n_soft := is_soft_ground(cells, p + Vector2i.UP)
		var s_soft := is_soft_ground(cells, p + Vector2i.DOWN)
		var w_soft := is_soft_ground(cells, p + Vector2i.LEFT)
		var e_soft := is_soft_ground(cells, p + Vector2i.RIGHT)
		if not (n_soft or s_soft or w_soft or e_soft):
			return

		# 1. Outer 90-degree road corners: carve smooth curved grass & earthen shoulder!
		var rad := s * 0.54
		var soil_rad := s * 0.62
		var corners := [
			[n_soft and w_soft, Vector2(0, 0), Vector2(rad, 0), Vector2(0, rad), Vector2(rad, rad)],
			[n_soft and e_soft, Vector2(s, 0), Vector2(s - rad, 0), Vector2(s, rad), Vector2(s - rad, rad)],
			[s_soft and w_soft, Vector2(0, s), Vector2(rad, s), Vector2(0, s - rad), Vector2(rad, s - rad)],
			[s_soft and e_soft, Vector2(s, s), Vector2(s - rad, s), Vector2(s, s - rad), Vector2(s - rad, s - rad)],
		]
		for c in corners:
			if not c[0]:
				continue
			var k: Vector2 = o + c[1]
			var center_s: Vector2 = o + Vector2(soil_rad if c[1].x == 0 else s - soil_rad, soil_rad if c[1].y == 0 else s - soil_rad)
			var pa_s: Vector2 = o + Vector2(soil_rad if c[1].x == 0 else s - soil_rad, c[1].y)
			var pb_s: Vector2 = o + Vector2(c[1].x, soil_rad if c[1].y == 0 else s - soil_rad)
			var poly_soil := _arc_corner_poly(k, pa_s, pb_s, center_s, soil_rad, 8)
			board.draw_colored_polygon(poly_soil, Color(soil_col.r, soil_col.g, soil_col.b, 0.72))

			var poly_grass := _arc_corner_poly(k, o + c[2], o + c[3], o + c[4], rad, 8)
			board.draw_colored_polygon(poly_grass, grass_col)
			# Organic grass blade tufts along the rounded shoulder
			var grass_hi := grass_col.lightened(0.14)
			for i in range(1, poly_grass.size() - 1, 2):
				var pt := poly_grass[i]
				board.draw_circle(pt, maxf(1.3, s * 0.06), grass_hi)

		# 2. Straight road edges meeting grass: feathered dirt margin + organic grass encroachment!
		var band := maxf(2.5, s * 0.12)
		if n_soft:
			board.draw_rect(Rect2(o.x, o.y, s, band), Color(soil_col.r, soil_col.g, soil_col.b, 0.45))
			_draw_tuft_strip(board, o, Vector2(s, 0), Vector2(0, 1), s, roll, grass_col, soil_col)
		if s_soft:
			board.draw_rect(Rect2(o.x, o.y + s - band, s, band), Color(soil_col.r, soil_col.g, soil_col.b, 0.45))
			_draw_tuft_strip(board, o + Vector2(0, s), Vector2(s, 0), Vector2(0, -1), s, roll ^ 0x17, grass_col, soil_col)
		if w_soft:
			board.draw_rect(Rect2(o.x, o.y, band, s), Color(soil_col.r, soil_col.g, soil_col.b, 0.45))
			_draw_tuft_strip(board, o, Vector2(0, s), Vector2(1, 0), s, roll ^ 0x31, grass_col, soil_col)
		if e_soft:
			board.draw_rect(Rect2(o.x + s - band, o.y, band, s), Color(soil_col.r, soil_col.g, soil_col.b, 0.45))
			_draw_tuft_strip(board, o + Vector2(s, 0), Vector2(0, s), Vector2(-1, 0), s, roll ^ 0x59, grass_col, soil_col)

	elif self_soft:
		var n_road := is_road(cells, p + Vector2i.UP)
		var s_road := is_road(cells, p + Vector2i.DOWN)
		var w_road := is_road(cells, p + Vector2i.LEFT)
		var e_road := is_road(cells, p + Vector2i.RIGHT)
		if not ((n_road and w_road) or (n_road and e_road) or (s_road and w_road) or (s_road and e_road)):
			return
		# 3. Inner concave L-corner fillets (eliminates the jagged step notches in diagonal roads!)
		var fillet_r := s * 0.66
		var inner_specs := [
			[n_road and w_road, Vector2(0, 0), Vector2i.UP, Vector2i.LEFT],
			[n_road and e_road, Vector2(s, 0), Vector2i.UP, Vector2i.RIGHT],
			[s_road and w_road, Vector2(0, s), Vector2i.DOWN, Vector2i.LEFT],
			[s_road and e_road, Vector2(s, s), Vector2i.DOWN, Vector2i.RIGHT],
		]
		for spec in inner_specs:
			if not spec[0]:
				continue
			var corner_local: Vector2 = spec[1]
			var k := o + corner_local
			var dir_x := 1.0 if corner_local.x == 0.0 else -1.0
			var dir_y := 1.0 if corner_local.y == 0.0 else -1.0
			var stone_col := _road_color(cells, p + spec[2], season).lerp(_road_color(cells, p + spec[3], season), 0.5) * tint_override
			var stone_dark := stone_col.darkened(0.24)
			var stone_hi := stone_col.lightened(0.14)

			# Outer soft soil feather rim around the concave fillet
			var r_soil := fillet_r + s * 0.10
			var c_soil := k + Vector2(dir_x * r_soil, dir_y * r_soil)
			var poly_soil := _arc_corner_poly(k, k + Vector2(dir_x * r_soil, 0), k + Vector2(0, dir_y * r_soil), c_soil, r_soil, 8)
			board.draw_colored_polygon(poly_soil, Color(soil_col.r, soil_col.g, soil_col.b, 0.62))

			# Smooth rounded cobblestone/flagstone quarter-fillet bridging the two road faces
			var c_stone := k + Vector2(dir_x * fillet_r, dir_y * fillet_r)
			var poly_stone := _arc_corner_poly(k, k + Vector2(dir_x * fillet_r, 0), k + Vector2(0, dir_y * fillet_r), c_stone, fillet_r, 8)
			board.draw_colored_polygon(poly_stone, stone_col)

			# Individual rounded cobble pavers along the curved fillet so it blends seamlessly with cobblestone texture!
			for i in range(4):
				var frac := (float(i) + 0.5) / 4.0
				var px := k.x + dir_x * fillet_r * (0.14 + 0.30 * frac)
				var py := k.y + dir_y * fillet_r * (0.44 - 0.30 * frac)
				var pr := maxf(1.8, s * (0.095 - 0.015 * float(i % 2)))
				board.draw_circle(Vector2(px, py), pr, stone_dark)
				board.draw_circle(Vector2(px - 0.4, py - 0.4), pr * 0.78, stone_hi if i % 2 == 0 else stone_col)


static func _draw_tuft_strip(board: Control, start: Vector2, along: Vector2, inward: Vector2,
		s: float, roll: int, grass_col: Color, soil_col: Color) -> void:
	var count := 5
	for i in range(count):
		var h := ((roll * 31 + i * 97) & 255)
		var t := (float(i) + 0.15 + float(h % 70) / 100.0) / float(count)
		var depth := s * (0.04 + float((h >> 3) % 7) * 0.014)
		var pt := start + along * t + inward * depth
		var rad := maxf(1.2, s * (0.055 + float(h % 4) * 0.014))
		board.draw_circle(pt, rad, grass_col if (h & 1) == 0 else soil_col)
		if (h & 3) == 0:
			board.draw_circle(pt - inward * (rad * 0.4), rad * 0.65, grass_col.lightened(0.15))
