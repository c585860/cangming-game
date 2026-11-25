extends Control

const World = preload("res://scripts/world.gd")
const Board = preload("res://scripts/board.gd")
const Survey = preload("res://scripts/survey.gd")
const Atlas = preload("res://scripts/city_atlas.gd")
const Items = preload("res://scripts/item_ui.gd")
const ActionMenu = preload("res://scripts/ccb_action_menu.gd")
const CCBUI = preload("res://scripts/ccb_ui.gd")
const CanglingCalendar = preload("res://scripts/cangling_calendar.gd")
const Weather = preload("res://scripts/weather.gd")
const MoveInput = preload("res://scripts/move_input.gd")
const UI = preload("res://scripts/ui_theme.gd")
const INK := UI.INK_IVORY
const SOFT := UI.INK_SOFT
const GOLD := UI.GOLD
const LINE := UI.BORDER_JADE
const NONE := Vector2i(-1, -1)

var world := World.new()
var weather := Weather.new()
var move_input := MoveInput.new()
var board: Board
var time_text: Label
var phase_pill: PanelContainer
var phase_label: Label
var weather_pill: PanelContainer
var weather_label: Label
var location_text: Label
var floor_label: Label
var quest_text: Label
var realm_badge: PanelContainer
var realm_label: Label
var stats_text: Label
var resources_text: Label
var needs_text: Label
var status_text: Label
var pending_dir_action := ""
var journal: VBoxContainer
var action_menu: PopupMenu
var action_cell := NONE
var action_ids := PackedStringArray()
var walker: Timer
var pending_site := NONE
var pending_action := ""
var minimap: Survey
var overlay_backdrop: ColorRect
var overlay: PanelContainer
var opened := ""
var look_at := NONE
var atlas: Atlas
var atlas_cells := PackedByteArray()
var atlas_seed := -1
var wait_timer: Timer
var wait_remaining := 0
var period_timer: Timer
var period_key: Key = KEY_NONE


func _ready() -> void:
	world.setup(randi())
	weather.sync(CanglingCalendar.at_minute(world.minutes), world.seed, true)
	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(["Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC", "sans-serif"])
	theme = Theme.new()
	theme.default_font = ui_font
	theme.default_font_size = 15
	_build_ui()
	_note("晨雾贴着河面。你从南门外抵达沧菱城。")
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG_DEEP
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var page := MarginContainer.new()
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		page.add_theme_constant_override("margin_" + side, 10)
	var layout := _column(page, 8)

	# Top header plaque
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_HEADER, UI.BORDER_JADE, 4, 12, 7, 1))
	layout.add_child(header_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	header_panel.add_child(top)
	UI.seal_stamp(top, "沧")
	var title_box := HBoxContainer.new()
	title_box.add_theme_constant_override("separation", 10)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)
	var title := _label(title_box, "沧菱城", 22, GOLD)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var subtitle := _label(title_box, "云梦水乡 · 古镇", 13, UI.INK_DIM)
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	weather_pill = PanelContainer.new()
	weather_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	weather_label = _label(weather_pill, "晴朗", 13, GOLD)
	top.add_child(weather_pill)

	phase_pill = PanelContainer.new()
	phase_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	phase_label = _label(phase_pill, "晨曦", 13, GOLD)
	top.add_child(phase_pill)

	for spec in [["大地图", "map"], ["背包", "inventory"], ["角色", "character"], ["菜单", "pause"]]:
		var nav := _button(top, spec[0], _show_overlay.bind(spec[1]))
		nav.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		nav.custom_minimum_size = Vector2(72, 32)

	# Main split: Framed Viewport + Scroll Sidebar
	var center := HBoxContainer.new()
	center.add_theme_constant_override("separation", 10)
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(center)

	var board_frame := PanelContainer.new()
	board_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_frame.add_theme_stylebox_override("panel", UI.panel_box(Color("090d0b"), UI.BORDER_GOLD.lerp(UI.BORDER_JADE, 0.5), 4, 2, 2, 1))
	center.add_child(board_frame)
	board = Board.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.build(world, weather)
	board_frame.add_child(board)
	board.cell_clicked.connect(_map_clicked)
	board.context_requested.connect(_open_actions)

	var side_panel := PanelContainer.new()
	side_panel.custom_minimum_size.x = 276
	side_panel.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_PANEL, UI.BORDER_JADE, 4, 10, 10, 1))
	center.add_child(side_panel)
	var side := _column(side_panel, 9)
	side.clip_contents = true

	# Location + Time + Minimap Card
	var loc_row := HBoxContainer.new()
	loc_row.add_theme_constant_override("separation", 6)
	side.add_child(loc_row)
	location_text = _label(loc_row, "", 19, INK)
	location_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var floor_pill := PanelContainer.new()
	floor_pill.add_theme_stylebox_override("panel", UI.pill_box(Color("1b2722"), UI.BORDER_JADE, 7, 2))
	floor_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	floor_label = _label(floor_pill, "地面层", 12, UI.JADE)
	loc_row.add_child(floor_pill)

	time_text = _label(side, "", 13, GOLD)

	var map_frame := PanelContainer.new()
	map_frame.add_theme_stylebox_override("panel", UI.panel_box(Color("0c110e"), UI.BORDER_JADE, 3, 2, 2, 1))
	side.add_child(map_frame)
	minimap = Survey.new()
	minimap.custom_minimum_size.y = 142
	minimap.build(world)
	map_frame.add_child(minimap)

	# Status & Resources Card
	var status_card := PanelContainer.new()
	status_card.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_CARD, UI.BORDER_SOFT, 4, 9, 7, 1))
	side.add_child(status_card)
	var status_col := _column(status_card, 5)
	var stat_head := HBoxContainer.new()
	stat_head.add_theme_constant_override("separation", 6)
	status_col.add_child(stat_head)
	var stat_title := _label(stat_head, "◈ 行旅状态", 13, SOFT)
	stat_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	realm_badge = PanelContainer.new()
	realm_badge.add_theme_stylebox_override("panel", UI.pill_box(Color("1b221e"), UI.BORDER_JADE, 8, 1))
	realm_label = _label(realm_badge, "平民", 12, SOFT)
	stat_head.add_child(realm_badge)
	stats_text = _label(status_col, "", 14, INK)
	resources_text = _label(status_col, "", 13, SOFT)
	needs_text = _label(status_col, "", 12, UI.JADE, true)

	# Active Quest Card
	var quest_card := PanelContainer.new()
	quest_card.add_theme_stylebox_override("panel", UI.accent_card(Color("1b2019"), UI.BORDER_GOLD, UI.BORDER_SOFT, 10, 8))
	side.add_child(quest_card)
	var quest_col := _column(quest_card, 4)
	_label(quest_col, "◈ 当前委托", 13, GOLD)
	quest_text = _label(quest_col, "", 14, INK, true)
	quest_text.custom_minimum_size.y = 38

	# Journal Log
	side.add_child(UI.hairline())
	_label(side, "◈ 见闻录", 13, SOFT)
	var log_scroll := ScrollContainer.new()
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(log_scroll)
	journal = _column(log_scroll, 6)
	journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Bottom Status Footer
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_HEADER, UI.BORDER_SOFT, 3, 10, 4, 1))
	layout.add_child(footer)
	var foot_row := HBoxContainer.new()
	foot_row.add_theme_constant_override("separation", 12)
	footer.add_child(foot_row)
	status_text = _label(foot_row, "", 13, GOLD)
	status_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hints := _label(foot_row, "回车 动作菜单 · o开 c关 e查 g拾 G拖家具 · E吃 W穿 T脱 · i囊 @身 |候 · K调", 12, UI.INK_DIM)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	action_menu = PopupMenu.new()
	action_menu.theme = theme
	UI.style_popup(action_menu)
	add_child(action_menu)
	action_menu.id_pressed.connect(_choose_action)

	walker = Timer.new()
	walker.wait_time = 0.125
	add_child(walker)
	walker.timeout.connect(_walk)
	wait_timer = Timer.new()
	wait_timer.wait_time = 0.04
	add_child(wait_timer)
	wait_timer.timeout.connect(_advance_wait)
	period_timer = Timer.new()
	period_timer.one_shot = true
	add_child(period_timer)
	period_timer.timeout.connect(_repeat_period)
	get_window().focus_exited.connect(func():
		period_timer.stop()
		move_input.reset())
	set_process(true)


