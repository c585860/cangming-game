extends PanelContainer

# Authentic Cataclysm-Cleanwater-Bomb (CCB) Classic Right Sidebar
# Faithfully mirrors Cataclysm-Cleanwater-Bomb/data/json/ui/sidebar-legacy-classic.json + src/panels.cpp:
# - Row 1 (3-column): 6 Body Part HP bars | Pain/Hunger/Thirst/Fatigue/Temp/Morale | STR/DEX/INT/PER/Focus/Safe
# - Row 2: Movement Mode, Speed, Sound, Stamina ||||| bar, Active State Badges (Grab/Haul/Lamp)
# - Row 3: Location + Z-level + Coords + Framed Overmap Minimap
# - Row 4: Season/Day/Clock + Weather + Lighting + Silver/Herbs
# - Row 5: Wielded item + Bottle / Volume / Weight / Warmth / Encumbrance
# - Row 6: 8-Direction CCB Compass (NW N NE / W @ E / SW S SE)
# - Row 7: Prompt Bar + Color-Coded CCB Message Log + Bottom Hotkey Reference Strip

const CCB = preload("res://scripts/ccb_theme.gd")
const Survey = preload("res://scripts/survey.gd")
const CanglingCalendar = preload("res://scripts/cangling_calendar.gd")

const PART_NAMES := ["头  ", "躯  ", "左臂", "右臂", "左腿", "右腿"]

var minimap: Survey
var status_prompt: Label
var log_container: VBoxContainer
var _log_history: Array[Dictionary] = []

# Row 1: Body parts (6), Needs (6), Stats (6)
var _part_labels: Array[Label] = []
var _pain_lbl: Label
var _hunger_lbl: Label
var _thirst_lbl: Label
var _fatigue_lbl: Label
var _temp_lbl: Label
var _morale_lbl: Label
var _str_lbl: Label
var _dex_lbl: Label
var _int_lbl: Label
var _per_lbl: Label
var _focus_lbl: Label
var _safe_lbl: Label

# Row 2: Move mode, speed, sound, stamina, flags
var _move_lbl: Label
var _speed_lbl: Label
var _sound_lbl: Label
var _stam_lbl: Label
var _flags_lbl: Label

# Row 3: Location, Z, Coords
var _loc_lbl: Label
var _z_lbl: Label

# Row 4: Time, Weather, Light, Quest
var _time_lbl: Label
var _weather_lbl: Label
var _light_lbl: Label
var _quest_lbl: Label

# Row 5: Wielded, Carry
var _wield_lbl: Label
var _carry_lbl: Label

# Row 6: 8-direction Compass cells (0..8 where 4 is '@')
var _compass_cells: Array[Label] = []


