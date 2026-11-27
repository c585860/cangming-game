extends RefCounted

# [i] Dual-Pane Inventory (src/inventory_ui.cpp) + [w/W/T/E/a/R/B] quick lettered selectors

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const H = preload("res://scripts/ccb/item_info_helper.gd")


static func inventory_panel(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var ccb: Dictionary = world.ccb_status()
	var worn: Array = world.ccb_worn()
	var bag: Array = world.ccb_inventory()

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 12)
	contents.add_child(hdr)
	VUI.mk_lbl(hdr, "负重: %s / %s" % [H.fmt_weight(int(ccb.get("carry_weight_g", 0))), H.fmt_weight(int(ccb.get("max_weight_g", 45000)))], 13, VUI.C_WHITE)
	VUI.mk_lbl(hdr, "容积: %s / %s" % [H.fmt_vol(int(ccb.get("carry_vol_ml", 0))), H.fmt_vol(int(ccb.get("max_vol_ml", 10000)))], 13, VUI.C_LTCYAN)
	VUI.mk_lbl(hdr, "总累赘: %d" % int(ccb.get("encumbrance", 0)), 13, VUI.C_YELLOW)
	contents.add_child(VUI.divider())

	var entries: Array = []
	var wid := str(ccb.get("wielded_id", ""))
	if not wid.is_empty():
		var w_info: Array = world.ccb_search_items(wid, "ALL", 25)
		var wd: Dictionary = {"id": wid, "name": str(ccb.get("wielded_name", wid)), "count": 1}
		for cand: Dictionary in w_info:
			if str(cand.get("id", "")) == wid:
				wd = cand
				break
		entries.append({"section": "WIELDED", "item": wd, "worn": false, "wielded": true})
	for w: Dictionary in worn:
		entries.append({"section": "WORN", "item": w, "worn": true, "wielded": false})
	for b: Dictionary in bag:
		entries.append({"section": "BAG", "item": b, "worn": false, "wielded": false})

	var sel_idx: int = clampi(int(game.ccb_inv_sel), 0, maxi(0, entries.size() - 1))
	game.ccb_inv_sel = sel_idx

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(split)

	var lp := PanelContainer.new()
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_stretch_ratio = 1.25
	lp.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 6, 1))
	split.add_child(lp)
	var lsc := ScrollContainer.new()
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lp.add_child(lsc)
	var lbox := VBoxContainer.new()
	lbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbox.add_theme_constant_override("separation", 1)
	lsc.add_child(lbox)

	var last_sec := ""
	const SEC_TITLES := {"WIELDED": "=== 手持武器 (WIELDED) ===", "WORN": "=== 已穿戴 (WORN) ===", "BAG": "=== 背包物品 (INVENTORY) ==="}
	if entries.is_empty():
		VUI.mk_lbl(lbox, "(你身上空空如也)", 13, VUI.C_DKGRAY)
	for i in range(entries.size()):
		var ent: Dictionary = entries[i]
		var sec: String = str(ent["section"])
		if sec != last_sec:
			last_sec = sec
			VUI.mk_lbl(lbox, SEC_TITLES[sec], 12, VUI.C_YELLOW)
		var it: Dictionary = ent["item"]
		var ltr := H.LETTERS.substr(i, 1) if i < H.LETTERS.length() else "-"
		var is_sel := (i == sel_idx)
		var idx := i
		var sel_cb := func():
			game.ccb_inv_sel = idx
			game._reopen_overlay("inventory")
		if i < H.LETTERS.length():
			game.overlay_hotkeys[ltr] = sel_cb
		var cnt := int(it.get("count", 1))
		var fg := VUI.C_LTRED if bool(it.get("filthy", false)) else (VUI.C_LTCYAN if bool(ent["worn"]) else (VUI.C_YELLOW if bool(ent["wielded"]) else VUI.C_LTGRAY))
		var b := Button.new()
		b.text = "%s%s - %s%s" % ["» " if is_sel else "  ", ltr, str(it.get("name", "")), (" ×%d" % cnt) if cnt > 1 else ""]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(b, is_sel, fg)
		b.pressed.connect(sel_cb)
		lbox.add_child(b)

	var rp := PanelContainer.new()
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.size_flags_stretch_ratio = 1.0
	rp.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 8, 6, 1))
	split.add_child(rp)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 6)
	rp.add_child(rcol)

	var info_box := VBoxContainer.new()
	info_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 4)
	rcol.add_child(info_box)

	if entries.is_empty():
		H.render_item_info(info_box, {})
		return

	var cur_ent: Dictionary = entries[sel_idx]
	var cur_it: Dictionary = cur_ent["item"]
	var iid := str(cur_it.get("id", ""))
	var is_worn := bool(cur_ent["worn"])
	var is_wielded := bool(cur_ent["wielded"])
	H.render_item_info(info_box, cur_it, is_worn, is_wielded)

	rcol.add_child(VUI.divider())
	var act_row := HFlowContainer.new()
	act_row.add_theme_constant_override("h_separation", 6)
	act_row.add_theme_constant_override("v_separation", 4)
	rcol.add_child(act_row)

	var add_act := func(lbl: String, cb: Callable, hi := false):
		var ab := Button.new()
		ab.text = lbl
		ab.focus_mode = Control.FOCUS_NONE
		VUI.style_button(ab, hi)
		ab.pressed.connect(cb)
		act_row.add_child(ab)

	if is_wielded:
		add_act.call("[收起武器]", func():
			game._note(world.ccb_unwield()); game._refresh(); game._reopen_overlay("inventory"), true)
		add_act.call("[激活使用]", func():
			game._note(world.ccb_use_item(iid)); game._drain_ccb_messages(); game._refresh(); game._reopen_overlay("inventory"))
	elif is_worn:
		add_act.call("[脱下装备]", func():
			game._note(world.ccb_takeoff(iid)); game._refresh(); game._reopen_overlay("inventory"), true)
		add_act.call("[分层整理 +]", func():
			game._reopen_overlay("armor_layers"))
	else:
		var sub := str(cur_it.get("subtype", ""))
		add_act.call("[使用/服用]", func():
			game._note(world.ccb_use_item(iid)); game._drain_ccb_messages(); game._refresh(); game._reopen_overlay("inventory"), sub == "COMESTIBLE")
		add_act.call("[手持]", func():
			game._note(world.ccb_wield(iid)); game._refresh(); game._reopen_overlay("inventory"))
		if sub == "ARMOR" or int(cur_it.get("covers_mask", 0)) != 0:
			add_act.call("[穿戴]", func():
				game._note(world.ccb_wear(iid)); game._refresh(); game._reopen_overlay("inventory"), not bool(cur_it.get("filthy", false)))
		if bool(cur_it.get("filthy", false)):
			add_act.call("[清洗脏污]", func():
				game._note(world.ccb_wash_item(iid)); game._refresh(); game._reopen_overlay("inventory"), true)
		add_act.call("[丢弃]", func():
			game._note(world.ccb_drop_item(iid)); game._refresh(); game._reopen_overlay("inventory"))


