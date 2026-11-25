extends RefCounted

# Authentic Cataclysm-Cleanwater-Bomb (CCB) Classic Dark Terminal UI Panels.
# Every dialog uses sharp 1px terminal borders, CCB curses colors, and lettered
# keyboard selection ('a - ...', 'b - ...') registered via game.register_overlay_hotkey().

const CCB = preload("res://scripts/ccb_theme.gd")
const CanglingCalendar = preload("res://scripts/cangling_calendar.gd")
const NONE := Vector2i(-1, -1)


static func _needs_banner(game: Control, parent: VBoxContainer) -> void:
	var st: Dictionary = game.world.character_status()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 5, 1))
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	game._label(col, "饱食:%s(%dkcal) | 水分:%s(%d%%) | 精力:%s | 耐力:%d%% | 手持:%s" % [
		str(st.get("hunger_text", "正常")), int(st.get("kcal", 2400)),
		str(st.get("thirst_text", "正常")), int(st.get("hydration", 100)),
		str(st.get("fatigue_text", "尚可")), int(round(float(st.get("stamina", 10000)) / 100.0)),
		str(st.get("wielded_name", "空手"))], 12, CCB.C_YELLOW)
	game._label(col, "容积:%d/%d ml | 负重:%.2f kg | 保暖:%d | 累赘:%d | 水壶:%d/%d ml" % [
		int(st.get("carry_volume_ml", 0)), int(st.get("max_carry_volume_ml", 2500)),
		float(st.get("carry_weight_g", 0)) / 1000.0,
		int(st.get("warmth", 0)), int(st.get("encumbrance", 0)),
		int(game.world.bottle_water()), int(game.world.bottle_capacity())], 12, CCB.C_LTGRAY)


static func _make_scroll_body(parent: VBoxContainer, gap := 4) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", gap)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body


static func _letter_row(game: Control, parent: Node, idx: int, label_text: String, callback: Callable, highlight := false) -> Button:
	var letter := CCB.letter_key(idx)
	var btn: Button = game._button(parent, "%s - %s" % [letter, label_text], callback, highlight)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if letter != "-":
		game.register_overlay_hotkey(letter, callback)
	return btn


static func eat_menu(game: Control, contents: VBoxContainer) -> void:
	_needs_banner(game, contents)
	var body := _make_scroll_body(contents, 4)
	var idx := 0

	if int(game.world.bottle_water()) > 0:
		game._label(body, "[ 随身水壶 ]", 12, CCB.C_CYAN)
		var drink_ml := mini(250, int(game.world.bottle_water()))
		_letter_row(game, body, idx, "喝一口清水 (%d ml，剩余 %d ml)" % [drink_ml, int(game.world.bottle_water())], func():
			game._note(game.world.drink_bottle(drink_ml))
			game._refresh()
			game._reopen_overlay("eat"), true)
		idx += 1

	var bag: Array = game.world.inventory()
	var edibles: Array = []
	for row: Dictionary in bag:
		if bool(row.get("is_food", false)) or bool(row.get("is_drink", false)):
			edibles.append(row)
	game._label(body, "[ 行囊中的食物与饮品 ]", 12, CCB.C_CYAN)
	if edibles.is_empty():
		game._label(body, "  (行囊中暂无可食用或饮用的物品)", 12, CCB.C_DKGRAY)
	else:
		for row: Dictionary in edibles:
			var id: int = int(row["id"])
			var verb := "饮用" if bool(row["is_drink"]) else "食用"
			var info := "%s: %s x%d  (热量 %+d kcal, 解渴 %+d)" % [
				verb, str(row["name"]), int(row["count"]), int(row["kcal"]), int(row["quench"])]
			_letter_row(game, body, idx, info, func():
				game._note(game.world.eat_item(id))
				game._refresh()
				game._reopen_overlay("eat"))
			idx += 1

	var nearby: Array = []
	var pos: Vector2i = game.world.pos
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := pos + Vector2i(dx, dy)
			for row: Dictionary in game.world.items_at(p):
				if bool(row.get("is_food", false)) or bool(row.get("is_drink", false)):
					nearby.append([p, row])
	if not nearby.is_empty():
		game._label(body, "[ 身旁桌面 / 地面上的食物与饮品 ]", 12, CCB.C_CYAN)
		for entry: Array in nearby:
			var p: Vector2i = entry[0]
			var row: Dictionary = entry[1]
			var id: int = int(row["id"])
			var verb := "直接饮用" if bool(row["is_drink"]) else "直接食用"
			_letter_row(game, body, idx, "%s: %s x%d  (热量 %+d, 解渴 %+d)" % [
				verb, str(row["name"]), int(row["count"]), int(row["kcal"]), int(row["quench"])], func():
				game._note(game.world.eat_item_at(p, id))
				game.board.invalidate_world_cache()
				game._refresh()
				game._reopen_overlay("eat"))
			idx += 1


