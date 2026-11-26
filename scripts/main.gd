extends Control

# Main Game Controller — Authentic Cataclysm-Cleanwater-Bomb (CCB) Layout & Controls.
# - Full-height viewport edge-to-edge on the left + authentic CCB Classic Right Sidebar (326px).
# - Pure Unicode character keybinding dispatcher (scripts/ccb_keymap.gd) — uppercase keys detected
#   directly via char(event.unicode), NOT shift+x!
# - Pure CCB movement (Numpad 1-9, Arrows, lowercase vi-keys h/j/k/l/y/u/b/n; NO WASD hijacking).

const World = preload("res://scripts/world.gd")
const Board = preload("res://scripts/board.gd")
const Atlas = preload("res://scripts/city_atlas.gd")
const Items = preload("res://scripts/item_ui.gd")
const ActionMenu = preload("res://scripts/ccb_action_menu.gd")
const CCBUI = preload("res://scripts/ccb_ui.gd")
const CCBSidebar = preload("res://scripts/ccb_sidebar.gd")
const CCB = preload("res://scripts/ccb_theme.gd")
const Keymap = preload("res://scripts/ccb_keymap.gd")
const CanglingCalendar = preload("res://scripts/cangling_calendar.gd")
const Weather = preload("res://scripts/weather.gd")
const MoveInput = preload("res://scripts/move_input.gd")
const NetSession = preload("res://scripts/net_session.gd")
const SkillUI = preload("res://scripts/skill_ui.gd")
const ShopUI = preload("res://scripts/shop_ui.gd")
const CraftUI = preload("res://scripts/craft_ui.gd")
const AudioAmbience = preload("res://scripts/audio_ambience.gd")
const NONE := Vector2i(-1, -1)
const REALTIME_MIN_PER_SEC := 1.0 / 1.5 # Real-time clock: 1 game minute every 1.5 real seconds (~36 min/day)

var world := World.new()
var weather := Weather.new()
var move_input := MoveInput.new()
var net_session := NetSession.new()
var audio_ambience: Node
var skill_tab := "wuxue"
var selected_skill_id := ""
var shop_mode := "buy"
var craft_tab := "全部"
var selected_craft_id := ""
var inv_cat := "全部"
var work_active := false
var work_kind := "workstation" # "workstation", "craft", "study", "dazuo"
var work_target := NONE
var work_recipe_id := ""
var work_item_id := -1
var work_elapsed := 0.0
var work_duration := 2.5
var work_label := ""
var spar_accum := 0.0
var realtime_clock_accum := 0.0
var board: Board
var sidebar: CCBSidebar
var pending_dir_action := ""
var action_menu: PopupMenu
var action_cell := NONE
var action_ids := PackedStringArray()
var walker: Timer
var pending_site := NONE
var pending_action := ""
var overlay_backdrop: ColorRect
var overlay: PanelContainer
var overlay_hotkeys: Dictionary = {}
var opened := ""
var look_at := NONE
var peek_return := false
var atlas: Atlas
var atlas_cells := PackedByteArray()
var atlas_seed := -1
var wait_timer: Timer
var wait_remaining := 0
var period_timer: Timer
var period_key: Key = KEY_NONE


func _ready() -> void:
	Board.Tiles.prewarm_game_sprites()
	world.setup(randi())
	weather.sync(CanglingCalendar.at_minute(world.minutes), world.seed, true)
	var ui_font: Font = null
	if ResourceLoader.exists("res://art/fonts/unifont.ttf"):
		var ff := FontFile.new()
		if ff.load_dynamic_font("res://art/fonts/unifont.ttf") == OK:
			ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			ff.hinting = TextServer.HINTING_LIGHT
			ui_font = ff
	if ui_font == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["Unifont", "Consolas", "Microsoft YaHei UI", "Noto Sans CJK SC", "monospace"])
		ui_font = fallback
	theme = Theme.new()
	theme.default_font = ui_font
	theme.default_font_size = 14
	_build_ui()
	audio_ambience = AudioAmbience.new()
	add_child(audio_ambience)
	_note("烟雨画桥，青瓦红灯。你踏入沧灵南门（随身潜能 30 点、铜钱 10 文）。按 M 查告示牌委托与全城师傅商铺，按 J 看技能，按 U 打坐运功，按 & 手工制作！")
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = CCB.BG_SCREEN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Authentic CCB Classic Layout: Edge-to-edge full-height viewport on left + 326px CCB Terminal Sidebar on right
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 0)
	add_child(split)
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	board = Board.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.build(world, weather)
	split.add_child(board)
	board.cell_clicked.connect(_map_clicked)
	board.context_requested.connect(_open_actions)

	sidebar = CCBSidebar.new()
	sidebar.build(world)
	split.add_child(sidebar)

	action_menu = PopupMenu.new()
	action_menu.theme = theme
	CCB.style_popup(action_menu)
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
	# Real-time clock progression (independent of player actions; only pauses in system/debug/help menus)
	if opened not in ["pause", "new", "help", "debug"] and (wait_timer == null or wait_timer.time_left <= 0.0):
		realtime_clock_accum += delta * REALTIME_MIN_PER_SEC
		if realtime_clock_accum >= 1.0:
			var whole_mins := int(realtime_clock_accum)
			realtime_clock_accum -= float(whole_mins)
			_sync_env_and_audio()
			world.advance_time(whole_mins)
			_refresh()
	# Multiplayer hook tick (0 overhead when offline; syncs local snapshot when host/client)
	net_session.tick(delta, world, board.motion.facing_x if board != null else 1,
		str(board.motion.posture) if board != null and board.motion.is_resting() else "")
	# Active Real-Time Sparring Loop (classic Wuxia MUD 1.3s/round exchanges!)
	var sp_st: Dictionary = world.spar_status()
	if bool(sp_st.get("active", false)):
		if opened.is_empty() and (action_menu == null or not action_menu.visible):
			spar_accum += delta
			if spar_accum >= 1.30:
				spar_accum = 0.0
				var r: Dictionary = world.step_spar_round()
				var msg: String = str(r.get("message", ""))
				if not msg.is_empty():
					_note(msg)
				_play_sfx("clash" if ("格" in msg or "架" in msg or "闪" in msg) else "hit")
				if bool(r.get("finished", false)):
					_set_prompt("")
				else:
					var s2: Dictionary = r.get("session", {})
					_set_prompt("切磋中：%s 气血 %d/%d（第%d合 | 按 U 调加力，Esc 或走开收招）" % [
						str(s2.get("npc_name", "")), int(s2.get("opp_hp", 0)), int(s2.get("opp_max_hp", 100)), int(s2.get("rounds", 0))
					])
				_refresh()
	else:
		spar_accum = 0.0
	# Active Real-Time Progress Bar (workstation / craft / study / dazuo — NO lock; Esc or move cancels!)
	if work_active:
		if not opened.is_empty():
			_cancel_workstation(false)
		else:
			work_elapsed += delta
			board.work_progress = clampf(work_elapsed / maxf(0.1, work_duration), 0.0, 1.0)
			board.work_label = work_label
			board.markers.queue_redraw()
			if work_elapsed >= work_duration:
				_finish_timed_task()
		return
	if not opened.is_empty() or (action_menu != null and action_menu.visible):
		return
	var step := move_input.tick(delta)
	if step != Vector2i.ZERO:
		_apply_directional_step(step)