func _process(delta: float) -> void:
	if not opened.is_empty() or (action_menu != null and action_menu.visible):
		return
	var step := move_input.tick(delta)
	if step != Vector2i.ZERO:
		_apply_directional_step(step)


func _apply_directional_step(direction: Vector2i) -> void:
	_stop()
	if not pending_dir_action.is_empty():
		var target: Vector2i = world.pos + direction
		var act := pending_dir_action
		pending_dir_action = ""
		_execute_directional_action(act, target)
		_refresh()
		return
	if look_at == NONE:
		if board.motion.is_resting():
			board.exit_posture()
			status_text.text = ""
		_move_one(world.pos + direction)
	else:
		look_at = (look_at + direction).clamp(Vector2i.ZERO, world.city_size - Vector2i.ONE)
		status_text.text = "环视：%s" % world.location(look_at)
	_refresh()


func _column(parent: Node, gap: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", gap)
	parent.add_child(column)
	return column


func _label(parent: Node, text: String, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.style_button(button, primary)
	parent.add_child(button)
	button.pressed.connect(callback)
	return button


func _floor_name(z: int) -> String:
	if z == 0:
		return "地面层"
	if z == 1:
		return "二层"
	if z == 2:
		return "阁楼"
	return "Z=%d" % z


func _refresh() -> void:
	var sky := CanglingCalendar.at_minute(world.minutes)
	weather.sync(sky, world.seed, false)
	time_text.text = "%s · %s" % [CanglingCalendar.time_label(world.minutes), weather.label()]
	var phase := UI.phase_info(sky)
	phase_label.text = phase[0]
	phase_label.add_theme_color_override("font_color", phase[1])
	phase_pill.add_theme_stylebox_override("panel", UI.pill_box(phase[2], phase[1].darkened(0.25), 9, 2))
	var wb := weather.badge()
	weather_label.text = wb[0]
	weather_label.add_theme_color_override("font_color", wb[1])
	weather_pill.add_theme_stylebox_override("panel", UI.pill_box(wb[2], wb[1].darkened(0.25), 9, 2))
	location_text.text = world.location(world.pos)
	floor_label.text = _floor_name(world.floor)
	quest_text.text = world.quest_text
	var cultivated := world.quest == 4
	realm_label.text = "引气一层" if cultivated else "平民"
	realm_label.add_theme_color_override("font_color", UI.JADE if cultivated else UI.INK_SOFT)
	realm_badge.add_theme_stylebox_override("panel", UI.pill_box(
		Color("173129") if cultivated else Color("1b221e"),
		UI.JADE if cultivated else UI.BORDER_JADE, 8, 1))
	stats_text.text = "铜钱 %d 文   ·   清露草 %d 株" % [world.coins, world.herbs]
	resources_text.text = "行囊水壶  %d / %d 毫升" % [world.bottle_water(), world.bottle_capacity()]
	var st: Dictionary = world.character_status()
	var grab_tag := "  ·  [拖拽家具中]" if world.is_grabbing() else ""
	needs_text.text = "饱食:%s · 水分:%s · 精力:%s%s" % [
		st.get("hunger_text", "正常"), st.get("thirst_text", "正常"), st.get("fatigue_text", "尚可"), grab_tag]
	board.follow(world.pos if look_at == NONE else look_at)
	minimap.queue_redraw()


func _note(text: String) -> void:
	if text.is_empty():
		return
	var record := _label(journal, "· " + text, 14, INK, true)
	journal.move_child(record, 0)
	if journal.get_child_count() > 10:
		var oldest := journal.get_child(10)
		journal.remove_child(oldest)
		oldest.queue_free()
	for i in range(journal.get_child_count()):
		var item: Label = journal.get_child(i)
		item.add_theme_color_override("font_color", INK if i == 0 else SOFT if i <= 2 else UI.INK_DIM)


func _stop() -> void:
	period_timer.stop()
	walker.stop()
	if wait_timer != null and wait_timer.time_left > 0.0:
		wait_timer.stop()
		wait_remaining = 0
		status_text.text = "等待已中止。"
	board.route.clear()
	board.route_head = 0
	pending_site = NONE
	pending_action = ""


func _map_clicked(cell: Vector2i) -> void:
	if not opened.is_empty():
		return
	if not pending_dir_action.is_empty():
		if world.near(cell):
			var act := pending_dir_action
			pending_dir_action = ""
			_execute_directional_action(act, cell)
			_refresh()
		else:
			status_text.text = "请点击紧邻身旁的格子，或按 Esc 取消。"
		return
	_begin_route(cell)


func _open_actions(cell: Vector2i) -> void:
	if not opened.is_empty():
		return
	_stop()
	_refresh()
	var actions := world.actions_at(cell)
	if actions.is_empty():
		return
	action_cell = cell
	action_ids.clear()
	action_menu.clear()
	for action: String in actions:
		action_menu.add_item(actions[action], action_ids.size())
		action_ids.append(action)
	action_menu.reset_size()
	action_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _choose_action(id: int) -> void:
	var action := action_ids[id]
	_begin_route(action_cell, "" if action == "walk" else action)


func _begin_route(cell: Vector2i, action := "") -> void:
	look_at = NONE
	_stop()
	if action != "rest" and board.motion.is_resting():
		board.exit_posture()
	status_text.text = ""
	if not action.is_empty() and world.near(cell):
		_perform_action(cell, action)
	elif cell != world.pos:
		var path := world.route_to(cell, not action.is_empty())
		if path.size() > 1:
			board.route = path
			board.route_head = 1
			pending_site = cell
			pending_action = action
			walker.start()
		else:
			status_text.text = "没有可走的路线。"
	_refresh()


func _move_one(next: Vector2i) -> bool:
	var was_grabbing: bool = world.is_grabbing()
	var next_tile: String = world.terrain_at(next)
	var opens_door: bool = next_tile == "D"
	var climbs_window: bool = next_tile == "O"
	if not world.move_one(next):
		if was_grabbing:
			status_text.text = "家具前方受阻，无法拖动。"
		return false
	if opens_door or was_grabbing:
		board.invalidate_lightmap()
	if climbs_window:
		status_text.text = "你翻越了雕花木窗。"
	return true


func _walk() -> void:
	var step: Vector2i = board.route[board.route_head]
	if not _move_one(step):
		_stop()
		status_text.text = "道路受阻。"
	elif world.pos == step:
		board.route_head += 1
		if board.route_head >= board.route.size():
			var target := pending_site
			var action := pending_action
			_stop()
			if not action.is_empty():
				_perform_action(target, action)
	_refresh()


func _new_game(field: LineEdit, error_label: Label) -> void:
	var text := field.text.strip_edges()
	if not text.is_empty() and (not text.is_valid_int() or text.to_int() < 0 or text.to_int() > 4294967295):
		error_label.text = "种子须为 0 至 4294967295 的整数。"
		return
	world.setup(randi() if text.is_empty() else text.to_int())
	weather.set_override(-1, CanglingCalendar.at_minute(world.minutes), world.seed, true)
	board.clear_footprints()
	board.invalidate_lightmap()
	atlas_cells.clear()
	look_at = NONE
	_stop()
	_close_overlay()
	_clear_journal()
	_note("晨雾贴着河面。你从南门外抵达沧菱城。")
	status_text.text = "城市种子：%d" % world.seed
	_refresh()


func _clear_journal() -> void:
	for entry in journal.get_children():
		journal.remove_child(entry)
		entry.queue_free()


func _save() -> void:
	_stop()
	status_text.text = "旅程已存档。" if world.save_game(World.SAVE_PATH) else "存档写入失败。"
	_refresh()


func _load() -> void:
	_stop()
	if world.load_game(World.SAVE_PATH):
		board.clear_footprints()
		board.invalidate_lightmap()
		atlas_cells.clear()
		look_at = NONE
		_clear_journal()
		_note("你回到了上次落笔的地方。")
		status_text.text = "已读取存档。"
	else:
		status_text.text = "没有可读取的存档。"
	_refresh()


func _start_wait(minutes: int) -> void:
	_close_overlay()
	_stop()
	wait_remaining = minutes
	status_text.text = "静候时光，按 Esc 可中止。"
	wait_timer.start()


func _advance_wait() -> void:
	if wait_remaining <= 0:
		wait_timer.stop()
		return
	world.advance_time(1)
	wait_remaining -= 1
	_refresh()
	if wait_remaining > 0 and wait_remaining % 15 == 0:
		status_text.text = "静候中，剩余 %02d:%02d；按 Esc 可中止。" % [wait_remaining / 60, wait_remaining % 60]
	if wait_remaining == 0:
		wait_timer.stop()
		status_text.text = "静候结束。"


func _debug_jump_time_of_day(target_hour: int, target_minute: int) -> void:
	var cur := posmod(world.minutes, CanglingCalendar.MINUTES_PER_DAY)
	var target := target_hour * 60 + target_minute
	var delta := posmod(target - cur, CanglingCalendar.MINUTES_PER_DAY)
	if delta == 0:
		delta = CanglingCalendar.MINUTES_PER_DAY
	world.advance_time(delta)
	board.invalidate_weather()
	status_text.text = "调试：时间已跳转至 %02d:%02d。" % [target_hour, target_minute]
	_refresh()


func _debug_jump_season(season_index: int) -> void:
	var sky := CanglingCalendar.at_minute(world.minutes)
	var cur_day := posmod(int(sky.day_index), CanglingCalendar.DAYS_PER_YEAR)
	var target_day := season_index * CanglingCalendar.DAYS_PER_SEASON + 15
	var delta_days := posmod(target_day - cur_day, CanglingCalendar.DAYS_PER_YEAR)
	if delta_days == 0:
		delta_days = CanglingCalendar.DAYS_PER_YEAR
	world.advance_time(delta_days * CanglingCalendar.MINUTES_PER_DAY)
	weather.sync(CanglingCalendar.at_minute(world.minutes), world.seed, true)
	board.invalidate_weather()
	status_text.text = "调试：季节已切换至%s季。" % CanglingCalendar.SEASONS[season_index]
	_refresh()


func _debug_advance(delta_minutes: int, label_text: String) -> void:
	world.advance_time(delta_minutes)
	board.invalidate_weather()
	status_text.text = "调试：时间推进 %s。" % label_text
	_refresh()


func _debug_set_weather(kind: int) -> void:
	var sky := CanglingCalendar.at_minute(world.minutes)
	weather.set_override(kind, sky, world.seed, true)
	if weather.snow_cover <= 0.12:
		board.clear_footprints()
	board.invalidate_weather()
	var name := "自动（随天时季节）" if kind < 0 else weather.label()
	status_text.text = "调试：天气已切换为「%s」。" % name
	_refresh()


func _debug_toggle_roofs() -> void:
	board.roofs_enabled = not board.roofs_enabled
	board.invalidate_weather()
	status_text.text = "调试：室外自动覆瓦屋顶已%s。" % ("开启" if board.roofs_enabled else "关闭")
	_refresh()


func _close_overlay() -> void:
	if overlay_backdrop != null:
		remove_child(overlay_backdrop)
		overlay_backdrop.queue_free()
		overlay_backdrop = null
	if overlay != null:
		remove_child(overlay)
		overlay.queue_free()
		overlay = null
	opened = ""
	atlas = null


func _show_overlay(kind: String, item_target := NONE) -> void:
	move_input.reset()
	if opened == kind:
		_close_overlay()
		return
	_close_overlay()
	_stop()
	_refresh()
	opened = kind
	overlay_backdrop = ColorRect.new()
	overlay_backdrop.color = Color(0.03, 0.05, 0.04, 0.72 if kind != "map" else 0.88)
	add_child(overlay_backdrop)
	overlay_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	overlay = PanelContainer.new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if kind == "map":
		overlay.offset_left = 14
		overlay.offset_right = -14
		overlay.offset_top = 14
		overlay.offset_bottom = -14
	elif kind in ["debug", "action_menu", "eat", "wear", "take_off", "pickup", "character", "inventory"]:
		overlay.anchor_left = 0.18
		overlay.anchor_right = 0.82
		overlay.anchor_top = 0.08
		overlay.anchor_bottom = 0.92
		overlay.offset_left = 0
		overlay.offset_right = 0
		overlay.offset_top = 0
		overlay.offset_bottom = 0
	else:
		overlay.anchor_left = 0.26
		overlay.anchor_right = 0.74
		overlay.anchor_top = 0.16
		overlay.anchor_bottom = 0.68
		overlay.offset_left = 0
		overlay.offset_right = 0
		overlay.offset_top = 0
		overlay.offset_bottom = 0
	if kind == "wait":
		overlay.anchor_top = 0.08
		overlay.anchor_bottom = 0.90
	overlay.add_theme_stylebox_override("panel", UI.panel_box(Color("111815"), UI.BORDER_GOLD, 6, 16, 14, 1))
	var contents := _column(overlay, 10)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	contents.add_child(heading)
	var glyphs := {"map": "图", "inventory": "囊", "character": "身", "pause": "卷", "wait": "时", "new": "始", "debug": "调",
		"action_menu": "令", "eat": "膳", "wear": "衣", "take_off": "解", "pickup": "拾"}
	var titles := {"map": "沧菱城舆图", "inventory": "随身行囊 (i)", "character": "人物与着装状态 (@)", "pause": "行旅名录",
		"wait": "静候天时 (|)", "new": "重开行旅", "debug": "调试菜单 (K)",
		"action_menu": "动作菜单 (Enter)", "eat": "进食与饮水 (E)", "wear": "穿戴衣物 (W)", "take_off": "脱下与整理着装 (T)", "pickup": "拾取与查看物品 (g / e)"}
	UI.seal_stamp(heading, glyphs[kind])
	var title := _label(heading, titles[kind], 21, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var close := _button(heading, "合卷", _close_overlay)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(72, 32)
	contents.add_child(UI.hairline())
	match kind:
		"map":
			_build_atlas(contents)
		"action_menu":
			ActionMenu.build_menu(self, contents)
		"eat":
			CCBUI.eat_menu(self, contents)
		"wear":
			CCBUI.wear_menu(self, contents)
		"take_off":
			CCBUI.take_off_menu(self, contents)
		"pickup":
			CCBUI.pickup_menu(self, contents, item_target)
		"inventory":
			Items.inventory(self, contents, item_target)
		"character":
			CCBUI.character_sheet(self, contents)
		"pause":
			_button(contents, "继续行旅", _close_overlay, true)
			_button(contents, "静候天时…", _show_overlay.bind("wait"))
			_button(contents, "调试菜单（K）…", _show_overlay.bind("debug"))
			_button(contents, "记入竹简（存档）", func(): _close_overlay(); _save())
			_button(contents, "重拾旧录（读档）", func(): _close_overlay(); _load())
			_button(contents, "另择城势（新旅程）", _show_overlay.bind("new"))
		"wait":
			_label(contents, "选择静候时长。天光、河雾与灯火将随游戏时辰流转，按 Esc 可随时中止。", 14, SOFT, true)
			for duration in [["10 分钟", 10], ["30 分钟", 30], ["1 小时", 60], ["3 小时", 180], ["6 小时", 360], ["12 小时", 720]]:
				_button(contents, "静候 " + duration[0], _start_wait.bind(duration[1]))
		"new":
			_label(contents, "城势种子", 14, SOFT)
			var field := LineEdit.new()
			field.placeholder_text = "留空则随机生成城势"
			field.max_length = 10
			UI.style_line_edit(field)
			contents.add_child(field)
			var error_label := _label(contents, "", 13, Color("e19a78"), true)
			_button(contents, "生成沧菱城", _new_game.bind(field, error_label), true)
			field.text_submitted.connect(func(_text: String): _new_game(field, error_label))
			field.grab_focus()
		"debug":
			_build_debug_menu(contents)


func _build_debug_menu(contents: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var body := _column(scroll, 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_CARD, UI.BORDER_JADE, 4, 12, 8, 1))
	body.add_child(summary)
	var scol := _column(summary, 3)
	_label(scol, "当前天时：%s" % CanglingCalendar.time_label(world.minutes), 14, GOLD)
	_label(scol, "当前天气：%s（%s） · 积水 %.0f%% · 积雪 %.0f%%" % [
		weather.label(),
		"自动" if weather.override_kind < 0 else "锁定",
		weather.wetness * 100.0, weather.snow_cover * 100.0], 13, SOFT)
	var perf: Dictionary = world.perf_stats()
	_label(scol, "性能：FPS %d · CPU %d 工作线程（%d 核） · 区块缓存 %d · 占用 %.0f KB · 自动释放 %d 次（%.0f KB） · 烘焙 %.1f ms" % [
		Engine.get_frames_per_second(),
		int(perf.get("cpu_threads", 1)),
		int(perf.get("hardware_threads", 1)),
		int(perf.get("cached_sectors", 0)),
		float(perf.get("memory_kb", 0.0)),
		int(perf.get("auto_trim_count", 0)),
		float(perf.get("auto_freed_kb", 0.0)),
		float(perf.get("last_bake_ms", 0.0))], 12, UI.JADE)

	# Time of day presets
	_label(body, "◈ 时间点跳转", 14, GOLD)
	var time_grid := GridContainer.new()
	time_grid.columns = 3
	time_grid.add_theme_constant_override("h_separation", 8)
	time_grid.add_theme_constant_override("v_separation", 8)
	body.add_child(time_grid)
	for preset in [["拂晓 05:30", 5, 30], ["清晨 07:20", 7, 20], ["正午 12:00", 12, 0],
			["午后 15:30", 15, 30], ["黄昏 17:45", 17, 45], ["子夜 00:30", 0, 30]]:
		_button(time_grid, preset[0], func(): _debug_jump_time_of_day(preset[1], preset[2]); _close_overlay())

	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 8)
	body.add_child(step_row)
	for step_spec in [["+1 小时", 60], ["+3 小时", 180], ["+6 小时", 360], ["+1 天", 1440]]:
		_button(step_row, step_spec[0], func(): _debug_advance(step_spec[1], step_spec[0]); _close_overlay())

	# Season jump
	_label(body, "◈ 切换季节", 14, GOLD)
	var season_row := HBoxContainer.new()
	season_row.add_theme_constant_override("separation", 8)
	body.add_child(season_row)
	for i in range(CanglingCalendar.SEASONS.size()):
		var sname: String = CanglingCalendar.SEASONS[i]
		_button(season_row, sname + "季", func(): _debug_jump_season(i); _close_overlay())

	# Weather overrides
	_label(body, "◈ 切换天气（雨天即显积水反光，雪天即覆雪留脚印）", 14, GOLD)
	var weather_grid := GridContainer.new()
	weather_grid.columns = 3
	weather_grid.add_theme_constant_override("h_separation", 8)
	weather_grid.add_theme_constant_override("v_separation", 8)
	body.add_child(weather_grid)
	var weather_specs := [
		["自动（随季节）", -1],
		["晴朗", Weather.Kind.CLEAR],
		["多云阴天", Weather.Kind.CLOUDY],
		["烟雨（细雨）", Weather.Kind.LIGHT_RAIN],
		["大雨（深积水）", Weather.Kind.HEAVY_RAIN],
		["小雪（薄雪）", Weather.Kind.LIGHT_SNOW],
		["大雪（厚雪脚印）", Weather.Kind.HEAVY_SNOW],
	]
	for spec in weather_specs:
		var is_active: bool = (spec[1] == -1 and weather.override_kind < 0) or (spec[1] >= 0 and weather.override_kind == spec[1])
		_button(weather_grid, spec[0], func(): _debug_set_weather(spec[1]); _close_overlay(), is_active)

	# Visual options
	_label(body, "◈ 画面与建筑调试", 14, GOLD)
	var opt_row := HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 8)
	body.add_child(opt_row)
	_button(opt_row, "室外自动覆瓦屋顶：%s" % ("开" if board.roofs_enabled else "关"),
		func(): _debug_toggle_roofs(); _close_overlay(), board.roofs_enabled)
	_button(opt_row, "清空脚印（雪/水）", func(): board.clear_footprints(); board.markers.queue_redraw(); _close_overlay())
	_button(opt_row, "立即释放冷缓存", func():
		var freed_kb := float(world.trim_memory(true)) / 1024.0
		var freed_pages: int = board.Tiles.trim_unused_pages(0)
		status_text.text = "内存管理：已释放 %.0f KB 区块缓存、%d 页图集。" % [freed_kb, freed_pages]
		_close_overlay())


func _stat_row(parent: Node, label_text: String, value_text: String, value_color: Color) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var k := _label(row, label_text, 15, SOFT)
	k.custom_minimum_size.x = 110
	var v := _label(row, value_text, 15, value_color)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _gui_input(event: InputEvent) -> void:
	if not opened.is_empty() and event is InputEventMouseButton:
		accept_event()


func _build_atlas(contents: VBoxContainer) -> void:
	var panel := HBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(panel)
	var atlas_frame := PanelContainer.new()
	atlas_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atlas_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	atlas_frame.add_theme_stylebox_override("panel", UI.panel_box(Color("0b100d"), UI.BORDER_JADE, 4, 2, 2, 1))
	panel.add_child(atlas_frame)
	atlas = Atlas.new()
	atlas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atlas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	atlas_frame.add_child(atlas)

	var side_card := PanelContainer.new()
	side_card.custom_minimum_size.x = 252
	side_card.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_CARD, UI.BORDER_JADE, 4, 12, 10, 1))
	panel.add_child(side_card)
	var side := _column(side_card, 8)
	_label(side, "◈ 选中区块", 13, SOFT)
	var name_label := _label(side, "", 20, UI.JADE, true)
	var details := _label(side, "", 14, INK, true)
	side.add_child(UI.hairline())
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	side.add_child(tools)
	_button(tools, "观全城", atlas.fit)
	_button(tools, "前往此地", atlas.travel, true)
	var quest_box := PanelContainer.new()
	quest_box.add_theme_stylebox_override("panel", UI.accent_card(Color("171e19"), UI.BORDER_GOLD, UI.BORDER_SOFT, 9, 7))
	side.add_child(quest_box)
	var qcol := _column(quest_box, 3)
	_label(qcol, "◈ 当前委托", 13, GOLD)
	_label(qcol, world.quest_text, 14, INK, true)

	side.add_child(UI.hairline())
	_label(side, "◈ 图例与操作", 13, SOFT)
	_label(side, "● 金点：城中地标\n● 玉点：旅人所在\n滚轮缩放 · 中键拖拽 · 右键前往", 13, UI.INK_DIM, true)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	_label(side, "%d × %d 格  ·  种子 %d" % [world.city_size.x, world.city_size.y, world.seed], 12, UI.INK_DIM)
	atlas.selection_changed.connect(func(title: String, data: String):
		name_label.text = title
		details.text = data)
	atlas.destination_requested.connect(_travel_from_overview)
	if atlas_cells.is_empty() or atlas_seed != world.seed:
		atlas_cells = world.city_survey()
		atlas_seed = world.seed
	atlas.build(world, atlas_cells)


