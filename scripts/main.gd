extends Control

const World = preload("res://scripts/world.gd")
const Board = preload("res://scripts/board.gd")
const Survey = preload("res://scripts/survey.gd")
const Atlas = preload("res://scripts/city_atlas.gd")
const Items = preload("res://scripts/item_ui.gd")
const CanglingCalendar = preload("res://scripts/cangling_calendar.gd")
const UI = preload("res://scripts/ui_theme.gd")
const INK := UI.INK_IVORY
const SOFT := UI.INK_SOFT
const GOLD := UI.GOLD
const LINE := UI.BORDER_JADE
const NONE := Vector2i(-1, -1)

var world := World.new()
var board: Board
var time_text: Label
var phase_pill: PanelContainer
var phase_label: Label
var location_text: Label
var floor_label: Label
var quest_text: Label
var realm_badge: PanelContainer
var realm_label: Label
var stats_text: Label
var resources_text: Label
var status_text: Label
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
	top.add_theme_constant_override("separation", 10)
	header_panel.add_child(top)
	UI.seal_stamp(top, "沧")
	var title_box := HBoxContainer.new()
	title_box.add_theme_constant_override("separation", 10)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)
	var title := _label(title_box, "沧菱城", 22, GOLD)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var subtitle := _label(title_box, "沧溟修真界 · 云梦水乡", 13, UI.INK_DIM)
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	phase_pill = PanelContainer.new()
	phase_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	phase_label = _label(phase_pill, "晨曦", 13, GOLD)
	top.add_child(phase_pill)

	for spec in [["大地图", "map"], ["背包", "inventory"], ["角色", "character"], ["菜单", "pause"]]:
		var nav := _button(top, spec[0], _show_overlay.bind(spec[1]))
		nav.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		nav.custom_minimum_size = Vector2(76, 32)

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
	board.build(world)
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

	# Realm & Resources Card
	var status_card := PanelContainer.new()
	status_card.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_CARD, UI.BORDER_SOFT, 4, 9, 7, 1))
	side.add_child(status_card)
	var status_col := _column(status_card, 5)
	var stat_head := HBoxContainer.new()
	stat_head.add_theme_constant_override("separation", 6)
	status_col.add_child(stat_head)
	var stat_title := _label(stat_head, "◈ 道途状态", 13, SOFT)
	stat_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	realm_badge = PanelContainer.new()
	realm_badge.add_theme_stylebox_override("panel", UI.pill_box(Color("1b2b25"), UI.JADE, 8, 1))
	realm_label = _label(realm_badge, "凡人", 12, UI.JADE)
	stat_head.add_child(realm_badge)
	stats_text = _label(status_col, "", 14, INK)
	resources_text = _label(status_col, "", 13, SOFT)

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
	var hints := _label(foot_row, "左键寻路 · 右键交互 · 滚轮缩放 · . 候时 · L 环视 · M 舆图", 12, UI.INK_DIM)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	action_menu = PopupMenu.new()
	action_menu.theme = theme
	UI.style_popup(action_menu)
	add_child(action_menu)
	action_menu.id_pressed.connect(_choose_action)

	walker = Timer.new()
	walker.wait_time = 0.04
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
	get_window().focus_exited.connect(period_timer.stop)


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
	button.custom_minimum_size.y = 35
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
	time_text.text = CanglingCalendar.time_label(world.minutes)
	var phase := UI.phase_info(sky)
	phase_label.text = phase[0]
	phase_label.add_theme_color_override("font_color", phase[1])
	phase_pill.add_theme_stylebox_override("panel", UI.pill_box(phase[2], phase[1].darkened(0.25), 9, 2))
	location_text.text = world.location(world.pos)
	floor_label.text = _floor_name(world.floor)
	quest_text.text = world.quest_text
	var cultivated := world.quest == 4
	realm_label.text = "引气一层" if cultivated else "凡人"
	realm_label.add_theme_color_override("font_color", UI.JADE if cultivated else UI.INK_SOFT)
	realm_badge.add_theme_stylebox_override("panel", UI.pill_box(
		Color("173129") if cultivated else Color("1b221e"),
		UI.JADE if cultivated else UI.BORDER_JADE, 8, 1))
	stats_text.text = "铜钱 %d 文   ·   清露草 %d 株" % [world.coins, world.herbs]
	resources_text.text = "行囊水壶  %d / %d 毫升" % [world.bottle_water(), world.bottle_capacity()]
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
	if opened.is_empty():
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
	var opens_door: bool = world.terrain_at(next) == "D"
	if not world.move_one(next):
		return false
	if opens_door:
		board.invalidate_lightmap()
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
	var glyphs := {"map": "图", "inventory": "囊", "character": "道", "pause": "卷", "wait": "时", "new": "始"}
	var titles := {"map": "沧菱城舆图", "inventory": "随身行囊", "character": "修士名帖", "pause": "行旅名录", "wait": "静候天时", "new": "重开行旅"}
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
		"inventory":
			Items.inventory(self, contents, item_target)
		"character":
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_CARD, UI.BORDER_JADE, 4, 14, 12, 1))
			contents.add_child(card)
			var info := _column(card, 8)
			_stat_row(info, "身份", "凡俗旅人", INK)
			_stat_row(info, "境界", "引气一层" if world.quest == 4 else "凡人", UI.JADE if world.quest == 4 else GOLD)
			_stat_row(info, "所在", "%s · %s" % [world.location(world.pos), _floor_name(world.floor)], INK)
			_stat_row(info, "资财", "铜钱 %d 文 · 清露草 %d 株" % [world.coins, world.herbs], GOLD)
			_stat_row(info, "行囊水壶", "%d / %d 毫升" % [world.bottle_water(), world.bottle_capacity()], SOFT)
		"pause":
			_button(contents, "继续行旅", _close_overlay, true)
			_button(contents, "静候天时…", _show_overlay.bind("wait"))
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
	_label(side, "● 金点：城中地标\n● 玉点：修士所在\n滚轮缩放 · 中键拖拽 · 右键前往", 13, UI.INK_DIM, true)

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
		"water_take", "water_pour":
			Items.water(self, position, action == "water_take")
		_:
			var result: String = world.interact(position, action)
			if not result.is_empty() and action in ["door", "window"]:
				board.invalidate_lightmap()
			_note(result)


