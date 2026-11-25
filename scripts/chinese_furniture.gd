extends RefCounted

# Traditional Ming/Qing Jiangnan Chinese furniture & interior facility renderer.
# Replaces modern/western tileset sprites with unified dark-rosewood, huanghuali,
# brocade silk, blue-and-white porcelain, cast-iron hearth, and lacquered fixtures.

const NEIGHBORS := [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]


static func _origin(board: Control, p: Vector2i) -> Vector2:
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	return Vector2((p - board.view_origin) * board.cell) + cam_offset


static func _has_tile(cells: Dictionary, p: Vector2i, t: String) -> bool:
	var d: Array = cells.get(p, [])
	return not d.is_empty() and d[0] == t


static func draw_fixture(board: Control, world: RefCounted, cells: Dictionary, p: Vector2i,
		tile: String, roll: int, lit_strength := 0.0) -> bool:
	var masking := board.has_method("surface_id")
	var o := _origin(board, p)
	var s := float(board.cell)
	var mcol: Color = board.call("surface_id", p) if masking else Color.WHITE

	match tile:
		"b":
			_draw_canopy_bed(board, cells, p, o, s, masking, mcol, roll)
		"t":
			_draw_eight_immortals_table(board, cells, p, o, s, masking, mcol)
		"l":
			_draw_scholar_desk(board, cells, p, o, s, masking, mcol)
		"k":
			_draw_shop_counter(board, cells, p, o, s, masking, mcol)
		"K":
			_draw_apothecary_cabinet(board, o, s, masking, mcol, roll)
		"c":
			_draw_lacquer_chest_cabinet(board, o, s, masking, mcol)
		"F":
			_draw_tall_wardrobe(board, o, s, masking, mcol)
		"r":
			_draw_bookshelf(board, cells, p, o, s, masking, mcol, roll)
		"C":
			_draw_cargo_trunk(board, o, s, masking, mcol, roll)
		"q":
			_draw_chair_or_stool(board, cells, p, o, s, masking, mcol, roll)
		"S":
			_draw_chinese_bench(board, cells, p, o, s, masking, mcol)
		"h":
			_draw_brick_hearth(board, o, s, masking, mcol, lit_strength)
		"u":
			var filled := world == null or int(world.water_at(p)) > 0
			_draw_porcelain_washstand(board, o, s, masking, mcol, filled)
		"a":
			var filled := world == null or int(world.water_at(p)) > 0
			_draw_earthen_vat(board, o, s, masking, mcol, filled)
		"P":
			_draw_bonsai_pot(board, o, s, masking, mcol, roll)
		"^", "v", "X":
			_draw_chinese_stairs(board, o, s, tile, masking, mcol)
		_:
			return false
	return true


static func _shadow(board: Control, r: Rect2, masking: bool) -> void:
	if not masking:
		board.draw_rect(Rect2(r.position + Vector2(1.5, 2.0), r.size), Color(0.03, 0.02, 0.02, 0.34))


