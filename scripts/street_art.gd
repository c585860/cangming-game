extends RefCounted

const Pack = preload("res://scripts/undead_tiles.gd")
const Lighting = preload("res://scripts/lighting.gd")
const NEIGHBORS := [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]
const FIXTURES := {
	"^": "t_wood_stairs_up", "v": "t_wood_stairs_down", "X": "t_wood_stairs_up",
	"C": "f_crate_c", "l": "f_desk", "h": "f_fireplace",
	"K": "f_dresser", "F": "f_wardrobe", "P": "f_indoor_plant",
}
const CONNECTED := {"b": "f_bed", "t": "f_table", "k": "f_counter", "S": "f_bench"}
const TREES := ["t_tree_willow", "t_tree_maple", "t_tree_pine"]
const SHRUBS := ["t_shrub", "t_shrub_lilac", "t_shrub_blackberry"]
const ROOM_SURFACES := ["i", "d", "R", "j", "J"]

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
	return Vector2((p - board.view_origin) * board.cell)


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
					# Contiguous sandy beaches draw as sand; isolated bank cells blend softly into grassy shore.
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


static func _draw_eaves(board: Control, cells: Dictionary, p: Vector2i) -> void:
	var data: Array = cells[p]
	if not Lighting.enclosed(data):
		return
	var tile: String = data[0]
	if tile not in ["#", "w", "O", "D", "o"]:
		return
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	var multi_story := (int(data[3]) & 4) != 0
	var tile_dark := Color(0.13, 0.17, 0.20, 0.90)
	var tile_mid := Color(0.22, 0.28, 0.32, 0.88)
	var tile_ridge := Color(0.35, 0.43, 0.47, 0.82) if multi_story else Color(0.28, 0.35, 0.39, 0.72)
	var shadow := Color(0.05, 0.07, 0.08, 0.38)
	var eave := maxf(3.0, s * (0.20 if multi_story else 0.16))

	var n_out := not Lighting.enclosed(cells.get(p + Vector2i.UP, []))
	var s_out := not Lighting.enclosed(cells.get(p + Vector2i.DOWN, []))
	var w_out := not Lighting.enclosed(cells.get(p + Vector2i.LEFT, []))
	var e_out := not Lighting.enclosed(cells.get(p + Vector2i.RIGHT, []))
	if not (n_out or s_out or w_out or e_out):
		return

	if n_out:
		board.draw_rect(Rect2(o.x, o.y - eave * 0.45, s, eave), tile_dark)
		board.draw_rect(Rect2(o.x, o.y - eave * 0.45, s, maxf(1.5, eave * 0.35)), tile_ridge)
		board.draw_rect(Rect2(o.x, o.y + eave * 0.55, s, maxf(1.5, s * 0.06)), shadow)
		var ribs := maxi(3, int(round(s / 8.0)))
		for i in range(1, ribs):
			var rx := o.x + s * float(i) / float(ribs)
			board.draw_line(Vector2(rx, o.y - eave * 0.38), Vector2(rx, o.y + eave * 0.48), tile_mid, 1.0)
	if s_out:
		board.draw_rect(Rect2(o.x, o.y + s - eave * 0.72, s, eave * 0.95), tile_dark)
		board.draw_rect(Rect2(o.x, o.y + s - eave * 0.72, s, maxf(1.5, eave * 0.32)), tile_mid)
		board.draw_rect(Rect2(o.x, o.y + s + eave * 0.22, s, maxf(2.0, s * 0.09)), shadow)
		var ribs := maxi(3, int(round(s / 8.0)))
		for i in range(1, ribs):
			var rx := o.x + s * float(i) / float(ribs)
			board.draw_line(Vector2(rx, o.y + s - eave * 0.65), Vector2(rx, o.y + s + eave * 0.20), tile_ridge, 1.0)
	if w_out:
		board.draw_rect(Rect2(o.x - eave * 0.35, o.y, eave * 0.85, s), tile_dark)
		board.draw_rect(Rect2(o.x - eave * 0.35, o.y, maxf(1.5, eave * 0.28), s), tile_ridge)
	if e_out:
		board.draw_rect(Rect2(o.x + s - eave * 0.50, o.y, eave * 0.85, s), tile_dark)
		board.draw_rect(Rect2(o.x + s + eave * 0.35, o.y, maxf(1.5, s * 0.07), s), shadow)

	# Subtle upturned eaves corner accent on exterior roof corners.
	if (n_out or s_out) and (w_out or e_out):
		var cx := o.x - eave * 0.35 if w_out else o.x + s + eave * 0.35
		var cy := o.y - eave * 0.45 if n_out else o.y + s + eave * 0.15
		board.draw_circle(Vector2(cx, cy), maxf(1.8, eave * 0.34), tile_ridge)

	# Cinnabar-and-gold lintel plaque over exterior doorways.
	if tile in ["D", "o"] and (n_out or s_out):
		var py := o.y - eave * 0.22 if n_out else o.y + s - eave * 0.52
		board.draw_rect(Rect2(o.x + s * 0.22, py, s * 0.56, maxf(2.5, eave * 0.52)), Color("7c2822"))
		board.draw_rect(Rect2(o.x + s * 0.22, py, s * 0.56, maxf(2.5, eave * 0.52)), Color("d6b262"), false, 1.0)


