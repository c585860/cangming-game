extends RefCounted

# Jiangnan / Huizhou traditional Chinese 3D architectural renderer:
# - Extruded 3/4-perspective plaster, timber, and grey-brick walls with tile caps & stone plinths
# - True 3D recessed wooden lattice windows (w closed / O open) matching wall thickness on both H & V walls
# - Double-leaf vermilion/chestnut timber doors with brass ring knockers, stone thresholds & lintel plaques
# - Traditional bamboo/timber courtyard fences & upturned dark-tile eaves

const Lighting = preload("res://scripts/lighting.gd")

const WALL_TILES := ["#", "w", "O", "D", "o"]


static func _origin(board: Control, p: Vector2i) -> Vector2:
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	return Vector2((p - board.view_origin) * board.cell) + cam_offset


static func _is_wall(cells: Dictionary, p: Vector2i) -> bool:
	var d: Array = cells.get(p, [])
	return not d.is_empty() and d[0] in WALL_TILES


static func _hash(p: Vector2i, seed: int) -> int:
	var n := ((p.x * 0x9e3779b9) ^ (p.y * 0x85ebca6b) ^ seed) & 0xffffffff
	n = ((n ^ (n >> 16)) * 0x7feb352d) & 0xffffffff
	return n ^ (n >> 15)


static func _wall_palette(surface: String) -> Dictionary:
	# H = Huizhou white lime plaster, N = warm timber hall, B = Jiangnan grey ashlar brick
	match surface:
		"B":
			return {
				"cap": Color("32393f"),
				"cap_hi": Color("4b545c"),
				"face": Color("7d8285"),
				"face_dark": Color("5f6468"),
				"line": Color("4b5054"),
				"plinth": Color("474d52"),
				"beam": Color("3b2c20"),
			}
		"N":
			return {
				"cap": Color("36281e"),
				"cap_hi": Color("523d2d"),
				"face": Color("8b5a3c"),
				"face_dark": Color("6c432b"),
				"line": Color("4b2d1b"),
				"plinth": Color("5b5e5d"),
				"beam": Color("4a2a1a"),
			}
		_:
			return {
				"cap": Color("2e363c"),
				"cap_hi": Color("48535c"),
				"face": Color("ddd5c5"),
				"face_dark": Color("c5bca9"),
				"line": Color("aba18e"),
				"plinth": Color("6c7072"),
				"beam": Color("4e3322"),
			}


static func draw_wall_segment(board: Control, cells: Dictionary, p: Vector2i, seed: int, night_warmth := 0.0) -> void:
	var data: Array = cells[p]
	var tile: String = data[0]
	var surface: String = data[1]
	var masking := board.has_method("surface_id")
	var o := _origin(board, p)
	var s := float(board.cell)

	if masking:
		var mcol: Color = board.call("surface_id", p)
		board.draw_rect(Rect2(o, Vector2(s, s)), mcol)
		return

	if tile == "#":
		_draw_solid_wall(board, cells, p, o, s, surface, _hash(p, seed))
	elif tile == "w" or tile == "O":
		_draw_3d_window(board, cells, p, o, s, surface, tile == "O", night_warmth)
	elif tile == "D" or tile == "o":
		if surface == "G":
			_draw_courtyard_gate(board, cells, p, o, s, tile == "o")
		else:
			_draw_chinese_door(board, cells, p, o, s, surface, tile == "o", night_warmth)
	elif tile == "f":
		_draw_chinese_fence(board, cells, p, o, s)

	_draw_eaves(board, cells, p, o, s)