static func _draw_canopy_bed(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		masking: bool, mcol: Color, roll: int) -> void:
	# Ming/Qing rosewood four-poster bed (架子床) with brocade quilt & embroidered pillow!
	var conn_n := _has_tile(cells, p + Vector2i.UP, "b")
	var conn_s := _has_tile(cells, p + Vector2i.DOWN, "b")
	var conn_w := _has_tile(cells, p + Vector2i.LEFT, "b")
	var conn_e := _has_tile(cells, p + Vector2i.RIGHT, "b")
	var pad_x := 0.0 if conn_w else s * 0.07
	var pad_r := 0.0 if conn_e else s * 0.07
	var pad_t := 0.0 if conn_n else s * 0.06
	var pad_b := 0.0 if conn_s else s * 0.08
	var r := Rect2(o.x + pad_x, o.y + pad_t, s - pad_x - pad_r, s - pad_t - pad_b)
	if masking:
		board.draw_rect(r, mcol)
		return

	_shadow(board, r, false)
	var wood_dark := Color("432217")
	var wood_mid := Color("693725")
	var wood_hi := Color("884c35")
	var sheet := Color("e6decb")
	var quilt_main := Color("8f342d") if (roll % 2 == 0) else Color("34665c")
	var quilt_trim := Color("d6b262")
	var quilt_hi := quilt_main.lightened(0.16)

	# Rosewood outer frame
	board.draw_rect(r, wood_mid)
	board.draw_rect(r, wood_dark, false, maxf(1.5, s * 0.06))
	var mat := Rect2(r.position + Vector2(s * 0.08 if not conn_w else 0.0, s * 0.09 if not conn_n else 0.0),
		r.size - Vector2((s * 0.08 if not conn_w else 0.0) + (s * 0.08 if not conn_e else 0.0),
			(s * 0.09 if not conn_n else 0.0) + (s * 0.09 if not conn_s else 0.0)))
	board.draw_rect(mat, sheet)

	# Headboard & embroidered pillow on the head tile (top/west end)
	var is_head := (not conn_n and conn_s) or (not conn_w and conn_e) or (not conn_n and not conn_s and not conn_w and not conn_e)
	if is_head:
		if not conn_n:
			# Carved headboard rail
			board.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, maxf(3.0, s * 0.14)), wood_dark)
			board.draw_rect(Rect2(r.position.x + s * 0.12, r.position.y + 1.0, r.size.x - s * 0.24, maxf(1.5, s * 0.05)), wood_hi)
		# Embroidered silk pillow (刺绣方枕)
		var pw := mat.size.x * 0.68
		var ph := maxf(4.0, s * 0.24)
		var px := mat.position.x + (mat.size.x - pw) * 0.5
		var py := mat.position.y + s * 0.06
		board.draw_rect(Rect2(px, py, pw, ph), Color("f2ead8"))
		board.draw_rect(Rect2(px, py, pw, ph), quilt_trim, false, 1.0)
		board.draw_rect(Rect2(px + pw * 0.28, py + ph * 0.28, pw * 0.44, ph * 0.44), quilt_main)
		# Folded silk quilt starting below pillow
		var qy := py + ph + s * 0.06
		if qy < mat.end.y - 2.0:
			var qh := mat.end.y - qy
			board.draw_rect(Rect2(mat.position.x, qy, mat.size.x, qh), quilt_main)
			board.draw_rect(Rect2(mat.position.x, qy, mat.size.x, maxf(2.0, s * 0.08)), quilt_hi)
			board.draw_line(Vector2(mat.position.x, qy + maxf(2.0, s * 0.08)), Vector2(mat.end.x, qy + maxf(2.0, s * 0.08)), quilt_trim, 1.0)
	else:
		# Foot section: brocade quilt with diamond silk stitching & footboard rail
		board.draw_rect(mat, quilt_main)
		var cx := mat.position.x + mat.size.x * 0.5
		var cy := mat.position.y + mat.size.y * 0.46
		var dr := minf(mat.size.x, mat.size.y) * 0.28
		board.draw_polyline(PackedVector2Array([
			Vector2(cx, cy - dr), Vector2(cx + dr, cy), Vector2(cx, cy + dr), Vector2(cx - dr, cy), Vector2(cx, cy - dr)
		]), Color(quilt_trim.r, quilt_trim.g, quilt_trim.b, 0.55), 1.0)
		if not conn_s:
			board.draw_rect(Rect2(r.position.x, r.end.y - maxf(3.0, s * 0.12), r.size.x, maxf(3.0, s * 0.12)), wood_dark)

	# Four carved canopy corner posts (雕花床柱)
	var post_r := maxf(2.0, s * 0.085)
	if not conn_n and not conn_w:
		board.draw_rect(Rect2(r.position, Vector2(post_r, post_r)), wood_dark)
		board.draw_rect(Rect2(r.position + Vector2(0.8, 0.8), Vector2(post_r * 0.5, post_r * 0.5)), quilt_trim)
	if not conn_n and not conn_e:
		board.draw_rect(Rect2(Vector2(r.end.x - post_r, r.position.y), Vector2(post_r, post_r)), wood_dark)
		board.draw_rect(Rect2(Vector2(r.end.x - post_r + 0.8, r.position.y + 0.8), Vector2(post_r * 0.5, post_r * 0.5)), quilt_trim)
	if not conn_s and not conn_w:
		board.draw_rect(Rect2(Vector2(r.position.x, r.end.y - post_r), Vector2(post_r, post_r)), wood_dark)
	if not conn_s and not conn_e:
		board.draw_rect(Rect2(Vector2(r.end.x - post_r, r.end.y - post_r), Vector2(post_r, post_r)), wood_dark)


