extends RefCounted

const Pack = preload("res://scripts/undead_tiles.gd")
const Lighting = preload("res://scripts/lighting.gd")
const ChineseArch = preload("res://scripts/chinese_architecture.gd")
const ChineseFurn = preload("res://scripts/chinese_furniture.gd")
const RoadBlend = preload("res://scripts/road_blending.gd")

const NEIGHBORS := [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]
const TREES := ["t_tree_willow", "t_tree_maple", "t_tree_pine"]
const SHRUBS := ["t_shrub", "t_shrub_lilac", "t_shrub_blackberry"]

static var cataclysm_mode := false

const SEASON_GRASS_TINT := {
	"spring": Color("eef6e8"),
	"summer": Color("e2f0db"),
	"autumn": Color("e8d9b8"),
	"winter": Color("d5dde0"),
}
const SEASON_STONE_TINT := {
	"spring": Color("e5ded0"),
	"summer": Color("eae4d6"),
	"autumn": Color("e2d4be"),
	"winter": Color("d6dde2"),
}


static func _hash(p: Vector2i, seed: int) -> int:
	var n := ((p.x * 0x9e3779b9) ^ (p.y * 0x85ebca6b) ^ seed) & 0xffffffff
	n = ((n ^ (n >> 16)) * 0x7feb352d) & 0xffffffff
	return n ^ (n >> 15)


static func _join(cells: Dictionary, p: Vector2i, allowed: Array, layer: int) -> int:
	var mask := 0
	for i in NEIGHBORS.size():
		var other: Array = cells.get(p + NEIGHBORS[i], [" ", ""])
		if other[layer] in allowed:
			mask |= 1 << i
	return mask


static func _count_neighbors(cells: Dictionary, p: Vector2i, allowed: Array) -> int:
	var count := 0
	for step: Vector2i in NEIGHBORS:
		var other: Array = cells.get(p + step, [" ", ""])
		if other[0] in allowed:
			count += 1
	return count


static func _cell_origin(board: Control, p: Vector2i) -> Vector2:
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	return Vector2((p - board.view_origin) * board.cell) + cam_offset


static func ground(board: Control, cells: Dictionary, p: Vector2i, seed: int, season := "spring",
		tint_override := Color.WHITE) -> void:
	var feature: String = cells[p][0]
	var surface: String = cells[p][1]
	if feature == " ":
		return
	var roll := _hash(p, seed)
	if cataclysm_mode:
		_ground_cataclysm(board, cells, p, feature, surface, roll, season, tint_override)
		return
	var stone_tint: Color = SEASON_STONE_TINT.get(season, Color("e5ded0")) * tint_override
	var grass_tint: Color = SEASON_GRASS_TINT.get(season, Color("eef6e8")) * tint_override
	match surface:
		"m":
			Pack.draw(board, "t_rock_floor", p, roll, _join(cells, p, ["m"], 1), 0, stone_tint)
		"p", "G":
			Pack.draw(board, "t_stone_masonry_floor", p, roll, _join(cells, p, ["p", "G", "m"], 1), 0,
				Color("dfd4be") * tint_override)
		"J", "j":
			Pack.draw(board, "t_stone_masonry_floor", p, roll, _join(cells, p, ["j", "J"], 1), 0,
				Color("b4aca0") * tint_override)
		"i", "H", "B", "N", "R":
			Pack.draw(board, "t_floor", p, roll, _join(cells, p, ["i", "H", "B", "N", "R"], 1), 0,
				Color("e6d8c3") * tint_override)
			if surface == "R":
				Pack.draw(board, "t_carpet_red", p, roll, _join(cells, p, ["R"], 1), 0,
					Color("d9bab0") * tint_override)
		"d":
			Pack.draw(board, "t_dirt", p, roll, -1, 0, Color("d0b996") * tint_override)
		_:
			match feature:
				"=":
					_draw_stone_arch_deck(board, cells, p, roll, tint_override)
				"W":
					Pack.draw(board, "t_water_moving_dp", p, roll, -1, 0, Color("dcecf0") * tint_override)
				"~":
					Pack.draw(board, "t_water_moving_sh", p, roll, _join(cells, p, ["~", "W"], 0), 0,
						Color("bad7da") * tint_override)
				"+":
					Pack.draw(board, "t_stone_road", p, roll, -1, 0, Color("ddd2be") * tint_override)
				":":
					Pack.draw(board, "t_dirt", p, roll, -1, 0, Color("d9c5a2") * tint_override, Vector2.ZERO, false, season)
				"s":
					var shore_links := _count_neighbors(cells, p, ["s", "~", "W", ":"])
					if shore_links >= 2:
						Pack.draw(board, "t_sand", p, roll, _join(cells, p, [":", "s", "~", "W"], 0), 0,
							Color("dfd0af") * tint_override, Vector2.ZERO, false, season)
					else:
						Pack.draw(board, "t_grass", p, roll, _join(cells, p, [".", "g", "Y", "L", "f", "s"], 0), 0,
							grass_tint.lerp(Color("d6c9a5") * tint_override, 0.28), Vector2.ZERO, false, season)
						if not board.has_method("surface_id"):
							var o := _cell_origin(board, p)
							var s := float(board.cell)
							board.draw_circle(o + Vector2(s * (0.3 + float(roll % 5) * 0.08), s * (0.35 + float((roll >> 3) % 5) * 0.07)),
								maxf(1.5, s * 0.07), Color(0.68, 0.64, 0.52, 0.34) * tint_override)
							board.draw_circle(o + Vector2(s * (0.62 - float((roll >> 6) % 4) * 0.08), s * (0.65 - float((roll >> 9) % 4) * 0.07)),
								maxf(1.2, s * 0.055), Color(0.56, 0.54, 0.45, 0.30) * tint_override)
				".", "g", "Y", "L", "f":
					var field := sin(p.x * 0.24 + seed % 37) * cos(p.y * 0.27 - seed % 23)
					var grass := "t_grass_long" if roll % 100 < 22.0 + field * 18.0 else "t_grass"
					Pack.draw(board, grass, p, roll, _join(cells, p, [".", "g", "Y", "L", "f", "s"], 0), 0,
						grass_tint, Vector2.ZERO, false, season)
				_:
					Pack.draw(board, "t_floor", p, roll, 15, 0, Color("e6d8c3") * tint_override)

	# Smooth organic rounded corners & feathered edges between cobblestone roads and grass!
	RoadBlend.blend_tile(board, cells, p, seed, season, tint_override)