func _perform_action(position: Vector2i, action: String) -> void:
	match action:
		"store":
			if world.actions_at(position).has(action):
				_show_overlay("inventory", position)
		"container":
			var open_msg: String = world.open_at(position)
			if not open_msg.is_empty():
				_note(open_msg)
				board.invalidate_world_cache()
			_show_overlay("pickup", position)
		"loot":
			_show_overlay("pickup", position)
		"water_take", "water_pour":
			Items.water(self, position, action == "water_take")
		_:
			var result: String = world.interact(position, action)
			if not result.is_empty():
				if action == "rest":
					var tile: String = world.terrain_at(position)
					if tile == "b":
						board.enter_posture(&"lying", position)
						status_text.text = "你正躺在床榻上歇息（按方向键即可起身）。"
					elif tile == "q" or tile == "S":
						board.enter_posture(&"sitting", position)
						status_text.text = "你正坐在椅凳上小憩（按方向键即可起身）。"
				elif action in ["door", "window", "stairs_up", "stairs_down"]:
					board.invalidate_lightmap()
				elif action in ["grab", "release_grab"]:
					status_text.text = result
					board.markers.queue_redraw()
				else:
					board.invalidate_world_cache()
			_note(result)


func _candidates_for_dir_action(act: String) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var pos: Vector2i = world.pos
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0 and act != "examine":
				continue
			var p := pos + Vector2i(dx, dy)
			var t: String = world.terrain_at(p)
			match act:
				"open":
					if t in ["D", "w"] or (t in ["c", "C", "F", "K", "r"] and not world.is_container_open(p)):
						found.append(p)
				"close":
					if t in ["o", "O"] or (t in ["c", "C", "F", "K", "r"] and world.is_container_open(p)):
						found.append(p)
				"grab":
					if t in ["q", "S", "t", "l", "C", "c", "a", "u", "b", "k", "K", "r", "P"]:
						found.append(p)
				"examine":
					if t in ["c", "C", "F", "K", "r", "b", "q", "S", "t", "l", "k", "h", "u", "a", "D", "o", "w", "O"] or not world.items_at(p).is_empty():
						found.append(p)
	return found