static func _draw_eight_immortals_table(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		masking: bool, mcol: Color) -> void:
	# Chinese Eight-Immortals square/joined dining table (八仙桌)
	var cw := _has_tile(cells, p + Vector2i.LEFT, "t")
	var ce := _has_tile(cells, p + Vector2i.RIGHT, "t")
	var cn := _has_tile(cells, p + Vector2i.UP, "t")
	var cs := _has_tile(cells, p + Vector2i.DOWN, "t")
	var r := Rect2(o.x + (0.0 if cw else s * 0.10), o.y + (0.0 if cn else s * 0.10),
		s - (0.0 if cw else s * 0.10) - (0.0 if ce else s * 0.10),
		s - (0.0 if cn else s * 0.10) - (0.0 if cs else s * 0.16))
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var wood_dark := Color("4a2818")
	var wood_top := Color("8d5432")
	var wood_inlay := Color("a36841")
	# Front apron + horse-hoof legs (束腰马蹄腿)
	if not cs:
		board.draw_rect(Rect2(r.position.x + s * 0.04, r.end.y - 1.0, r.size.x - s * 0.08, maxf(3.0, s * 0.13)), wood_dark)
		if not cw:
			board.draw_rect(Rect2(r.position.x + s * 0.04, r.end.y, maxf(2.5, s * 0.10), maxf(4.0, s * 0.16)), wood_dark)
		if not ce:
			board.draw_rect(Rect2(r.end.x - s * 0.14, r.end.y, maxf(2.5, s * 0.10), maxf(4.0, s * 0.16)), wood_dark)
	board.draw_rect(r, wood_top)
	board.draw_rect(r.grow(-maxf(2.0, s * 0.08)), wood_inlay)
	board.draw_rect(r, wood_dark, false, maxf(1.4, s * 0.05))
	# Delicate celadon tea cup accent on isolated dining tables
	if not (cw or ce or cn or cs):
		board.draw_circle(r.position + r.size * Vector2(0.32, 0.36), maxf(1.8, s * 0.07), Color("c4d8cd"))
		board.draw_circle(r.position + r.size * Vector2(0.32, 0.36), maxf(1.0, s * 0.035), Color("708d6c"))


static func _draw_scholar_desk(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		masking: bool, mcol: Color) -> void:
	# Carved Chinese scholar's writing desk (雕花书案) with xuan paper, inkstone & brush rest
	var cw := _has_tile(cells, p + Vector2i.LEFT, "l")
	var ce := _has_tile(cells, p + Vector2i.RIGHT, "l")
	var r := Rect2(o.x + (0.0 if cw else s * 0.08), o.y + s * 0.14,
		s - (0.0 if cw else s * 0.08) - (0.0 if ce else s * 0.08), s * 0.68)
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var dark := Color("3e2115")
	var top := Color("764227")
	var hi := Color("945838")
	board.draw_rect(Rect2(r.position.x + s * 0.05, r.end.y - 1.0, r.size.x - s * 0.10, maxf(3.0, s * 0.14)), dark)
	board.draw_rect(r, top)
	board.draw_rect(Rect2(r.position + Vector2(2.0, 2.0), r.size - Vector2(4.0, 4.0)), hi, false, 1.0)
	board.draw_rect(r, dark, false, 1.3)
	# Sheet of xuan rice paper (宣纸), inkstone (砚台), and red seal
	board.draw_rect(Rect2(r.position.x + r.size.x * 0.22, r.position.y + r.size.y * 0.22, r.size.x * 0.36, r.size.y * 0.56), Color("ebe3cf"))
	board.draw_line(Vector2(r.position.x + r.size.x * 0.30, r.position.y + r.size.y * 0.34),
		Vector2(r.position.x + r.size.x * 0.30, r.position.y + r.size.y * 0.68), Color("36383a"), 1.0)
	board.draw_line(Vector2(r.position.x + r.size.x * 0.42, r.position.y + r.size.y * 0.32),
		Vector2(r.position.x + r.size.x * 0.42, r.position.y + r.size.y * 0.62), Color("36383a"), 1.0)
	board.draw_rect(Rect2(r.position.x + r.size.x * 0.66, r.position.y + r.size.y * 0.28, maxf(3.0, s * 0.13), maxf(3.5, s * 0.16)), Color("262a2e"))
	board.draw_rect(Rect2(r.position.x + r.size.x * 0.70, r.position.y + r.size.y * 0.58, maxf(2.0, s * 0.08), maxf(2.0, s * 0.08)), Color("b8372a"))