func _set_prompt(text: String) -> void:
	if sidebar != null:
		sidebar.set_prompt(text)


func _clock_str() -> String:
	var day_min := posmod(int(world.minutes), CanglingCalendar.MINUTES_PER_DAY)
	return "%02d:%02d" % [day_min / 60, day_min % 60]


func _apply_directional_step(direction: Vector2i) -> void:
	if work_active:
		_cancel_workstation(true)
	_stop()
	if not pending_dir_action.is_empty():
		var target: Vector2i = world.pos + direction
		var act := pending_dir_action
		pending_dir_action = ""
		_set_prompt("")
		_execute_directional_action(act, target)
		_refresh()
		return
	if peek_return:
		look_at = NONE
		peek_return = false
		_set_prompt("")
	if look_at == NONE:
		if board.motion.is_resting():
			board.exit_posture()
			_set_prompt("")
		_move_one(world.pos + direction)
	else:
		look_at = (look_at + direction).clamp(Vector2i.ZERO, world.city_size - Vector2i.ONE)
		_set_prompt("环视: %s (%d,%d) — 按 Esc 返回" % [world.location(look_at), look_at.x, look_at.y])
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
	button.custom_minimum_size.y = 28
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CCB.style_button(button, primary)
	parent.add_child(button)
	button.pressed.connect(callback)
	return button


func register_overlay_hotkey(ch: String, callback: Callable) -> void:
	if not ch.is_empty() and not overlay_hotkeys.has(ch):
		overlay_hotkeys[ch] = callback


func _floor_name(z: int) -> String:
	if z == 0:
		return "地面层"
	if z == 1:
		return "二层"
	if z == 2:
		return "三层阁楼"
	return "Z=%d" % z


func _play_sfx(kind: String) -> void:
	if audio_ambience != null and audio_ambience.has_method("play_sfx"):
		audio_ambience.play_sfx(kind)


func _sync_env_and_audio() -> void:
	var sky := CanglingCalendar.at_minute(world.minutes)
	var base_c := 16.0
	match str(sky.get("season", "春")):
		"春": base_c = 16.0
		"夏": base_c = 27.0
		"秋": base_c = 15.0
		"冬": base_c = 2.0
	var hr := float(sky.get("hour", 12.0))
	var diurnal := -4.5 * cos((hr - 14.0) * PI / 12.0)
	var weather_chill := -3.2 * float(weather.rain) - 5.5 * float(weather.snow)
	world.sync_environment(base_c + diurnal + weather_chill, float(weather.rain))
	if audio_ambience != null and audio_ambience.has_method("set_environment"):
		var indoors := false
		var p: Vector2i = world.pos
		if board != null and board.cells.has(p):
			indoors = (int(board.cells[p][3]) & 1) != 0
		var near_w := 0.0
		if world.floor == 0:
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var t: String = world.terrain_at(p + Vector2i(dx, dy))
					if t == "W" or t == "~":
						near_w = 0.8
						break
				if near_w > 0.0:
					break
		audio_ambience.set_environment(float(weather.rain), near_w, indoors)


func _refresh() -> void:
	var sky := CanglingCalendar.at_minute(world.minutes)
	weather.sync(sky, world.seed, false)
	_sync_env_and_audio()
	board.follow(world.pos if look_at == NONE else look_at)
	if sidebar != null:
		sidebar.refresh(world, weather, board)


func _note(text: String) -> void:
	if text.is_empty() or sidebar == null:
		return
	sidebar.add_message(text, _clock_str())


func _stop() -> void:
	period_timer.stop()
	walker.stop()
	if wait_timer != null and wait_timer.time_left > 0.0:
		wait_timer.stop()
		wait_remaining = 0
		_set_prompt("")
		_note("等待已中止。")
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
			_set_prompt("")
			_execute_directional_action(act, cell)
			_refresh()
		else:
			_set_prompt("请点击紧邻身旁的格子，或按 Esc 取消。")
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
	peek_return = false
	_stop()
	if action != "rest" and board.motion.is_resting():
		board.exit_posture()
	_set_prompt("")
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
			_note("没有可走的路线。")
	_refresh()