static func wear_menu(game: Control, contents: VBoxContainer) -> void:
	_needs_banner(game, contents)
	var body := _make_scroll_body(contents, 4)
	var bag: Array = game.world.inventory()
	var clothes: Array = []
	for row: Dictionary in bag:
		if bool(row.get("is_clothing", false)):
			clothes.append(row)
	game._label(body, "[ 选择穿戴衣物 (每部位最多叠穿 2 层，按对应字母穿戴) ]", 12, CCB.C_CYAN)
	if clothes.is_empty():
		game._label(body, "  (行囊中没有未穿戴的衣物。按 o 或 e 打开衣柜/木柜搜寻衣物)", 12, CCB.C_DKGRAY, true)
		return
	var idx := 0
	for row: Dictionary in clothes:
		var id: int = int(row["id"])
		var text := "穿上 %s x%d  [%s | 保暖+%d | 累赘+%d | 容积+%d ml]" % [
			str(row["name"]), int(row["count"]), str(row["slot"]),
			int(row["warmth"]), int(row["encumbrance"]), int(row["storage_ml"])]
		_letter_row(game, body, idx, text, func():
			game._note(game.world.wear_item(id))
			game.board.player_layer.queue_redraw()
			game._refresh()
			game._reopen_overlay("wear"), true)
		idx += 1


static func take_off_menu(game: Control, contents: VBoxContainer) -> void:
	_needs_banner(game, contents)
	var body := _make_scroll_body(contents, 4)
	var st: Dictionary = game.world.character_status()
	var worn: Array = st.get("worn", [])
	game._label(body, "[ 当前着装层级 (按字母或点击脱下并收入行囊) ]", 12, CCB.C_CYAN)
	if worn.is_empty():
		game._label(body, "  (当前未穿戴任何衣物)", 12, CCB.C_DKGRAY)
		return
	var idx := 0
	for row: Dictionary in worn:
		var widx: int = int(row["worn_index"])
		var text := "脱下 [%s] %s  (保暖+%d | 累赘+%d | 容积+%d ml)" % [
			str(row["slot"]), str(row["name"]),
			int(row["warmth"]), int(row["encumbrance"]), int(row["storage_ml"])]
		_letter_row(game, body, idx, text, func():
			game._note(game.world.take_off_item(widx))
			game.board.player_layer.queue_redraw()
			game._refresh()
			game._reopen_overlay("take_off"))
		idx += 1


static func wield_menu(game: Control, contents: VBoxContainer) -> void:
	_needs_banner(game, contents)
	var body := _make_scroll_body(contents, 4)
	var st: Dictionary = game.world.character_status()
	var wielded_id: int = int(st.get("wielded_id", -1))
	var idx := 0

	if wielded_id >= 0:
		game._label(body, "[ 当前手持 ]", 12, CCB.C_CYAN)
		_letter_row(game, body, idx, "收起「%s」改为空手" % str(st.get("wielded_name", "")), func():
			game._note(game.world.unwield())
			game._refresh()
			game._close_overlay(), true)
		idx += 1

	game._label(body, "[ 从行囊选择手持物品 (提高砸物破拆力 / 按 A 直接使用手持物) ]", 12, CCB.C_CYAN)
	var bag: Array = game.world.inventory()
	if bag.is_empty():
		game._label(body, "  (行囊为空)", 12, CCB.C_DKGRAY)
		return
	for row: Dictionary in bag:
		var id: int = int(row["id"])
		var b_dmg: int = int(row.get("bash_dmg", 0))
		var info := "%s x%d  [%s | 砸击+%d | %d g]" % [
			str(row["name"]), int(row["count"]), str(row["category"]), b_dmg, int(row["weight_g"])]
		_letter_row(game, body, idx, info, func():
			game._note(game.world.wield_item(id))
			game._refresh()
			game._close_overlay(), b_dmg >= 8)
		idx += 1


