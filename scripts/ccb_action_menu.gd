extends RefCounted

# Authentic CCB Enter Action Menu (modeled on Cataclysm-Cleanwater-Bomb src/action.cpp).
# Presents context-sensitive quick actions at top followed by categorized gameplay actions
# with registered CCB hotkeys and full keyboard/mouse selection.

const UI = preload("res://scripts/ui_theme.gd")


static func build_menu(game: Control, contents: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	# 1. Context-sensitive recommended actions (CCB action_weightings style)
	var quick := _contextual_actions(game)
	if not quick.is_empty():
		_add_section(game, body, "◈ 当前可用快捷动作", quick, true)

	# 2. Look / Observation (CCB category: look)
	_add_section(game, body, "◈ 观察与勘察", [
		["观察天空与天时", "sky", "—"],
		["环视周围地形", "look", "x / L"],
		["查看周围物品", "pickup", "g / ,"],
		["打开全城舆图", "map", "m"],
	])

	# 3. Interaction & Environment (CCB category: interact)
	_add_section(game, body, "◈ 交互与环境", [
		["检查 / 互动邻格（开柜取物）", "examine", "e"],
		["开门 / 开窗 / 打开柜门", "open", "o"],
		["关门 / 关窗 / 合上柜门", "close", "c"],
		["抓取 / 松开拖拽家具", "grab", "G"],
		["上楼梯", "stairs_up", "<"],
		["下楼梯", "stairs_down", ">"],
	])

	# 4. Inventory, Eating & Clothing (CCB category: inventory)
	_add_section(game, body, "◈ 物品、饮食与着装", [
		["打开随身行囊", "inventory", "i"],
		["进食 / 饮水", "eat", "E"],
		["穿戴衣物", "wear", "W"],
		["脱下 / 整理着装", "take_off", "T / +"],
		["丢弃行囊物品", "drop", "D"],
	])

	# 5. Status, Rest & Misc (CCB category: info / misc)
	_add_section(game, body, "◈ 人物状态与休整", [
		["查看人物与着装状态", "character", "@"],
		["静候一段时间", "wait", "|"],
		["小睡 / 原地歇息", "sleep", "$"],
		["保存进度", "save", "—"],
		["读取存档", "load", "—"],
		["调试菜单", "debug", "K"],
	])


static func _contextual_actions(game: Control) -> Array:
	var list: Array = []
	var world: Object = game.world
	if world.is_grabbing():
		list.append(["松开当前拖拽的家具", "grab", "G"])
	if game.board.motion.is_resting():
		list.append(["起身继续赶路", "stand", "方向键"])
	var status: Dictionary = world.character_status()
	if int(status.get("kcal", 2400)) < 1650 or int(status.get("hydration", 100)) < 60:
		list.append(["进食 / 饮水（当前：%s / %s）" % [status.get("hunger_text", ""), status.get("thirst_text", "")], "eat", "E"])
	# Check adjacent tiles for doors, beds/chairs, containers, or loose items
	var has_openable := false
	var has_seat_or_bed := false
	var has_items := false
	var pos: Vector2i = world.pos
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := pos + Vector2i(dx, dy)
			var t: String = world.terrain_at(p)
			if t in ["D", "w", "c", "C", "F", "K"]:
				has_openable = true
			if t in ["b", "q", "S"]:
				has_seat_or_bed = true
			if not world.items_at(p).is_empty():
				has_items = true
	if has_openable:
		list.append(["开门 / 开窗 / 打开柜门", "open", "o"])
	if has_items:
		list.append(["拾取周围物品", "pickup", "g"])
	if has_seat_or_bed and not game.board.motion.is_resting():
		list.append(["在身旁床榻 / 椅凳歇息", "rest_nearby", "$"])
	return list


static func _add_section(game: Control, parent: VBoxContainer, title: String, entries: Array, primary := false) -> void:
	game._label(parent, title, 13, UI.GOLD if primary else UI.INK_SOFT)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for spec: Array in entries:
		var label_text: String = "%s   [%s]" % [spec[0], spec[2]]
		var act_id: String = spec[1]
		var btn: Button = game._button(grid, label_text, func():
			game._close_overlay()
			game._run_ccb_action(act_id), primary)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