func build(world: RefCounted) -> void:
	custom_minimum_size.x = 326
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = CCB.BG_PANEL
	sb.border_color = CCB.BORDER
	sb.border_width_left = 1
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.clip_contents = true
	add_child(root)

	# --- ROW 1: 3-Column CCB Classic Core Panel (Body HP | Needs | Core Stats) ---
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	root.add_child(row1)

	var col_hp := VBoxContainer.new()
	col_hp.add_theme_constant_override("separation", 1)
	col_hp.custom_minimum_size.x = 104
	row1.add_child(col_hp)
	_part_labels.clear()
	for i in range(6):
		_part_labels.append(_mk_lbl(col_hp, "%s |||||" % PART_NAMES[i], 12, CCB.C_LTGREEN))

	var col_needs := VBoxContainer.new()
	col_needs.add_theme_constant_override("separation", 1)
	col_needs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(col_needs)
	_pain_lbl = _mk_lbl(col_needs, "无痛", 12, CCB.C_GREEN)
	_hunger_lbl = _mk_lbl(col_needs, "饱足", 12, CCB.C_GREEN)
	_thirst_lbl = _mk_lbl(col_needs, "不渴", 12, CCB.C_GREEN)
	_fatigue_lbl = _mk_lbl(col_needs, "精力尚可", 12, CCB.C_LTGRAY)
	_temp_lbl = _mk_lbl(col_needs, "体温: 舒适", 12, CCB.C_LTGRAY)
	_morale_lbl = _mk_lbl(col_needs, "心境: :)", 12, CCB.C_LTGREEN)

	var col_stats := VBoxContainer.new()
	col_stats.add_theme_constant_override("separation", 1)
	col_stats.custom_minimum_size.x = 76
	row1.add_child(col_stats)
	_str_lbl = _mk_lbl(col_stats, "力量  8", 12, CCB.C_WHITE)
	_dex_lbl = _mk_lbl(col_stats, "敏捷  8", 12, CCB.C_WHITE)
	_int_lbl = _mk_lbl(col_stats, "智力  8", 12, CCB.C_WHITE)
	_per_lbl = _mk_lbl(col_stats, "感知  8", 12, CCB.C_WHITE)
	_focus_lbl = _mk_lbl(col_stats, "专注 100", 12, CCB.C_CYAN)
	_safe_lbl = _mk_lbl(col_stats, "安全  开", 12, CCB.C_LTGREEN)

	root.add_child(CCB.divider())

	# --- ROW 2: Movement Mode, Speed, Sound, Stamina Bar & Active Flags ---
	var row2a := HBoxContainer.new()
	row2a.add_theme_constant_override("separation", 8)
	root.add_child(row2a)
	_move_lbl = _mk_lbl(row2a, "姿态: 行走", 12, CCB.C_WHITE)
	_speed_lbl = _mk_lbl(row2a, "速度 100", 12, CCB.C_LTGRAY)
	_sound_lbl = _mk_lbl(row2a, "声响 0", 12, CCB.C_DKGRAY)
	_sound_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var row2b := HBoxContainer.new()
	row2b.add_theme_constant_override("separation", 6)
	root.add_child(row2b)
	_stam_lbl = _mk_lbl(row2b, "耐力 ||||| 100%", 12, CCB.C_CYAN)
	_flags_lbl = _mk_lbl(row2b, "", 12, CCB.C_YELLOW)
	_flags_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flags_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	root.add_child(CCB.divider())

	# --- ROW 3: Location + Z-level + Black-Framed Minimap ---
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	root.add_child(row3)
	_loc_lbl = _mk_lbl(row3, "沧菱城", 13, CCB.C_LTCYAN)
	_loc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_z_lbl = _mk_lbl(row3, "Z:0 (地面)", 12, CCB.C_LTGRAY)

	var map_frame := PanelContainer.new()
	map_frame.add_theme_stylebox_override("panel", CCB.box(Color("050505"), CCB.BORDER, 1, 1, 1))
	root.add_child(map_frame)
	minimap = Survey.new()
	minimap.custom_minimum_size.y = 112
	minimap.build(world)
	map_frame.add_child(minimap)

	root.add_child(CCB.divider())

	# --- ROW 4: Date, Clock, Weather, Lighting & Active Mission ---
	var row4a := HBoxContainer.new()
	row4a.add_theme_constant_override("separation", 6)
	root.add_child(row4a)
	_time_lbl = _mk_lbl(row4a, "", 12, CCB.C_YELLOW)
	_time_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather_lbl = _mk_lbl(row4a, "", 12, CCB.C_WHITE)

	var row4b := HBoxContainer.new()
	row4b.add_theme_constant_override("separation", 6)
	root.add_child(row4b)
	_light_lbl = _mk_lbl(row4b, "光线: 明亮", 12, CCB.C_LTGRAY)
	_light_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_lbl = _mk_lbl(row4b, "铜钱 0 | 药草 0/3", 12, CCB.C_BROWN)

	root.add_child(CCB.divider())

	# --- ROW 5: Wielded Item & Carry Capacity ---
	_wield_lbl = _mk_lbl(root, "手持: 空手", 12, CCB.C_WHITE)
	_carry_lbl = _mk_lbl(root, "水壶 500/750ml | 容积 0.0/2.5L | 重 0.0kg", 11, CCB.C_LTGRAY)

	root.add_child(CCB.divider())

	# --- ROW 6: Authentic CCB 8-Direction Compass ---
	var comp_grid := GridContainer.new()
	comp_grid.columns = 3
	comp_grid.add_theme_constant_override("h_separation", 4)
	comp_grid.add_theme_constant_override("v_separation", 1)
	root.add_child(comp_grid)
	_compass_cells.clear()
	for i in range(9):
		var lbl := _mk_lbl(comp_grid, "@" if i == 4 else ".", 11, CCB.C_LTCYAN if i == 4 else CCB.C_DKGRAY)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 4:
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif i % 3 == 2:
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_compass_cells.append(lbl)

	root.add_child(CCB.divider())

	# --- ROW 7: Active Direction/Action Prompt + CCB Message Log ---
	status_prompt = _mk_lbl(root, "", 12, CCB.C_YELLOW, true)
	status_prompt.visible = false

	var log_scroll := ScrollContainer.new()
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(log_scroll)
	log_container = VBoxContainer.new()
	log_container.add_theme_constant_override("separation", 2)
	log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_container)

	root.add_child(CCB.divider())

	# --- ROW 8: Compact CCB Key Strip ---
	var key_bar := _mk_lbl(root, "Enter动作 o开 c关 s砸 e查/翻 g拾 G拖 \\运 w持 a用 E吃 W穿 T脱 R读 V周 ?键", 10, CCB.C_DKGRAY, true)
	key_bar.clip_text = false