func _move_one(next: Vector2i) -> bool:
	var was_grabbing: bool = world.is_grabbing()
	var was_hauling: bool = bool(world.character_status().get("hauling", false))
	var next_tile: String = world.terrain_at(next)
	var opens_door: bool = next_tile == "D"
	var climbs_window: bool = next_tile == "O" or next_tile == "%"
	if not world.move_one(next):
		if was_grabbing:
			_note("家具前方受阻，无法继续拖动。")
		elif next_tile == "f":
			_note("前方是木篱（按 e 翻越，或按 s 砸断）。")
		elif next_tile == "w":
			_note("前方是关闭的雕花木窗（按 o 推开，或按 s 砸碎）。")
		return false
	if opens_door:
		_play_sfx("door")
	elif weather != null and float(weather.wetness) > 0.35 and not bool(world.character_status().get("is_indoors", false)):
		_play_sfx("step_puddle")
	else:
		_play_sfx("step_stone")
	if opens_door or was_grabbing:
		board.invalidate_lightmap()
	elif was_hauling:
		board.invalidate_world_cache()
	if climbs_window:
		_note("你翻越了%s。" % ("残破木窗" if next_tile == "%" else "雕花木窗"))
	return true


func _walk() -> void:
	var step: Vector2i = board.route[board.route_head]
	if not _move_one(step):
		_stop()
		_note("道路受阻。")
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
	peek_return = false
	_stop()
	_close_overlay()
	sidebar.clear_messages()
	_note("烟雨画桥，青瓦红灯。你再次踏入沧灵南门。(种子 %d)" % world.seed)
	_refresh()


func _save() -> void:
	_stop()
	_note("游戏进度已存档。" if world.save_game(World.SAVE_PATH) else "存档写入失败。")
	_refresh()


func _load() -> void:
	_stop()
	if world.load_game(World.SAVE_PATH):
		board.clear_footprints()
		board.invalidate_lightmap()
		atlas_cells.clear()
		look_at = NONE
		peek_return = false
		sidebar.clear_messages()
		_note("已读取上次保存的进度。")
	else:
		_note("没有可读取的存档。")
	_refresh()


func _start_wait(minutes: int) -> void:
	_close_overlay()
	_stop()
	wait_remaining = minutes
	_set_prompt("静候中 (%02d:%02d)... 按 Esc 中止" % [wait_remaining / 60, wait_remaining % 60])
	wait_timer.start()


func _advance_wait() -> void:
	if wait_remaining <= 0:
		wait_timer.stop()
		return
	world.advance_time(1)
	wait_remaining -= 1
	_refresh()
	if wait_remaining > 0 and wait_remaining % 15 == 0:
		_set_prompt("静候中 (剩余 %02d:%02d)... 按 Esc 中止" % [wait_remaining / 60, wait_remaining % 60])
	if wait_remaining == 0:
		wait_timer.stop()
		_set_prompt("")
		_note("静候结束。")


func _debug_jump_time_of_day(target_hour: int, target_minute: int) -> void:
	var cur := posmod(world.minutes, CanglingCalendar.MINUTES_PER_DAY)
	var target := target_hour * 60 + target_minute
	var delta := posmod(target - cur, CanglingCalendar.MINUTES_PER_DAY)
	if delta == 0:
		delta = CanglingCalendar.MINUTES_PER_DAY
	world.advance_time(delta)
	board.invalidate_weather()
	_note("调试: 时间跳转至 %02d:%02d。" % [target_hour, target_minute])
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
	_note("调试: 季节切换至%s季。" % CanglingCalendar.SEASONS[season_index])
	_refresh()


func _debug_advance(delta_minutes: int, label_text: String) -> void:
	world.advance_time(delta_minutes)
	board.invalidate_weather()
	_note("调试: 时间推进 %s。" % label_text)
	_refresh()


func _debug_set_weather(kind: int) -> void:
	var sky := CanglingCalendar.at_minute(world.minutes)
	weather.set_override(kind, sky, world.seed, true)
	if weather.snow_cover <= 0.12:
		board.clear_footprints()
	board.invalidate_weather()
	var wname := "自动" if kind < 0 else weather.label()
	_note("调试: 天气切换为「%s」。" % wname)
	_refresh()


func _debug_toggle_roofs() -> void:
	board.roofs_enabled = not board.roofs_enabled
	board.invalidate_weather()
	_note("调试: 室外覆瓦屋顶已%s。" % ("开启" if board.roofs_enabled else "关闭"))
	_refresh()


func _close_overlay() -> void:
	overlay_hotkeys.clear()
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


func _reopen_overlay(kind: String, item_target := NONE) -> void:
	_close_overlay()
	_show_overlay(kind, item_target)


