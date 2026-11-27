extends RefCounted

# [K] Debug Menu — Authentic Place for Spawning Items / Monsters / Testing Radiation & Mutations

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")


static func build(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var db: Dictionary = world.ccb_db_stats()
	VUI.mk_lbl(contents, "CCB 调试菜单 (仅调试使用) — 物品:%d | 怪物:%d | 掉落组:%d | 解剖表:%d" % [
		int(db.get("items", 0)), int(db.get("monsters", 0)), int(db.get("monsterdrop_groups", 0)), int(db.get("harvests", 0))
	], 12, VUI.C_YELLOW)

	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 6)
	contents.add_child(qrow)
	for ms: Array in [["mon_zombie", "刷普通丧尸"], ["mon_zombie_cop", "刷警察丧尸"], ["mon_zombie_fireman", "刷消防丧尸"], ["mon_zombie_scientist", "刷科学家丧尸"]]:
		var b := Button.new(); b.text = ms[1]; b.focus_mode = Control.FOCUS_NONE; VUI.style_button(b)
		var mid: String = ms[0]
		b.pressed.connect(func():
			world.ccb_debug_spawn_monster(mid, world.pos + Vector2i(1, 0))
			game._note("[调试] 在身旁生成了 %s。" % mid)
			game._refresh())
		qrow.add_child(b)

	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 6)
	contents.add_child(rrow)
	var b_rad := Button.new(); b_rad.text = "+80 mSv 辐射"; b_rad.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_rad)
	b_rad.pressed.connect(func():
		for m in world.ccb_irradiate(80.0, true): game._note(str(m))
		game._refresh())
	rrow.add_child(b_rad)
	var b_mut := Button.new(); b_mut.text = "随机变异 (BEAST)"; b_mut.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_mut)
	b_mut.pressed.connect(func():
		for m in world.ccb_mutate_category("BEAST"): game._note(str(m))
		game._refresh())
	rrow.add_child(b_mut)
	var b_pur := Button.new(); b_pur.text = "净化变异"; b_pur.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_pur)
	b_pur.pressed.connect(func():
		for m in world.ccb_purify(): game._note(str(m))
		game._refresh())
	rrow.add_child(b_pur)

	contents.add_child(VUI.divider())
	VUI.mk_lbl(contents, "刷取原版物品（10,366 件全量库，位于调试菜单而非 [i] 背包）：", 12, VUI.C_LTCYAN)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	contents.add_child(srow)
	var ed := LineEdit.new()
	ed.text = str(game.ccb_search_query)
	ed.placeholder_text = "输入物品中文/英文/ID 搜索（如 katana / hazmat / mutagen / crowbar）"
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VUI.style_line_edit(ed)
	ed.text_submitted.connect(func(v: String): game.ccb_search_query = v.strip_edges(); game._reopen_overlay("debug"))
	srow.add_child(ed)
	var sb := Button.new(); sb.text = "搜索"; sb.focus_mode = Control.FOCUS_NONE; VUI.style_button(sb)
	sb.pressed.connect(func(): game.ccb_search_query = ed.text.strip_edges(); game._reopen_overlay("debug"))
	srow.add_child(sb)

	var results: Array = world.ccb_search_items(str(game.ccb_search_query), "ALL", 40)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; contents.add_child(sc)
	var lbox := VBoxContainer.new(); lbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lbox.add_theme_constant_override("separation", 2); sc.add_child(lbox)
	for it: Dictionary in results:
		var iid := str(it.get("id", ""))
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); lbox.add_child(row)
		var l := VUI.mk_lbl(row, "%s  [%s | %s]" % [str(it.get("name", iid)), str(it.get("subtype", "")), iid], 12, VUI.C_WHITE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var gb := Button.new(); gb.text = "+刷取×1"; gb.focus_mode = Control.FOCUS_NONE; VUI.style_button(gb)
		gb.pressed.connect(func(): game._note(world.ccb_give_item(iid, 1)); game._refresh())
		row.add_child(gb)