static func _draw_shop_counter(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		masking: bool, mcol: Color) -> void:
	# Chinese shop/inn counter (长柜台) with dark-elm top & fretwork front skirt
	var cw := _has_tile(cells, p + Vector2i.LEFT, "k")
	var ce := _has_tile(cells, p + Vector2i.RIGHT, "k")
	var cn := _has_tile(cells, p + Vector2i.UP, "k")
	var cs := _has_tile(cells, p + Vector2i.DOWN, "k")
	var r := Rect2(o.x + (0.0 if cw else s * 0.06), o.y + (0.0 if cn else s * 0.08),
		s - (0.0 if cw else s * 0.06) - (0.0 if ce else s * 0.06),
		s - (0.0 if cn else s * 0.08) - (0.0 if cs else s * 0.08))
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var dark := Color("422618")
	var top := Color("845332")
	var front := Color("633a22")
	var brass := Color("d4af59")
	board.draw_rect(r, top)
	if not cs:
		var fh := maxf(4.0, r.size.y * 0.34)
		board.draw_rect(Rect2(r.position.x, r.end.y - fh, r.size.x, fh), front)
		board.draw_rect(Rect2(r.position.x + 2.0, r.end.y - fh + 1.5, r.size.x - 4.0, fh - 3.0), Color("96653f"), false, 1.0)
	board.draw_rect(r, dark, false, 1.3)
	if not cw and not cs:
		board.draw_rect(Rect2(r.position.x, r.end.y - 3.0, 3.0, 3.0), brass)
	if not ce and not cs:
		board.draw_rect(Rect2(r.end.x - 3.0, r.end.y - 3.0, 3.0, 3.0), brass)


static func _draw_apothecary_cabinet(board: Control, o: Vector2, s: float, masking: bool, mcol: Color, roll: int) -> void:
	# Chinese medicine/curio display cabinet (百子药柜 / 博古展柜)
	var r := Rect2(o.x + s * 0.08, o.y + s * 0.06, s * 0.84, s * 0.86)
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var dark := Color("442316")
	var body := Color("764026")
	var top := Color("945836")
	var brass := Color("dfb960")
	board.draw_rect(r, body)
	board.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.24), top)
	# 3x3 neat grid of apothecary herb drawers with tiny golden brass pulls
	var gx0 := r.position.x + 2.5
	var gy0 := r.position.y + r.size.y * 0.28
	var gw := (r.size.x - 5.0) / 3.0
	var gh := (r.size.y * 0.68) / 3.0
	for ry in range(3):
		for rx in range(3):
			var dr := Rect2(gx0 + float(rx) * gw + 0.8, gy0 + float(ry) * gh + 0.8, gw - 1.6, gh - 1.6)
			board.draw_rect(dr, Color("63331e"))
			board.draw_rect(dr, dark, false, 0.9)
			board.draw_circle(dr.position + dr.size * 0.5, maxf(0.9, s * 0.03), brass)
	# Tiny celadon porcelain jar on top shelf
	if roll % 2 == 0:
		board.draw_circle(Vector2(r.position.x + r.size.x * 0.30, r.position.y + r.size.y * 0.13), maxf(2.0, s * 0.075), Color("8cb5a6"))
	board.draw_rect(r, dark, false, 1.4)


static func _draw_lacquer_chest_cabinet(board: Control, o: Vector2, s: float, masking: bool, mcol: Color) -> void:
	# Chinese double-door chest cabinet (中式木柜) with circular brass lockplate (铜面叶)
	var r := Rect2(o.x + s * 0.10, o.y + s * 0.10, s * 0.80, s * 0.80)
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var dark := Color("3f2014")
	var body := Color("733922")
	var top := Color("945435")
	var brass := Color("dfb95e")
	board.draw_rect(r, body)
	board.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.26), top)
	var mid_x := r.position.x + r.size.x * 0.5
	board.draw_line(Vector2(mid_x, r.position.y + r.size.y * 0.26), Vector2(mid_x, r.end.y), dark, 1.2)
	# Round brass medallion across door seam
	board.draw_circle(Vector2(mid_x, r.position.y + r.size.y * 0.58), maxf(2.2, s * 0.09), brass)
	board.draw_circle(Vector2(mid_x, r.position.y + r.size.y * 0.58), maxf(1.0, s * 0.035), dark)
	board.draw_rect(r, dark, false, 1.3)