static func _draw_solid_wall(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		surface: String, roll: int) -> void:
	var pal := _wall_palette(surface)
	var has_n := _is_wall(cells, p + Vector2i.UP)
	var has_s := _is_wall(cells, p + Vector2i.DOWN)
	var has_w := _is_wall(cells, p + Vector2i.LEFT)
	var has_e := _is_wall(cells, p + Vector2i.RIGHT)
	var cap_h := maxf(4.0, s * 0.28)
	var plinth_h := maxf(3.0, s * 0.17)
	var south_open := not has_s

	# 1. Vertical facade body (3/4 extruded front face)
	var face_col: Color = pal["face"]
	var jitter := (float(roll % 7) - 3.0) * 0.012
	face_col = Color(clampf(face_col.r + jitter, 0.0, 1.0), clampf(face_col.g + jitter, 0.0, 1.0), clampf(face_col.b + jitter, 0.0, 1.0))
	board.draw_rect(Rect2(o, Vector2(s, s)), face_col)

	if surface == "B":
		# Running-bond Jiangnan grey brick courses
		var rows := 4
		var rh := (s - cap_h - plinth_h) / float(rows)
		for r in range(rows):
			var ry := o.y + cap_h + float(r) * rh
			board.draw_line(Vector2(o.x, ry), Vector2(o.x + s, ry), pal["line"], 1.0)
			var bx_off := (s * 0.25) if (r % 2 == 1) else 0.0
			for c in range(2):
				var bx := o.x + fposmod(bx_off + float(c) * s * 0.5, s)
				board.draw_line(Vector2(bx, ry), Vector2(bx, ry + rh), pal["line"], 1.0)
	elif surface == "N":
		# Vertical timber wall planks & horizontal waist rail
		var planks := 4
		for i in range(1, planks):
			var px := o.x + s * float(i) / float(planks)
			board.draw_line(Vector2(px, o.y + cap_h), Vector2(px, o.y + s), pal["line"], 1.0)
		board.draw_rect(Rect2(o.x, o.y + s * 0.62, s, maxf(1.5, s * 0.07)), pal["beam"])
	else:
		# Whitewashed Huizhou lime plaster with subtle plaster grain & wooden dado rail
		board.draw_rect(Rect2(o.x, o.y + cap_h, s, maxf(2.0, s * 0.08)), pal["face_dark"])
		if roll % 5 == 0:
			board.draw_rect(Rect2(o.x + s * 0.18, o.y + s * 0.44, s * 0.26, s * 0.12), Color(0.75, 0.71, 0.63, 0.35))

	# 2. Top 3D wall cap (dark charcoal tile coping / timber beam)
	if has_s and not (has_w or has_e):
		# Pure N-S vertical wall: 3D narrow extruded wall thickness with top coping & side shadow
		var side_pad := s * 0.14
		board.draw_rect(Rect2(o.x, o.y, s, s), pal["face_dark"])
		board.draw_rect(Rect2(o.x + side_pad, o.y, s - side_pad * 2.0, s), pal["cap"])
		board.draw_rect(Rect2(o.x + side_pad + 1.0, o.y, maxf(1.5, s * 0.12), s), pal["cap_hi"])
		board.draw_line(Vector2(o.x + side_pad, o.y), Vector2(o.x + side_pad, o.y + s), pal["beam"], 1.2)
		board.draw_line(Vector2(o.x + s - side_pad, o.y), Vector2(o.x + s - side_pad, o.y + s), pal["beam"], 1.2)
		return

	board.draw_rect(Rect2(o.x, o.y, s, cap_h), pal["cap"])
	board.draw_rect(Rect2(o.x, o.y, s, maxf(1.5, cap_h * 0.28)), pal["cap_hi"])
	board.draw_rect(Rect2(o.x, o.y + cap_h, s, maxf(1.5, s * 0.06)), Color(0.06, 0.07, 0.08, 0.32))

	# Vertical dark timber pillar at wall corners / T-junctions
	var is_corner := (has_n or has_s) and (has_w or has_e)
	if is_corner or (not has_w) or (not has_e):
		var col_w := maxf(2.5, s * 0.14)
		if not has_w or (is_corner and has_e):
			board.draw_rect(Rect2(o.x, o.y + cap_h * 0.7, col_w, s - cap_h * 0.7), pal["beam"])
		if not has_e or (is_corner and has_w):
			board.draw_rect(Rect2(o.x + s - col_w, o.y + cap_h * 0.7, col_w, s - cap_h * 0.7), pal["beam"])

	# 3. Grey-stone plinth along bottom of exposed south facade
	if south_open:
		board.draw_rect(Rect2(o.x, o.y + s - plinth_h, s, plinth_h), pal["plinth"])
		board.draw_line(Vector2(o.x, o.y + s - plinth_h), Vector2(o.x + s, o.y + s - plinth_h), Color("94999c"), 1.0)
		board.draw_line(Vector2(o.x + s * 0.5, o.y + s - plinth_h), Vector2(o.x + s * 0.5, o.y + s), Color("3c4146"), 1.0)
		# Soft ground contact shadow below south wall
		board.draw_rect(Rect2(o.x, o.y + s, s, maxf(2.0, s * 0.12)), Color(0.03, 0.04, 0.05, 0.34))