func _start_directional_action(act: String) -> void:
	if act == "grab" and world.is_grabbing():
		var msg: String = world.release_grab()
		status_text.text = msg
		_note(msg)
		board.markers.queue_redraw()
		_refresh()
		return
	var cands := _candidates_for_dir_action(act)
	if cands.is_empty():
		var labels := {"open": "打开的门、窗或柜子", "close": "关闭的门、窗或柜子", "grab": "抓取拖拽的家具", "examine": "检查或互动的对象"}
		status_text.text = "身旁没有可%s。" % labels.get(act, "操作的目标")
		return
	if cands.size() == 1:
		_execute_directional_action(act, cands[0])
		_refresh()
		return
	pending_dir_action = act
	var prompts := {"open": "向哪个方向开门/窗/柜？", "close": "向哪个方向关门/窗/柜？", "grab": "抓取哪个方向的家具？", "examine": "检查哪个方向？"}
	status_text.text = "%s（按方向键/小键盘或点击邻格，Esc 取消）" % prompts.get(act, "请选择方向")


func _execute_directional_action(act: String, target: Vector2i) -> void:
	match act:
		"open":
			var msg: String = world.open_at(target)
			if msg.is_empty():
				status_text.text = "那个方向没有可打开的门、窗或柜子。"
			else:
				status_text.text = msg
				_note(msg)
				board.invalidate_lightmap()
				if world.is_container_open(target) and not world.items_at(target).is_empty():
					_show_overlay("pickup", target)
		"close":
			var msg: String = world.close_at(target)
			if msg.is_empty():
				status_text.text = "那个方向没有可关闭的门、窗或柜子。"
			else:
				status_text.text = msg
				_note(msg)
				board.invalidate_lightmap()
		"grab":
			var msg: String = world.grab_furniture(target)
			status_text.text = msg
			_note(msg)
			board.markers.queue_redraw()
		"examine":
			var t: String = world.terrain_at(target)
			if t in ["c", "C", "F", "K", "r"]:
				_perform_action(target, "container")
			elif not world.items_at(target).is_empty():
				_show_overlay("pickup", target)
			else:
				var msg: String = world.interact(target, "inspect")
				if msg.is_empty():
					msg = "这里似乎没有什么特别的东西。"
				status_text.text = msg
				_note(msg)