static func walls(board: Control, cells: Dictionary, p: Vector2i, seed: int, season := "spring",
		night_warmth := 0.0) -> void:
	var tile: String = cells[p][0]
	var surface: String = cells[p][1]
	var roll := _hash(p, seed)
	var masking := board.has_method("surface_id")
	if tile in ["#", "w", "O"]:
		var id := "t_rock_wall" if surface == "B" else "t_wall_wood" if surface == "N" else "t_adobe_brick_wall"
		var tint := Color("cfd6d8") if surface == "B" else Color("e9d5be") if surface == "N" else Color("ede4d4")
		Pack.draw(board, id, p, roll, _join(cells, p, ["#", "w", "O", "D", "o"], 0), 0, tint)
		if tile == "w":
			if not masking:
				var o := _cell_origin(board, p)
				var s := float(board.cell)
				var frame_col := Color("4b3523")
				var muntin_col := Color("694b31")
				var paper := Color("d5ccb4").lerp(Color("f4c470"), clampf(night_warmth, 0.0, 1.0) * 0.88)
				var pad := s * 0.14
				var inner := Rect2(o + Vector2(pad, pad), Vector2(s - pad * 2.0, s - pad * 2.0))
				board.draw_rect(Rect2(o + Vector2(pad - 1.5, pad - 1.5), inner.size + Vector2(3.0, 3.0)), frame_col)
				board.draw_rect(inner, paper)
				var bw := maxf(1.2, s * 0.055)
				board.draw_line(Vector2(o.x + s * 0.5, inner.position.y), Vector2(o.x + s * 0.5, inner.end.y), muntin_col, bw)
				board.draw_line(Vector2(inner.position.x, o.y + s * 0.38), Vector2(inner.end.x, o.y + s * 0.38), muntin_col, bw)
				board.draw_line(Vector2(inner.position.x, o.y + s * 0.64), Vector2(inner.end.x, o.y + s * 0.64), muntin_col, bw)
				board.draw_rect(inner, frame_col, false, maxf(1.5, s * 0.06))
			else:
				Pack.draw(board, "t_window_bars", p, roll)
		elif tile == "O":
			Pack.draw(board, "t_window_no_curtains_open", p, roll, -1, 0, Color("d8c4a6"))
	elif tile in ["D", "o"]:
		if surface == "G":
			Pack.draw(board, "t_fencegate_c" if tile == "D" else "t_fencegate_o", p, roll,
				_join(cells, p, ["f", "D", "o", "#", "w", "O"], 0))
		else:
			Pack.draw(board, "t_door_c" if tile == "D" else "t_door_o", p, roll, -1, 0, Color("e2cfb6"))
	elif tile == "f":
		var fmask := _join(cells, p, ["f", "D", "o", "#", "w", "O"], 0)
		if fmask == 0:
			fmask = 6
		Pack.draw(board, "t_fence", p, roll, fmask, 0, Color("d6c4a8"))
	if not masking:
		_draw_eaves(board, cells, p)


