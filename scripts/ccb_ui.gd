extends RefCounted

# Modular CCB gameplay UI panels:
# - Eat / Drink (E)
# - Wear clothing (W) & Take off / Layer manager (T / +)
# - Pickup / Examine Container (g / , / e)
# - Character Needs, Warmth, Encumbrance & Clothing Sheet (@)
# - Sky & Time Observation

const UI = preload("res://scripts/ui_theme.gd")
const CanglingCalendar = preload("res://scripts/cangling_calendar.gd")
const NONE := Vector2i(-1, -1)


static func _needs_banner(game: Control, parent: VBoxContainer) -> void:
	var st: Dictionary = game.world.character_status()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_CARD, UI.BORDER_JADE, 4, 10, 7, 1))
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	game._label(col, "饱食：%s（%d kcal）   ·   水分：%s（%d%%）   ·   精力：%s" % [
		st.get("hunger_text", "正常"), int(st.get("kcal", 2400)),
		st.get("thirst_text", "正常"), int(st.get("hydration", 100)),
		st.get("fatigue_text", "尚可")], 13, UI.GOLD)
	game._label(col, "容积：%d / %d ml   ·   负重：%.2f kg   ·   保暖 %d   ·   累赘 %d   ·   水壶 %d/%d ml" % [
		int(st.get("carry_volume_ml", 0)), int(st.get("max_carry_volume_ml", 2500)),
		float(st.get("carry_weight_g", 0)) / 1000.0,
		int(st.get("warmth", 0)), int(st.get("encumbrance", 0)),
		int(game.world.bottle_water()), int(game.world.bottle_capacity())], 12, UI.INK_SOFT)


static func eat_menu(game: Control, contents: VBoxContainer) -> void:
	_needs_banner(game, contents)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	# Quick drink from carried water bottle
	if int(game.world.bottle_water()) > 0:
		game._label(body, "◈ 随身水壶", 13, UI.GOLD)
		var drink_ml := mini(250, int(game.world.bottle_water()))
		game._button(body, "喝一口清水（%d ml，剩余 %d ml）" % [drink_ml, int(game.world.bottle_water())], func():
			game._note(game.world.drink_bottle(drink_ml))
			game._refresh()
			game._close_overlay()
			game._show_overlay("eat"), true)

	# Carried food & drinks
	var bag: Array = game.world.inventory()
	var edibles: Array = []
	for row: Dictionary in bag:
		if bool(row.get("is_food", false)) or bool(row.get("is_drink", false)):
			edibles.append(row)
	game._label(body, "◈ 行囊中的食粮与茶水", 13, UI.INK_SOFT)
	if edibles.is_empty():
		game._label(body, "  行囊中暂无可食用或饮用的物品。", 13, UI.INK_DIM)
	else:
		for row: Dictionary in edibles:
			var id: int = int(row["id"])
			var verb := "饮用" if bool(row["is_drink"]) else "食用"
			var info := "%s × %d  （热量 %+d kcal，解渴 %+d）" % [
				row["name"], int(row["count"]), int(row["kcal"]), int(row["quench"])]
			game._button(body, "%s：%s" % [verb, info], func():
				game._note(game.world.eat_item(id))
				game._refresh()
				game._close_overlay()
				game._show_overlay("eat"))

	# Nearby table/counter/ground food & drinks
	var nearby: Array = []
	var pos: Vector2i = game.world.pos
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := pos + Vector2i(dx, dy)
			for row: Dictionary in game.world.items_at(p):
				if bool(row.get("is_food", false)) or bool(row.get("is_drink", false)):
					nearby.append([p, row])
	if not nearby.is_empty():
		game._label(body, "◈ 身旁桌面 / 地面上的食物与茶水", 13, UI.INK_SOFT)
		for entry: Array in nearby:
			var p: Vector2i = entry[0]
			var row: Dictionary = entry[1]
			var id: int = int(row["id"])
			var verb := "直接饮用" if bool(row["is_drink"]) else "直接食用"
			game._button(body, "%s：%s × %d  （热量 %+d，解渴 %+d）" % [
				verb, row["name"], int(row["count"]), int(row["kcal"]), int(row["quench"])], func():
				game._note(game.world.eat_item_at(p, id))
				game.board.invalidate_world_cache()
				game._refresh()
				game._close_overlay()
				game._show_overlay("eat"))


