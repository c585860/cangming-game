extends RefCounted

const Pack = preload("res://scripts/undead_tiles.gd")
const Lighting = preload("res://scripts/lighting.gd")
const ChineseArch = preload("res://scripts/chinese_architecture.gd")
const ChineseFurn = preload("res://scripts/chinese_furniture.gd")
const RoadBlend = preload("res://scripts/road_blending.gd")

const NEIGHBORS := [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]
const TREES := ["t_tree_willow", "t_tree_maple", "t_tree_pine"]
const SHRUBS := ["t_shrub", "t_shrub_lilac", "t_shrub_blackberry"]

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
					Pack.draw(board, "t_dock", p, roll, _join(cells, p, ["="], 0), 0, Color("e2d1b6") * tint_override)
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


static func walls(board: Control, cells: Dictionary, p: Vector2i, seed: int, _season := "spring",
		night_warmth := 0.0) -> void:
	var tile: String = cells[p][0]
	if tile in ["#", "w", "O", "D", "o", "f"]:
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


static func _draw_bridge_rails(board: Control, cells: Dictionary, p: Vector2i, emitters: Dictionary, lit_strength: float) -> void:
	var masking := board.has_method("surface_id")
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	var col: Color = board.call("surface_id", p) if masking else Color("6e2d22")
	var hi: Color = board.call("surface_id", p) if masking else Color("944232")
	var stone_cap: Color = board.call("surface_id", p) if masking else Color("d6d1c4")
	var north_water: bool = cells.get(p + Vector2i.UP, [" "])[0] in ["~", "W"]
	var south_water: bool = cells.get(p + Vector2i.DOWN, [" "])[0] in ["~", "W"]
	if north_water:
		board.draw_rect(Rect2(o.x, o.y + s * 0.04, s, maxf(2.0, s * 0.11)), col)
		board.draw_rect(Rect2(o.x, o.y + s * 0.04, s, maxf(1.0, s * 0.04)), hi)
		if posmod(p.x, 3) == 0:
			board.draw_rect(Rect2(o.x + s * 0.42, o.y, maxf(2.4, s * 0.16), maxf(3.5, s * 0.20)), hi)
			board.draw_circle(Vector2(o.x + s * 0.50, o.y + s * 0.04), maxf(1.5, s * 0.07), stone_cap)
	if south_water:
		if not masking:
			board.draw_rect(Rect2(o.x, o.y + s, s, maxf(3.0, s * 0.18)), Color(0.03, 0.06, 0.08, 0.34))
		board.draw_rect(Rect2(o.x, o.y + s * 0.85, s, maxf(2.0, s * 0.11)), col)
		board.draw_rect(Rect2(o.x, o.y + s * 0.85, s, maxf(1.0, s * 0.04)), hi)
		if posmod(p.x, 3) == 0:
			board.draw_rect(Rect2(o.x + s * 0.42, o.y + s * 0.78, maxf(2.4, s * 0.16), maxf(3.5, s * 0.20)), hi)
			board.draw_circle(Vector2(o.x + s * 0.50, o.y + s * 0.82), maxf(1.5, s * 0.07), stone_cap)
	if emitters.get(p) == &"bridge_lamp":
		_draw_lantern_post(board, p, lit_strength, true)


static func detail(board: Control, world: RefCounted, cells: Dictionary, p: Vector2i, seed: int,
		season := "spring", emitters: Dictionary = {}, lit_strength := 0.0) -> void:
	var tile: String = cells[p][0]
	var roll := _hash(p, seed)
	var masking := board.has_method("surface_id")
	if tile == "L":
		_draw_lantern_post(board, p, lit_strength, false)
	elif tile == "=":
		_draw_bridge_rails(board, cells, p, emitters, lit_strength)
	elif tile == "~" and not masking:
		var near_bank := _count_neighbors(cells, p, ["s", ".", "g", "Y", ":"]) > 0
		var near_bridge := _count_neighbors(cells, p, ["="]) > 0
		if near_bank and not near_bridge:
			var flora := roll % 29
			if flora == 0:
				Pack.draw(board, "f_cattails", p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
			elif flora == 1 or flora == 2:
				Pack.draw(board, "f_lilypad", p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
			elif flora == 3 and season in ["spring", "summer"]:
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
		var item: String = world.prop_at(p)
		if not item.is_empty():
			Pack.draw(board, item, p, roll, -1, 0, Color.WHITE, Vector2(0, -3))


static func site_landmark(board: Control, p: Vector2i, site: StringName, lit_strength := 0.0) -> void:
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	var center := o + Vector2.ONE * (s * 0.5)
	if site == &"altar":
		Pack.draw(board, "t_stone_masonry_floor", p, 0, 15, 0, Color("cfd9d2"))
		var aura := 0.45 + 0.45 * lit_strength
		board.draw_circle(center, s * 0.62, Color(0.28, 0.88, 0.72, 0.14 + 0.14 * lit_strength))
		board.draw_arc(center, s * 0.56, 0.0, TAU, 32, Color(0.42, 0.94, 0.78, aura), maxf(1.4, s * 0.055), true)
		board.draw_arc(center, s * 0.39, 0.0, TAU, 24, Color(0.76, 0.99, 0.90, aura * 0.85), maxf(1.0, s * 0.035), true)
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			board.draw_circle(center + dir * (s * 0.56), maxf(1.6, s * 0.065), Color(0.78, 1.0, 0.92, aura))
		Pack.draw(board, "t_pillar", p, 0, -1, 0, Color("d4ece4"))
	elif site == &"herb":
		board.draw_circle(center + Vector2(0, s * 0.08), s * 0.28, Color(0.42, 0.94, 0.74, 0.14 + 0.18 * lit_strength))
		Pack.draw(board, "mayapple", p)
	elif site == &"merchant" or site == &"ferryman":
		board.draw_circle(o + Vector2(s * 0.82, s * 0.24), maxf(2.0, s * 0.11),
			Color("c96a42").lerp(Color("ffd67a"), 0.35 + 0.65 * lit_strength))
		character(board, p, site)


static func character(board: Control, p: Vector2i, role: StringName, target: Control = null) -> void:
	var dest: Control = target if target != null else board
	var masking := dest.has_method("surface_id")
	var tint: Color = dest.call("surface_id", p) if masking else Color.WHITE
	var outfit := "overlay_worn_cloak"
	var outfit_tint := tint if masking else Color("c9e3d7")
	match role:
		&"merchant":
			outfit = "overlay_worn_robe"
			outfit_tint = tint if masking else Color("e9d29c")
		&"ferryman":
			outfit = "overlay_worn_straw_hat"
			outfit_tint = tint if masking else Color("e4d4b2")
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	var origin := Vector2((p - board.view_origin) * board.cell) + cam_offset
	for id: String in ["player_male", "overlay_worn_pants", "overlay_worn_boots", "overlay_worn_tunic"]:
		Pack.draw_at(dest, id, origin, float(board.cell), 0, -1, 0, tint)
	Pack.draw_at(dest, outfit, origin, float(board.cell), 0, -1, 0, outfit_tint)
