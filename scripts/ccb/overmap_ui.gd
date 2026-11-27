extends RefCounted

# [m] Authentic Interactive Fog-of-War Overmap (Cataclysm-Cleanwater-Bomb/src/overmap_ui.cpp)

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")


class InteractiveOvermapCanvas extends Control:
	var data: Dictionary = {}
	var player_omt := Vector2i.ZERO
	var cursor_omt := Vector2i.ZERO

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1))
		var rows: Array = data.get("rows", [])
		var cols: Array = data.get("colors", [])
		var seen: Array = data.get("seen", [])
		var notes: Dictionary = data.get("notes", {})
		var center: Vector2i = data.get("center", cursor_omt)
		var rad: int = int(data.get("radius", 16))
		var side := rad * 2 + 1
		if rows.is_empty():
			return
		var cw := floorf((size.x - 8.0) / float(side))
		var ch := floorf((size.y - 8.0) / float(side))
		var step := maxf(10.0, minf(cw, ch))
		var ox := (size.x - step * float(side)) * 0.5
		var oy := (size.y - step * float(side)) * 0.5
		var font := get_theme_default_font()
		var fsz := maxi(10, int(step * 0.85))
		for gy in range(mini(side, rows.size())):
			var rstr: String = str(rows[gy])
			var crow: Array = cols[gy]
			var srow: Array = seen[gy] if gy < seen.size() else []
			for gx in range(mini(side, rstr.length())):
				var omt := center + Vector2i(gx - rad, gy - rad)
				var px := ox + float(gx) * step
				var py := oy + float(gy) * step
				var is_seen := true
				if gx < srow.size():
					is_seen = bool(srow[gx])
				if omt == cursor_omt:
					draw_rect(Rect2(px, py, step, step), VUI.BG_SELECT)
					draw_rect(Rect2(px, py, step, step), VUI.C_YELLOW, false, 1.0)
				var nkey := "%d,%d" % [omt.x, omt.y]
				if omt == player_omt:
					draw_string(font, Vector2(px, py + step * 0.82), "@", HORIZONTAL_ALIGNMENT_CENTER, step, fsz, VUI.C_YELLOW)
				elif notes.has(nkey):
					draw_string(font, Vector2(px, py + step * 0.82), "!", HORIZONTAL_ALIGNMENT_CENTER, step, fsz, VUI.C_LTGREEN)
				elif is_seen:
					draw_string(font, Vector2(px, py + step * 0.82), rstr.substr(gx, 1), HORIZONTAL_ALIGNMENT_CENTER, step, fsz, Color(str(crow[gx])))
				else:
					draw_string(font, Vector2(px, py + step * 0.82), "?", HORIZONTAL_ALIGNMENT_CENTER, step, fsz, Color(0.22, 0.22, 0.24, 1.0))
		draw_rect(Rect2(Vector2.ZERO, size), VUI.BORDER, false, 1.0)


