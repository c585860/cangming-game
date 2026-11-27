extends RefCounted

# [&] Authentic Dual-Pane Crafting GUI (Cataclysm-Cleanwater-Bomb/src/crafting_gui.cpp)

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const H = preload("res://scripts/ccb/item_info_helper.gd")

const CRAFT_CATS := [
	["CC_WEAPON", "武器"],
	["CC_AMMO", "弹药"],
	["CC_FOOD", "食物"],
	["CC_CHEM", "化工"],
	["CC_ELECTRONIC", "电子"],
	["CC_ARMOR", "护甲"],
	["CC_OTHER", "其他"],
]


static func build(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var cat: String = str(game.ccb_craft_cat)
	if cat.is_empty() or cat == "ALL":
		cat = "CC_WEAPON"

	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 3)
	contents.add_child(cat_row)
	for ci in range(CRAFT_CATS.size()):
		var c: Array = CRAFT_CATS[ci]
		var cid: String = c[0]
		var b := Button.new()
		b.text = "%d.%s" % [ci + 1, c[1]]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		VUI.style_button(b, cat == cid)
		var cb := func():
			game.ccb_craft_cat = cid
			game.ccb_craft_sel = 0
			game._reopen_overlay("craft")
		game.overlay_hotkeys[str(ci + 1)] = cb
		b.pressed.connect(cb)
		cat_row.add_child(b)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	contents.add_child(srow)
	var ed := LineEdit.new()
	ed.text = str(game.ccb_craft_query)
	ed.placeholder_text = "搜索 2,823 条原版合成配方（如 绷带 / 撬棍 / 净水 / bandage）..."
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VUI.style_line_edit(ed)
	ed.text_submitted.connect(func(v: String):
		game.ccb_craft_query = v.strip_edges(); game.ccb_craft_sel = 0; game._reopen_overlay("craft"))
	srow.add_child(ed)
	var sb := Button.new(); sb.text = "搜索"; sb.focus_mode = Control.FOCUS_NONE; VUI.style_button(sb)
	sb.pressed.connect(func():
		game.ccb_craft_query = ed.text.strip_edges(); game.ccb_craft_sel = 0; game._reopen_overlay("craft"))
	srow.add_child(sb)

	var q_str := str(game.ccb_craft_query)
	var list: Array = world.ccb_recipe_list("ALL" if not q_str.is_empty() else cat, q_str, 80)
	var sel_idx := clampi(int(game.ccb_craft_sel), 0, maxi(0, list.size() - 1))
	game.ccb_craft_sel = sel_idx

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(split)

	var lp := PanelContainer.new()
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_stretch_ratio = 1.05
	lp.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 6, 1))
	split.add_child(lp)
	var lsc := ScrollContainer.new(); lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL; lp.add_child(lsc)
	var lbox := VBoxContainer.new(); lbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lbox.add_theme_constant_override("separation", 1); lsc.add_child(lbox)

	if list.is_empty():
		VUI.mk_lbl(lbox, "(未找到匹配的原版配方)", 12, VUI.C_DKGRAY)
	for i in range(list.size()):
		var r: Dictionary = list[i]
		var can_m := bool(r.get("can_craft", false))
		var is_sel := (i == sel_idx)
		var idx := i
		var b := Button.new()
		b.text = "%s%s  [%s Lv.%d]" % ["» " if is_sel else "  ", str(r.get("name", "")), str(r.get("skill_name", "")), int(r.get("difficulty", 0))]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(b, is_sel, VUI.C_WHITE if can_m else VUI.C_DKGRAY)
		b.pressed.connect(func(): game.ccb_craft_sel = idx; game._reopen_overlay("craft"))
		lbox.add_child(b)

	var rp := PanelContainer.new()
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.size_flags_stretch_ratio = 1.25
	rp.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 8, 6, 1))
	split.add_child(rp)
	var rcol := VBoxContainer.new(); rcol.add_theme_constant_override("separation", 5); rp.add_child(rcol)

	if list.is_empty():
		return

	var r: Dictionary = list[sel_idx]
	var rid := str(r.get("id", ""))
	var can_m := bool(r.get("can_craft", false))
	var diff := int(r.get("difficulty", 0))
	var psk := int(r.get("player_skill", 0))
	VUI.mk_lbl(rcol, "%s  (产出 ×%d)" % [str(r.get("name", "")), int(r.get("charges", 1))], 15, VUI.C_YELLOW)
	VUI.mk_lbl(rcol, "主技能: %s (需求 Lv.%d / 当前 Lv.%d)   耗时: %d 分钟" % [
		str(r.get("skill_name", "")), diff, psk, int(r.get("time_min", 5))
	], 12, VUI.C_LTGREEN if psk >= diff else VUI.C_LTRED)
	rcol.add_child(VUI.divider())
	VUI.mk_lbl(rcol, "所需材料 (每槽位满足任一替代品)：", 12, VUI.C_YELLOW)
	for slot in r.get("comp_slots", []):
		if not slot is Array or slot.is_empty(): continue
		var parts := PackedStringArray()
		var ok := false
		for alt: Dictionary in slot:
			var have := int(alt.get("have", 0))
			var need := int(alt.get("need", 1))
			if have >= need: ok = true
			parts.append("%s (%d/%d)" % [str(alt.get("name", "")), have, need])
		VUI.mk_lbl(rcol, "  %s %s" % [">" if ok else "x", " 或 ".join(parts)], 12, VUI.C_LTGREEN if ok else VUI.C_LTRED, true)

	var rinfo: Dictionary = r.get("result_info", {})
	if not rinfo.is_empty():
		rcol.add_child(VUI.divider())
		VUI.mk_lbl(rcol, "成品属性：重量 %s | 体积 %s | 钝%d/斩%d/刺%d" % [
			H.fmt_weight(int(rinfo.get("weight_g", 0))), H.fmt_vol(int(rinfo.get("vol_ml", 0))),
			int(rinfo.get("bash", 0)), int(rinfo.get("cut", 0)), int(rinfo.get("stab", 0))
		], 11, VUI.C_LTCYAN)
		VUI.mk_lbl(rcol, str(rinfo.get("desc", "")), 11, VUI.C_LTGRAY, true)

	var sp := Control.new(); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL; rcol.add_child(sp)
	var brow := HBoxContainer.new(); brow.add_theme_constant_override("separation", 8); rcol.add_child(brow)
	var do_craft := func(cnt: int):
		var msg: String = world.ccb_craft_batch(rid, cnt) if cnt > 1 else world.ccb_craft_recipe(rid)
		game._note(msg); game._drain_ccb_messages(); game._refresh(); game._reopen_overlay("craft")
	var b1 := Button.new(); b1.text = "[c] 制作 ×1"; b1.focus_mode = Control.FOCUS_NONE; b1.disabled = not can_m
	VUI.style_button(b1, can_m)
	b1.pressed.connect(func(): do_craft.call(1))
	brow.add_child(b1)
	var b5 := Button.new(); b5.text = "[b] 批量制作 ×5 (省时15%)"; b5.focus_mode = Control.FOCUS_NONE; b5.disabled = not can_m
	VUI.style_button(b5)
	b5.pressed.connect(func(): do_craft.call(5))
	brow.add_child(b5)
	if can_m:
		game.overlay_hotkeys["c"] = func(): do_craft.call(1)
		game.overlay_hotkeys["b"] = func(): do_craft.call(5)