static func _ground_cataclysm(board: Control, cells: Dictionary, p: Vector2i, feature: String, surface: String,
		roll: int, season: String, tint_override: Color) -> void:
	var grass_tint: Color = SEASON_GRASS_TINT.get(season, Color("d8e6d0")) * Color(0.90, 0.92, 0.88) * tint_override
	match surface:
		"m":
			Pack.draw(board, "t_pavement", p, roll, _join(cells, p, ["m"], 1), 0, Color("cfd4d8") * tint_override)
			if not board.has_method("surface_id"):
				var o := _cell_origin(board, p)
				var s := float(board.cell)
				# Subtle yellow asphalt center road markings on main avenues
				if (p.x == 119 or p.x == 66 or p.x == 172) and (p.y % 4 == 0 or p.y % 4 == 1):
					board.draw_rect(Rect2(o.x + s * 0.88, o.y + s * 0.10, maxf(2.0, s * 0.12), s * 0.80), Color("c9a83c", 0.72) * tint_override)
				elif (p.y == 53 or p.y == 101 or p.y == 149 or p.y == 191) and (p.x % 4 == 0 or p.x % 4 == 1):
					board.draw_rect(Rect2(o.x + s * 0.10, o.y + s * 0.88, s * 0.80, maxf(2.0, s * 0.12)), Color("c9a83c", 0.72) * tint_override)
		"p", "G":
			Pack.draw(board, "t_sidewalk", p, roll, _join(cells, p, ["p", "G"], 1), 0, Color("d4d6d8") * tint_override)
		"i", "H", "B", "N", "R":
			Pack.draw(board, "t_concrete", p, roll, _join(cells, p, ["i", "H", "B", "N", "R"], 1), 0, Color("cfd3d6") * tint_override)
		_:
			match feature:
				"=":
					Pack.draw(board, "t_pavement", p, roll, -1, 0, Color("b8bec4") * tint_override)
				"W":
					Pack.draw(board, "t_water_moving_dp", p, roll, -1, 0, Color("c4d9e0") * tint_override)
				"~":
					Pack.draw(board, "t_water_moving_sh", p, roll, _join(cells, p, ["~", "W"], 0), 0, Color("a8c6ce") * tint_override)
				"+":
					Pack.draw(board, "t_pavement", p, roll, -1, 0, Color("cfd4d8") * tint_override)
				":":
					Pack.draw(board, "t_sidewalk", p, roll, -1, 0, Color("d4d6d8") * tint_override)
				".", "g", "Y", "L", "f":
					var grass := "t_grass_long" if (roll % 100) < 28 else "t_grass"
					Pack.draw(board, grass, p, roll, _join(cells, p, [".", "g", "Y", "L", "f"], 0), 0, grass_tint, Vector2.ZERO, false, season)
				_:
					Pack.draw(board, "t_concrete", p, roll, 15, 0, Color("cfd3d6") * tint_override)