static func apply_menu(game: Control, contents: VBoxContainer) -> void:
	_needs_banner(game, contents)
	var body := _make_scroll_body(contents, 4)
	var st: Dictionary = game.world.character_status()
	var bag: Array = game.world.inventory()
	var idx := 0
	var found := false

	game._label(body, "[ 选择要使用/激活的物品 (工具 / 照明 / 医疗 / 书籍) ]", 12, CCB.C_CYAN)
	if int(st.get("wielded_id", -1)) >= 0:
		found = true
		_letter_row(game, body, idx, "[手持] 直接激活：%s" % str(st.get("wielded_name", "")), func():
			game._note(game.world.apply_wielded())
			game.board.player_layer.queue_redraw()
			game._refresh()
			game._close_overlay(), true)
		idx += 1

	for row: Dictionary in bag:
		var usable := bool(row.get("is_tool", false)) or bool(row.get("is_medical", false)) or bool(row.get("is_book", false))
		if not usable:
			continue
		found = true
		var id: int = int(row["id"])
		var info := "%s x%d  [%s] — %s" % [
			str(row["name"]), int(row["count"]), str(row["category"]), str(row.get("desc", ""))]
		_letter_row(game, body, idx, info, func():
			game._note(game.world.apply_item(id))
			game.board.player_layer.queue_redraw()
			game._refresh()
			game._close_overlay())
		idx += 1

	if not found:
		game._label(body, "  (行囊中没有可激活的工具、照明灯具、纱布或书籍)", 12, CCB.C_DKGRAY)


static func read_menu(game: Control, contents: VBoxContainer) -> void:
	_needs_banner(game, contents)
	var body := _make_scroll_body(contents, 4)
	var bag: Array = game.world.inventory()
	var idx := 0
	game._label(body, "[ 选择要研读的书籍 (按字母开始阅读，耗时 25 分钟) ]", 12, CCB.C_CYAN)
	for row: Dictionary in bag:
		if not bool(row.get("is_book", false)):
			continue
		var id: int = int(row["id"])
		_letter_row(game, body, idx, "%s x%d — %s" % [str(row["name"]), int(row["count"]), str(row.get("desc", ""))], func():
			game._note(game.world.read_book(id))
			game._refresh()
			game._close_overlay(), true)
		idx += 1
	if idx == 0:
		game._label(body, "  (行囊中暂无书籍。可在民居书架 r 或书案 l 上拾取线装古籍)", 12, CCB.C_DKGRAY, true)


static func move_mode_menu(game: Control, contents: VBoxContainer) -> void:
	var st: Dictionary = game.world.character_status()
	var cur: int = int(st.get("move_mode", 0))
	game._label(contents, "[ 切换移动姿态 (\") — 影响移动耗时、声响与耐力消耗 ]", 12, CCB.C_CYAN)
	var specs := [
		[0, "行走  (默认姿态，速度正常，声响 6，不耗耐力)"],
		[1, "奔跑  (快速穿越障碍，声响 14，每步消耗耐力)"],
		[2, "潜行  (压低脚步，声响 2，移动耗时稍增)"],
		[3, "匍匐  (静默伏地前行，声响 0，移动较慢)"],
	]
	for i in range(specs.size()):
		var mode_id: int = specs[i][0]
		var desc: String = specs[i][1]
		var tag := "  <当前>" if mode_id == cur else ""
		_letter_row(game, contents, i, desc + tag, func():
			game._note(game.world.set_move_mode(mode_id))
			game.board.markers.queue_redraw()
			game._refresh()
			game._close_overlay(), mode_id == cur)