func _run_ccb_action(act_id: String) -> void:
	match act_id:
		"sky":
			var msg := CCBUI.observe_sky_message(self)
			status_text.text = msg
			_note(msg)
		"look":
			_stop()
			look_at = world.pos if look_at == NONE else NONE
			status_text.text = "环视：%s" % world.location(look_at) if look_at != NONE else ""
			_refresh()
		"map", "inventory", "eat", "wear", "take_off", "pickup", "character", "wait", "debug":
			_show_overlay(act_id)
		"drop":
			_show_overlay("inventory")
		"open", "close", "examine", "grab":
			_start_directional_action(act_id)
		"stairs_up":
			var msg: String = world.change_floor(1)
			status_text.text = msg
			_note(msg)
			board.invalidate_lightmap()
			_refresh()
		"stairs_down":
			var msg: String = world.change_floor(-1)
			status_text.text = msg
			_note(msg)
			board.invalidate_lightmap()
			_refresh()
		"stand":
			board.exit_posture()
			status_text.text = "你起身整了整衣衫。"
			_refresh()
		"sleep", "rest_nearby":
			var pos: Vector2i = world.pos
			var bed := NONE
			var seat := NONE
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var p := pos + Vector2i(dx, dy)
					var t: String = world.terrain_at(p)
					if t == "b" and bed == NONE:
						bed = p
					elif (t == "q" or t == "S") and seat == NONE:
						seat = p
			if bed != NONE:
				_perform_action(bed, "rest")
			elif seat != NONE:
				_perform_action(seat, "rest")
			else:
				world.rest_minutes(30, false)
				var msg := "你寻了处角落小憩半个时辰。"
				status_text.text = msg
				_note(msg)
			_refresh()
		"save":
			_save()
		"load":
			_load()