static func _draw_3d_window(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		surface: String, is_open: bool, night_warmth: float) -> void:
	var pal := _wall_palette(surface)
	var has_w := _is_wall(cells, p + Vector2i.LEFT)
	var has_e := _is_wall(cells, p + Vector2i.RIGHT)
	var has_n := _is_wall(cells, p + Vector2i.UP)
	var has_s := _is_wall(cells, p + Vector2i.DOWN)
	var horizontal := (int(has_w) + int(has_e)) >= (int(has_n) + int(has_s))

	var frame_dark := Color("3b2416")
	var frame_mid := Color("623e25")
	var frame_hi := Color("825637")
	var paper := Color("ded4bd").lerp(Color("ffcb6b"), clampf(night_warmth, 0.0, 1.0) * 0.88)
	var paper_shadow := paper.darkened(0.14)

	if horizontal:
		# True 3D facade window matching the horizontal wall's top cap, recessed jamb, and protruding windowsill!
		var cap_h := maxf(4.0, s * 0.25)
		var sill_h := maxf(3.0, s * 0.13)
		var plinth_h := maxf(2.5, s * 0.11)

		# Wall surround + top cap + lower plinth
		board.draw_rect(Rect2(o, Vector2(s, s)), pal["face"])
		board.draw_rect(Rect2(o.x, o.y, s, cap_h), pal["cap"])
		board.draw_rect(Rect2(o.x, o.y, s, maxf(1.5, cap_h * 0.28)), pal["cap_hi"])
		board.draw_rect(Rect2(o.x, o.y + s - plinth_h, s, plinth_h), pal["plinth"])

		# Window recess cavity (depth shadow inside the thick 3D wall!)
		var wx := o.x + s * 0.11
		var wy := o.y + cap_h + s * 0.03
		var ww := s * 0.78
		var wh := s - cap_h - sill_h - plinth_h - s * 0.03
		var outer_r := Rect2(wx, wy, ww, wh)
		board.draw_rect(outer_r.grow(1.5), frame_dark)
		# Deep top lintel shadow inside recess
		board.draw_rect(Rect2(wx, wy, ww, maxf(2.0, wh * 0.16)), Color(0.10, 0.07, 0.05, 0.72))

		var inner := Rect2(wx + 2.0, wy + 2.0, maxf(4.0, ww - 4.0), maxf(4.0, wh - 4.0))
		if is_open:
			# Dark interior opening + angled open Chinese wooden shutters on left & right!
			board.draw_rect(inner, Color("171b1e"))
			var sh_w := maxf(3.0, ww * 0.24)
			var l_shutter := PackedVector2Array([
				Vector2(wx, wy), Vector2(wx + sh_w, wy + s * 0.06),
				Vector2(wx + sh_w, wy + wh + s * 0.05), Vector2(wx, wy + wh)
			])
			var r_shutter := PackedVector2Array([
				Vector2(wx + ww, wy), Vector2(wx + ww - sh_w, wy + s * 0.06),
				Vector2(wx + ww - sh_w, wy + wh + s * 0.05), Vector2(wx + ww, wy + wh)
			])
			board.draw_colored_polygon(l_shutter, frame_mid)
			board.draw_colored_polygon(r_shutter, frame_mid)
			board.draw_polyline(l_shutter, frame_dark, 1.0)
			board.draw_polyline(r_shutter, frame_dark, 1.0)
		else:
			# Warm translucent oiled-paper + traditional Chinese lattice mullions (井字+回纹角)
			board.draw_rect(inner, paper)
			board.draw_rect(Rect2(inner.position.x, inner.position.y, inner.size.x, maxf(1.5, inner.size.y * 0.18)), paper_shadow)
			var bw := maxf(1.0, s * 0.045)
			var cx := inner.position.x + inner.size.x * 0.5
			var x1 := inner.position.x + inner.size.x * 0.25
			var x2 := inner.position.x + inner.size.x * 0.75
			var cy := inner.position.y + inner.size.y * 0.5
			# Center mullion + delicate Chinese sub-bars
			board.draw_line(Vector2(cx, inner.position.y), Vector2(cx, inner.end.y), frame_dark, bw * 1.2)
			board.draw_line(Vector2(x1, inner.position.y), Vector2(x1, inner.end.y), frame_mid, bw * 0.85)
			board.draw_line(Vector2(x2, inner.position.y), Vector2(x2, inner.end.y), frame_mid, bw * 0.85)
			board.draw_line(Vector2(inner.position.x, cy), Vector2(inner.end.x, cy), frame_mid, bw)
			# Decorative corner fretwork squares
			var sq := maxf(2.0, inner.size.y * 0.22)
			board.draw_rect(Rect2(inner.position + Vector2(1.0, 1.0), Vector2(sq, sq)), frame_mid, false, 1.0)
			board.draw_rect(Rect2(Vector2(inner.end.x - sq - 1.0, inner.position.y + 1.0), Vector2(sq, sq)), frame_mid, false, 1.0)

		board.draw_rect(outer_r, frame_mid, false, maxf(1.2, s * 0.05))
		# Protruding 3D carved wooden windowsill ledge + shadow below
		var sill_y := wy + wh
		board.draw_rect(Rect2(wx - s * 0.06, sill_y, ww + s * 0.12, sill_h), frame_hi)
		board.draw_rect(Rect2(wx - s * 0.06, sill_y + sill_h * 0.55, ww + s * 0.12, sill_h * 0.45), frame_dark)
		board.draw_rect(Rect2(wx - s * 0.04, sill_y + sill_h, ww + s * 0.08, maxf(1.5, s * 0.06)), Color(0.04, 0.05, 0.06, 0.42))
	else:
		# True 3D side-wall window embedded seamlessly in the extruded N-S wall thickness!
		var side_pad := s * 0.14
		var inner_w := s - side_pad * 2.0
		board.draw_rect(Rect2(o, Vector2(s, s)), pal["face_dark"])
		# Top & bottom solid wall jamb segments
		var jamb_h := s * 0.15
		board.draw_rect(Rect2(o.x + side_pad, o.y, inner_w, jamb_h), pal["cap"])
		board.draw_rect(Rect2(o.x + side_pad, o.y + s - jamb_h, inner_w, jamb_h), pal["cap"])
		# Deep side window casement spanning middle of the 3D vertical wall
		var wy := o.y + jamb_h
		var wh := s - jamb_h * 2.0
		var frame_r := Rect2(o.x + side_pad - 1.0, wy, inner_w + 2.0, wh)
		board.draw_rect(frame_r, frame_dark)
		var pane_r := Rect2(o.x + side_pad + s * 0.10, wy + 2.0, maxf(4.0, inner_w - s * 0.20), maxf(4.0, wh - 4.0))
		if is_open:
			board.draw_rect(pane_r, Color("171b1e"))
			# Open wooden casement wing sticking slightly outward
			board.draw_rect(Rect2(o.x + side_pad - s * 0.08, wy + 1.0, s * 0.14, wh * 0.42), frame_hi)
			board.draw_rect(Rect2(o.x + side_pad - s * 0.08, wy + wh * 0.58, s * 0.14, wh * 0.41), frame_hi)
		else:
			board.draw_rect(pane_r, paper)
			# Perspective recessed sill highlights on east/west thickness + 3 horizontal muntins
			board.draw_rect(Rect2(o.x + side_pad, wy + 1.0, maxf(2.0, s * 0.08), wh - 2.0), frame_hi)
			board.draw_rect(Rect2(o.x + s - side_pad - maxf(2.0, s * 0.08), wy + 1.0, maxf(2.0, s * 0.08), wh - 2.0), frame_mid)
			for i in range(1, 4):
				var ly := pane_r.position.y + pane_r.size.y * float(i) / 4.0
				board.draw_line(Vector2(pane_r.position.x, ly), Vector2(pane_r.end.x, ly), frame_dark, 1.0)
			board.draw_line(Vector2(pane_r.position.x + pane_r.size.x * 0.5, pane_r.position.y),
				Vector2(pane_r.position.x + pane_r.size.x * 0.5, pane_r.end.y), frame_mid, 1.0)
		board.draw_rect(frame_r, frame_mid, false, 1.1)


