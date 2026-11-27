extends RefCounted

# [g] / [,] Authentic Multi-Select Pickup (Cataclysm-Cleanwater-Bomb/src/pickup.cpp)

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const H = preload("res://scripts/ccb/item_info_helper.gd")


static func build(game: Control, contents: VBoxContainer, target := Vector2i(-1, -1)) -> void:
	var world: Object = game.world
	var ccb: Dictionary = world.ccb_status()
	var p: Vector2i = target if target != Vector2i(-1, -1) else world.pos
	var items: Array = world.ccb_items_at(p)
	var corpses: Array = world.ccb_corpses_at(p)

	if items.is_empty() and corpses.is_empty() and target == Vector2i(-1, -1):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0: continue
				var np: Vector2i = world.pos + Vector2i(dx, dy)
				if not world.ccb_items_at(np).is_empty() or not world.ccb_corpses_at(np).is_empty():
					p = np
					items = world.ccb_items_at(p)
					corpses = world.ccb_corpses_at(p)
					break
			if not items.is_empty() or not corpses.is_empty():
				break

	var picked_set: Dictionary = game.ccb_pickup_sel
	var add_w := 0
	var add_v := 0
	var sel_cnt := 0
	for i in range(items.size()):
		if picked_set.has(i):
			var it: Dictionary = items[i]
			var c := int(it.get("count", 1))
			add_w += int(it.get("weight_g", 0)) * c
			add_v += int(it.get("vol_ml", 0)) * c
			sel_cnt += 1

	var cur_w := int(ccb.get("carry_weight_g", 0))
	var max_w := int(ccb.get("max_weight_g", 45000))
	var cur_v := int(ccb.get("carry_vol_ml", 0))
	var max_v := int(ccb.get("max_vol_ml", 10000))

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 12)
	contents.add_child(hdr)
	VUI.mk_lbl(hdr, "坐标:(%d,%d)" % [p.x, p.y], 12, VUI.C_YELLOW)
	VUI.mk_lbl(hdr, "负重: %s (+%s) / %s" % [H.fmt_weight(cur_w), H.fmt_weight(add_w), H.fmt_weight(max_w)], 12,
		VUI.C_LTRED if (cur_w + add_w > max_w) else VUI.C_WHITE)
	VUI.mk_lbl(hdr, "容积: %s (+%s) / %s" % [H.fmt_vol(cur_v), H.fmt_vol(add_v), H.fmt_vol(max_v)], 12,
		VUI.C_LTRED if (cur_v + add_v > max_v) else VUI.C_LTCYAN)
	contents.add_child(VUI.divider())

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	contents.add_child(bar)

	var toggle_all := func():
		if picked_set.size() >= items.size():
			picked_set.clear()
		else:
			for i in range(items.size()):
				picked_set[i] = true
		game._reopen_overlay("pickup", p)
	game.overlay_hotkeys[","] = toggle_all

	var confirm_pick := func():
		if picked_set.is_empty():
			game._close_overlay()
			return
		var picked_ids: Array[String] = []
		for i in range(items.size()):
			if picked_set.has(i):
				picked_ids.append(str(items[i].get("id", "")))
		picked_set.clear()
		for iid in picked_ids:
			var m: String = world.ccb_take_item(p, iid)
			if not m.is_empty():
				game._note(m)
		game._drain_ccb_messages()
		game._refresh()
		if world.ccb_items_at(p).is_empty() and world.ccb_corpses_at(p).is_empty():
			game._close_overlay()
		else:
			game._reopen_overlay("pickup", p)
	game.overlay_hotkeys["\n"] = confirm_pick

	var b_all := Button.new(); b_all.text = "[,] 全选/取消全选"; b_all.focus_mode = Control.FOCUS_NONE
	VUI.style_button(b_all)
	b_all.pressed.connect(toggle_all)
	bar.add_child(b_all)

	var b_go := Button.new(); b_go.text = "[Enter] 确认拾取已勾选 (%d项)" % sel_cnt; b_go.focus_mode = Control.FOCUS_NONE
	VUI.style_button(b_go, sel_cnt > 0)
	b_go.pressed.connect(confirm_pick)
	bar.add_child(b_go)

	var b_all_now := Button.new(); b_all_now.text = "[一键全捡]"; b_all_now.focus_mode = Control.FOCUS_NONE
	VUI.style_button(b_all_now)
	b_all_now.pressed.connect(func():
		picked_set.clear()
		game._note(world.ccb_take_all_at(p))
		game._drain_ccb_messages()
		game._refresh()
		game._close_overlay())
	bar.add_child(b_all_now)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	sc.add_child(box)

	if items.is_empty():
		VUI.mk_lbl(box, "(该处没有地面物品)", 12, VUI.C_DKGRAY)
	for i in range(items.size()):
		var it: Dictionary = items[i]
		var ltr := H.LETTERS.substr(i, 1) if i < H.LETTERS.length() else "-"
		var checked := picked_set.has(i)
		var idx := i
		var tog_one := func():
			if picked_set.has(idx): picked_set.erase(idx)
			else: picked_set[idx] = true
			game._reopen_overlay("pickup", p)
		if i < H.LETTERS.length():
			game.overlay_hotkeys[ltr] = tog_one
		var fg := VUI.C_LTGREEN if checked else (VUI.C_LTRED if bool(it.get("filthy", false)) else VUI.C_LTGRAY)
		var b := Button.new()
		b.text = " %s  %s  %-28s ×%d   (%s / %s)" % [
			ltr, "[+]" if checked else "[ ]",
			str(it.get("name", "")), int(it.get("count", 1)),
			H.fmt_weight(int(it.get("weight_g", 0))), H.fmt_vol(int(it.get("vol_ml", 0)))
		]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(b, checked, fg)
		b.pressed.connect(tog_one)
		box.add_child(b)

	if not corpses.is_empty():
		box.add_child(VUI.divider())
		VUI.mk_lbl(box, "=== 该处尸体 (%d) ===" % corpses.size(), 12, VUI.C_LTRED)
		for c: Dictionary in corpses:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			box.add_child(row)
			var cl := VUI.mk_lbl(row, "%s  %s" % [str(c.get("name", "")), "[会复活!]" if bool(c.get("revives", false)) else "[安全]"], 12,
				VUI.C_LTRED if bool(c.get("revives", false)) else VUI.C_DKGRAY)
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if not bool(c.get("pulped", false)):
				var pb := Button.new(); pb.text = "[s] 捣烂尸体"; pb.focus_mode = Control.FOCUS_NONE; VUI.style_button(pb, false, true)
				pb.pressed.connect(func():
					game._note(world.ccb_pulp_at(p)); game._drain_ccb_messages(); game._refresh(); game._reopen_overlay("pickup", p))
				row.add_child(pb)
			var bb := Button.new(); bb.text = "[B] 解剖尸体"; bb.focus_mode = Control.FOCUS_NONE; VUI.style_button(bb)
			bb.pressed.connect(func():
				game._note(world.ccb_butcher_at(p)); game._drain_ccb_messages(); game._refresh(); game._reopen_overlay("pickup", p))
			row.add_child(bb)
