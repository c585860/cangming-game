extends RefCounted

# Authentic CCB Crafting Menu ('&') adapted for Jiangnan Wuxia life skills:
# Cooking (基本厨艺), Medicine (基本药学), Smithing (基本锻造), Tailoring & Copying (读书写字).

const CCB = preload("res://scripts/ccb_theme.gd")
const CATS := ["全部", "烹饪", "制药", "锻造", "裁缝抄录"]


static func open_panel(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var active_cat: String = str(game.craft_tab) if str(game.craft_tab) in CATS else "全部"
	var env: Dictionary = world.craft_env_dict()

	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 5, 1))
	contents.add_child(banner)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 2)
	banner.add_child(bcol)
	var hearth_s := "可用" if bool(env.get("near_hearth", false)) else "无"
	var anvil_s := "可用" if bool(env.get("near_anvil", false)) else "无"
	var water_s := "充足" if (bool(env.get("near_water", false)) or int(world.bottle_water()) >= 150) else "缺水"
	var ws_s := "工坊免具+提速" if bool(env.get("near_workshop", false)) else "普通场所"
	game._label(bcol, "炉灶: %s  |  锻炉铁砧: %s  |  水源: %s  |  场地: %s  |  水壶: %d ml" % [
		hearth_s, anvil_s, water_s, ws_s, int(world.bottle_water())
	], 12, CCB.C_YELLOW)
	game._label(bcol, "1-5 切分类  |  按对应字母选中配方  |  [Space/Enter] 启动实时制作读条（移动或 Esc 可打断）", 11, CCB.C_LTGRAY)

	# Category tabs
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	contents.add_child(tab_row)
	for i in range(CATS.size()):
		var cat: String = CATS[i]
		var cb := func():
			game.craft_tab = cat
			game._reopen_overlay("craft")
		var btn: Button = game._button(tab_row, "[%d] %s" % [i + 1, cat], cb, cat == active_cat)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.register_overlay_hotkey(str(i + 1), cb)

	var recipes: Array = world.craft_recipe_list(active_cat)
	if recipes.is_empty():
		game._label(contents, "该分类下暂无配方。", 12, CCB.C_DKGRAY)
		return

	var sel_id: String = str(game.selected_craft_id)
	var sel_row: Dictionary = recipes[0]
	for r: Dictionary in recipes:
		if str(r.get("id", "")) == sel_id:
			sel_row = r
			break
	game.selected_craft_id = str(sel_row.get("id", ""))

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(split)

	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 1.35
	split.add_child(left_scroll)
	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 3)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(list_box)

	for i in range(recipes.size()):
		var r: Dictionary = recipes[i]
		var rid: String = str(r.get("id", ""))
		var can_c: bool = bool(r.get("can_craft", false))
		var letter := CCB.letter_key(i)
		var is_sel: bool = rid == str(game.selected_craft_id)
		var tag := "[可制]" if can_c else "[缺件]"
		var line := "%s - %s [%s] %s" % [letter, tag, str(r.get("category", "")), str(r.get("name", ""))]
		var pick_cb := func():
			game.selected_craft_id = rid
			game._reopen_overlay("craft")
		var btn: Button = game._button(list_box, line, pick_cb, is_sel)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not is_sel:
			btn.add_theme_color_override("font_color", CCB.C_LTGREEN if can_c else CCB.C_DKGRAY)
		if letter != "-":
			game.register_overlay_hotkey(letter, pick_cb)

	# Right details card
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 10, 10, 1))
	split.add_child(card)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 6)
	card.add_child(dcol)

	var can_make: bool = bool(sel_row.get("can_craft", false))
	var dur: float = float(sel_row.get("duration_sec", 2.5))
	var rname: String = str(sel_row.get("name", ""))
	var rid_sel: String = str(sel_row.get("id", ""))
	game._label(dcol, rname, 16, CCB.C_YELLOW)
	game._label(dcol, "分类: %s  |  前置: %s  |  耗时: %.1f 秒" % [
		str(sel_row.get("category", "")), str(sel_row.get("req_label", "")), dur
	], 11, CCB.C_CYAN, true)
	dcol.add_child(CCB.divider())
	game._label(dcol, "成品：%s" % str(sel_row.get("output_label", "")), 13, CCB.C_LTGREEN)
	game._label(dcol, "材料：%s" % str(sel_row.get("ingredients", "")), 12, CCB.C_WHITE, true)
	game._label(dcol, str(sel_row.get("desc", "")), 12, CCB.C_LTGRAY, true)
	if not can_make:
		game._label(dcol, "当前受阻：%s" % str(sel_row.get("reason", "")), 12, CCB.C_LTRED, true)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dcol.add_child(sp)

	var start_cb := func():
		game._start_craft_task(rid_sel, rname, dur)
	var cbtn: Button = game._button(dcol, "[Space] 开始制作「%s」(%.1f 秒)" % [rname, dur], start_cb, can_make)
	cbtn.custom_minimum_size.y = 32
	if not can_make:
		cbtn.add_theme_color_override("font_color", CCB.C_DKGRAY)
	game.register_overlay_hotkey(" ", start_cb)