func _show_overlay(kind: String, item_target := NONE) -> void:
	move_input.reset()
	if opened == kind:
		_close_overlay()
		return
	_close_overlay()
	_stop()
	_refresh()
	opened = kind
	overlay_hotkeys.clear()
	overlay_backdrop = ColorRect.new()
	overlay_backdrop.color = Color(0.0, 0.0, 0.0, 0.65 if kind != "map" else 0.85)
	add_child(overlay_backdrop)
	overlay_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	overlay = PanelContainer.new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if kind == "map":
		overlay.offset_left = 10
		overlay.offset_right = -10
		overlay.offset_top = 10
		overlay.offset_bottom = -10
	elif kind in ["debug", "action_menu", "eat", "wear", "take_off", "pickup", "character", "inventory",
			"wield", "apply", "read", "list_nearby", "messages", "help", "skills", "learn_npc", "multiplayer",
			"shop", "craft", "exert", "dismantle", "missions"]:
		overlay.anchor_left = 0.14
		overlay.anchor_right = 0.86
		overlay.anchor_top = 0.07
		overlay.anchor_bottom = 0.93
		overlay.offset_left = 0
		overlay.offset_right = 0
		overlay.offset_top = 0
		overlay.offset_bottom = 0
	else:
		overlay.anchor_left = 0.25
		overlay.anchor_right = 0.75
		overlay.anchor_top = 0.16
		overlay.anchor_bottom = 0.76
		overlay.offset_left = 0
		overlay.offset_right = 0
		overlay.offset_top = 0
		overlay.offset_bottom = 0

	overlay.add_theme_stylebox_override("panel", CCB.box(CCB.BG_PANEL, CCB.BORDER_BRIGHT, 12, 10, 1))
	var contents := _column(overlay, 8)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	contents.add_child(heading)

	var titles := {
		"map": "沧灵城全图 [m]",
		"inventory": "随身行囊 [i]",
		"character": "人物属性与着装 [@]",
		"pause": "系统菜单 [Esc]",
		"wait": "静候等待 [|]",
		"new": "重置沧灵城",
		"debug": "调试菜单 [K]",
		"action_menu": "动作菜单 [Enter]",
		"eat": "进食 / 饮水 [E]",
		"wear": "穿戴衣物 [W]",
		"take_off": "脱下与整理着装 [T / +]",
		"pickup": "拾取与查看物品 [g / ,]",
		"wield": "手持物品 [w]",
		"apply": "使用 / 激活物品 [a]",
		"read": "阅读书籍 [R]",
		"list_nearby": "周边物品与设施 [V]",
		"move_mode": "移动姿态 [\"]",
		"messages": "历史消息日志 [P]",
		"missions": "沧灵城见闻与帮工 [M]",
		"skills": "江湖技能面板 · 武学 / 激发 / 研究 [J]",
		"learn_npc": "向师傅请教技艺 (消耗潜能)",
		"shop": "市井商贸 · 钱庄 · 典当 · 客栈",
		"craft": "CCB 手工制作 · 烹饪 / 制药 / 锻造 / 抄录 [&]",
		"exert": "内功盘膝打坐与运功法门 [U]",
		"dismantle": "拆解衣物 / 床品得碎布条 [B]",
		"multiplayer": "多人联机接口 (Multiplayer) [O]",
		"help": "CCB 键位帮助 [? / 0]",
	}
	var title := _label(heading, titles.get(kind, kind), 16, CCB.C_YELLOW)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var close := _button(heading, "[Esc] 关闭", _close_overlay)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(88, 26)
	contents.add_child(CCB.divider())

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
		"wield":
			CCBUI.wield_menu(self, contents)
		"apply":
			CCBUI.apply_menu(self, contents)
		"read":
			CCBUI.read_menu(self, contents)
		"list_nearby":
			CCBUI.list_nearby_menu(self, contents)
		"move_mode":
			CCBUI.move_mode_menu(self, contents)
		"messages":
			CCBUI.messages_menu(self, contents)
		"missions":
			CCBUI.missions_menu(self, contents)
		"skills":
			SkillUI.skill_panel(self, contents)
		"learn_npc":
			SkillUI.learn_panel(self, contents, item_target)
		"shop":
			ShopUI.open_panel(self, contents, item_target)
		"craft":
			CraftUI.open_panel(self, contents)
		"exert":
			SkillUI.exert_panel(self, contents)
		"dismantle":
			CCBUI.dismantle_menu(self, contents)
		"multiplayer":
			SkillUI.multiplayer_panel(self, contents)
		"help":
			CCBUI.help_menu(self, contents)
		"inventory":
			Items.inventory(self, contents, item_target)
		"character":
			CCBUI.character_sheet(self, contents)
		"pause":
			var entries := [
				["继续游戏", func(): _close_overlay(), true],
				["江湖技能面板 [J]", func(): _show_overlay("skills"), false],
				["多人联机接口 [O]", func(): _show_overlay("multiplayer"), false],
				["键位帮助 [?]", func(): _show_overlay("help"), false],
				["静候等待 [|]", func(): _show_overlay("wait"), false],
				["调试菜单 [K]", func(): _show_overlay("debug"), false],
				["保存进度 [S]", func(): _close_overlay(); _save(), false],
				["读取存档", func(): _close_overlay(); _load(), false],
				["新建城市（指定种子）", func(): _show_overlay("new"), false],
			]
			for i in range(entries.size()):
				var letter := CCB.letter_key(i)
				var cb: Callable = entries[i][1]
				var b := _button(contents, "%s - %s" % [letter, entries[i][0]], cb, entries[i][2])
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				register_overlay_hotkey(letter, cb)
		"wait":
			_label(contents, "选择静候时长 (按字母立即开始，随时按 Esc 中止)：", 12, CCB.C_LTGRAY, true)
			var durs := [["5 分钟", 5], ["15 分钟", 15], ["30 分钟", 30], ["1 小时", 60], ["3 小时", 180], ["6 小时", 360], ["12 小时", 720]]
			for i in range(durs.size()):
				var letter := CCB.letter_key(i)
				var mins: int = durs[i][1]
				var cb := func(): _start_wait(mins)
				var b := _button(contents, "%s - 静候 %s" % [letter, durs[i][0]], cb)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				register_overlay_hotkey(letter, cb)
		"new":
			_label(contents, "输入城市种子 (留空则随机生成):", 12, CCB.C_LTGRAY)
			var field := LineEdit.new()
			field.placeholder_text = "留空随机"
			field.max_length = 10
			CCB.style_line_edit(field)
			contents.add_child(field)
			var error_label := _label(contents, "", 12, CCB.C_RED, true)
			_button(contents, "生成新城市", _new_game.bind(field, error_label), true)
			field.text_submitted.connect(func(_text: String): _new_game(field, error_label))
			field.grab_focus()
		"debug":
			_build_debug_menu(contents)