static func _draw_tall_wardrobe(board: Control, o: Vector2, s: float, masking: bool, mcol: Color) -> void:
	# Ming-style tall double-tier crimson/chestnut wardrobe (顶箱立柜)
	var r := Rect2(o.x + s * 0.08, o.y + s * 0.04, s * 0.84, s * 0.90)
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var dark := Color("3b1b14")
	var lacquer := Color("782f24")
	var hi := Color("984334")
	var brass := Color("e2be64")
	board.draw_rect(r, lacquer)
	# Top cap + upper chest seam
	board.draw_rect(Rect2(r.position.x - 1.0, r.position.y, r.size.x + 2.0, maxf(3.0, s * 0.11)), dark)
	var split_y := r.position.y + r.size.y * 0.30
	board.draw_line(Vector2(r.position.x, split_y), Vector2(r.end.x, split_y), dark, 1.4)
	var mid_x := r.position.x + r.size.x * 0.5
	board.draw_line(Vector2(mid_x, r.position.y + s * 0.11), Vector2(mid_x, r.end.y), dark, 1.3)
	# Panel inlays
	board.draw_rect(Rect2(r.position.x + 2.5, split_y + 2.5, r.size.x * 0.5 - 4.0, r.end.y - split_y - 5.5), hi, false, 1.0)
	board.draw_rect(Rect2(mid_x + 1.5, split_y + 2.5, r.size.x * 0.5 - 4.0, r.end.y - split_y - 5.5), hi, false, 1.0)
	# Circular brass lock medallions on upper and lower tiers
	board.draw_circle(Vector2(mid_x, r.position.y + r.size.y * 0.20), maxf(1.5, s * 0.055), brass)
	board.draw_circle(Vector2(mid_x, r.position.y + r.size.y * 0.58), maxf(2.4, s * 0.095), brass)
	board.draw_rect(r, dark, false, 1.4)


static func _draw_bookshelf(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		masking: bool, mcol: Color, roll: int) -> void:
	# Chinese dark-wood bookshelf / bogu curio rack (书架 / 博古架)
	var r := Rect2(o.x + s * 0.08, o.y + s * 0.06, s * 0.84, s * 0.86)
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var dark := Color("3c2215")
	var shelf := Color("6e4026")
	var back := Color("2e1b12")
	board.draw_rect(r, back)
	var tiers := 3
	var th := r.size.y / float(tiers)
	var book_cols := [Color("375175"), Color("8d382c"), Color("d9cbb0"), Color("426856"), Color("9c783c")]
	for t in range(tiers):
		var ty := r.position.y + float(t) * th
		board.draw_rect(Rect2(r.position.x, ty + th - 2.2, r.size.x, 2.2), shelf)
		# Thread-bound ancient books & scrolls
		var slots := 5
		var sw := (r.size.x - 4.0) / float(slots)
		for i in range(slots):
			if ((roll + t * 7 + i * 3) % 6) == 0:
				continue
			var col: Color = book_cols[(roll + t * 5 + i) % book_cols.size()]
			var bh := th * (0.56 + float((roll + i) % 3) * 0.08)
			board.draw_rect(Rect2(r.position.x + 2.0 + float(i) * sw + 0.5, ty + th - 2.2 - bh, maxf(1.8, sw - 1.2), bh), col)
	board.draw_rect(r, dark, false, 1.5)


static func _draw_cargo_trunk(board: Control, o: Vector2, s: float, masking: bool, mcol: Color, roll: int) -> void:
	# Iron-bound camphor cargo chest (箍铁樟木货箱) with red paper seal strip
	var r := Rect2(o.x + s * 0.12, o.y + s * 0.14, s * 0.76, s * 0.72)
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var wood := Color("8b623b")
	var wood_dark := Color("593b20")
	var iron := Color("34393d")
	board.draw_rect(r, wood)
	board.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.34), wood.lightened(0.12))
	board.draw_line(Vector2(r.position.x, r.position.y + r.size.y * 0.34), Vector2(r.end.x, r.position.y + r.size.y * 0.34), wood_dark, 1.3)
	# Iron corner straps
	board.draw_rect(Rect2(r.position.x + r.size.x * 0.16, r.position.y, maxf(2.0, s * 0.07), r.size.y), iron)
	board.draw_rect(Rect2(r.end.x - r.size.x * 0.16 - maxf(2.0, s * 0.07), r.position.y, maxf(2.0, s * 0.07), r.size.y), iron)
	# Red merchant seal strip (封条)
	if roll % 2 == 0:
		board.draw_rect(Rect2(r.position.x + r.size.x * 0.44, r.position.y + r.size.y * 0.18, maxf(2.2, s * 0.10), r.size.y * 0.48), Color("b8352a"))
	board.draw_rect(r, wood_dark, false, 1.3)