func _mk_lbl(parent: Node, text: String, font_size: int, color: Color, wrap := false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	if wrap:
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)
	return lbl


func set_prompt(text: String) -> void:
	status_prompt.text = text
	status_prompt.visible = not text.is_empty()


func add_message(text: String, clock_text: String) -> void:
	if text.is_empty():
		return
	var col := CCB.C_WHITE
	if "砸" in text or "碎" in text or "受阻" in text or "不足" in text or "无法" in text or "没有" in text or "已空" in text:
		col = CCB.C_YELLOW if ("没有" in text or "受阻" in text or "无法" in text or "不足" in text or "已空" in text) else CCB.C_LTRED
	elif "拿起" in text or "拾取" in text or "穿上" in text or "吃" in text or "饮" in text or "喝" in text or "包扎" in text or "点亮" in text or "研读" in text:
		col = CCB.C_LTGREEN
	elif "翻越" in text or "翻过" in text or "跃过" in text or "打开" in text or "推开" in text or "拖拽" in text or "拖运" in text:
		col = CCB.C_LTCYAN
	elif "存档" in text or "调试" in text or "姿态" in text or "安全模式" in text:
		col = CCB.C_YELLOW

	_log_history.push_front({"clock": clock_text, "text": text, "color": col})
	if _log_history.size() > 80:
		_log_history.resize(80)

	var entry := _mk_lbl(log_container, "[%s] %s" % [clock_text, text], 12, col, true)
	log_container.move_child(entry, 0)
	if log_container.get_child_count() > 16:
		var old := log_container.get_child(16)
		log_container.remove_child(old)
		old.queue_free()
	for i in range(log_container.get_child_count()):
		var lbl: Label = log_container.get_child(i)
		if i == 0:
			lbl.add_theme_color_override("font_color", col)
		elif i <= 2:
			lbl.add_theme_color_override("font_color", col.lerp(CCB.C_LTGRAY, 0.35))
		else:
			lbl.add_theme_color_override("font_color", CCB.C_DKGRAY)


func clear_messages() -> void:
	_log_history.clear()
	for c in log_container.get_children():
		log_container.remove_child(c)
		c.queue_free()


func get_history() -> Array[Dictionary]:
	return _log_history