func _build_debug_menu(contents: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var body := _column(scroll, 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 6, 1))
	body.add_child(summary)
	var scol := _column(summary, 2)
	_label(scol, "时间: %s  |  天气: %s (%s)  |  积水 %.0f%%  积雪 %.0f%%" % [
		CanglingCalendar.time_label(world.minutes), weather.label(),
		"自动" if weather.override_kind < 0 else "锁定",
		weather.wetness * 100.0, weather.snow_cover * 100.0], 12, CCB.C_YELLOW)
	var perf: Dictionary = world.perf_stats()
	_label(scol, "FPS:%d | CPU:%d/%d核 | 区块:%d | 内存:%.0fKB | 释放:%d次(%.0fKB) | 烘焙:%.1fms" % [
		Engine.get_frames_per_second(),
		int(perf.get("cpu_threads", 1)), int(perf.get("hardware_threads", 1)),
		int(perf.get("cached_sectors", 0)), float(perf.get("memory_kb", 0.0)),
		int(perf.get("auto_trim_count", 0)), float(perf.get("auto_freed_kb", 0.0)),
		float(perf.get("last_bake_ms", 0.0))], 12, CCB.C_CYAN)

	_label(body, "[ 时间跳转 ]", 12, CCB.C_CYAN)
	var time_grid := GridContainer.new()
	time_grid.columns = 3
	time_grid.add_theme_constant_override("h_separation", 6)
	time_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(time_grid)
	for preset in [["拂晓 05:30", 5, 30], ["清晨 07:20", 7, 20], ["正午 12:00", 12, 0],
			["午后 15:30", 15, 30], ["黄昏 17:45", 17, 45], ["子夜 00:30", 0, 30]]:
		_button(time_grid, preset[0], func(): _debug_jump_time_of_day(preset[1], preset[2]); _close_overlay())

	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 6)
	body.add_child(step_row)
	for step_spec in [["+1小时", 60], ["+3小时", 180], ["+6小时", 360], ["+1天", 1440]]:
		_button(step_row, step_spec[0], func(): _debug_advance(step_spec[1], step_spec[0]); _close_overlay())

	_label(body, "[ 切换季节 ]", 12, CCB.C_CYAN)
	var season_row := HBoxContainer.new()
	season_row.add_theme_constant_override("separation", 6)
	body.add_child(season_row)
	for i in range(CanglingCalendar.SEASONS.size()):
		var sname: String = CanglingCalendar.SEASONS[i]
		_button(season_row, sname + "季", func(): _debug_jump_season(i); _close_overlay())

	_label(body, "[ 切换天气 ]", 12, CCB.C_CYAN)
	var weather_grid := GridContainer.new()
	weather_grid.columns = 3
	weather_grid.add_theme_constant_override("h_separation", 6)
	weather_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(weather_grid)
	var weather_specs := [
		["自动", -1], ["晴朗", Weather.Kind.CLEAR], ["多云阴天", Weather.Kind.CLOUDY],
		["烟雨", Weather.Kind.LIGHT_RAIN], ["大雨", Weather.Kind.HEAVY_RAIN],
		["小雪", Weather.Kind.LIGHT_SNOW], ["大雪", Weather.Kind.HEAVY_SNOW],
	]
	for spec in weather_specs:
		var is_active: bool = (spec[1] == -1 and weather.override_kind < 0) or (spec[1] >= 0 and weather.override_kind == spec[1])
		_button(weather_grid, spec[0], func(): _debug_set_weather(spec[1]); _close_overlay(), is_active)

	_label(body, "[ 画面与内存 ]", 12, CCB.C_CYAN)
	var opt_row := HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 6)
	body.add_child(opt_row)
	_button(opt_row, "屋顶显示:%s" % ("开" if board.roofs_enabled else "关"),
		func(): _debug_toggle_roofs(); _close_overlay(), board.roofs_enabled)
	_button(opt_row, "清空脚印", func(): board.clear_footprints(); board.markers.queue_redraw(); _close_overlay())
	_button(opt_row, "释放冷缓存", func():
		var freed_kb := float(world.trim_memory(true)) / 1024.0
		var freed_pages: int = board.Tiles.trim_unused_pages(0)
		_note("内存管理: 已释放 %.0f KB 区块缓存、%d 页图集。" % [freed_kb, freed_pages])
		_close_overlay())


func _gui_input(event: InputEvent) -> void:
	if not opened.is_empty() and event is InputEventMouseButton:
		accept_event()