static func list_nearby_menu(game: Control, contents: VBoxContainer) -> void:
	game._label(contents, "[ 周边物品与重要设施清单 (V) — 半径 12 格，按字母或点击自动寻路前往 ]", 12, CCB.C_CYAN)
	var rows: Array = game.world.list_nearby(12)
	var body := _make_scroll_body(contents, 3)
	if rows.is_empty():
		game._label(body, "  (周围 12 格内暂无可见物品或重要设施)", 12, CCB.C_DKGRAY)
		return
	var idx := 0
	for row: Dictionary in rows:
		var kind: String = str(row.get("kind", "item"))
		var pos: Vector2i = row.get("pos", Vector2i.ZERO)
		var dir: String = str(row.get("dir", ""))
		var dist: int = int(row.get("dist", 0))
		var line := ""
		if kind == "item":
			line = "[物] %s x%d  (%s %d格 · %s)" % [
				str(row.get("name", "")), int(row.get("count", 1)), dir, dist, str(row.get("tile_label", ""))]
		else:
			line = "[景] %s  (%s %d格)" % [str(row.get("name", "")), dir, dist]
		_letter_row(game, body, idx, line, func():
			game._close_overlay()
			game._begin_route(pos, "loot" if kind == "item" and dist <= 1 else ""), kind == "item")
		idx += 1
		if idx >= 48:
			break


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

	var body := _make_scroll_body(contents, 5)
	var found_any := false
	var idx := 0
	for p: Vector2i in targets:
		var items: Array = game.world.items_at(p)
		if items.is_empty():
			continue
		found_any = true
		var header_row := HBoxContainer.new()
		header_row.add_theme_constant_override("separation", 6)
		body.add_child(header_row)
		var loc_tag := "脚下" if p == game.world.pos else "邻格 (%d, %d)" % [p.x, p.y]
		var lbl: Label = game._label(header_row, "[ %s ]" % loc_tag, 12, CCB.C_YELLOW)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var all_btn: Button = game._button(header_row, ", - 全部拾取", func():
			game._note(game.world.take_all_at(p))
			game.board.invalidate_world_cache()
			game._refresh()
			game._reopen_overlay("pickup", target), true)
		all_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		all_btn.custom_minimum_size = Vector2(104, 26)
		if targets.size() == 1 or p == game.world.pos:
			game.register_overlay_hotkey(",", func():
				game._note(game.world.take_all_at(p))
				game.board.invalidate_world_cache()
				game._refresh()
				game._reopen_overlay("pickup", target))

		for row: Dictionary in items:
			var id: int = int(row["id"])
			var item_row := HBoxContainer.new()
			item_row.add_theme_constant_override("separation", 5)
			body.add_child(item_row)
			var desc := "%s x%d  [%s | %d ml | %d g]" % [
				str(row["name"]), int(row["count"]), str(row["category"]), int(row["volume_ml"]), int(row["weight_g"])]
			_letter_row(game, item_row, idx, desc, func():
				game._note(game.world.take_item_at(p, id))
				game.board.invalidate_world_cache()
				game._refresh()
				game._reopen_overlay("pickup", target))
			idx += 1
			if bool(row.get("is_food", false)) or bool(row.get("is_drink", false)):
				var eat_btn: Button = game._button(item_row, "吃喝", func():
					game._note(game.world.eat_item_at(p, id))
					game.board.invalidate_world_cache()
					game._refresh()
					game._reopen_overlay("pickup", target))
				eat_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				eat_btn.custom_minimum_size = Vector2(64, 28)
			elif bool(row.get("is_clothing", false)):
				var wear_btn: Button = game._button(item_row, "穿上", func():
					var msg: String = game.world.take_item_at(p, id)
					if msg.begins_with("你拿起了"):
						msg = game.world.wear_item(id)
					game._note(msg)
					game.board.invalidate_world_cache()
					game.board.player_layer.queue_redraw()
					game._refresh()
					game._reopen_overlay("pickup", target))
				wear_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				wear_btn.custom_minimum_size = Vector2(64, 28)

	if not found_any:
		game._label(body, "  (此处及周围暂无可见物品)", 12, CCB.C_DKGRAY)

	if target != NONE:
		var foot := HBoxContainer.new()
		foot.add_theme_constant_override("separation", 8)
		contents.add_child(foot)
		game._button(foot, "从行囊放入物品到此位置…", func():
			game._close_overlay()
			game._show_overlay("inventory", target))