static func _draw_chair_or_stool(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		masking: bool, mcol: Color, roll: int) -> void:
	# Chinese horseshoe armchair (圈椅) or carved drum stool (绣墩)
	var is_stool: bool = cells[p][1] in ["j", "J", "d"] or roll % 3 == 0
	var center := o + Vector2(s * 0.5, s * 0.54)
	if masking:
		board.draw_circle(center, s * 0.30, mcol)
		return
	var dark := Color("432215")
	var wood := Color("7d4629")
	var cushion := Color("94352c") if (roll % 2 == 0) else Color("4a6b5d")
	var trim := Color("d9b560")

	if is_stool:
		# Round drum stool (红木绣墩 / 青瓷鼓凳)
		board.draw_circle(center + Vector2(1.5, 2.0), s * 0.26, Color(0.03, 0.02, 0.02, 0.32))
		board.draw_circle(center, s * 0.25, wood)
		board.draw_circle(center, s * 0.18, cushion)
		board.draw_arc(center, s * 0.25, 0.0, TAU, 18, dark, 1.3, true)
		board.draw_arc(center, s * 0.18, 0.0, TAU, 16, trim, 0.9, true)
	else:
		# Rosewood horseshoe armchair (中式圈椅) facing nearby table/desk
		var seat := Rect2(o.x + s * 0.22, o.y + s * 0.28, s * 0.56, s * 0.48)
		_shadow(board, seat, false)
		board.draw_rect(seat, wood)
		board.draw_rect(seat.grow(-maxf(2.0, s * 0.08)), cushion)
		board.draw_rect(seat, dark, false, 1.3)
		# Curved headrest/backrest oriented opposite the nearest table/desk
		var back_side := 0 # 0=north, 1=south, 2=west, 3=east
		if cells.get(p + Vector2i.DOWN, [" "])[0] in ["t", "l", "k"]:
			back_side = 0
		elif cells.get(p + Vector2i.UP, [" "])[0] in ["t", "l", "k"]:
			back_side = 1
		elif cells.get(p + Vector2i.RIGHT, [" "])[0] in ["t", "l", "k"]:
			back_side = 2
		elif cells.get(p + Vector2i.LEFT, [" "])[0] in ["t", "l", "k"]:
			back_side = 3
		var bt := maxf(3.0, s * 0.12)
		match back_side:
			0:
				board.draw_rect(Rect2(seat.position.x - 1.0, seat.position.y - bt * 0.7, seat.size.x + 2.0, bt), dark)
				board.draw_rect(Rect2(seat.position.x, seat.position.y - bt * 0.7, seat.size.x, bt * 0.42), wood)
			1:
				board.draw_rect(Rect2(seat.position.x - 1.0, seat.end.y - bt * 0.3, seat.size.x + 2.0, bt), dark)
			2:
				board.draw_rect(Rect2(seat.position.x - bt * 0.6, seat.position.y - 1.0, bt, seat.size.y + 2.0), dark)
			3:
				board.draw_rect(Rect2(seat.end.x - bt * 0.4, seat.position.y - 1.0, bt, seat.size.y + 2.0), dark)


static func _draw_chinese_bench(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		masking: bool, mcol: Color) -> void:
	# Chinese long rosewood bench / spring bench (春凳) with silk seat pad
	var cw := _has_tile(cells, p + Vector2i.LEFT, "S")
	var ce := _has_tile(cells, p + Vector2i.RIGHT, "S")
	var cn := _has_tile(cells, p + Vector2i.UP, "S")
	var cs := _has_tile(cells, p + Vector2i.DOWN, "S")
	var horiz := (cw or ce) or not (cn or cs)
	var r: Rect2
	if horiz:
		r = Rect2(o.x + (0.0 if cw else s * 0.08), o.y + s * 0.26,
			s - (0.0 if cw else s * 0.08) - (0.0 if ce else s * 0.08), s * 0.48)
	else:
		r = Rect2(o.x + s * 0.24, o.y + (0.0 if cn else s * 0.08),
			s * 0.52, s - (0.0 if cn else s * 0.08) - (0.0 if cs else s * 0.08))
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var dark := Color("432215")
	var wood := Color("7d4528")
	var pad := Color("8d392e")
	var trim := Color("d6b25e")
	board.draw_rect(r, wood)
	var inset := Rect2(r.position + Vector2(2.0, 2.5), r.size - Vector2(4.0, 5.0))
	board.draw_rect(inset, pad)
	board.draw_rect(inset, trim, false, 0.9)
	board.draw_rect(r, dark, false, 1.3)
	if horiz:
		board.draw_rect(Rect2(r.position.x + 2.0, r.end.y, r.size.x - 4.0, maxf(2.5, s * 0.10)), dark)