static func _draw_chinese_door(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float,
		surface: String, is_open: bool, night_warmth: float) -> void:
	var pal := _wall_palette(surface)
	var has_w := _is_wall(cells, p + Vector2i.LEFT)
	var has_e := _is_wall(cells, p + Vector2i.RIGHT)
	var has_n := _is_wall(cells, p + Vector2i.UP)
	var has_s := _is_wall(cells, p + Vector2i.DOWN)
	var horizontal := (int(has_w) + int(has_e)) >= (int(has_n) + int(has_s))

	var frame := Color("3b2216")
	var leaf_dark := Color("63271e")
	var leaf_mid := Color("7d3326")
	var leaf_hi := Color("964231")
	var brass := Color("d9b45a")
	var stone := Color("8b8e8d")

	if horizontal:
		var cap_h := maxf(4.0, s * 0.24)
		# Overhead carved lintel & wall cap
		board.draw_rect(Rect2(o.x, o.y, s, cap_h), pal["cap"])
		board.draw_rect(Rect2(o.x, o.y, s, maxf(1.5, cap_h * 0.28)), pal["cap_hi"])
		# Doorway side jamb pillars
		var jamb_w := maxf(3.0, s * 0.12)
		board.draw_rect(Rect2(o.x, o.y + cap_h, jamb_w, s - cap_h), frame)
		board.draw_rect(Rect2(o.x + s - jamb_w, o.y + cap_h, jamb_w, s - cap_h), frame)
		# Raised stone threshold (石门槛)
		var th_h := maxf(2.5, s * 0.11)
		board.draw_rect(Rect2(o.x + jamb_w * 0.5, o.y + s - th_h, s - jamb_w, th_h), stone)
		board.draw_line(Vector2(o.x + jamb_w * 0.5, o.y + s - th_h), Vector2(o.x + s - jamb_w * 0.5, o.y + s - th_h), Color("b0b3b0"), 1.0)

		var dw := s - jamb_w * 2.0
		var dh := s - cap_h - th_h
		var dr := Rect2(o.x + jamb_w, o.y + cap_h, dw, dh)
		if is_open:
			# Open double door swung inwards
			board.draw_rect(dr, Color(0.08, 0.06, 0.05, 0.28))
			board.draw_rect(Rect2(dr.position.x, dr.position.y, maxf(3.0, dw * 0.22), dh * 0.85), leaf_mid)
			board.draw_rect(Rect2(dr.end.x - maxf(3.0, dw * 0.22), dr.position.y, maxf(3.0, dw * 0.22), dh * 0.85), leaf_mid)
		else:
			# Closed Chinese double-leaf timber door with carved panels & brass ring knockers (铜铺首)
			board.draw_rect(dr, leaf_mid)
			board.draw_rect(Rect2(dr.position.x, dr.position.y, dw, maxf(2.0, dh * 0.14)), leaf_dark)
			var mid_x := dr.position.x + dw * 0.5
			# Recessed upper & lower carved panels on each leaf
			for side in [0, 1]:
				var lx := dr.position.x + (0.0 if side == 0 else dw * 0.5) + 1.5
				var lw := dw * 0.5 - 3.0
				board.draw_rect(Rect2(lx, dr.position.y + dh * 0.14, lw, dh * 0.34), leaf_hi, false, 1.0)
				board.draw_rect(Rect2(lx, dr.position.y + dh * 0.56, lw, dh * 0.34), leaf_dark, false, 1.0)
			board.draw_line(Vector2(mid_x, dr.position.y), Vector2(mid_x, dr.end.y), frame, 1.4)
			# Brass ring knockers
			var ky := dr.position.y + dh * 0.52
			var kr := maxf(1.5, s * 0.055)
			board.draw_circle(Vector2(mid_x - maxf(2.5, dw * 0.13), ky), kr, brass)
			board.draw_circle(Vector2(mid_x + maxf(2.5, dw * 0.13), ky), kr, brass)
			board.draw_rect(dr, frame, false, 1.1)
	else:
		# Vertical wall doorway
		var side_pad := s * 0.14
		var inner_w := s - side_pad * 2.0
		board.draw_rect(Rect2(o.x + side_pad, o.y, inner_w, maxf(3.0, s * 0.13)), frame)
		board.draw_rect(Rect2(o.x + side_pad, o.y + s - maxf(3.0, s * 0.13), inner_w, maxf(3.0, s * 0.13)), frame)
		var dr := Rect2(o.x + side_pad + 1.0, o.y + s * 0.13, inner_w - 2.0, s * 0.74)
		if is_open:
			board.draw_rect(Rect2(dr.position.x, dr.position.y, dr.size.x * 0.85, maxf(3.0, dr.size.y * 0.22)), leaf_mid)
		else:
			board.draw_rect(dr, leaf_mid)
			board.draw_line(Vector2(dr.position.x, o.y + s * 0.5), Vector2(dr.end.x, o.y + s * 0.5), frame, 1.3)
			board.draw_circle(Vector2(dr.position.x + dr.size.x * 0.5, o.y + s * 0.42), maxf(1.3, s * 0.045), brass)
			board.draw_circle(Vector2(dr.position.x + dr.size.x * 0.5, o.y + s * 0.58), maxf(1.3, s * 0.045), brass)
			board.draw_rect(dr, frame, false, 1.1)

	# Warm paper lanterns flanking exterior main street doorway at dusk/night
	var s_out := not Lighting.enclosed(cells.get(p + Vector2i.DOWN, []))
	if horizontal and s_out and Lighting.enclosed(cells[p]):
		var glow := clampf(night_warmth, 0.0, 1.0)
		var lcol := Color("b84232").lerp(Color("ffcf68"), 0.25 + 0.75 * glow)
		var lr := maxf(2.0, s * 0.085)
		board.draw_circle(Vector2(o.x + s * 0.08, o.y + s * 0.42), lr, lcol)
		board.draw_circle(Vector2(o.x + s * 0.92, o.y + s * 0.42), lr, lcol)