func _build_atlas(contents: VBoxContainer) -> void:
	var panel := HBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(panel)
	var atlas_frame := PanelContainer.new()
	atlas_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atlas_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	atlas_frame.add_theme_stylebox_override("panel", CCB.box(Color("050505"), CCB.BORDER, 1, 1, 1))
	panel.add_child(atlas_frame)
	atlas = Atlas.new()
	atlas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atlas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	atlas_frame.add_child(atlas)

	var side_card := PanelContainer.new()
	side_card.custom_minimum_size.x = 240
	side_card.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 8, 1))
	panel.add_child(side_card)
	var side := _column(side_card, 6)
	_label(side, "[ 选中区块 ]", 12, CCB.C_CYAN)
	var name_label := _label(side, "", 16, CCB.C_YELLOW, true)
	var details := _label(side, "", 12, CCB.C_WHITE, true)
	side.add_child(CCB.divider())
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	side.add_child(tools)
	_button(tools, "观全城", atlas.fit)
	_button(tools, "前往此地", atlas.travel, true)
	side.add_child(CCB.divider())
	_label(side, "[ 当前委托 ]", 12, CCB.C_CYAN)
	_label(side, world.quest_text, 12, CCB.C_WHITE, true)
	side.add_child(CCB.divider())
	_label(side, "滚轮缩放 | 中键拖拽 | 右键自动寻路", 11, CCB.C_DKGRAY, true)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	_label(side, "%d x %d | 种子 %d" % [world.city_size.x, world.city_size.y, world.seed], 11, CCB.C_DKGRAY)
	atlas.selection_changed.connect(func(title_txt: String, data_txt: String):
		name_label.text = title_txt
		details.text = data_txt)
	atlas.destination_requested.connect(_travel_from_overview)
	if atlas_cells.is_empty() or atlas_seed != world.seed:
		atlas_cells = world.city_survey()
		atlas_seed = world.seed
	atlas.build(world, atlas_cells)


func _cancel_workstation(notify := true) -> void:
	if not work_active:
		return
	var was_kind := work_kind
	work_active = false
	work_kind = "workstation"
	work_target = NONE
	work_recipe_id = ""
	work_item_id = -1
	work_elapsed = 0.0
	work_label = ""
	if board != null:
		board.work_progress = 0.0
		board.work_label = ""
		if was_kind == "dazuo" and board.motion.is_resting():
			board.exit_posture()
		board.markers.queue_redraw()
	_set_prompt("")
	if notify:
		if was_kind == "dazuo":
			_note("你缓缓吐出一口浊气，收功起身。")
		elif was_kind == "study":
			_note("你合上书卷，暂且停读。")
		elif was_kind == "craft":
			_note("已中断当前制作。")
		else:
			_note("已中断当前工位劳作。")


func _finish_timed_task() -> void:
	var kind := work_kind
	if kind == "dazuo":
		work_elapsed = 0.0
		var r: Dictionary = world.dazuo_cycle()
		_note(str(r.get("message", "")))
		_play_sfx("meditate")
		if not bool(r.get("continue", false)):
			_cancel_workstation(false)
		_refresh()
		return
	var target := work_target
	var rid := work_recipe_id
	var iid := work_item_id
	_cancel_workstation(false)
	if kind == "workstation":
		var res: Dictionary = net_session.dispatch_action(world, {"type": "workstation", "target": target})
		_note(str(res.get("message", "")))
		_play_sfx("work")
	elif kind == "craft":
		var res: Dictionary = net_session.dispatch_action(world, {"type": "craft", "recipe_id": rid})
		_note(str(res.get("message", "")))
		_play_sfx("work")
	elif kind == "study":
		var res: Dictionary = net_session.dispatch_action(world, {"type": "study_book", "item_id": iid})
		_note(str(res.get("message", "")))
		_play_sfx("book")
	_refresh()


func _start_workstation(position: Vector2i) -> void:
	_cancel_workstation(false)
	var chk: Dictionary = world.can_work_at_station(position)
	if not bool(chk.get("ok", false)):
		_note(str(chk.get("reason", "无法在此工位劳作。")))
		return
	var ws: Dictionary = chk.get("station", {})
	work_active = true
	work_kind = "workstation"
	work_target = position
	work_elapsed = 0.0
	work_duration = float(ws.get("duration_sec", 2.5))
	work_label = str(ws.get("name", "工位劳作"))
	if board != null:
		if position.x < world.pos.x:
			board.motion.facing_x = -1
		elif position.x > world.pos.x:
			board.motion.facing_x = 1
		board.work_progress = 0.02
		board.work_label = work_label
		board.markers.queue_redraw()
	_set_prompt("正在「%s」劳作中 (%.1f 秒，按 Esc 可随时中断)..." % [work_label, work_duration])


func _start_craft_task(recipe_id: String, recipe_name: String, duration: float) -> void:
	var chk: Dictionary = world.can_craft_recipe(recipe_id)
	if not bool(chk.get("ok", false)):
		_note(str(chk.get("reason", "制作条件未满足。")))
		return
	_close_overlay()
	_cancel_workstation(false)
	work_active = true
	work_kind = "craft"
	work_recipe_id = recipe_id
	work_elapsed = 0.0
	work_duration = maxf(0.8, duration)
	work_label = "制作：" + recipe_name
	if board != null:
		board.work_progress = 0.02
		board.work_label = work_label
		board.markers.queue_redraw()
	_set_prompt("正在制作「%s」(%.1f 秒，移动或 Esc 可中断)..." % [recipe_name, work_duration])


func _start_study_book(item_id: int, book_name: String) -> void:
	_cancel_workstation(false)
	work_active = true
	work_kind = "study"
	work_item_id = item_id
	work_elapsed = 0.0
	work_duration = 2.5
	work_label = "精读：" + book_name
	if board != null:
		board.work_progress = 0.02
		board.work_label = work_label
		board.markers.queue_redraw()
	_set_prompt("正在精读《%s》(2.5 秒，移动或 Esc 可中断)..." % book_name)


func _start_dazuo() -> void:
	_cancel_workstation(false)
	if int(world.skill_level("force")) <= 0:
		_note("你尚未习得「基本内功」，请先赴扬威武馆向陈馆主请教。")
		return
	work_active = true
	work_kind = "dazuo"
	work_elapsed = 0.0
	work_duration = 2.0
	work_label = "盘膝打坐吐纳"
	if board != null:
		board.enter_posture(&"meditating", world.pos)
		board.work_progress = 0.02
		board.work_label = work_label
		board.markers.queue_redraw()
	_play_sfx("meditate")
	_set_prompt("盘膝打坐运周天中（满内力后可冲关提上限，移动或 Esc 收功）...")