static func character_sheet(game: Control, contents: VBoxContainer) -> void:
	var st: Dictionary = game.world.character_status()
	var body := _make_scroll_body(contents, 8)

	# 3-column CCB @ summary
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)

	var c1 := PanelContainer.new()
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c1.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 6, 1))
	top.add_child(c1)
	var v1 := VBoxContainer.new()
	v1.add_theme_constant_override("separation", 3)
	c1.add_child(v1)
	game._label(v1, "[ 基础属性 ]", 12, CCB.C_CYAN)
	game._label(v1, "力量 STR: %d   敏捷 DEX: %d" % [int(st.get("str", 8)), int(st.get("dex", 8))], 13, CCB.C_WHITE)
	game._label(v1, "智力 INT: %d   感知 PER: %d" % [int(st.get("int", 8)), int(st.get("per", 8))], 13, CCB.C_WHITE)
	game._label(v1, "速度: %d   专注: %d   破拆力: %d" % [int(st.get("speed", 100)), int(st.get("focus", 100)), int(st.get("bash_power", 12))], 12, CCB.C_YELLOW)
	game._label(v1, "手持: %s" % str(st.get("wielded_name", "空手")), 12, CCB.C_LTCYAN)

	var c2 := PanelContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c2.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 6, 1))
	top.add_child(c2)
	var v2 := VBoxContainer.new()
	v2.add_theme_constant_override("separation", 3)
	c2.add_child(v2)
	game._label(v2, "[ 生理与状态 ]", 12, CCB.C_CYAN)
	game._label(v2, "饱食: %s (%d/%d kcal)" % [str(st.get("hunger_text", "")), int(st.get("kcal", 2400)), int(st.get("kcal_max", 3600))], 12, CCB.C_WHITE)
	game._label(v2, "水分: %s (%d%%)  精力: %s" % [str(st.get("thirst_text", "")), int(st.get("hydration", 100)), str(st.get("fatigue_text", ""))], 12, CCB.C_WHITE)
	game._label(v2, "耐力: %d%%   疼痛: %s   姿态: %s" % [int(round(float(st.get("stamina", 10000)) / 100.0)), str(st.get("pain_text", "无痛")), str(st.get("move_mode_text", "行走"))], 12, CCB.C_LTGRAY)
	game._label(v2, "容积: %d/%d ml  负重: %.2f kg  保暖:%d  累赘:%d" % [
		int(st.get("carry_volume_ml", 0)), int(st.get("max_carry_volume_ml", 2500)),
		float(st.get("carry_weight_g", 0)) / 1000.0, int(st.get("warmth", 0)), int(st.get("encumbrance", 0))], 12, CCB.C_LTGRAY)

	# Body part HP table
	var hp_arr: Array = st.get("part_hp", [84, 84, 84, 84, 84, 84])
	var max_hp: int = int(st.get("max_part_hp", 84))
	var names := ["头部", "躯干", "左臂", "右臂", "左腿", "右腿"]
	var hp_line := ""
	for i in range(mini(6, hp_arr.size())):
		hp_line += "%s:%d/%d  " % [names[i], int(hp_arr[i]), max_hp]
	game._label(body, "[ 肢体健康 ]  " + hp_line, 12, CCB.C_LTGREEN, true)

	game._label(body, "[ 当前着装层级 (按字母脱下 / W穿戴) ]", 12, CCB.C_CYAN)
	var worn: Array = st.get("worn", [])
	if worn.is_empty():
		game._label(body, "  (当前未穿戴衣物)", 12, CCB.C_DKGRAY)
	else:
		var idx := 0
		for row: Dictionary in worn:
			var widx: int = int(row["worn_index"])
			_letter_row(game, body, idx, "[%s] %s  (保暖+%d | 累赘+%d | 容积+%d ml)  [点击脱下]" % [
				str(row["slot"]), str(row["name"]),
				int(row["warmth"]), int(row["encumbrance"]), int(row["storage_ml"])], func():
				game._note(game.world.take_off_item(widx))
				game.board.player_layer.queue_redraw()
				game._refresh()
				game._reopen_overlay("character"))
			idx += 1

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	body.add_child(actions)
	game._button(actions, "进食/饮水 (E)", func(): game._close_overlay(); game._show_overlay("eat"), true)
	game._button(actions, "穿戴衣物 (W)", func(): game._close_overlay(); game._show_overlay("wear"))
	game._button(actions, "手持物品 (w)", func(): game._close_overlay(); game._show_overlay("wield"))


static func messages_menu(game: Control, contents: VBoxContainer) -> void:
	game._label(contents, "[ 历史消息日志 (P) — 按 Esc 关闭 ]", 12, CCB.C_CYAN)
	var body := _make_scroll_body(contents, 3)
	var hist: Array[Dictionary] = game.sidebar.get_history()
	if hist.is_empty():
		game._label(body, "  (暂无历史消息)", 12, CCB.C_DKGRAY)
		return
	for entry: Dictionary in hist:
		game._label(body, "[%s] %s" % [str(entry["clock"]), str(entry["text"])], 12, entry["color"], true)