static func _draw_brick_hearth(board: Control, o: Vector2, s: float, masking: bool, mcol: Color, lit_strength: float) -> void:
	# Jiangnan grey-brick firewood hearth (青砖土灶) with cast-iron wok & glowing embers
	var r := Rect2(o.x + s * 0.06, o.y + s * 0.06, s * 0.88, s * 0.86)
	if masking:
		board.draw_rect(r, mcol)
		return
	_shadow(board, r, false)
	var brick := Color("7a7e80")
	var brick_dark := Color("505457")
	var rim := Color("9fa3a2")
	board.draw_rect(r, brick)
	board.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.16), rim)
	board.draw_rect(r, brick_dark, false, 1.5)
	# Cast-iron wok (铸铁大锅) recessed into brick top
	var wc := Vector2(o.x + s * 0.50, o.y + s * 0.44)
	board.draw_circle(wc, s * 0.25, Color("202326"))
	board.draw_circle(wc, s * 0.20, Color("313538"))
	board.draw_arc(wc, s * 0.25, 0.0, TAU, 20, Color("5a5f63"), 1.2, true)
	# Wooden wok handle knob
	board.draw_circle(wc, maxf(1.8, s * 0.06), Color("825232"))
	# Glowing firebox opening along lower front of hearth
	var fx := o.x + s * 0.34
	var fy := o.y + s * 0.72
	board.draw_rect(Rect2(fx, fy, s * 0.32, s * 0.18), Color("24140e"))
	board.draw_circle(Vector2(o.x + s * 0.50, fy + s * 0.10), maxf(2.4, s * 0.11),
		Color(1.0, 0.48, 0.14, 0.65 + 0.30 * lit_strength))
	board.draw_circle(Vector2(o.x + s * 0.50, fy + s * 0.10), maxf(1.3, s * 0.055), Color(1.0, 0.88, 0.48, 0.92))


static func _draw_porcelain_washstand(board: Control, o: Vector2, s: float, masking: bool, mcol: Color, filled: bool) -> void:
	# Chinese wooden washstand with blue-and-white porcelain basin (青花瓷水盆架)
	var c := o + Vector2(s * 0.50, s * 0.54)
	if masking:
		board.draw_circle(c, s * 0.34, mcol)
		return
	board.draw_circle(c + Vector2(1.5, 2.0), s * 0.32, Color(0.03, 0.02, 0.02, 0.32))
	# Rosewood tripod frame & rear towel rack bar
	board.draw_rect(Rect2(o.x + s * 0.18, o.y + s * 0.10, s * 0.64, maxf(2.5, s * 0.09)), Color("5c331e"))
	board.draw_rect(Rect2(o.x + s * 0.24, o.y + s * 0.14, maxf(2.0, s * 0.07), s * 0.42), Color("5c331e"))
	board.draw_rect(Rect2(o.x + s * 0.70, o.y + s * 0.14, maxf(2.0, s * 0.07), s * 0.42), Color("5c331e"))
	# Porcelain basin rim
	board.draw_circle(c, s * 0.30, Color("e6ecee"))
	board.draw_arc(c, s * 0.30, 0.0, TAU, 20, Color("3c6294"), 1.6, true)
	if filled:
		board.draw_circle(c, s * 0.23, Color("5a94a2"))
		board.draw_arc(c + Vector2(-s * 0.05, -s * 0.05), s * 0.10, PI * 0.9, PI * 1.6, 8, Color(0.86, 0.96, 1.0, 0.65), 1.0)
	else:
		board.draw_circle(c, s * 0.23, Color("cfd9dc"))
		board.draw_circle(c, s * 0.08, Color("486fa0"))