static func _draw_lantern_post(board: Control, p: Vector2i, lit_strength: float, hanging_only := false) -> void:
	var masking := board.has_method("surface_id")
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	var mask_col: Color = board.call("surface_id", p) if masking else Color.WHITE
	var wood_dark := mask_col if masking else Color("3c2b1e")
	var wood_mid := mask_col if masking else Color("5e432d")
	var cap_col := mask_col if masking else Color("2a2624")
	var glow := clampf(lit_strength, 0.0, 1.0)
	var paper := mask_col if masking else Color("c96a42").lerp(Color("ffce70"), 0.30 + glow * 0.70)
	var core := mask_col if masking else Color("ffe8a6").lerp(Color("fff6d2"), glow)

	if not hanging_only:
		# Base plinth & vertical carved timber post
		board.draw_rect(Rect2(o.x + s * 0.38, o.y + s * 0.78, s * 0.24, s * 0.14), wood_dark)
		board.draw_rect(Rect2(o.x + s * 0.44, o.y + s * 0.16, s * 0.12, s * 0.66), wood_mid)
		# Curved eaves cross-arm
		board.draw_rect(Rect2(o.x + s * 0.36, o.y + s * 0.15, s * 0.38, s * 0.09), wood_dark)
	var lx := o.x + (s * 0.64 if not hanging_only else s * 0.50)
	var ly := o.y + (s * 0.32 if not hanging_only else s * 0.36)
	var lw := maxf(4.0, s * 0.24)
	var lh := maxf(5.0, s * 0.28)
	# Lantern cap & tassel
	board.draw_rect(Rect2(lx - lw * 0.62, ly - lh * 0.58, lw * 1.24, maxf(1.5, s * 0.07)), cap_col)
	board.draw_rect(Rect2(lx - lw * 0.5, ly - lh * 0.46, lw, lh), paper)
	if not masking:
		board.draw_rect(Rect2(lx - lw * 0.26, ly - lh * 0.28, lw * 0.52, lh * 0.56), core)
		board.draw_line(Vector2(lx, ly + lh * 0.54), Vector2(lx, ly + lh * 0.85), Color("b84434"), maxf(1.0, s * 0.05))
		if glow > 0.15:
			board.draw_circle(Vector2(lx, ly), s * 0.34, Color(1.0, 0.72, 0.32, 0.16 * glow))