func refresh(world: RefCounted, weather: RefCounted, board: Control) -> void:
	var st: Dictionary = world.character_status()
	var hp_arr: Array = st.get("part_hp", [84, 84, 84, 84, 84, 84])
	var max_hp: int = int(st.get("max_part_hp", 84))
	for i in range(mini(6, hp_arr.size())):
		var hp: int = int(hp_arr[i])
		_part_labels[i].text = "%s %s" % [PART_NAMES[i], CCB.hp_bar_text(hp, max_hp)]
		_part_labels[i].add_theme_color_override("font_color", CCB.hp_bar_color(hp, max_hp))

	# Needs
	var pain: int = int(st.get("pain", 0))
	_pain_lbl.text = str(st.get("pain_text", "无痛"))
	_pain_lbl.add_theme_color_override("font_color", CCB.C_GREEN if pain <= 0 else (CCB.C_YELLOW if pain < 25 else CCB.C_RED))

	var kcal: int = int(st.get("kcal", 2400))
	_hunger_lbl.text = "饱食:%s" % str(st.get("hunger_text", "正常"))
	_hunger_lbl.add_theme_color_override("font_color", CCB.C_GREEN if kcal >= 1700 else (CCB.C_YELLOW if kcal >= 1000 else CCB.C_RED))

	var hyd: int = int(st.get("hydration", 100))
	_thirst_lbl.text = "口渴:%s" % str(st.get("thirst_text", "正常"))
	_thirst_lbl.add_theme_color_override("font_color", CCB.C_GREEN if hyd >= 65 else (CCB.C_YELLOW if hyd >= 35 else CCB.C_RED))

	var fat: int = int(st.get("fatigue", 0))
	_fatigue_lbl.text = "精力:%s" % str(st.get("fatigue_text", "尚可"))
	_fatigue_lbl.add_theme_color_override("font_color", CCB.C_LTGREEN if fat < 30 else (CCB.C_YELLOW if fat < 65 else CCB.C_RED))

	var warmth: int = int(st.get("warmth", 0))
	var temp_str := "暖和" if warmth >= 35 else ("舒适" if warmth >= 15 else "微凉")
	_temp_lbl.text = "保暖:%s(%d)" % [temp_str, warmth]
	_temp_lbl.add_theme_color_override("font_color", CCB.C_LTGRAY if warmth >= 15 else CCB.C_CYAN)

	var morale: int = int(st.get("morale", 10))
	var face := ":D" if morale >= 20 else (":)" if morale >= 5 else (":|" if morale >= -10 else ":("))
	_morale_lbl.text = "心境: %s" % face
	_morale_lbl.add_theme_color_override("font_color", CCB.C_LTGREEN if morale >= 5 else (CCB.C_YELLOW if morale >= -10 else CCB.C_RED))

	# Stats
	_str_lbl.text = "力量  %d" % int(st.get("str", 8))
	_dex_lbl.text = "敏捷  %d" % int(st.get("dex", 8))
	_int_lbl.text = "智力  %d" % int(st.get("int", 8))
	_per_lbl.text = "感知  %d" % int(st.get("per", 8))
	_focus_lbl.text = "专注 %d" % int(st.get("focus", 100))
	var safe: bool = bool(st.get("safe_mode", true))
	_safe_lbl.text = "安全  %s" % ("开" if safe else "关")
	_safe_lbl.add_theme_color_override("font_color", CCB.C_LTGREEN if safe else CCB.C_RED)

	# Row 2: Move mode / speed / sound / stamina / badges
	var mmode: int = int(st.get("move_mode", 0))
	var mlabel: String = str(st.get("move_mode_text", "行走"))
	_move_lbl.text = "姿态:[%s]" % mlabel
	var mcol := CCB.C_WHITE if mmode == 0 else (CCB.C_YELLOW if mmode == 1 else (CCB.C_CYAN if mmode == 2 else CCB.C_DKGRAY))
	_move_lbl.add_theme_color_override("font_color", mcol)
	_speed_lbl.text = "速度 %d" % int(st.get("speed", 100))
	var snd: int = int(st.get("last_sound", 0))
	_sound_lbl.text = "声响 %d" % snd
	_sound_lbl.add_theme_color_override("font_color", CCB.C_RED if snd >= 24 else (CCB.C_YELLOW if snd >= 10 else CCB.C_DKGRAY))

	var stam: int = int(st.get("stamina", 10000))
	var stam_pct := int(round(float(stam) / 100.0))
	_stam_lbl.text = "耐力 %s %d%%" % [CCB.hp_bar_text(stam, 10000), stam_pct]
	_stam_lbl.add_theme_color_override("font_color", CCB.C_CYAN if stam >= 5000 else (CCB.C_YELLOW if stam >= 2500 else CCB.C_RED))

	var badges: PackedStringArray = PackedStringArray()
	if world.is_grabbing():
		badges.append("[拖家具]")
	if bool(st.get("hauling", false)):
		badges.append("[拖运]")
	if bool(st.get("lamp_lit", false)):
		var lname: String = str(st.get("light_name", "照明"))
		badges.append("[%s]" % (lname if not lname.is_empty() else "点灯"))
	_flags_lbl.text = " ".join(badges)

	# Row 3: Location + Z + Coords
	var pos: Vector2i = world.pos
	var z: int = int(world.floor)
	var z_name := "地面" if z == 0 else ("二层" if z == 1 else "三层")
	_loc_lbl.text = str(world.location(pos))
	_z_lbl.text = "Z:%d %s (%d,%d)" % [z, z_name, pos.x, pos.y]

	# Row 4: Calendar + Weather + Light + Quest
	var sky := CanglingCalendar.at_minute(world.minutes)
	var phase := CCB.phase_label_color(sky)
	_time_lbl.text = "%s · %s" % [CanglingCalendar.time_label(world.minutes), phase[0]]
	_time_lbl.add_theme_color_override("font_color", phase[1])
	_weather_lbl.text = weather.label()
	var indoors := false
	if board != null and board.cells.has(pos):
		indoors = (int(board.cells[pos][3]) & 1) != 0
	var lname_lit: String = str(st.get("light_name", ""))
	var light_desc := "%s照明" % lname_lit if bool(st.get("lamp_lit", false)) and not lname_lit.is_empty() else ("室内微光" if indoors else ("日光充足" if float(sky.get("daylight", 1.0)) > 0.45 else "夜色朦胧"))
	_light_lbl.text = "照明: %s" % light_desc
	_quest_lbl.text = "铜钱 %d文 | 药草 %d/3" % [int(world.coins), int(world.herbs)]

	# Row 5: Wielded & Carry
	var wield_txt: String = str(st.get("wielded_name", "空手"))
	var bash_pw: int = int(st.get("bash_power", 12))
	_wield_lbl.text = "手持: %s  (破拆:%d | 累赘:%d)" % [wield_txt, bash_pw, int(st.get("encumbrance", 0))]
	_wield_lbl.add_theme_color_override("font_color", CCB.C_YELLOW if int(st.get("wielded_id", -1)) >= 0 else CCB.C_WHITE)

	var vol_l := float(st.get("carry_volume_ml", 0)) / 1000.0
	var max_l := float(st.get("max_carry_volume_ml", 2500)) / 1000.0
	var wt_kg := float(st.get("carry_weight_g", 0)) / 1000.0
	_carry_lbl.text = "水壶 %d/%dml | 容积 %.1f/%.1fL | 重 %.1fkg" % [
		int(world.bottle_water()), int(world.bottle_capacity()), vol_l, max_l, wt_kg]

	# Row 6: 8-Direction CCB Compass (slots: 0=NW, 1=N, 2=NE, 3=W, 4=@, 5=E, 6=SW, 7=S, 8=SE)
	var comp: Array = world.compass_summary()
	const MAP_IDX := [0, 1, 2, 3, -1, 4, 5, 6, 7]
	for slot in range(9):
		var cidx: int = MAP_IDX[slot]
		if cidx < 0:
			_compass_cells[slot].text = "  @  "
			_compass_cells[slot].add_theme_color_override("font_color", CCB.C_LTCYAN)
			continue
		if cidx < comp.size():
			var row: Dictionary = comp[cidx]
			var dname: String = str(row.get("dir", "")).strip_edges()
			var lbl_txt: String = str(row.get("label", ""))
			var dist: int = int(row.get("dist", 0))
			if lbl_txt.is_empty():
				_compass_cells[slot].text = "%s: -" % dname
				_compass_cells[slot].add_theme_color_override("font_color", CCB.C_DKGRAY)
			else:
				_compass_cells[slot].text = "%s:%s(%d)" % [dname, lbl_txt, dist]
				var ccol := CCB.C_YELLOW if ("沈青" in lbl_txt or "渡夫" in lbl_txt or "药草" in lbl_txt or "石台" in lbl_txt) else CCB.C_LTGRAY
				_compass_cells[slot].add_theme_color_override("font_color", ccol)

	minimap.queue_redraw()
