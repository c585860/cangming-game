extends RefCounted

# Authentic Cataclysm-Cleanwater-Bomb (CCB) Enter Action Menu
# (modeled on Cataclysm-Cleanwater-Bomb/src/action.cpp).
# Crisp dark terminal list with lettered selection ('a - ...', 'b - ...') and exact CCB hotkeys.

const CCB = preload("res://scripts/ccb_theme.gd")


static func build_menu(game: Control, contents: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var idx := 0
	var quick := _contextual_actions(game)
	if not quick.is_empty():
		idx = _add_section(game, body, "[ 当前推荐动作 ]", quick, idx, true)

	idx = _add_section(game, body, "[ 观察与勘察 ]", [
		["观察天空与天时", "sky", "—"],
		["环视周围地形", "look", "x / ;"],
		["探头窥视邻格", "peek", "X"],
		["列出周边物品与设施", "list_nearby", "V"],
		["打开全城舆图", "map", "m"],
	], idx)

	idx = _add_section(game, body, "[ 世界互动 ]", [
		["检查 / 翻越障碍 (篱/窗/桌)", "examine", "e"],
		["开门 / 开窗 / 打开柜门", "open", "o"],
		["关门 / 关窗 / 合上柜门", "close", "c"],
		["砸碎门窗 / 木篱 / 家具", "smash", "s"],
		["抓取 / 松开拖拽家具", "grab", "G"],
		["开关地面物品拖运", "haul", "\\"],
		["与身旁人物交谈", "chat", "C"],
		["上楼梯", "stairs_up", "<"],
		["下楼梯", "stairs_down", ">"],
	], idx)

	idx = _add_section(game, body, "[ 物品、饮食与着装 ]", [
		["拾取周围物品", "pickup", "g / ,"],
		["打开随身行囊", "inventory", "i"],
		["手持物品 / 空手", "wield", "w"],
		["使用 / 激活物品 (点灯/包扎)", "apply", "a"],
		["进食 / 饮水", "eat", "E"],
		["穿戴衣物", "wear", "W"],
		["脱下 / 整理着装", "take_off", "T / +"],
		["阅读随身书籍", "read", "R"],
		["丢弃物品到脚下", "drop", "d"],
		["选择方向丢弃物品", "drop_dir", "D"],
	], idx)

	idx = _add_section(game, body, "[ 状态与系统 ]", [
		["江湖技能面板 (武学/武道/练气/仙道)", "skills", "J"],
		["多人联机接口设置 (Multiplayer)", "multiplayer", "O"],
		["切换移动姿态 (走/跑/潜/匍)", "move_mode", "\""],
		["人物属性与着装状态", "character", "@"],
		["当前委托进展", "missions", "M"],
		["历史消息日志", "messages", "P"],
		["静候一段时间", "wait", "|"],
		["躺床 / 坐椅 / 原地小憩", "sleep", "$"],
		["开关安全模式", "safe_mode", "!"],
		["保存游戏", "save", "S"],
		["读取存档", "load", "—"],
		["键位帮助一览", "help", "? / 0"],
		["调试菜单", "debug", "K"],
	], idx)


static func _contextual_actions(game: Control) -> Array:
	var list: Array = []
	var world: Object = game.world
	if world.is_grabbing():
		list.append(["松开当前拖拽的家具", "grab", "G"])
	var status: Dictionary = world.character_status()
	if bool(status.get("hauling", false)):
		list.append(["停止拖运地面物品", "haul", "\\"])
	if game.board.motion.is_resting():
		list.append(["起身继续赶路", "stand", "方向键"])
	if int(status.get("kcal", 2400)) < 1650 or int(status.get("hydration", 100)) < 60:
		list.append(["进食 / 饮水 (当前:%s / %s)" % [status.get("hunger_text", ""), status.get("thirst_text", "")], "eat", "E"])

	var has_openable := false
	var has_climbable := false
	var has_seat_or_bed := false
	var has_items := false
	var pos: Vector2i = world.pos
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := pos + Vector2i(dx, dy)
			var t: String = world.terrain_at(p)
			if t in ["D", "w", "c", "C", "F", "K"]:
				has_openable = true
			if t in ["f", "O", "%", "t", "l", "k"]:
				has_climbable = true
			if t in ["b", "q", "S"]:
				has_seat_or_bed = true
			if not world.items_at(p).is_empty():
				has_items = true
	if has_openable:
		list.append(["开门 / 开窗 / 打开柜门", "open", "o"])
	if has_climbable:
		list.append(["翻越身旁木篱 / 窗户 / 桌案", "examine", "e"])
	if has_items:
		list.append(["拾取周围物品", "pickup", "g"])
	if has_seat_or_bed and not game.board.motion.is_resting():
		list.append(["在身旁床榻 / 椅凳歇息", "sleep", "$"])
	return list


static func _add_section(game: Control, parent: VBoxContainer, title: String, entries: Array, start_idx: int, primary := false) -> int:
	game._label(parent, title, 12, CCB.C_YELLOW if primary else CCB.C_CYAN)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	var idx := start_idx
	for spec: Array in entries:
		var letter := CCB.letter_key(idx)
		var label_text := "%s - %s   [%s]" % [letter, str(spec[0]), str(spec[2])]
		var act_id: String = str(spec[1])
		var cb := func():
			game._close_overlay()
			game._run_ccb_action(act_id)
		var btn: Button = game._button(grid, label_text, cb, primary)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if letter != "-":
			game.register_overlay_hotkey(letter, cb)
		idx += 1
	return idx