func _travel_from_overview(destination: Vector2i) -> void:
	if world.floor != 0:
		_note("先回到地面层。")
		_close_overlay()
		return
	_close_overlay()
	_map_clicked(destination)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.pressed:
		move_input.handle_key_release(event)
		if period_timer != null and (event.keycode == KEY_PERIOD or event.keycode == KEY_KP_5 or (period_key != KEY_NONE and event.physical_keycode == period_key)):
			period_timer.stop()


func _period_tick() -> void:
	world.advance_time(1)
	_refresh()


func _repeat_period() -> void:
	var held := Input.is_physical_key_pressed(period_key) if period_key != KEY_NONE else Input.is_key_pressed(KEY_PERIOD)
	if not held or not opened.is_empty() or action_menu.visible:
		return
	for modifier: Key in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		if Input.is_key_pressed(modifier):
			return
	_period_tick()
	period_timer.start(0.11)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var key: Key = event.physical_keycode
	var kc: Key = event.keycode
	var shift: bool = event.shift_pressed
	var ctrl_or_alt: bool = event.ctrl_pressed or event.alt_pressed or event.meta_pressed

	if key == KEY_ESCAPE and not event.echo:
		if not pending_dir_action.is_empty():
			pending_dir_action = ""
			status_text.text = "已取消操作。"
			get_viewport().set_input_as_handled()
			return
		if wait_timer.time_left > 0.0:
			_stop()
			_refresh()
			get_viewport().set_input_as_handled()
			return
		if not opened.is_empty():
			_close_overlay()
		elif look_at != NONE or not board.route.is_empty():
			look_at = NONE
			_stop()
			_refresh()
		else:
			_show_overlay("pause")
		get_viewport().set_input_as_handled()
		return

	if not opened.is_empty():
		if atlas != null and atlas.keyboard(key):
			get_viewport().set_input_as_handled()
		return

	if not event.echo and not ctrl_or_alt:
		# Enter -> CCB Action Menu
		if kc == KEY_ENTER or kc == KEY_KP_ENTER or key == KEY_ENTER or key == KEY_KP_ENTER:
			_show_overlay("action_menu")
			get_viewport().set_input_as_handled()
			return
		# CCB Shift+Key bindings (uppercase letters & symbols — zero conflict with lowercase WASD!)
		if shift:
			if key == KEY_E:
				_show_overlay("eat")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_W:
				_show_overlay("wear")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_T or key == KEY_EQUAL:
				_show_overlay("take_off")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_G:
				_start_directional_action("grab")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_D:
				_show_overlay("inventory")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_2 or kc == KEY_AT:
				_show_overlay("character")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_BACKSLASH or kc == KEY_BAR:
				_show_overlay("wait")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_4 or kc == KEY_DOLLAR:
				_run_ccb_action("sleep")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_COMMA or kc == KEY_LESS:
				_run_ccb_action("stairs_up")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_PERIOD or kc == KEY_GREATER:
				_run_ccb_action("stairs_down")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_K:
				_show_overlay("debug")
				get_viewport().set_input_as_handled()
				return
		else:
			# CCB lowercase single-key bindings (o open, c close, e examine, g/, pickup, i inv, m map, x/L look, k debug)
			if key == KEY_O:
				_start_directional_action("open")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_C:
				_start_directional_action("close")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_E:
				_start_directional_action("examine")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_G or key == KEY_COMMA:
				_show_overlay("pickup")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_I:
				_show_overlay("inventory")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_M:
				_show_overlay("map")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_K:
				_show_overlay("debug")
				get_viewport().set_input_as_handled()
				return
			if key == KEY_X or key == KEY_L:
				_run_ccb_action("look")
				get_viewport().set_input_as_handled()
				return

	if (kc == KEY_PERIOD or kc == KEY_KP_5 or key == KEY_KP_5) and not (shift or ctrl_or_alt):
		if not event.echo:
			_stop()
			period_key = key
			_period_tick()
			period_timer.start(0.27)
		get_viewport().set_input_as_handled()
		return
	if move_input.is_movement_key(event) and not shift:
		var direction := move_input.handle_key_press(event)
		if direction != Vector2i.ZERO:
			_apply_directional_step(direction)
		get_viewport().set_input_as_handled()