func _perform_action(position: Vector2i, action: String) -> void:
	match action:
		"learn_menu":
			_show_overlay("learn_npc", position)
		"shop_menu", "bank_menu":
			shop_mode = "buy"
			_show_overlay("shop", position)
		"bounty_board":
			_show_overlay("missions")
		"bounty_turnin":
			_note(world.turn_in_bounty(position))
			_play_sfx("coin")
		"spar":
			var sr: Dictionary = world.start_spar(position)
			_note(str(sr.get("message", "")))
			if bool(sr.get("ok", false)):
				spar_accum = 0.65
				_play_sfx("clash")
				_set_prompt("切磋开始！（每 1.3 秒交手一合，按 U 调加力，Esc 或走开收招）")
		"workstation":
			_start_workstation(position)
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
						_set_prompt("正躺在床榻上歇息 (按方向键起身)")
					elif tile == "q" or tile == "S":
						board.enter_posture(&"sitting", position)
						_set_prompt("正坐在椅凳上歇息 (按方向键起身)")
				elif action in ["door", "window", "smash", "stairs_up", "stairs_down"]:
					board.invalidate_lightmap()
				elif action in ["grab", "release_grab"]:
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
				"smash":
					if t in ["w", "O", "D", "o", "f", "b", "q", "S", "t", "l", "k", "K", "c", "F", "r", "C", "a", "u", "P", "g"]:
						found.append(p)
				"grab":
					if t in ["q", "S", "t", "l", "C", "c", "a", "u", "b", "k", "K", "r", "P"]:
						found.append(p)
				"examine":
					if t in ["c", "C", "F", "K", "r", "b", "q", "S", "t", "l", "k", "h", "u", "a", "D", "o", "w", "O", "%", "f"] \
							or not world.items_at(p).is_empty() \
							or not world.workstation_at(p).is_empty() \
							or world.site_at(p) == &"notice_board" \
							or world.site_at(p) in Board.NPC_SITES:
						found.append(p)
				"chat":
					if world.site_at(p) in Board.NPC_SITES:
						found.append(p)
				"drop_dir", "peek":
					found.append(p)
	return found


func _start_directional_action(act: String) -> void:
	if act == "grab" and world.is_grabbing():
		var msg: String = world.release_grab()
		_note(msg)
		board.markers.queue_redraw()
		_refresh()
		return
	var cands := _candidates_for_dir_action(act)
	if cands.is_empty():
		var labels := {
			"open": "打开的门、窗或柜子",
			"close": "关闭的门、窗或柜子",
			"smash": "砸碎的物件",
			"grab": "抓取拖拽的家具",
			"examine": "检查或翻越的对象",
			"chat": "交谈的人物",
		}
		_note("身旁没有可%s。" % labels.get(act, "操作的目标"))
		return
	if cands.size() == 1 and act not in ["drop_dir", "peek"]:
		_execute_directional_action(act, cands[0])
		_refresh()
		return
	pending_dir_action = act
	var prompts := {
		"open": "向哪个方向开门/窗/柜？",
		"close": "向哪个方向关门/窗/柜？",
		"smash": "向哪个方向砸碎？",
		"grab": "抓取哪个方向的家具？",
		"examine": "检查 / 翻越哪个方向？",
		"drop_dir": "向哪个方向丢弃物品？",
		"peek": "向哪个方向探头窥视？",
		"chat": "与哪个方向的人物交谈？",
	}
	_set_prompt("%s (方向键/小键盘/vi键/点击邻格，Esc取消)" % prompts.get(act, "选择方向"))


func _execute_directional_action(act: String, target: Vector2i) -> void:
	match act:
		"open":
			var msg: String = world.open_at(target)
			if msg.is_empty():
				_note("那个方向没有可打开的门、窗或柜子。")
			else:
				_note(msg)
				board.invalidate_lightmap()
				if world.is_container_open(target) and not world.items_at(target).is_empty():
					_show_overlay("pickup", target)
		"close":
			var msg: String = world.close_at(target)
			if msg.is_empty():
				_note("那个方向没有可关闭的门、窗或柜子。")
			else:
				_note(msg)
				board.invalidate_lightmap()
		"smash":
			var msg: String = world.smash_at(target)
			_note(msg)
			board.invalidate_lightmap()
		"grab":
			var msg: String = world.grab_furniture(target)
			_note(msg)
			board.markers.queue_redraw()
		"drop_dir":
			_show_overlay("inventory", target)
		"peek":
			var delta := target - world.pos
			look_at = (world.pos + delta * 3).clamp(Vector2i.ZERO, world.city_size - Vector2i.ONE)
			peek_return = true
			_set_prompt("窥视: %s (%d,%d) — 按任意方向键或 Esc 缩回" % [world.location(look_at), look_at.x, look_at.y])
		"chat":
			var s: StringName = world.site_at(target)
			if s in Board.NPC_SITES:
				_note(world.interact(target, "talk"))
			else:
				_note("那个方向没有人可以交谈。")
		"examine":
			var s: StringName = world.site_at(target)
			if s == &"notice_board":
				_show_overlay("missions")
				return
			if s in Board.NPC_SITES:
				_open_actions(target)
				return
			if not world.workstation_at(target).is_empty():
				_start_workstation(target)
				return
			var t: String = world.terrain_at(target)
			# CCB examine: fences / open & broken windows climb directly; containers open & show loot;
			# hearths warm up; tables/counters with items loot, empty climb!
			if t in ["f", "O", "%"]:
				var cmsg: String = world.climb_at(target)
				_note(cmsg)
				board.invalidate_lightmap()
			elif t in ["c", "C", "F", "K", "r"]:
				_perform_action(target, "container")
			elif not world.items_at(target).is_empty():
				_show_overlay("pickup", target)
			elif t in ["t", "l", "k"]:
				var cmsg: String = world.climb_at(target)
				_note(cmsg)
			elif t == "h":
				_perform_action(target, "warm_hearth")
			elif t == "u":
				_perform_action(target, "wash")
			else:
				var msg: String = world.interact(target, "inspect")
				_note(msg if not msg.is_empty() else "那里没有什么特别的东西。")