static func _draw_courtyard_gate(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float, is_open: bool) -> void:
	var post := Color("4f3521")
	var slat := Color("7d5736")
	var hi := Color("9c7048")
	# Two courtyard wooden gateposts with small tile caps
	var pw := maxf(3.5, s * 0.16)
	board.draw_rect(Rect2(o.x + s * 0.04, o.y + s * 0.22, pw, s * 0.66), post)
	board.draw_rect(Rect2(o.x + s * 0.96 - pw, o.y + s * 0.22, pw, s * 0.66), post)
	board.draw_rect(Rect2(o.x + s * 0.01, o.y + s * 0.16, pw + s * 0.06, maxf(2.5, s * 0.10)), Color("364047"))
	board.draw_rect(Rect2(o.x + s * 0.93 - pw, o.y + s * 0.16, pw + s * 0.06, maxf(2.5, s * 0.10)), Color("364047"))
	if not is_open:
		var gx := o.x + s * 0.04 + pw
		var gw := s - (s * 0.04 + pw) * 2.0
		board.draw_rect(Rect2(gx, o.y + s * 0.34, gw, s * 0.44), slat)
		board.draw_line(Vector2(gx, o.y + s * 0.44), Vector2(gx + gw, o.y + s * 0.44), post, 1.4)
		board.draw_line(Vector2(gx, o.y + s * 0.68), Vector2(gx + gw, o.y + s * 0.68), post, 1.4)
		for i in range(1, 5):
			var vx := gx + gw * float(i) / 5.0
			board.draw_line(Vector2(vx, o.y + s * 0.34), Vector2(vx, o.y + s * 0.78), hi if i % 2 == 0 else post, 1.0)
	else:
		board.draw_rect(Rect2(o.x + s * 0.04 + pw, o.y + s * 0.18, maxf(3.0, s * 0.12), s * 0.36), slat)
		board.draw_rect(Rect2(o.x + s * 0.96 - pw - maxf(3.0, s * 0.12), o.y + s * 0.18, maxf(3.0, s * 0.12), s * 0.36), slat)