static func _draw_modern_streetlight(board: Control, p: Vector2i, lit_strength: float) -> void:
	var masking := board.has_method("surface_id")
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	var mc: Color = board.call("surface_id", p) if masking else Color.WHITE
	var pole := mc if masking else Color("58626b")
	var head := mc if masking else Color("3b444d")
	board.draw_rect(Rect2(o.x + s * 0.44, o.y + s * 0.14, maxf(2.4, s * 0.11), s * 0.78), pole)
	board.draw_rect(Rect2(o.x + s * 0.42, o.y + s * 0.12, s * 0.36, maxf(2.4, s * 0.10)), head)
	if not masking:
		var glow := clampf(lit_strength, 0.0, 1.0)
		var bulb := Color("a8b8c4").lerp(Color("ffe8a8"), 0.25 + 0.75 * glow)
		board.draw_circle(o + Vector2(s * 0.74, s * 0.20), maxf(2.2, s * 0.09), bulb)
		if glow > 0.12:
			board.draw_circle(o + Vector2(s * 0.74, s * 0.24), s * 0.42, Color(1.0, 0.88, 0.56, 0.20 * glow))


static func walls(board: Control, cells: Dictionary, p: Vector2i, seed: int, _season := "spring",
		night_warmth := 0.0) -> void:
	var tile: String = cells[p][0]
	if cataclysm_mode:
		var roll := _hash(p, seed)
		var mask := _join(cells, p, ["#", "w", "O", "%", "D", "o"], 0)
		match tile:
			"#": Pack.draw(board, "t_brick_wall", p, roll, mask)
			"D": Pack.draw(board, "t_door_c", p, roll, mask)
			"o": Pack.draw(board, "t_door_o", p, roll, mask)
			"w": Pack.draw(board, "t_window", p, roll, mask)
			"O": Pack.draw(board, "t_window_open", p, roll, mask)
			"%": Pack.draw(board, "t_window_frame", p, roll, mask)
			"f": Pack.draw(board, "t_chainfence", p, roll, _join(cells, p, ["f", "#"], 0))
		return
	if tile in ["#", "w", "O", "%", "D", "o", "f"]:
		ChineseArch.draw_wall_segment(board, cells, p, seed, night_warmth)


static func _draw_lantern_post(board: Control, p: Vector2i, lit_strength: float, hanging_only := false) -> void:
	var masking := board.has_method("surface_id")
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	var mask_col: Color = board.call("surface_id", p) if masking else Color.WHITE
	var wood_dark := mask_col if masking else Color("4a2018")
	var wood_mid := mask_col if masking else Color("753124")
	var stone := mask_col if masking else Color("6c7072")
	var cap_col := mask_col if masking else Color("2b2f33")
	var glow := clampf(lit_strength, 0.0, 1.0)
	var paper := mask_col if masking else Color("cf5c3a").lerp(Color("ffd274"), 0.30 + glow * 0.70)
	var core := mask_col if masking else Color("ffe8a6").lerp(Color("fff8dc"), glow)

	if not hanging_only:
		# Carved stone plinth & vermilion Chinese lantern pillar (朱木挑檐宫灯柱)
		board.draw_rect(Rect2(o.x + s * 0.35, o.y + s * 0.78, s * 0.30, s * 0.15), stone)
		board.draw_rect(Rect2(o.x + s * 0.44, o.y + s * 0.14, s * 0.12, s * 0.66), wood_mid)
		# Upturned carved timber bracket arm
		board.draw_rect(Rect2(o.x + s * 0.34, o.y + s * 0.13, s * 0.42, s * 0.08), wood_dark)
		board.draw_rect(Rect2(o.x + s * 0.72, o.y + s * 0.09, s * 0.08, s * 0.08), wood_dark)
	var lx := o.x + (s * 0.65 if not hanging_only else s * 0.50)
	var ly := o.y + (s * 0.33 if not hanging_only else s * 0.36)
	var lw := maxf(4.5, s * 0.25)
	var lh := maxf(5.5, s * 0.29)
	# Hexagonal palace lantern roof cap & silk red tassel
	board.draw_rect(Rect2(lx - lw * 0.66, ly - lh * 0.60, lw * 1.32, maxf(1.8, s * 0.08)), cap_col)
	board.draw_rect(Rect2(lx - lw * 0.5, ly - lh * 0.46, lw, lh), paper)
	if not masking:
		board.draw_rect(Rect2(lx - lw * 0.26, ly - lh * 0.28, lw * 0.52, lh * 0.56), core)
		board.draw_rect(Rect2(lx - lw * 0.5, ly - lh * 0.46, lw, lh), wood_dark, false, 1.0)
		board.draw_line(Vector2(lx, ly + lh * 0.54), Vector2(lx, ly + lh * 0.90), Color("c43b2c"), maxf(1.2, s * 0.055))
		if glow > 0.15:
			board.draw_circle(Vector2(lx, ly), s * 0.36, Color(1.0, 0.72, 0.32, 0.18 * glow))