func _run_ccb_action(act_id: String) -> void:
	match act_id:
		"action_menu":
			_show_overlay("action_menu")
		"sky":
			_note(CCBUI.observe_sky_message(self))
		"look":
			_stop()
			peek_return = false
			look_at = world.pos if look_at == NONE else NONE
			_set_prompt("环视: %s (%d,%d) — 按 Esc 结束" % [world.location(look_at), look_at.x, look_at.y] if look_at != NONE else "")
			_refresh()
		"map", "inventory", "eat", "wear", "take_off", "pickup", "character", "wait", "debug", \
				"wield", "apply", "read", "list_nearby", "move_mode", "messages", "missions", "skills", \
				"multiplayer", "craft", "exert", "dismantle", "help":
			_show_overlay(act_id)
		"toggle_audio":
			if audio_ambience != null and audio_ambience.has_method("toggle_mute"):
				var is_m: bool = audio_ambience.toggle_mute()
				_note("江南环境声景与交互音效已%s。" % ("静音" if is_m else "开启"))
		"drop":
			_show_overlay("inventory", world.pos)
		"open", "close", "smash", "examine", "grab", "drop_dir", "peek", "chat":
			_start_directional_action(act_id)
		"apply_wielded":
			_note(world.apply_wielded())
			board.player_layer.queue_redraw()
			_refresh()
		"haul":
			_note(world.toggle_haul())
			board.markers.queue_redraw()
			_refresh()
		"safe_mode":
			_note(world.toggle_safe_mode())
			_refresh()
		"zoom_in":
			board.zoom = clampi(board.zoom + 1, 0, Board.ZOOMS.size() - 1)
			board._update_view()
		"zoom_out":
			board.zoom = clampi(board.zoom - 1, 0, Board.ZOOMS.size() - 1)
			board._update_view()
		"stairs_up":
			_note(world.change_floor(1))
			board.invalidate_lightmap()
			_refresh()
		"stairs_down":
			_note(world.change_floor(-1))
			board.invalidate_lightmap()
			_refresh()
		"stand":
			board.exit_posture()
			_set_prompt("")
			_note("你起身整了整衣衫。")
			_refresh()
		"sleep":
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
				_note("你在原地小憩了半个时辰。")
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
	# Real-time clock mode: idling recovers a breath of stamina without altering game time
	world.rest_minutes(1, false)
	_refresh()


func _repeat_period() -> void:
	var held := Input.is_physical_key_pressed(period_key) if period_key != KEY_NONE else Input.is_key_pressed(KEY_PERIOD)
	if not held or not opened.is_empty() or action_menu.visible:
		return
	_period_tick()
	period_timer.start(0.11)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var key: Key = event.physical_keycode

	if key == KEY_ESCAPE and not event.echo:
		if bool(world.spar_status().get("active", false)):
			_note(world.stop_spar())
			_set_prompt("")
			_refresh()
			get_viewport().set_input_as_handled()
			return
		if work_active:
			_cancel_workstation(true)
			get_viewport().set_input_as_handled()
			return
		if not pending_dir_action.is_empty():
			pending_dir_action = ""
			_set_prompt("")
			_note("已取消操作。")
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
			peek_return = false
			_set_prompt("")
			_stop()
			_refresh()
		else:
			_show_overlay("pause")
		get_viewport().set_input_as_handled()
		return

	# Active CCB Overlay: dispatch lettered shortcuts ('a'..'z', 'A'..'Z', ',') directly via event.unicode!
	if not opened.is_empty():
		if atlas != null and atlas.keyboard(key):
			get_viewport().set_input_as_handled()
			return
		if opened not in ["new", "multiplayer"] and not event.echo and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed):
			var ch := Keymap.event_char(event)
			if not ch.is_empty() and overlay_hotkeys.has(ch):
				var cb: Callable = overlay_hotkeys[ch]
				cb.call()
				get_viewport().set_input_as_handled()
		return

	# If waiting for a direction (o/c/s/e/G/D/X/C), accept movement direction keys first!
	if not pending_dir_action.is_empty():
		if move_input.is_movement_key(event):
			var d := move_input.key_to_dir(event)
			if d != Vector2i.ZERO:
				_apply_directional_step(d)
			get_viewport().set_input_as_handled()
			return

	# Pure CCB Unicode-character action bindings (uppercase detected directly via char(event.unicode), NOT shift+x!)
	if not event.echo:
		var act := Keymap.match_action(event)
		if not act.is_empty():
			_run_ccb_action(act)
			get_viewport().set_input_as_handled()
			return

	# Pass 1 turn ('.' / '5' / KP_5)
	if Keymap.is_wait_turn_key(event):
		if not event.echo:
			_stop()
			period_key = key
			_period_tick()
			period_timer.start(0.27)
		get_viewport().set_input_as_handled()
		return

	# Pure CCB 8-direction movement (Numpad 1-9, Arrows, lowercase vi-keys h/j/k/l/y/u/b/n)
	if move_input.is_movement_key(event):
		var direction := move_input.handle_key_press(event)
		if direction != Vector2i.ZERO:
			_apply_directional_step(direction)
		get_viewport().set_input_as_handled()