func _travel_from_overview(destination: Vector2i) -> void:
	if world.floor != 0:
		_note("先回到地面层。")
		_close_overlay()
		return
	_close_overlay()
	_map_clicked(destination)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.pressed and period_timer != null:
		if event.keycode == KEY_PERIOD or (period_key != KEY_NONE and event.physical_keycode == period_key):
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
	var views := {KEY_M: "map", KEY_I: "inventory", KEY_C: "character"}
	if not event.echo and views.has(key):
		_show_overlay(views[key])
		get_viewport().set_input_as_handled()
		return
	if key == KEY_ESCAPE and not event.echo:
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
	if event.keycode == KEY_PERIOD and not (event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed):
		if not event.echo:
			_stop()
			period_key = key
			_period_tick()
			period_timer.start(0.27)
		get_viewport().set_input_as_handled()
		return
	if key == KEY_L and not event.echo:
		_stop()
		look_at = world.pos if look_at == NONE else NONE
		status_text.text = "环视：%s" % world.location(look_at) if look_at != NONE else ""
		_refresh()
		get_viewport().set_input_as_handled()
		return
	var direction := Vector2i.ZERO
	match key:
		KEY_UP, KEY_W: direction = Vector2i.UP
		KEY_DOWN, KEY_S: direction = Vector2i.DOWN
		KEY_LEFT, KEY_A: direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D: direction = Vector2i.RIGHT
	if direction != Vector2i.ZERO:
		_stop()
		if look_at == NONE:
			_move_one(world.pos + direction)
		else:
			look_at = (look_at + direction).clamp(Vector2i.ZERO, world.city_size - Vector2i.ONE)
			status_text.text = "环视：%s" % world.location(look_at)
		_refresh()
		get_viewport().set_input_as_handled()