static func _bridge_span_info(cells: Dictionary, p: Vector2i) -> Dictionary:
	# Detect whether this '=' bridge spans E-W (water N/S) or N-S (water E/W) and compute arch crown progress (0..1)
	var wn: int = 0
	var ws: int = 0
	var ww: int = 0
	var we: int = 0
	var d_n: int = 0
	while d_n < 14 and cells.get(p + Vector2i(0, -(d_n + 1)), [" "])[0] == "=":
		d_n += 1
	var d_s: int = 0
	while d_s < 14 and cells.get(p + Vector2i(0, d_s + 1), [" "])[0] == "=":
		d_s += 1
	var d_w: int = 0
	while d_w < 18 and cells.get(p + Vector2i(-(d_w + 1), 0), [" "])[0] == "=":
		d_w += 1
	var d_e: int = 0
	while d_e < 18 and cells.get(p + Vector2i(d_e + 1, 0), [" "])[0] == "=":
		d_e += 1
	if cells.get(p + Vector2i(0, -(d_n + 1)), [" "])[0] in ["~", "W"]: wn = 1
	if cells.get(p + Vector2i(0, d_s + 1), [" "])[0] in ["~", "W"]: ws = 1
	if cells.get(p + Vector2i(-(d_w + 1), 0), [" "])[0] in ["~", "W"]: ww = 1
	if cells.get(p + Vector2i(d_e + 1, 0), [" "])[0] in ["~", "W"]: we = 1
	var is_ew: bool = (wn + ws) > (ww + we) or ((wn + ws) == (ww + we) and (d_w + d_e) >= (d_n + d_s))
	var span_len: float = float(maxi(1, (d_w + d_e) if is_ew else (d_n + d_s)))
	var t_pos: float = float(d_w if is_ew else d_n) / span_len
	var crown: float = sin(clampf(t_pos, 0.0, 1.0) * PI)
	return {"is_ew": is_ew, "crown": crown, "t": t_pos, "d_n": d_n, "d_s": d_s, "d_w": d_w, "d_e": d_e}