static func wear_menu(game: Control, contents: VBoxContainer) -> void:
	_needs_banner(game, contents)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var bag: Array = game.world.inventory()
	var clothes: Array = []
	for row: Dictionary in bag:
		if bool(row.get("is_clothing", false)):
			clothes.append(row)
	game._label(body, "◈ 选择行囊中的衣物穿戴（每部位最多叠穿 2 层）", 13, UI.GOLD)
	if clothes.is_empty():
		game._label(body, "  行囊中没有未穿戴的衣物。可打开民居衣柜（o / e）搜寻衣物。", 13, UI.INK_DIM, true)
	else:
		for row: Dictionary in clothes:
			var id: int = int(row["id"])
			var text := "穿上 %s × %d  [%s · 保暖+%d · 累赘+%d · 容积+%d ml]" % [
				row["name"], int(row["count"]), row["slot"],
				int(row["warmth"]), int(row["encumbrance"]), int(row["storage_ml"])]
			game._button(body, text, func():
				game._note(game.world.wear_item(id))
				game.board.player_layer.queue_redraw()
				game._refresh()
				game._close_overlay()
				game._show_overlay("wear"), true)


static func take_off_menu(game: Control, contents: VBoxContainer) -> void:
	_needs_banner(game, contents)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var st: Dictionary = game.world.character_status()
	var worn: Array = st.get("worn", [])
	game._label(body, "◈ 当前穿戴着装（点击脱下收入行囊）", 13, UI.GOLD)
	if worn.is_empty():
		game._label(body, "  当前未穿戴任何衣物。", 13, UI.INK_DIM)
	else:
		for row: Dictionary in worn:
			var widx: int = int(row["worn_index"])
			var text := "脱下 %s  [%s · 保暖+%d · 累赘+%d · 容积+%d ml]" % [
				row["name"], row["slot"],
				int(row["warmth"]), int(row["encumbrance"]), int(row["storage_ml"])]
			game._button(body, text, func():
				game._note(game.world.take_off_item(widx))
				game.board.player_layer.queue_redraw()
				game._refresh()
				game._close_overlay()
				game._show_overlay("take_off"))


static func pickup_menu(game: Control, contents: VBoxContainer, target: Vector2i) -> void:
	_needs_banner(game, contents)
	var targets: Array[Vector2i] = []
	if target != NONE:
		targets.append(target)
	else:
		var pos: Vector2i = game.world.pos
		targets.append(pos)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				targets.append(pos + Vector2i(dx, dy))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var found_any := false
	for p: Vector2i in targets:
		var items: Array = game.world.items_at(p)
		if items.is_empty():
			continue
		found_any = true
		var header_row := HBoxContainer.new()
		header_row.add_theme_constant_override("separation", 8)
		body.add_child(header_row)
		var loc_tag := "脚下" if p == game.world.pos else "邻格 (%d, %d)" % [p.x, p.y]
		var lbl: Label = game._label(header_row, "◈ %s" % loc_tag, 13, UI.GOLD)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var all_btn: Button = game._button(header_row, "全部拾取", func():
			game._note(game.world.take_all_at(p))
			game.board.invalidate_world_cache()
			game._refresh()
			game._close_overlay()
			game._show_overlay("pickup", target), true)
		all_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		all_btn.custom_minimum_size = Vector2(90, 28)

		for row: Dictionary in items:
			var id: int = int(row["id"])
			var item_row := HBoxContainer.new()
			item_row.add_theme_constant_override("separation", 6)
			body.add_child(item_row)
			var desc := "%s × %d  [%s · %d ml · %d g]" % [
				row["name"], int(row["count"]), row["category"], int(row["volume_ml"]), int(row["weight_g"])]
			var take_btn: Button = game._button(item_row, "拾取：%s" % desc, func():
				game._note(game.world.take_item_at(p, id))
				game.board.invalidate_world_cache()
				game._refresh()
				game._close_overlay()
				game._show_overlay("pickup", target))
			if bool(row.get("is_food", false)) or bool(row.get("is_drink", false)):
				var eat_btn: Button = game._button(item_row, "直接吃喝", func():
					game._note(game.world.eat_item_at(p, id))
					game.board.invalidate_world_cache()
					game._refresh()
					game._close_overlay()
					game._show_overlay("pickup", target))
				eat_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				eat_btn.custom_minimum_size = Vector2(88, 34)
			elif bool(row.get("is_clothing", false)):
				var wear_btn: Button = game._button(item_row, "拾取并穿上", func():
					var msg: String = game.world.take_item_at(p, id)
					if msg.begins_with("你拿起了"):
						msg = game.world.wear_item(id)
					game._note(msg)
					game.board.invalidate_world_cache()
					game.board.player_layer.queue_redraw()
					game._refresh()
					game._close_overlay()
					game._show_overlay("pickup", target))
				wear_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				wear_btn.custom_minimum_size = Vector2(96, 34)

	if not found_any:
		game._label(body, "  此处及周围暂无散落物品。", 14, UI.INK_DIM)

	if target != NONE:
		var foot := HBoxContainer.new()
		foot.add_theme_constant_override("separation", 8)
		contents.add_child(foot)
		game._button(foot, "从行囊放入物品…", func():
			game._close_overlay()
			game._show_overlay("inventory", target))