static func _draw_chinese_fence(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float) -> void:
	var conn_tiles := ["f", "D", "o", "#", "w", "O"]
	var n: bool = cells.get(p + Vector2i.UP, [" "])[0] in conn_tiles
	var so: bool = cells.get(p + Vector2i.DOWN, [" "])[0] in conn_tiles
	var w: bool = cells.get(p + Vector2i.LEFT, [" "])[0] in conn_tiles
	var e: bool = cells.get(p + Vector2i.RIGHT, [" "])[0] in conn_tiles
	if not (n or so or w or e):
		w = true
		e = true
	var post := Color("4f3622")
	var rail := Color("7d5938")
	var hi := Color("a27a50")
	var cx := o.x + s * 0.5
	var cy := o.y + s * 0.52
	# Ground shadow
	board.draw_rect(Rect2(o.x + (0.0 if w else s * 0.38), o.y + s * 0.76,
		(s if (w and e) else s * 0.62 if (w or e) else s * 0.24), maxf(2.0, s * 0.10)), Color(0.04, 0.05, 0.04, 0.28))
	if w or e:
		var x0 := o.x if w else cx
		var x1 := o.x + s if e else cx
		board.draw_rect(Rect2(x0, o.y + s * 0.34, x1 - x0, maxf(2.0, s * 0.10)), rail)
		board.draw_rect(Rect2(x0, o.y + s * 0.60, x1 - x0, maxf(2.0, s * 0.10)), rail)
		board.draw_line(Vector2(x0, o.y + s * 0.34), Vector2(x1, o.y + s * 0.34), hi, 1.0)
		var pickets := 4
		for i in range(pickets):
			var px := lerpf(x0 + s * 0.08, x1 - s * 0.08, float(i) / float(maxi(1, pickets - 1)))
			board.draw_rect(Rect2(px - 1.2, o.y + s * 0.26, 2.4, s * 0.52), post)
	if n or so:
		var y0 := o.y if n else cy
		var y1 := o.y + s if so else cy
		board.draw_rect(Rect2(cx - s * 0.08, y0, s * 0.16, y1 - y0), rail)
		board.draw_line(Vector2(cx - s * 0.08, y0), Vector2(cx - s * 0.08, y1), hi, 1.0)
	# Central bamboo/timber post with dark cap
	var pw := maxf(3.0, s * 0.16)
	board.draw_rect(Rect2(cx - pw * 0.5, o.y + s * 0.20, pw, s * 0.60), post)
	board.draw_rect(Rect2(cx - pw * 0.62, o.y + s * 0.17, pw * 1.24, maxf(2.0, s * 0.07)), Color("364047"))