static func _draw_stone_arch_deck(board: Control, cells: Dictionary, p: Vector2i, roll: int, tint_override: Color) -> void:
	# Realistic Weathered Jiangnan Carved Bluestone / Granite Stepped Arch Bridge (青白石块砌台阶拱桥 — Image 1!)
	var masking := board.has_method("surface_id")
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	if masking:
		board.draw_rect(Rect2(o, Vector2(s, s)), board.call("surface_id", p))
		return
	var info := _bridge_span_info(cells, p)
	var is_ew: bool = bool(info["is_ew"])
	var crown: float = float(info["crown"])
	var near_water: bool = (cells.get(p + Vector2i.UP, [" "])[0] in ["~", "W"]) \
		or (cells.get(p + Vector2i.DOWN, [" "])[0] in ["~", "W"]) \
		or (cells.get(p + Vector2i.LEFT, [" "])[0] in ["~", "W"]) \
		or (cells.get(p + Vector2i.RIGHT, [" "])[0] in ["~", "W"])

	# Rich weathered grey-bluestone tone (NOT flat beige!) — shaded darker at bridge approaches, sunlit at arch crown!
	var stone_base := Color("696b69").lerp(Color("9d9b91"), 0.22 + crown * 0.62)
	if near_water:
		stone_base = stone_base.darkened(0.08)
	var mortar := Color("3e403f") * tint_override
	board.draw_rect(Rect2(o, Vector2(s, s)), mortar)

	# Staggered multi-tone carved granite ashlar blocks (3 stepped courses per tile x 2 staggered slabs)
	var courses := 3
	var pad := 1.0
	for k in range(courses):
		var sub_roll := _hash(Vector2i(p.x * 7 + k, p.y * 11 + k), 0x4b19)
		var is_step_edge := (k == 0)
		var split := 0.42 + float(sub_roll % 5) * 0.05 if ((k + (p.x if is_ew else p.y)) % 2 == 0) else 0.56 - float(sub_roll % 4) * 0.05
		for half in range(2):
			var h_roll := _hash(Vector2i(p.x * 13 + k * 3 + half, p.y * 17 + half), 0x8831)
			var delta := (float(h_roll % 11) - 5.0) * 0.015
			var warm_shift := (float((h_roll >> 4) % 5) - 2.0) * 0.008
			var bcol := Color(
				clampf(stone_base.r + delta + warm_shift, 0.0, 1.0),
				clampf(stone_base.g + delta + warm_shift * 0.5, 0.0, 1.0),
				clampf(stone_base.b + delta - warm_shift * 0.4, 0.0, 1.0)
			) * tint_override
			var rect: Rect2
			if is_ew:
				var x0 := o.x + (float(k) / float(courses)) * s
				var bw := (s / float(courses)) - pad
				var y0 := o.y + (0.0 if half == 0 else s * split)
				var bh := (s * split if half == 0 else s * (1.0 - split)) - pad
				rect = Rect2(x0, y0, maxf(1.5, bw), maxf(1.5, bh))
			else:
				var y0 := o.y + (float(k) / float(courses)) * s
				var bh := (s / float(courses)) - pad
				var x0 := o.x + (0.0 if half == 0 else s * split)
				var bw := (s * split if half == 0 else s * (1.0 - split)) - pad
				rect = Rect2(x0, y0, maxf(1.5, bw), maxf(1.5, bh))
			board.draw_rect(rect, bcol)
			# Subtle chiseled sunlit step highlight on the crown-facing lip & weathered shadow on lower edge
			var hi_col := bcol.lightened(0.18 if is_step_edge else 0.10)
			var sh_col := bcol.darkened(0.20)
			if is_ew:
				board.draw_line(rect.position, Vector2(rect.position.x, rect.end.y), hi_col, 1.0)
				board.draw_line(Vector2(rect.end.x, rect.position.y), rect.end, sh_col, 1.0)
			else:
				board.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), hi_col, 1.0)
				board.draw_line(Vector2(rect.position.x, rect.end.y), rect.end, sh_col, 1.0)

	# Subtle damp moss weathering in outer stone crevices near the river
	if near_water and (roll % 5 == 0):
		board.draw_rect(Rect2(o.x + s * 0.15, o.y + s * 0.15, s * 0.24, s * 0.18),
			Color(0.24, 0.34, 0.22, 0.26) * tint_override)


