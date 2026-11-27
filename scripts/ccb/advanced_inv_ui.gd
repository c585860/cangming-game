extends RefCounted

# [/] Authentic Dual-Pane Advanced Inventory Manager (Cataclysm-Cleanwater-Bomb/src/advanced_inv.cpp)

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const H = preload("res://scripts/ccb/item_info_helper.gd")


static func _loc_name(loc: String) -> String:
	const MAP := {
		"I": "背包 [I]", "5": "脚下 [5]",
		"8": "北 [8]", "2": "南 [2]", "4": "西 [4]", "6": "东 [6]",
		"7": "西北 [7]", "9": "东北 [9]", "1": "西南 [1]", "3": "东南 [3]",
	}
	return str(MAP.get(loc, loc))


static func _loc_pos(world: Object, loc: String) -> Vector2i:
	const OFF := {
		"5": Vector2i(0, 0), "8": Vector2i(0, -1), "2": Vector2i(0, 1),
		"4": Vector2i(-1, 0), "6": Vector2i(1, 0), "7": Vector2i(-1, -1),
		"9": Vector2i(1, -1), "1": Vector2i(-1, 1), "3": Vector2i(1, 1),
	}
	return world.pos + OFF.get(loc, Vector2i.ZERO)


static func build(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var l_loc: String = str(game.ccb_adv_left)
	var r_loc: String = str(game.ccb_adv_right)
	var active_side: int = int(game.ccb_adv_side)

	VUI.mk_lbl(contents, "双栏高级物品管理器 — 选择左右两侧源/目标容器，点击物品即刻转移至对面", 12, VUI.C_YELLOW)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(split)

	for side: int in [0, 1]:
		var my_loc: String = l_loc if side == 0 else r_loc
		var op_loc: String = r_loc if side == 0 else l_loc
		var is_act: bool = (side == active_side)

		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_BRIGHT if is_act else VUI.BORDER_DIM, 6, 6, 1))
		split.add_child(p)
		var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 4); p.add_child(col)

		VUI.mk_lbl(col, "%s %s" % ["▶" if is_act else " ", _loc_name(my_loc)], 13, VUI.C_YELLOW if is_act else VUI.C_LTGRAY)
		var sel_row := HFlowContainer.new()
		sel_row.add_theme_constant_override("h_separation", 3)
		sel_row.add_theme_constant_override("v_separation", 3)
		col.add_child(sel_row)
		for lk in ["I", "5", "8", "2", "4", "6", "7", "9", "1", "3"]:
			var lb := Button.new(); lb.text = lk; lb.focus_mode = Control.FOCUS_NONE
			VUI.style_button(lb, my_loc == lk)
			var lkey: String = lk
			var s_idx: int = side
			lb.pressed.connect(func():
				if s_idx == 0: game.ccb_adv_left = lkey
				else: game.ccb_adv_right = lkey
				game.ccb_adv_side = s_idx
				game._reopen_overlay("advanced_inv"))
			sel_row.add_child(lb)
		col.add_child(VUI.divider())

		var from_bag := (my_loc == "I")
		var to_bag := (op_loc == "I")
		var from_p := _loc_pos(world, my_loc)
		var to_p := _loc_pos(world, op_loc)
		var items: Array = world.ccb_inventory() if from_bag else world.ccb_items_at(from_p)

		var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; col.add_child(sc)
		var list_box := VBoxContainer.new(); list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list_box.add_theme_constant_override("separation", 1); sc.add_child(list_box)

		if items.is_empty():
			VUI.mk_lbl(list_box, "(空)", 12, VUI.C_DKGRAY)
		for i in range(items.size()):
			var it: Dictionary = items[i]
			var iid := str(it.get("id", ""))
			var cnt := int(it.get("count", 1))
			var b := Button.new()
			b.text = " %s  ×%d   (%s)" % [str(it.get("name", iid)), cnt, H.fmt_weight(int(it.get("weight_g", 0)))]
			b.focus_mode = Control.FOCUS_NONE
			VUI.style_row_button(b, false, VUI.C_LTRED if bool(it.get("filthy", false)) else VUI.C_WHITE)
			var s_idx: int = side
			b.pressed.connect(func():
				game.ccb_adv_side = s_idx
				if my_loc != op_loc:
					game._note(world.ccb_transfer_item(from_p, from_bag, to_p, to_bag, iid, cnt))
					game._drain_ccb_messages()
					game._refresh()
				game._reopen_overlay("advanced_inv"))
			list_box.add_child(b)