static func character_sheet(game: Control, contents: VBoxContainer) -> void:
	var st: Dictionary = game.world.character_status()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_CARD, UI.BORDER_JADE, 4, 14, 10, 1))
	body.add_child(card)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	card.add_child(info)
	game._stat_row(info, "身份", "凡俗旅人", UI.INK_IVORY)
	game._stat_row(info, "所在", "%s · %s" % [game.world.location(game.world.pos), game._floor_name(game.world.floor)], UI.INK_IVORY)
	game._stat_row(info, "天时天气", "%s · %s" % [CanglingCalendar.time_label(game.world.minutes), game.weather.label()], UI.GOLD)
	game._stat_row(info, "饱食 / 热量", "%s（%d / %d kcal）" % [st.get("hunger_text", "正常"), int(st.get("kcal", 2400)), int(st.get("kcal_max", 3600))], UI.GOLD)
	game._stat_row(info, "水分 / 解渴", "%s（%d%%）" % [st.get("thirst_text", "正常"), int(st.get("hydration", 100))], UI.JADE)
	game._stat_row(info, "精力 / 疲惫", "%s（疲惫 %d%%）" % [st.get("fatigue_text", "尚可"), int(st.get("fatigue", 0))], UI.INK_SOFT)
	game._stat_row(info, "携带容积", "%d / %d ml（总重 %.2f kg）" % [int(st.get("carry_volume_ml", 0)), int(st.get("max_carry_volume_ml", 2500)), float(st.get("carry_weight_g", 0)) / 1000.0], UI.INK_SOFT)
	game._stat_row(info, "保暖 / 累赘", "保暖 %d · 累赘 %d" % [int(st.get("warmth", 0)), int(st.get("encumbrance", 0))], UI.INK_SOFT)

	game._label(body, "◈ 当前着装层级（按 W 穿戴 / T 脱下）", 13, UI.GOLD)
	var worn: Array = st.get("worn", [])
	if worn.is_empty():
		game._label(body, "  当前未穿戴任何衣物。", 13, UI.INK_DIM)
	else:
		for row: Dictionary in worn:
			var widx: int = int(row["worn_index"])
			var row_box := HBoxContainer.new()
			row_box.add_theme_constant_override("separation", 8)
			body.add_child(row_box)
			var lbl: Label = game._label(row_box, "· [%s] %s  （保暖+%d · 累赘+%d · 容积+%d ml）" % [
				row["slot"], row["name"], int(row["warmth"]), int(row["encumbrance"]), int(row["storage_ml"])], 13, UI.INK_IVORY)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var btn: Button = game._button(row_box, "脱下", func():
				game._note(game.world.take_off_item(widx))
				game.board.player_layer.queue_redraw()
				game._refresh()
				game._close_overlay()
				game._show_overlay("character"))
			btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			btn.custom_minimum_size = Vector2(68, 28)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	game._button(actions, "进食 / 饮水 (E)", func(): game._close_overlay(); game._show_overlay("eat"), true)
	game._button(actions, "穿戴衣物 (W)", func(): game._close_overlay(); game._show_overlay("wear"))


static func observe_sky_message(game: Control) -> String:
	var sky := CanglingCalendar.at_minute(game.world.minutes)
	var phase := UI.phase_info(sky)
	var w_label: String = game.weather.label()
	var indoors := false
	var p: Vector2i = game.world.pos
	if game.board.cells.has(p):
		indoors = (int(game.board.cells[p][3]) & 1) != 0
	if indoors:
		return "你身处室内屋檐之下，透过雕花木窗望见外头：%s，%s，天色为「%s」。" % [
			CanglingCalendar.time_label(game.world.minutes), w_label, phase[0]]
	return "你抬头仰望天际：%s，天气「%s」，此时正值「%s」（积水 %.0f%%，积雪 %.0f%%）。" % [
		CanglingCalendar.time_label(game.world.minutes), w_label, phase[0],
		float(game.weather.wetness) * 100.0, float(game.weather.snow_cover) * 100.0]