static func _draw_bridge_rails(board: Control, cells: Dictionary, p: Vector2i, emitters: Dictionary, lit_strength: float) -> void:
	# Weathered Carved Grey-White Granite Arch Parapets, Relief Panels, Sculpted Pillars (望柱) & Vaulted Stone Arch (石券桥洞)
	var masking := board.has_method("surface_id")
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	var stone_wall: Color = board.call("surface_id", p) if masking else Color("9e9c92")
	var stone_top: Color = board.call("surface_id", p) if masking else Color("cbc7ba")
	var stone_panel: Color = board.call("surface_id", p) if masking else Color("7c7c76")
	var stone_dark: Color = board.call("surface_id", p) if masking else Color("4a4b48")
	var north_water: bool = cells.get(p + Vector2i.UP, [" "])[0] in ["~", "W"]
	var south_water: bool = cells.get(p + Vector2i.DOWN, [" "])[0] in ["~", "W"]
	var west_water: bool = cells.get(p + Vector2i.LEFT, [" "])[0] in ["~", "W"]
	var east_water: bool = cells.get(p + Vector2i.RIGHT, [" "])[0] in ["~", "W"]
	var info := _bridge_span_info(cells, p)
	var crown: float = float(info["crown"])

	if north_water:
		var rh := maxf(3.6, s * 0.19)
		board.draw_rect(Rect2(o.x, o.y, s, rh), stone_wall)
		board.draw_rect(Rect2(o.x + 2.0, o.y + rh * 0.36, s - 4.0, rh * 0.40), stone_panel)
		board.draw_rect(Rect2(o.x, o.y, s, maxf(1.4, rh * 0.30)), stone_top)
		board.draw_line(Vector2(o.x, o.y + rh), Vector2(o.x + s, o.y + rh), stone_dark, 1.2)
		if posmod(p.x, 2) == 0:
			var pw := maxf(3.6, s * 0.21)
			var pr := Rect2(o.x + s * 0.40, o.y - s * 0.05, pw, rh + s * 0.10)
			board.draw_rect(pr, stone_top)
			board.draw_rect(pr, stone_dark, false, 1.0)
			if not masking:
				board.draw_circle(pr.get_center(), maxf(1.2, pw * 0.26), Color("dedbd0"))
	if south_water:
		if not masking:
			# Visible Coursed Stone Spandrel Wall + Arched Voussoir Stone Ring + Vaulted Dark Arch Cavity (Image 1!)
			var spandrel_h := maxf(5.5, s * (0.28 + (1.0 - crown) * 0.14))
			board.draw_rect(Rect2(o.x, o.y + s, s, spandrel_h), Color("747673"))
			# Horizontal masonry course lines on bridge side facade
			board.draw_line(Vector2(o.x, o.y + s + spandrel_h * 0.5), Vector2(o.x + s, o.y + s + spandrel_h * 0.5), Color("4c4e4c"), 1.0)
			board.draw_line(Vector2(o.x + s * 0.5, o.y + s), Vector2(o.x + s * 0.5, o.y + s + spandrel_h), Color("4c4e4c"), 1.0)
			# Curved vaulted arch opening (highest & deepest under the center arch crown!)
			var arch_h := s * (0.14 + crown * 0.36)
			var arch_top := o.y + s + spandrel_h * (1.0 - crown * 0.65)
			board.draw_rect(Rect2(o.x, arch_top, s, arch_h), Color(0.03, 0.06, 0.08, 0.52 + 0.24 * crown))
			if crown > 0.20:
				# Carved pale-stone arch voussoir trim along the curved arch lip
				board.draw_line(Vector2(o.x, arch_top), Vector2(o.x + s, arch_top), Color("b8b5aa"), maxf(1.6, s * 0.07))
			# Warm golden lantern reflection shimmering along arch under-lip at dusk/night (Image 3!)
			if lit_strength > 0.10:
				board.draw_rect(Rect2(o.x, arch_top + arch_h * 0.15, s, arch_h * 0.45),
					Color(1.0, 0.76, 0.34, 0.22 * lit_strength * (0.4 + 0.6 * crown)))
		var rh := maxf(3.6, s * 0.19)
		board.draw_rect(Rect2(o.x, o.y + s - rh, s, rh), stone_wall)
		board.draw_rect(Rect2(o.x + 2.0, o.y + s - rh * 0.72, s - 4.0, rh * 0.40), stone_panel)
		board.draw_rect(Rect2(o.x, o.y + s - rh, s, maxf(1.4, rh * 0.30)), stone_top)
		board.draw_line(Vector2(o.x, o.y + s), Vector2(o.x + s, o.y + s), stone_dark, 1.3)
		if posmod(p.x, 2) == 0:
			var pw := maxf(3.6, s * 0.21)
			var pr := Rect2(o.x + s * 0.40, o.y + s - rh - s * 0.05, pw, rh + s * 0.10)
			board.draw_rect(pr, stone_top)
			board.draw_rect(pr, stone_dark, false, 1.0)
			if not masking:
				board.draw_circle(pr.get_center(), maxf(1.2, pw * 0.26), Color("dedbd0"))
	if west_water:
		var rw := maxf(3.6, s * 0.19)
		board.draw_rect(Rect2(o.x, o.y, rw, s), stone_wall)
		board.draw_rect(Rect2(o.x + rw * 0.34, o.y + 2.0, rw * 0.40, s - 4.0), stone_panel)
		board.draw_rect(Rect2(o.x, o.y, maxf(1.4, rw * 0.30), s), stone_top)
		board.draw_line(Vector2(o.x + rw, o.y), Vector2(o.x + rw, o.y + s), stone_dark, 1.2)
		if posmod(p.y, 2) == 0:
			var ph := maxf(3.6, s * 0.21)
			var pr := Rect2(o.x - s * 0.05, o.y + s * 0.40, rw + s * 0.10, ph)
			board.draw_rect(pr, stone_top)
			board.draw_rect(pr, stone_dark, false, 1.0)
	if east_water:
		if not masking:
			var spandrel_w := maxf(4.5, s * (0.22 + (1.0 - crown) * 0.12))
			board.draw_rect(Rect2(o.x + s, o.y, spandrel_w, s), Color("747673"))
			var arch_w := s * (0.14 + crown * 0.30)
			var arch_left := o.x + s + spandrel_w * (1.0 - crown * 0.65)
			board.draw_rect(Rect2(arch_left, o.y, arch_w, s), Color(0.03, 0.06, 0.08, 0.46 + 0.22 * crown))
			if crown > 0.20:
				board.draw_line(Vector2(arch_left, o.y), Vector2(arch_left, o.y + s), Color("b8b5aa"), maxf(1.5, s * 0.065))
			if lit_strength > 0.10:
				board.draw_rect(Rect2(arch_left + arch_w * 0.15, o.y, arch_w * 0.45, s),
					Color(1.0, 0.76, 0.34, 0.20 * lit_strength * (0.4 + 0.6 * crown)))
		var rw := maxf(3.6, s * 0.19)
		board.draw_rect(Rect2(o.x + s - rw, o.y, rw, s), stone_wall)
		board.draw_rect(Rect2(o.x + s - rw * 0.74, o.y + 2.0, rw * 0.40, s - 4.0), stone_panel)
		board.draw_rect(Rect2(o.x + s - rw, o.y, maxf(1.4, rw * 0.30), s), stone_top)
		board.draw_line(Vector2(o.x + s, o.y), Vector2(o.x + s, o.y + s), stone_dark, 1.3)
		if posmod(p.y, 2) == 0:
			var ph := maxf(3.6, s * 0.21)
			var pr := Rect2(o.x + s - rw - s * 0.05, o.y + s * 0.40, rw + s * 0.10, ph)
			board.draw_rect(pr, stone_top)
			board.draw_rect(pr, stone_dark, false, 1.0)
	if emitters.get(p) == &"bridge_lamp":
		_draw_lantern_post(board, p, lit_strength, true)