static func _draw_earthen_vat(board: Control, o: Vector2, s: float, masking: bool, mcol: Color, filled: bool) -> void:
	# Glazed dark-brown earthenware water vat (釉面大水缸)
	var c := o + Vector2(s * 0.50, s * 0.52)
	if masking:
		board.draw_circle(c, s * 0.38, mcol)
		return
	board.draw_circle(c + Vector2(2.0, 2.5), s * 0.37, Color(0.03, 0.02, 0.02, 0.36))
	board.draw_circle(c, s * 0.36, Color("5a3622"))
	board.draw_arc(c, s * 0.35, 0.0, TAU, 22, Color("8a5838"), 2.0, true)
	board.draw_arc(c, s * 0.37, 0.0, TAU, 22, Color("361e12"), 1.2, true)
	if filled:
		board.draw_circle(c, s * 0.26, Color("366a78"))
		board.draw_circle(c + Vector2(-s * 0.07, -s * 0.07), s * 0.07, Color(0.74, 0.90, 0.96, 0.45))
	else:
		board.draw_circle(c, s * 0.26, Color("362218"))


static func _draw_bonsai_pot(board: Control, o: Vector2, s: float, masking: bool, mcol: Color, roll: int) -> void:
	# Blue-and-white porcelain bonsai / orchid pot (青花瓷盆景)
	var c := o + Vector2(s * 0.50, s * 0.62)
	if masking:
		board.draw_circle(o + Vector2(s * 0.5, s * 0.48), s * 0.34, mcol)
		return
	board.draw_circle(c + Vector2(1.5, 2.0), s * 0.24, Color(0.03, 0.03, 0.03, 0.30))
	board.draw_circle(c, s * 0.23, Color("e3eaee"))
	board.draw_arc(c, s * 0.23, 0.0, TAU, 16, Color("3b6194"), 1.6, true)
	board.draw_circle(c, s * 0.16, Color("4b3828"))
	# Miniature twisted trunk & jade foliage puffs
	board.draw_line(c, c + Vector2(-s * 0.06, -s * 0.22), Color("5c3d26"), maxf(1.8, s * 0.07))
	var leaf1 := Color("3b6e42") if (roll % 2 == 0) else Color("497d4d")
	var leaf2 := Color("599457")
	board.draw_circle(c + Vector2(-s * 0.12, -s * 0.26), s * 0.15, leaf1)
	board.draw_circle(c + Vector2(s * 0.10, -s * 0.22), s * 0.13, leaf1)
	board.draw_circle(c + Vector2(0.0, -s * 0.32), s * 0.14, leaf2)


static func _draw_chinese_stairs(board: Control, o: Vector2, s: float, tile: String, masking: bool, mcol: Color) -> void:
	# Traditional lacquered timber staircase (红木扶手楼梯)
	var r := Rect2(o.x + s * 0.06, o.y + s * 0.04, s * 0.88, s * 0.92)
	if masking:
		board.draw_rect(r, mcol)
		return
	var rail := Color("6e291f")
	var tread := Color("8d5d38")
	var dark := Color("432615")
	board.draw_rect(r, dark)
	var steps := 5
	var sh := (r.size.y - 4.0) / float(steps)
	for i in range(steps):
		var sy := r.position.y + 2.0 + float(i) * sh
		var shade := 0.82 + 0.06 * float(i) if tile != "v" else 1.08 - 0.07 * float(i)
		board.draw_rect(Rect2(r.position.x + 3.0, sy, r.size.x - 6.0, sh - 1.2),
			Color(tread.r * shade, tread.g * shade, tread.b * shade))
	# Vermilion side handrails
	var rw := maxf(2.5, s * 0.10)
	board.draw_rect(Rect2(r.position.x, r.position.y, rw, r.size.y), rail)
	board.draw_rect(Rect2(r.end.x - rw, r.position.y, rw, r.size.y), rail)
	board.draw_rect(r, dark, false, 1.1)
	# Subtle gilded direction chevron
	var cx := o.x + s * 0.5
	var cy := o.y + s * 0.5
	var gold := Color("ebd082")
	if tile == "^" or tile == "X":
		board.draw_polyline(PackedVector2Array([Vector2(cx - s * 0.14, cy + s * 0.04), Vector2(cx, cy - s * 0.12), Vector2(cx + s * 0.14, cy + s * 0.04)]), gold, 1.6)
	if tile == "v" or tile == "X":
		var oy := s * 0.16 if tile == "X" else 0.0
		board.draw_polyline(PackedVector2Array([Vector2(cx - s * 0.14, cy - s * 0.04 + oy), Vector2(cx, cy + s * 0.12 + oy), Vector2(cx + s * 0.14, cy - s * 0.04 + oy)]), gold, 1.6)