static func _draw_bridge_rails(board: Control, cells: Dictionary, p: Vector2i, emitters: Dictionary, lit_strength: float) -> void:
	var masking := board.has_method("surface_id")
	var o := _cell_origin(board, p)
	var s := float(board.cell)
	var col: Color = board.call("surface_id", p) if masking else Color("5c422c")
	var hi: Color = board.call("surface_id", p) if masking else Color("7d5c3e")
	var north_water: bool = cells.get(p + Vector2i.UP, [" "])[0] in ["~", "W"]
	var south_water: bool = cells.get(p + Vector2i.DOWN, [" "])[0] in ["~", "W"]
	if north_water:
		board.draw_rect(Rect2(o.x, o.y + s * 0.04, s, maxf(2.0, s * 0.11)), col)
		board.draw_rect(Rect2(o.x, o.y + s * 0.04, s, maxf(1.0, s * 0.04)), hi)
		if posmod(p.x, 3) == 0:
			board.draw_rect(Rect2(o.x + s * 0.42, o.y, maxf(2.0, s * 0.16), maxf(3.0, s * 0.20)), hi)
	if south_water:
		if not masking:
			board.draw_rect(Rect2(o.x, o.y + s, s, maxf(3.0, s * 0.18)), Color(0.03, 0.06, 0.08, 0.34))
		board.draw_rect(Rect2(o.x, o.y + s * 0.85, s, maxf(2.0, s * 0.11)), col)
		board.draw_rect(Rect2(o.x, o.y + s * 0.85, s, maxf(1.0, s * 0.04)), hi)
		if posmod(p.x, 3) == 0:
			board.draw_rect(Rect2(o.x + s * 0.42, o.y + s * 0.78, maxf(2.0, s * 0.16), maxf(3.0, s * 0.20)), hi)
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
		# Scatter lotus pads, blossoms, and reeds along quiet river shallows.
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
	elif CONNECTED.has(tile):
		var mask := _join(cells, p, [tile], 0)
		var id: String = "f_sofa" if tile == "S" and mask == 0 and roll % 3 == 0 else CONNECTED[tile]
		var furn_tint := Color("decbb2") if tile == "k" else Color.WHITE
		Pack.draw(board, id, p, roll, mask, 0, furn_tint)
	elif tile == "r":
		var id := "f_bookcase" if cells[p][1] in ["i", "R"] else "f_rack_wood"
		Pack.draw(board, id, p, roll, -1, 0, Color("e6d4be"))
	elif tile == "c":
		Pack.draw(board, "f_dresser", p, roll, -1, 0, Color("dec7ad"))
	elif tile == "a":
		var empty: bool = world != null and int(world.water_at(p)) <= 0
		Pack.draw(board, "f_fvat_empty" if empty else "f_fvat_full", p, roll, -1, 0, Color("dec9ae"))
	elif tile == "u":
		var empty: bool = world != null and int(world.water_at(p)) <= 0
		Pack.draw(board, "f_fvat_wood_empty" if empty else "f_fvat_wood_full", p, roll, -1, 0, Color("e4d4be"))
	elif FIXTURES.has(tile):
		var tint := Color("e6d2b6") if tile == "K" else Color.WHITE
		Pack.draw(board, FIXTURES[tile], p, roll, _join(cells, p, [tile], 0) if tile == "l" else -1, 0, tint)
		if tile == "h" and not masking:
			var o := _cell_origin(board, p)
			var s := float(board.cell)
			board.draw_circle(o + Vector2(s * 0.50, s * 0.62), maxf(2.0, s * 0.14),
				Color(1.0, 0.52, 0.16, 0.55 + 0.30 * lit_strength))
			board.draw_circle(o + Vector2(s * 0.50, s * 0.62), maxf(1.2, s * 0.07), Color(1.0, 0.86, 0.48, 0.85))
		elif tile == "X" and not masking:
			var o := _cell_origin(board, p)
			var s := float(board.cell)
			board.draw_rect(Rect2(o.x + s * 0.66, o.y + s * 0.66, s * 0.22, s * 0.22), Color("d9c27c"))
	elif tile == "q":
		var id := "f_stool" if cells[p][1] in ["j", "J", "d"] or roll % 3 == 0 else "f_chair"
		var facing := roll % 4
		for i in NEIGHBORS.size():
			var other: Array = cells.get(p + NEIGHBORS[i], [" ", ""])
			if other[0] in ["t", "l", "k"]:
				facing = [0, 3, 1, 2][i]
				break
		Pack.draw(board, id, p, roll, -1, facing, Color("e2cfb8"))
	elif tile == "Y":
		Pack.draw(board, TREES[roll % TREES.size()], p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
	elif tile == "g":
		Pack.draw(board, SHRUBS[roll % SHRUBS.size()], p, roll, -1, 0, Color.WHITE, Vector2.ZERO, false, season)
	if not masking and emitters.get(p) == &"candle":
		var o := _cell_origin(board, p)
		var s := float(board.cell)
		board.draw_circle(o + Vector2(s * 0.52, s * 0.42), maxf(1.8, s * 0.09), Color("b88b4a"))
		board.draw_circle(o + Vector2(s * 0.52, s * 0.38), maxf(1.3, s * 0.065),
			Color(1.0, 0.86, 0.45, 0.72 + 0.28 * lit_strength))
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
		# Hanging lantern post beside the NPC so market and dock feel alive day and night.
		board.draw_circle(o + Vector2(s * 0.82, s * 0.24), maxf(2.0, s * 0.11),
			Color("c96a42").lerp(Color("ffd67a"), 0.35 + 0.65 * lit_strength))
		character(board, p, site)


static func roof_tile(board: Control, cells: Dictionary, roof_tiles: Dictionary, p: Vector2i, seed: int) -> void:
	var o := _cell_origin(board, p)
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
	var jitter := (float(roll % 9) - 4.0) * 0.005

	var base := Color(0.20 + jitter, 0.26 + jitter, 0.30 + jitter) if north_slope else Color(0.27 + jitter, 0.34 + jitter, 0.39 + jitter)
	if multi_story:
		base = base.darkened(0.08)
	var rib_dark := base.darkened(0.28)
	var rib_light := base.lightened(0.14)
	var ridge_col := Color("637279") if multi_story else Color("58676e")
	var ridge_hi := Color("88979d")

	# Base slate roof tile plane
	board.draw_rect(Rect2(o, Vector2(s, s)), base)

	# Horizontal clay tile course steps
	var courses := 3
	for c in range(1, courses):
		var cy := o.y + s * float(c) / float(courses)
		board.draw_line(Vector2(o.x, cy), Vector2(o.x + s, cy), rib_dark, 1.0)

	# Vertical interlocking Jiangnan clay tile ribs (瓦垄)
	var ribs := maxi(4, int(round(s / 7.5)))
	for i in range(ribs):
		var rx := o.x + s * (float(i) + 0.5) / float(ribs)
		board.draw_line(Vector2(rx, o.y), Vector2(rx, o.y + s), rib_dark, 1.0)
		board.draw_line(Vector2(rx + 1.0, o.y), Vector2(rx + 1.0, o.y + s), Color(rib_light.r, rib_light.g, rib_light.b, 0.55), 1.0)

	# Central pitched roof ridge beam (正脊)
	if is_ridge:
		var ry := o.y + s * 0.36 if rel <= 0 else o.y + s * 0.10
		var rh := maxf(3.0, s * 0.24)
		board.draw_rect(Rect2(o.x, ry, s, rh), ridge_col)
		board.draw_rect(Rect2(o.x, ry, s, maxf(1.5, rh * 0.32)), ridge_hi)
		board.draw_rect(Rect2(o.x, ry + rh, s, maxf(2.0, s * 0.08)), Color(0.05, 0.08, 0.10, 0.42))

	# Outer roof edges & Jiangnan pale-plaster gable trims (山墙封边)
	var n_edge := not roof_tiles.has(p + Vector2i.UP)
	var s_edge := not roof_tiles.has(p + Vector2i.DOWN)
	var w_edge := not roof_tiles.has(p + Vector2i.LEFT)
	var e_edge := not roof_tiles.has(p + Vector2i.RIGHT)
	var trim := maxf(2.5, s * 0.12)
	if n_edge:
		board.draw_rect(Rect2(o.x, o.y, s, trim), ridge_col)
		board.draw_rect(Rect2(o.x, o.y, s, maxf(1.0, trim * 0.35)), ridge_hi)
	if s_edge:
		board.draw_rect(Rect2(o.x, o.y + s - trim, s, trim), rib_dark)
		board.draw_rect(Rect2(o.x, o.y + s, s, maxf(2.5, s * 0.12)), Color(0.04, 0.06, 0.08, 0.44))
	if w_edge:
		board.draw_rect(Rect2(o.x, o.y, trim, s), Color("c4bca8"))
		board.draw_rect(Rect2(o.x, o.y, maxf(1.2, trim * 0.38), s), Color("58646a"))
	if e_edge:
		board.draw_rect(Rect2(o.x + s - trim, o.y, trim, s), Color("b4ac98"))
		board.draw_rect(Rect2(o.x + s - maxf(1.2, trim * 0.38), o.y, maxf(1.2, trim * 0.38), s), Color("465156"))
		board.draw_rect(Rect2(o.x + s, o.y, maxf(2.0, s * 0.09), s), Color(0.04, 0.06, 0.08, 0.32))


static func snow_footprint(canvas: Control, origin: Vector2, cell_size: float, dir: Vector2,
		side: float, alpha: float, daylight: float) -> void:
	if alpha <= 0.02:
		return
	var angle := dir.angle() if dir.length_squared() > 0.01 else 0.0
	var perp := Vector2(-sin(angle), cos(angle))
	var center := origin + Vector2.ONE * (cell_size * 0.5) + perp * (side * cell_size * 0.13)
	var length := maxf(3.2, cell_size * 0.21)
	var width := maxf(2.0, cell_size * 0.11)
	var bright := lerpf(0.28, 1.0, daylight)
	var indent := Color(0.32 * bright, 0.43 * bright, 0.56 * bright, 0.52 * alpha)
	var rim := Color(0.92 * bright, 0.96 * bright, 1.0 * bright, 0.36 * alpha)
	canvas.draw_set_transform(center, angle, Vector2.ONE)
	canvas.draw_rect(Rect2(Vector2(-length * 0.5, -width * 0.5) + Vector2(0.8, 0.8), Vector2(length, width)), rim)
	canvas.draw_rect(Rect2(Vector2(-length * 0.5, -width * 0.5), Vector2(length, width)), indent)
	canvas.draw_set_transform(Vector2.ZERO)


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
	var origin := Vector2((p - board.view_origin) * board.cell)
	for id: String in ["player_male", "overlay_worn_pants", "overlay_worn_boots", "overlay_worn_tunic"]:
		Pack.draw_at(dest, id, origin, float(board.cell), 0, -1, 0, tint)
	Pack.draw_at(dest, outfit, origin, float(board.cell), 0, -1, 0, outfit_tint)