static func detail(board: Control, world: RefCounted, cells: Dictionary, p: Vector2i, seed: int,
		season := "spring", emitters: Dictionary = {}, lit_strength := 0.0,
		props_map: Dictionary = {}, use_props_map := false) -> void:
	var tile: String = cells[p][0]
	var roll := _hash(p, seed)
	var masking := board.has_method("surface_id")
	if cataclysm_mode:
		if tile == "L":
			_draw_modern_streetlight(board, p, lit_strength)
		elif tile == "Y":
			Pack.draw(board, TREES[roll % TREES.size()], p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
		elif tile == "g":
			Pack.draw(board, SHRUBS[roll % SHRUBS.size()], p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
		else:
			const CCB_FURN := {
				"b": "f_bed", "t": "f_table", "c": "f_locker", "F": "f_locker",
				"C": "f_crate_c", "k": "f_counter", "K": "f_rack", "r": "f_bookcase",
				"l": "f_table", "h": "f_oven", "u": "f_sink", "q": "f_chair",
				"S": "f_sofa", "a": "f_trashcan",
			}
			if CCB_FURN.has(tile):
				Pack.draw(board, CCB_FURN[tile], p, roll, -1, 0, Color.WHITE)
		return
	if tile == "L":
		_draw_lantern_post(board, p, lit_strength, false)
	elif tile == "=":
		_draw_bridge_rails(board, cells, p, emitters, lit_strength)
	elif tile == "~" and not masking:
		var near_bank := _count_neighbors(cells, p, ["s", ".", "g", "Y", ":"]) > 0
		var near_bridge := _count_neighbors(cells, p, ["="]) > 0
		if near_bank and not near_bridge:
			var flora := roll % 15
			if flora == 0:
				Pack.draw(board, "f_cattails", p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
			elif flora >= 1 and flora <= 3:
				Pack.draw(board, "f_lilypad", p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
			elif flora == 4 and season in ["spring", "summer"]:
				Pack.draw(board, "f_lotus", p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
	elif ChineseFurn.draw_fixture(board, world, cells, p, tile, roll, lit_strength):
		pass
	elif tile == "Y":
		Pack.draw(board, TREES[roll % TREES.size()], p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
	elif tile == "g":
		Pack.draw(board, SHRUBS[roll % SHRUBS.size()], p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)

	if not masking and emitters.get(p) == &"candle":
		var o := _cell_origin(board, p)
		var s := float(board.cell)
		# Brass Chinese candlestick & glowing candle flame
		board.draw_circle(o + Vector2(s * 0.52, s * 0.44), maxf(2.0, s * 0.095), Color("b88b4a"))
		board.draw_rect(Rect2(o.x + s * 0.49, o.y + s * 0.34, maxf(1.8, s * 0.065), s * 0.10), Color("d64234"))
		board.draw_circle(o + Vector2(s * 0.52, s * 0.33), maxf(1.4, s * 0.065),
			Color(1.0, 0.86, 0.45, 0.78 + 0.22 * lit_strength))
	if world != null and tile not in [" ", "F"]:
		var item: String = String(props_map.get(p, "")) if use_props_map else String(world.prop_at(p))
		if not item.is_empty():
			# Beds already render integrated Chinese pillows & brocade quilts; keep bedding lootable without smearing flat western sprites over the bed.
			if not (tile == "b" and item in ["pillow", "blanket", "sheet_cotton", "quilt"]):
				Pack.draw(board, item, p, roll, -1, 0, Color.WHITE, Vector2(0, -3))


const YANGZHOU_NPCS := [
	&"innkeeper", &"blacksmith", &"herbalist", &"martial_master",
	&"weapon_coach", &"scholar", &"pawnbroker", &"boatman", &"storyteller",
]


static func site_landmark(board: Control, p: Vector2i, site: StringName, lit_strength := 0.0) -> void:
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	if site in YANGZHOU_NPCS:
		board.draw_circle(o + Vector2(s * 0.82, s * 0.24), maxf(2.0, s * 0.11),
			Color("c96a42").lerp(Color("ffd67a"), 0.35 + 0.65 * lit_strength))
		character(board, p, site)


static func character(board: Control, p: Vector2i, role: StringName, target: Control = null) -> void:
	var dest: Control = target if target != null else board
	var masking := dest.has_method("surface_id")
	var tint: Color = dest.call("surface_id", p) if masking else Color.WHITE
	var outfit := "overlay_worn_cloak"
	var outfit_tint := tint if masking else Color("c9e3d7")
	var hat := ""
	var hat_tint := tint if masking else Color.WHITE
	match role:
		&"innkeeper":
			outfit = "overlay_worn_robe"
			outfit_tint = tint if masking else Color("e09662")
		&"blacksmith":
			outfit = "overlay_worn_coat_winter"
			outfit_tint = tint if masking else Color("6f5648")
			hat = "overlay_worn_bandana"
			hat_tint = tint if masking else Color("b44838")
		&"herbalist":
			outfit = "overlay_worn_robe"
			outfit_tint = tint if masking else Color("a8cfb8")
		&"martial_master":
			outfit = "overlay_worn_cloak"
			outfit_tint = tint if masking else Color("c85042")
			hat = "overlay_worn_bandana"
			hat_tint = tint if masking else Color("e6c878")
		&"weapon_coach":
			outfit = "overlay_worn_coat_winter"
			outfit_tint = tint if masking else Color("546273")
			hat = "overlay_worn_bandana"
			hat_tint = tint if masking else Color("c9483b")
		&"scholar":
			outfit = "overlay_worn_robe"
			outfit_tint = tint if masking else Color("7c98b3")
		&"pawnbroker":
			outfit = "overlay_worn_robe"
			outfit_tint = tint if masking else Color("8698bd")
		&"boatman":
			outfit = "overlay_worn_cloak"
			outfit_tint = tint if masking else Color("88a6b4")
			hat = "overlay_worn_straw_hat"
			hat_tint = tint if masking else Color("e4d4b2")
		&"storyteller":
			outfit = "overlay_worn_robe"
			outfit_tint = tint if masking else Color("e4d29e")
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	var origin := Vector2((p - board.view_origin) * board.cell) + cam_offset
	for id: String in ["player_male", "overlay_worn_pants", "overlay_worn_boots", "overlay_worn_tunic"]:
		Pack.draw_at(dest, id, origin, float(board.cell), 0, -1, 0, tint)
	Pack.draw_at(dest, outfit, origin, float(board.cell), 0, -1, 0, outfit_tint)
	if not hat.is_empty():
		Pack.draw_at(dest, hat, origin, float(board.cell), 0, -1, 0, hat_tint)