static func build(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var player_omt: Vector2i = world.ccb_world_to_omt(world.pos)
	if not bool(game.ccb_om_cursor_init):
		game.ccb_om_cursor = player_omt
		game.ccb_om_cursor_init = true
	var cur: Vector2i = game.ccb_om_cursor
	var rad := 16
	var data: Dictionary = world.ccb_overmap_slice(cur, rad)
	var seen: Array = data.get("seen", [])
	var notes: Dictionary = data.get("notes", {})
	var cur_seen := true
	if rad < seen.size() and rad < (seen[rad] as Array).size():
		cur_seen = bool(seen[rad][rad])
	var cur_name := str(data.get("current_name", "旷野")) if cur_seen else "未探索区域 (迷雾)"
	var cur_note := str(notes.get("%d,%d" % [cur.x, cur.y], ""))

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(split)

	var canvas := InteractiveOvermapCanvas.new()
	canvas.data = data
	canvas.player_omt = player_omt
	canvas.cursor_omt = cur
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_stretch_ratio = 1.6
	split.add_child(canvas)

	var rp := PanelContainer.new()
	rp.custom_minimum_size.x = 270
	rp.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 8, 6, 1))
	split.add_child(rp)
	var rbox := VBoxContainer.new(); rbox.add_theme_constant_override("separation", 5); rp.add_child(rbox)

	VUI.mk_lbl(rbox, cur_name, 15, VUI.C_YELLOW)
	VUI.mk_lbl(rbox, "光标 OMT: (%d, %d)   Z: %d" % [cur.x, cur.y, int(world.floor)], 12, VUI.C_WHITE)
	VUI.mk_lbl(rbox, "玩家 OMT: (%d, %d)   距离: %d 格" % [player_omt.x, player_omt.y, abs(cur.x - player_omt.x) + abs(cur.y - player_omt.y)], 12, VUI.C_LTCYAN)
	if not cur_note.is_empty():
		VUI.mk_lbl(rbox, "地图笔记: " + cur_note, 12, VUI.C_LTGREEN, true)
	rbox.add_child(VUI.divider())

	var move_cur := func(d: Vector2i):
		game.ccb_om_cursor = cur + d
		game._reopen_overlay("map")
	game.overlay_hotkeys["h"] = func(): move_cur.call(Vector2i(-1, 0))
	game.overlay_hotkeys["l"] = func(): move_cur.call(Vector2i(1, 0))
	game.overlay_hotkeys["k"] = func(): move_cur.call(Vector2i(0, -1))
	game.overlay_hotkeys["j"] = func(): move_cur.call(Vector2i(0, 1))
	game.overlay_hotkeys["c"] = func(): game.ccb_om_cursor = player_omt; game._reopen_overlay("map")

	VUI.mk_lbl(rbox, "添加/编辑该格笔记 [N]：", 12, VUI.C_YELLOW)
	var note_ed := LineEdit.new()
	note_ed.text = cur_note
	note_ed.placeholder_text = "输入笔记内容（留空清除）..."
	VUI.style_line_edit(note_ed)
	note_ed.text_submitted.connect(func(v: String): world.ccb_set_overmap_note(cur, v); game._reopen_overlay("map"))
	rbox.add_child(note_ed)
	var b_note := Button.new(); b_note.text = "保存笔记"; b_note.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_note)
	b_note.pressed.connect(func(): world.ccb_set_overmap_note(cur, note_ed.text); game._reopen_overlay("map"))
	rbox.add_child(b_note)

	rbox.add_child(VUI.divider())
	VUI.mk_lbl(rbox, "搜索已探索地点 [f]：", 12, VUI.C_YELLOW)
	var s_ed := LineEdit.new()
	s_ed.text = str(game.ccb_om_search)
	s_ed.placeholder_text = "如 避难所 / 药房 / 超市 / 警局..."
	VUI.style_line_edit(s_ed)
	s_ed.text_submitted.connect(func(v: String):
		game.ccb_om_search = v.strip_edges()
		var res: Array = world.ccb_search_overmap(game.ccb_om_search, player_omt, 40)
		if not res.is_empty(): game.ccb_om_cursor = res[0]["omt"]
		game._reopen_overlay("map"))
	rbox.add_child(s_ed)
	if not str(game.ccb_om_search).is_empty():
		var res: Array = world.ccb_search_overmap(str(game.ccb_om_search), player_omt, 40)
		VUI.mk_lbl(rbox, "已探索匹配: %d 处" % res.size(), 11, VUI.C_LTGREEN if not res.is_empty() else VUI.C_DKGRAY)
		for i in range(mini(4, res.size())):
			var r0: Dictionary = res[i]
			var tomt: Vector2i = r0["omt"]
			var jb := Button.new()
			jb.text = "» %s (%d,%d) 距%d" % [str(r0["name"]), tomt.x, tomt.y, int(r0["dist"])]
			jb.focus_mode = Control.FOCUS_NONE
			VUI.style_row_button(jb, false, VUI.C_LTCYAN)
			jb.pressed.connect(func(): game.ccb_om_cursor = tomt; game._reopen_overlay("map"))
			rbox.add_child(jb)

	rbox.add_child(VUI.divider())
	var b_center := Button.new(); b_center.text = "[c] 居中到玩家 @"; b_center.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_center)
	b_center.pressed.connect(func(): game.ccb_om_cursor = player_omt; game._reopen_overlay("map"))
	rbox.add_child(b_center)

	var b_trav := Button.new(); b_trav.text = "[W] 自动向光标位置赶路"; b_trav.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_trav, true)
	var travel_cb := func():
		var target_wp := cur * 24 + Vector2i(12, 12)
		game._close_overlay()
		game._map_clicked(target_wp)
	game.overlay_hotkeys["W"] = travel_cb
	b_trav.pressed.connect(travel_cb)
	rbox.add_child(b_trav)

	rbox.add_child(VUI.divider())
	VUI.mk_lbl(rbox, "图例: @ 自己 | ! 笔记 | ? 迷雾\nS 避难所 | ^ 民宅 | $ 超市 | + 药房\nP 警局 | F 消防 | H 五金 | R 核废料\n按键: h/j/k/l 移动光标 | c 居中 | W 赶路", 11, VUI.C_DKGRAY, true)