static func _draw_eaves(board: Control, cells: Dictionary, p: Vector2i, o: Vector2, s: float) -> void:
	var data: Array = cells[p]
	if not Lighting.enclosed(data):
		return
	var tile: String = data[0]
	if tile not in WALL_TILES:
		return
	var stories := 3 if (int(data[3]) & 16) != 0 else 2 if (int(data[3]) & 4) != 0 else 1
	var tile_dark := Color(0.14, 0.18, 0.22, 0.92)
	var tile_mid := Color(0.24, 0.30, 0.35, 0.90)
	var tile_ridge := Color(0.38, 0.45, 0.50, 0.86) if stories >= 2 else Color(0.30, 0.37, 0.42, 0.78)
	var shadow := Color(0.04, 0.06, 0.08, 0.38)
	var eave := maxf(3.0, s * (0.21 if stories >= 2 else 0.16))

	var n_out := not Lighting.enclosed(cells.get(p + Vector2i.UP, []))
	var s_out := not Lighting.enclosed(cells.get(p + Vector2i.DOWN, []))
	var w_out := not Lighting.enclosed(cells.get(p + Vector2i.LEFT, []))
	var e_out := not Lighting.enclosed(cells.get(p + Vector2i.RIGHT, []))
	if not (n_out or s_out or w_out or e_out):
		return

	if n_out:
		board.draw_rect(Rect2(o.x, o.y - eave * 0.45, s, eave), tile_dark)
		board.draw_rect(Rect2(o.x, o.y - eave * 0.45, s, maxf(1.5, eave * 0.35)), tile_ridge)
		var ribs := maxi(4, int(round(s / 7.5)))
		for i in range(1, ribs):
			var rx := o.x + s * float(i) / float(ribs)
			board.draw_line(Vector2(rx, o.y - eave * 0.38), Vector2(rx, o.y + eave * 0.48), tile_mid, 1.0)
	if s_out:
		board.draw_rect(Rect2(o.x, o.y - eave * 0.30, s, eave * 0.82), tile_dark)
		board.draw_rect(Rect2(o.x, o.y - eave * 0.30, s, maxf(1.5, eave * 0.28)), tile_ridge)
		board.draw_rect(Rect2(o.x, o.y + eave * 0.52, s, maxf(1.5, s * 0.07)), shadow)
		var ribs := maxi(4, int(round(s / 7.5)))
		for i in range(1, ribs):
			var rx := o.x + s * float(i) / float(ribs)
			board.draw_line(Vector2(rx, o.y - eave * 0.22), Vector2(rx, o.y + eave * 0.46), tile_mid, 1.0)
	if w_out:
		board.draw_rect(Rect2(o.x - eave * 0.35, o.y, eave * 0.72, s), tile_dark)
		board.draw_rect(Rect2(o.x - eave * 0.35, o.y, maxf(1.5, eave * 0.24), s), tile_ridge)
	if e_out:
		board.draw_rect(Rect2(o.x + s - eave * 0.38, o.y, eave * 0.72, s), tile_dark)
		board.draw_rect(Rect2(o.x + s + eave * 0.34, o.y, maxf(1.5, s * 0.07), s), shadow)

	# Upturned Chinese flying-eave corner finials (飞檐翘角)
	if (n_out or s_out) and (w_out or e_out):
		var cx := o.x - eave * 0.52 if w_out else o.x + s + eave * 0.52
		var cy := o.y - eave * 0.55 if n_out else o.y - eave * 0.45
		var horn := PackedVector2Array([
			Vector2(o.x if w_out else o.x + s, o.y),
			Vector2(cx, cy),
			Vector2(o.x + (eave * 0.5 if w_out else s - eave * 0.5), o.y + eave * 0.3),
		])
		board.draw_colored_polygon(horn, tile_dark)
		board.draw_circle(Vector2(cx, cy), maxf(1.6, eave * 0.28), tile_ridge)

	# Cinnabar & gilded doorway plaque (朱漆金边门匾) over exterior doorways
	if tile in ["D", "o"] and (n_out or s_out):
		var py := o.y - eave * 0.18 if n_out else o.y + maxf(1.0, eave * 0.10)
		var ph := maxf(3.0, eave * 0.58)
		board.draw_rect(Rect2(o.x + s * 0.18, py, s * 0.64, ph), Color("7a231c"))
		board.draw_rect(Rect2(o.x + s * 0.18, py, s * 0.64, ph), Color("dfb964"), false, 1.0)
		# Tiny golden calligraphic dots in center of plaque
		board.draw_rect(Rect2(o.x + s * 0.34, py + ph * 0.35, s * 0.08, maxf(1.0, ph * 0.30)), Color("f0d486"))
		board.draw_rect(Rect2(o.x + s * 0.46, py + ph * 0.35, s * 0.08, maxf(1.0, ph * 0.30)), Color("f0d486"))
		board.draw_rect(Rect2(o.x + s * 0.58, py + ph * 0.35, s * 0.08, maxf(1.0, ph * 0.30)), Color("f0d486"))
