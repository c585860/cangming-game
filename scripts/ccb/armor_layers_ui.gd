extends RefCounted

# [+] Authentic Clothing Layering / Sort Armor (Cataclysm-Cleanwater-Bomb/src/armor_layers.cpp)

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const H = preload("res://scripts/ccb/item_info_helper.gd")


static func build(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var worn: Array = world.ccb_worn()
	var ccb: Dictionary = world.ccb_status()
	var sel_idx := clampi(int(game.ccb_armor_sel), 0, maxi(0, worn.size() - 1))
	game.ccb_armor_sel = sel_idx

	VUI.mk_lbl(contents, "衣物穿戴顺序（从内层到外层）— 同部位超过 2 层产生叠层累赘惩罚", 12, VUI.C_YELLOW)
	contents.add_child(VUI.divider())

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(split)

	var lp := PanelContainer.new()
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 6, 1))
	split.add_child(lp)
	var lbox := VBoxContainer.new(); lbox.add_theme_constant_override("separation", 2); lp.add_child(lbox)
	VUI.mk_lbl(lbox, "[ 已穿戴衣物 (%d件) ]" % worn.size(), 12, VUI.C_YELLOW)
	if worn.is_empty():
		VUI.mk_lbl(lbox, "(未穿戴任何衣物)", 12, VUI.C_DKGRAY)
	for i in range(worn.size()):
		var w: Dictionary = worn[i]
		var ltr := H.LETTERS.substr(i, 1) if i < H.LETTERS.length() else "-"
		var is_sel := (i == sel_idx)
		var idx := i
		var cb := func(): game.ccb_armor_sel = idx; game._reopen_overlay("armor_layers")
		if i < H.LETTERS.length(): game.overlay_hotkeys[ltr] = cb
		var b := Button.new()
		b.text = "%s%s - %d层: %s  (累赘%d 暖%d)" % ["» " if is_sel else "  ", ltr, i + 1, str(w.get("name", "")), int(w.get("encumbrance", 0)), int(w.get("warmth", 0))]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(b, is_sel, VUI.C_LTCYAN if is_sel else VUI.C_LTGRAY)
		b.pressed.connect(cb)
		lbox.add_child(b)

	if not worn.is_empty():
		lbox.add_child(VUI.divider())
		var brow := HBoxContainer.new(); brow.add_theme_constant_override("separation", 6); lbox.add_child(brow)
		var b_up := Button.new(); b_up.text = "[↑] 向内层移"; b_up.focus_mode = Control.FOCUS_NONE; b_up.disabled = (sel_idx <= 0); VUI.style_button(b_up)
		b_up.pressed.connect(func():
			if world.ccb_reorder_worn(sel_idx, -1):
				game.ccb_armor_sel = sel_idx - 1; game._refresh(); game._reopen_overlay("armor_layers"))
		brow.add_child(b_up)
		var b_dn := Button.new(); b_dn.text = "[↓] 向外层移"; b_dn.focus_mode = Control.FOCUS_NONE; b_dn.disabled = (sel_idx >= worn.size() - 1); VUI.style_button(b_dn)
		b_dn.pressed.connect(func():
			if world.ccb_reorder_worn(sel_idx, 1):
				game.ccb_armor_sel = sel_idx + 1; game._refresh(); game._reopen_overlay("armor_layers"))
		brow.add_child(b_dn)
		var b_off := Button.new(); b_off.text = "[T] 脱下"; b_off.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_off, false, true)
		b_off.pressed.connect(func():
			game._note(world.ccb_takeoff(str(worn[sel_idx].get("id", "")))); game._refresh(); game._reopen_overlay("armor_layers"))
		brow.add_child(b_off)

	var mp := PanelContainer.new()
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 8, 6, 1))
	split.add_child(mp)
	var mbox := VBoxContainer.new(); mp.add_child(mbox)
	H.render_item_info(mbox, worn[sel_idx] if not worn.is_empty() else {}, true, false)

	var rp := PanelContainer.new()
	rp.custom_minimum_size.x = 240
	rp.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 8, 6, 1))
	split.add_child(rp)
	var rbox := VBoxContainer.new(); rbox.add_theme_constant_override("separation", 3); rp.add_child(rbox)
	VUI.mk_lbl(rbox, "[ 各部位累赘与防护 ]", 12, VUI.C_YELLOW)
	for bp: Dictionary in ccb.get("body_parts", []):
		var tot := int(bp.get("total_encumbrance", 0))
		VUI.mk_lbl(rbox, "%-4s  %2d+%d  暖%3d  甲%d/%d/%d" % [
			str(bp.get("name", "")), int(bp.get("encumbrance", 0)), int(bp.get("layer_penalty", 0)),
			int(bp.get("warmth", 0)), int(bp.get("armor_bash", 0)), int(bp.get("armor_cut", 0)), int(bp.get("armor_stab", 0))
		], 12, VUI.C_LTGRAY if tot < 15 else (VUI.C_YELLOW if tot < 35 else VUI.C_LTRED))