static func missions_menu(game: Control, contents: VBoxContainer) -> void:
	game._label(contents, "[ 当前委托与进展 (M) ]", 12, CCB.C_CYAN)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER_CYAN, 10, 8, 1))
	contents.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	game._label(col, "当前目标：%s" % str(game.world.quest_text), 14, CCB.C_YELLOW, true)
	game._label(col, "修为境界：%s  |  铜钱：%d 文  |  清露草：%d / 3 株" % [
		"引气一层" if int(game.world.quest) == 4 else "凡俗旅人", int(game.world.coins), int(game.world.herbs)], 13, CCB.C_WHITE)
	game._label(col, "当前所在：%s (%d, %d)" % [str(game.world.location(game.world.pos)), game.world.pos.x, game.world.pos.y], 12, CCB.C_LTGRAY)


static func help_menu(game: Control, contents: VBoxContainer) -> void:
	game._label(contents, "[ CCB 原版键位对照表 (? / 0) — 大写键直接检测大写字母，支持 CapsLock 或 Shift ]", 12, CCB.C_YELLOW, true)
	var body := _make_scroll_body(contents, 4)
	var groups := [
		["移动与观察", [
			"小键盘 1-9 / 方向键 / vi键(h,j,k,l,y,u,b,n) : 八方向移动 (不占用 WASD)",
			". / 5 / 小键盘5 : 原地等待 1 分钟 (长按流逝时间)",
			"\" : 切换移动姿态 (行走 / 奔跑 / 潜行 / 匍匐)",
			"x / ; : 环视周围地形   |   X : 探头窥视邻格",
			"V : 列出周围物品与设施并自动寻路   |   m : 全城大地图",
			"z / Z : 放大 / 缩小视野",
		]],
		["世界互动 (完整移植 CCB)", [
			"Enter : 打开 CCB 动作菜单",
			"o : 开门 / 开窗 / 打开柜门   |   c : 关门 / 关窗 / 合上柜门",
			"s : 砸碎门窗、木篱、家具与陶缸 (窗户砸碎后可直接翻越)",
			"e : 检查 / 互动邻格 (开柜取物 / 翻越木篱、开窗、碎窗、桌案)",
			"G : 抓取 / 松开拖拽家具   |   \\ : 开关地面物品拖运",
			"< / > : 上楼梯 / 下楼梯   |   C : 与身旁人物交谈",
		]],
		["物品、饮食、工具与着装", [
			"g / , : 拾取周围物品   |   i : 打开随身行囊",
			"d : 丢弃物品到脚下   |   D : 选择方向丢弃物品",
			"w : 手持物品 / 换回空手   |   a : 使用物品 (点灯/包扎/火折子)",
			"A : 直接使用当前手持物品   |   R : 阅读随身书籍",
			"E : 进食 / 饮水   |   W : 穿戴衣物   |   T / + : 脱下与整理着装",
		]],
		["角色与系统", [
			"@ : 人物状态、肢体健康与着装页   |   M : 委托任务   |   P : 消息日志",
			"| : 静候一段时间   |   $ : 躺床/坐椅/原地小憩   |   ! : 开关安全模式",
			"S : 保存游戏   |   Esc : 取消 / 系统菜单   |   K : 调试菜单",
		]],
	]
	for g in groups:
		game._label(body, "── %s ──" % g[0], 12, CCB.C_CYAN)
		for line: String in g[1]:
			game._label(body, "  " + line, 12, CCB.C_WHITE, true)


static func observe_sky_message(game: Control) -> String:
	var sky := CanglingCalendar.at_minute(game.world.minutes)
	var phase := CCB.phase_label_color(sky)
	var w_label: String = game.weather.label()
	var indoors := false
	var p: Vector2i = game.world.pos
	if game.board.cells.has(p):
		indoors = (int(game.board.cells[p][3]) & 1) != 0
	if indoors:
		return "你身处室内屋檐之下，透过窗棂望见外头：%s，%s，天色「%s」。" % [
			CanglingCalendar.time_label(game.world.minutes), w_label, phase[0]]
	return "你抬头仰望天际：%s，天气「%s」，此时正值「%s」(积水 %.0f%%，积雪 %.0f%%)。" % [
		CanglingCalendar.time_label(game.world.minutes), w_label, phase[0],
		float(game.weather.wetness) * 100.0, float(game.weather.snow_cover) * 100.0]