static func eat_menu(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var rows := []
	for it: Dictionary in world.ccb_inventory():
		var iid := str(it.get("id", ""))
		var sub := str(it.get("subtype", ""))
		if sub == "COMESTIBLE" or iid.contains("mutagen") or iid.contains("purifier") or iid.contains("iodine") or iid.contains("prussian") or iid.contains("antibiotic"):
			rows.append({
				"label": "%s ×%d  (热量:%d 解渴:%+d)" % [str(it.get("name", iid)), int(it.get("count", 1)), int(it.get("kcal", 0)), int(it.get("quench", 0))],
				"color": VUI.C_LTGREEN,
				"cb": func():
					game._note(world.ccb_use_item(iid)); game._drain_ccb_messages(); game._refresh(); game._close_overlay(),
			})
	H.build_letter_selector(game, contents, "行囊中没有可食用或服用的补给。", rows)


static func wear_menu(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var rows := []
	for it: Dictionary in world.ccb_inventory():
		var iid := str(it.get("id", ""))
		if str(it.get("subtype", "")) == "ARMOR" or int(it.get("covers_mask", 0)) != 0:
			var filthy := bool(it.get("filthy", false))
			rows.append({
				"label": "%s  防%d/%d/%d  累赘:%d%s" % [str(it.get("name", iid)), int(it.get("armor_bash", 0)), int(it.get("armor_cut", 0)), int(it.get("armor_stab", 0)), int(it.get("encumbrance", 0)), " [需先清洗]" if filthy else ""],
				"color": VUI.C_LTRED if filthy else VUI.C_LTCYAN,
				"cb": func():
					game._note(world.ccb_wear(iid)); game._refresh(); game._close_overlay(),
			})
	H.build_letter_selector(game, contents, "行囊中没有可穿戴的护甲或衣物。", rows)


static func take_off_menu(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var rows := []
	for it: Dictionary in world.ccb_worn():
		var iid := str(it.get("id", ""))
		rows.append({
			"label": "%s  防%d/%d/%d  累赘:%d" % [str(it.get("name", iid)), int(it.get("armor_bash", 0)), int(it.get("armor_cut", 0)), int(it.get("armor_stab", 0)), int(it.get("encumbrance", 0))],
			"color": VUI.C_WHITE,
			"cb": func():
				game._note(world.ccb_takeoff(iid)); game._refresh(); game._close_overlay(),
		})
	H.build_letter_selector(game, contents, "当前未穿戴任何装备。", rows)


static func wield_menu(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var rows := [{
		"label": "(空手 — 收起当前手持物品)",
		"color": VUI.C_YELLOW,
		"cb": func(): game._note(world.ccb_unwield()); game._refresh(); game._close_overlay(),
	}]
	for it: Dictionary in world.ccb_inventory():
		var iid := str(it.get("id", ""))
		rows.append({
			"label": "%s  (钝%d / 斩%d / 刺%d)" % [str(it.get("name", iid)), int(it.get("bash", 0)), int(it.get("cut", 0)), int(it.get("stab", 0))],
			"color": VUI.C_WHITE,
			"cb": func(): game._note(world.ccb_wield(iid)); game._refresh(); game._close_overlay(),
		})
	H.build_letter_selector(game, contents, "行囊为空。", rows)


static func apply_menu(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var rows := []
	for it: Dictionary in world.ccb_inventory():
		var iid := str(it.get("id", ""))
		rows.append({
			"label": "%s ×%d  [%s]" % [str(it.get("name", iid)), int(it.get("count", 1)), str(it.get("subtype", ""))],
			"color": VUI.C_LTCYAN,
			"cb": func(): game._note(world.ccb_use_item(iid)); game._drain_ccb_messages(); game._refresh(); game._close_overlay(),
		})
	H.build_letter_selector(game, contents, "行囊中没有可激活使用的物品。", rows)


static func read_menu(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var rows := []
	for it: Dictionary in world.ccb_inventory():
		if str(it.get("subtype", "")) == "BOOK":
			var nm := str(it.get("name", ""))
			rows.append({
				"label": "%s — %s" % [nm, str(it.get("desc", "")).left(50)],
				"color": VUI.C_YELLOW,
				"cb": func():
					world.ccb_wait_minutes(15); game._drain_ccb_messages()
					game._note("你研读了「%s」15 分钟。" % nm); game._refresh(); game._close_overlay(),
			})
	H.build_letter_selector(game, contents, "行囊中没有原版书籍。", rows)


static func butcher_menu(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var rows := []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p: Vector2i = world.pos + Vector2i(dx, dy)
			for c: Dictionary in world.ccb_corpses_at(p):
				var pos_c := p
				rows.append({
					"label": "解剖「%s」 (%d,%d) — 原版 Harvest 表产出肉/骨/筋腱" % [str(c.get("name", "")), pos_c.x, pos_c.y],
					"color": VUI.C_LTGREEN,
					"cb": func():
						game._note(world.ccb_butcher_at(pos_c)); game._drain_ccb_messages(); game._refresh(); game._close_overlay(),
				})
				if not bool(c.get("pulped", false)):
					rows.append({
						"label": "捣烂「%s」 (%d,%d) — 防止尸体复活" % [str(c.get("name", "")), pos_c.x, pos_c.y],
						"color": VUI.C_LTRED,
						"cb": func():
							game._note(world.ccb_pulp_at(pos_c)); game._drain_ccb_messages(); game._refresh(); game._close_overlay(),
					})
	H.build_letter_selector(game, contents, "身旁没有可解剖或捣烂的尸体。", rows)
