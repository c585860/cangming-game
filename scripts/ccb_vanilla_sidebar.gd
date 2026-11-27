extends PanelContainer

# Pure Vanilla Cataclysm-Cleanwater-Bomb (CCB) Right Sidebar Engine
# Faithfully modeled on Cataclysm-Cleanwater-Bomb/data/json/ui/sidebar-legacy-classic.json,
# sidebar-structured.json, src/panels.cpp, and src/pixel_minimap.cpp:
#  - Pure black #000000 panel, 0px corners, crisp 1px white left border (NO custom glass cards, NO pills!)
#  - Classic Layout Top Block: 5x7 Overmap ASCII mini-grid RIGHT BESIDE 6-limb "|||||" HP bars
#    + Pain/Hunger/Thirst/Fatigue/Temp + Str/Dex/Int/Per/Safe
#  - Move/Speed/Stamina/Sound/Wield/Weight/Location/Date+Weather+Light/Bio-Rad/8-Dir Compass
#  - REAL Local Pixel Minimap (ccb_pixel_minimap.gd)
#  - Clean Curses Message Log at bottom (NO custom prefixes!)
#  - Runtime Customizable via '}' Sidebar Options Panel Manager (toggle & reorder every panel + switch layout!)

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const PixelMinimap = preload("res://scripts/ccb_pixel_minimap.gd")
const CanglingCalendar = preload("res://scripts/cangling_calendar.gd")

const PANEL_DEFS := [
	{"id": "overmap_hp",   "name": "小大地图 + 部位血量 (5x7 OMT & HP)", "enabled": true},
	{"id": "needs_stats",  "name": "需求与四维属性 (Needs & Stats)",     "enabled": true},
	{"id": "move_stam",    "name": "姿态、速度与耐力 (Move / Speed / Stamina)", "enabled": true},
	{"id": "location",     "name": "地点、时间、天气与光照 (Place / Time / Weather)", "enabled": true},
	{"id": "wield_carry",  "name": "手持武器与负重容积 (Wield / Weight / Vol)", "enabled": true},
	{"id": "rad_mut",      "name": "辐射、伤口与诱变状态 (Rad / Wounds / Mut)", "enabled": true},
	{"id": "compass",      "name": "八向威胁罗盘 (Compass)",             "enabled": true},
	{"id": "pixel_minimap","name": "像素小地图 (Pixel Minimap [N])",     "enabled": true},
	{"id": "messages",     "name": "消息日志 (Messages [P])",            "enabled": true},
]

const LIMB_SHORT := ["头", "躯", "左臂", "右臂", "左腿", "右腿"]

var layout_style := "classic" # "classic", "structured", "compact"
var panel_order: Array[Dictionary] = []
var pixel_minimap_enabled := true

var _world: RefCounted
var _root: VBoxContainer
var _sections: Dictionary = {} # panel_id -> Control
var _om_cells: Array[Label] = [] # 7*5 or 5*7 Overmap ASCII cells in top-left!
var _limb_bars: Array[Label] = []
var _limb_nums: Array[Label] = []
var _pain_lbl: Label
var _hunger_lbl: Label
var _thirst_lbl: Label
var _fatigue_lbl: Label
var _temp_lbl: Label
var _morale_lbl: Label
var _stats_line1: Label
var _stats_line2: Label
var _move_line: Label
var _stam_bar_lbl: Label
var _loc_line: Label
var _time_line: Label
var _weather_line: Label
var _wield_line: Label
var _carry_line: Label
var _rad_line: Label
var _wound_line: Label
var _compass_lbls: Array[Label] = []
var pixel_minimap: PixelMinimap
var status_prompt: Label
var log_container: VBoxContainer
var _log_history: Array[Dictionary] = []


class MiniOvermapGrid extends Control:
	var world: RefCounted
	var radius_x := 3 # 7 cols
	var radius_y := 2 # 5 rows (exact CCB 7x5 / 5x7 compact sidebar overmap!)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1))
		if world == null or not world.is_cataclysm_pack():
			return
		var omt: Vector2i = world.ccb_world_to_omt(world.pos)
		var r := maxi(radius_x, radius_y)
		var data: Dictionary = world.ccb_overmap_slice(omt, r)
		var rows: Array = data.get("rows", [])
		var cols: Array = data.get("colors", [])
		var seen: Array = data.get("seen", [])
		if rows.is_empty():
			return
		var font := get_theme_default_font()
		var nx := radius_x * 2 + 1
		var ny := radius_y * 2 + 1
		var cw := floorf((size.x - 4.0) / float(nx))
		var ch := floorf((size.y - 4.0) / float(ny))
		var ox := (size.x - cw * float(nx)) * 0.5
		var oy := (size.y - ch * float(ny)) * 0.5
		var fsz := maxi(10, int(minf(cw, ch) * 0.85))
		for gy in range(ny):
			var sy := gy + (r - radius_y)
			if sy < 0 or sy >= rows.size():
				continue
			var rstr: String = str(rows[sy])
			var crow: Array = cols[sy]
			var srow: Array = seen[sy] if sy < seen.size() else []
			for gx in range(nx):
				var sx := gx + (r - radius_x)
				if sx < 0 or sx >= rstr.length():
					continue
				var px := ox + float(gx) * cw
				var py := oy + float(gy) * ch
				var is_seen := true
				if sx < srow.size():
					is_seen = bool(srow[sx])
				var ch_s := rstr.substr(sx, 1) if is_seen else "?"
				var col := Color(str(crow[sx])) if is_seen else VUI.C_DKGRAY
				if gx == radius_x and gy == radius_y:
					draw_rect(Rect2(px, py, cw, ch), VUI.BG_SELECT)
					draw_string(font, Vector2(px, py + ch * 0.82), "@", HORIZONTAL_ALIGNMENT_CENTER, cw, fsz, VUI.C_YELLOW)
				else:
					draw_string(font, Vector2(px, py + ch * 0.82), ch_s, HORIZONTAL_ALIGNMENT_CENTER, cw, fsz, col)
		draw_rect(Rect2(Vector2.ZERO, size), VUI.BORDER_DIM, false, 1.0)


var _mini_omt: MiniOvermapGrid


func build(world: RefCounted) -> void:
	_world = world
	panel_order.clear()
	for d: Dictionary in PANEL_DEFS:
		panel_order.append(d.duplicate())

	custom_minimum_size.x = 344
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = VUI.BG_BLACK
	sb.border_color = VUI.BORDER
	sb.border_width_left = 1
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	add_theme_stylebox_override("panel", sb)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 3)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.clip_contents = true
	add_child(_root)

	_build_all_sections()
	apply_panel_order()


func _build_all_sections() -> void:
	_sections.clear()
	_limb_bars.clear()
	_limb_nums.clear()
	_compass_lbls.clear()

	# 1. OVERMAP 7x5 + 6-LIMB ASCII HP BARS (Exact sidebar-legacy-classic.json top row!)
	var sec_om_hp := VBoxContainer.new()
	sec_om_hp.add_theme_constant_override("separation", 2)
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 8)
	sec_om_hp.add_child(top_hbox)

	_mini_omt = MiniOvermapGrid.new()
	_mini_omt.world = _world
	_mini_omt.custom_minimum_size = Vector2(114, 86)
	top_hbox.add_child(_mini_omt)

	var hp_col := VBoxContainer.new()
	hp_col.add_theme_constant_override("separation", 0)
	hp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(hp_col)
	for i in range(6):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		hp_col.add_child(hb)
		var nl := VUI.mk_lbl(hb, LIMB_SHORT[i], 12, VUI.C_LTGRAY)
		nl.custom_minimum_size.x = 30
		var bl := VUI.mk_lbl(hb, "|||||", 12, VUI.C_LTGREEN)
		bl.custom_minimum_size.x = 42
		var vl := VUI.mk_lbl(hb, "84", 12, VUI.C_LTGREEN)
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_limb_bars.append(bl)
		_limb_nums.append(vl)
	sec_om_hp.add_child(VUI.divider(VUI.BORDER_DIM))
	_sections["overmap_hp"] = sec_om_hp

	# 2. NEEDS & 4 STATS (Classic 2-column curses table)
	var sec_ns := VBoxContainer.new()
	sec_ns.add_theme_constant_override("separation", 1)
	var ns_row := HBoxContainer.new()
	ns_row.add_theme_constant_override("separation", 6)
	sec_ns.add_child(ns_row)
	var c1 := VBoxContainer.new()
	c1.add_theme_constant_override("separation", 0)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ns_row.add_child(c1)
	_pain_lbl = VUI.mk_lbl(c1, "疼痛: 无", 12, VUI.C_GREEN)
	_hunger_lbl = VUI.mk_lbl(c1, "饥饿: 饱足", 12, VUI.C_GREEN)
	_thirst_lbl = VUI.mk_lbl(c1, "口渴: 不渴", 12, VUI.C_GREEN)
	var c2 := VBoxContainer.new()
	c2.add_theme_constant_override("separation", 0)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ns_row.add_child(c2)
	_fatigue_lbl = VUI.mk_lbl(c2, "精力: 清醒", 12, VUI.C_LTGRAY)
	_temp_lbl = VUI.mk_lbl(c2, "体温: 舒适", 12, VUI.C_LTGRAY)
	_morale_lbl = VUI.mk_lbl(c2, "士气: :)", 12, VUI.C_LTGREEN)
	_stats_line1 = VUI.mk_lbl(sec_ns, "力量 8  敏捷 8  智力 8  感知 8", 12, VUI.C_WHITE)
	_stats_line2 = VUI.mk_lbl(sec_ns, "专注 100   安全模式: 开   击杀: 0", 12, VUI.C_LTCYAN)
	sec_ns.add_child(VUI.divider(VUI.BORDER_DIM))
	_sections["needs_stats"] = sec_ns

	# 3. MOVE MODE / SPEED / STAMINA ASCII BAR
	var sec_ms := VBoxContainer.new()
	sec_ms.add_theme_constant_override("separation", 1)
	_move_line = VUI.mk_lbl(sec_ms, "姿态: 行走   速度: 100   声响: 0", 12, VUI.C_WHITE)
	_stam_bar_lbl = VUI.mk_lbl(sec_ms, "耐力: |||||||||| 100%", 12, VUI.C_LTCYAN)
	sec_ms.add_child(VUI.divider(VUI.BORDER_DIM))
	_sections["move_stam"] = sec_ms

	# 4. PLACE / DATE+TIME / WEATHER+LIGHT
	var sec_loc := VBoxContainer.new()
	sec_loc.add_theme_constant_override("separation", 1)
	_loc_line = VUI.mk_lbl(sec_loc, "地点: 应急避难所 (0,0) Z:0", 12, VUI.C_YELLOW)
	_time_line = VUI.mk_lbl(sec_loc, "春 第1天 07:20:00", 12, VUI.C_WHITE)
	_weather_line = VUI.mk_lbl(sec_loc, "天气: 晴朗   光照: 明亮", 12, VUI.C_LTGRAY)
	sec_loc.add_child(VUI.divider(VUI.BORDER_DIM))
	_sections["location"] = sec_loc

	# 5. WIELDED WEAPON & CARRY WEIGHT/VOLUME
	var sec_wc := VBoxContainer.new()
	sec_wc.add_theme_constant_override("separation", 1)
	_wield_line = VUI.mk_lbl(sec_wc, "手持: 空手", 12, VUI.C_WHITE)
	_carry_line = VUI.mk_lbl(sec_wc, "负重: 0.0/45.0 kg  容积: 0.0/10.0 L  累赘: 0", 11, VUI.C_LTGRAY)
	sec_wc.add_child(VUI.divider(VUI.BORDER_DIM))
	_sections["wield_carry"] = sec_wc

	# 6. RADIATION / WOUNDS / MUTAGEN (Pure curses line, NO custom box!)
	var sec_rm := VBoxContainer.new()
	sec_rm.add_theme_constant_override("separation", 1)
	_rad_line = VUI.mk_lbl(sec_rm, "辐射: 0 mSv (安全) | 诱变:0 变异:0", 11, VUI.C_LTGREEN)
	_wound_line = VUI.mk_lbl(sec_rm, "伤势: 无流血/咬伤/感染", 11, VUI.C_DKGRAY)
	sec_rm.add_child(VUI.divider(VUI.BORDER_DIM))
	_sections["rad_mut"] = sec_rm

	# 7. 8-DIR COMPASS (Exact CCB compass danger display)
	var sec_comp := VBoxContainer.new()
	sec_comp.add_theme_constant_override("separation", 1)
	var cg := GridContainer.new()
	cg.columns = 3
	cg.add_theme_constant_override("h_separation", 4)
	cg.add_theme_constant_override("v_separation", 0)
	sec_comp.add_child(cg)
	const COMP_DEF := ["NW .", "N .", "NE .", "W .", "@", "E .", "SW .", "S .", "SE ."]
	for i in range(9):
		var l := VUI.mk_lbl(cg, COMP_DEF[i], 11, VUI.C_YELLOW if i == 4 else VUI.C_DKGRAY)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_compass_lbls.append(l)
	sec_comp.add_child(VUI.divider(VUI.BORDER_DIM))
	_sections["compass"] = sec_comp

	# 8. REAL LOCAL PIXEL MINIMAP (Cataclysm-Cleanwater-Bomb/src/pixel_minimap.cpp!)
	var sec_pm := VBoxContainer.new()
	sec_pm.add_theme_constant_override("separation", 2)
	pixel_minimap = PixelMinimap.new()
	pixel_minimap.build(_world, 38)
	pixel_minimap.custom_minimum_size = Vector2(320, 128)
	pixel_minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_pm.add_child(pixel_minimap)
	sec_pm.add_child(VUI.divider(VUI.BORDER_DIM))
	_sections["pixel_minimap"] = sec_pm

	# 9. MESSAGES LOG (Pure curses log area at bottom)
	var sec_msg := VBoxContainer.new()
	sec_msg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sec_msg.add_theme_constant_override("separation", 2)
	status_prompt = VUI.mk_lbl(sec_msg, "", 12, VUI.C_YELLOW, true)
	status_prompt.visible = false
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec_msg.add_child(sc)
	log_container = VBoxContainer.new()
	log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_container.add_theme_constant_override("separation", 1)
	sc.add_child(log_container)
	_sections["messages"] = sec_msg


func apply_panel_order() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
	for entry: Dictionary in panel_order:
		var pid: String = str(entry["id"])
		if not _sections.has(pid):
			continue
		var node: Control = _sections[pid]
		var vis: bool = bool(entry.get("enabled", true))
		if pid == "pixel_minimap":
			vis = vis and pixel_minimap_enabled
		if layout_style == "compact" and pid in ["compass", "rad_mut"]:
			vis = false
		node.visible = vis
		_root.add_child(node)


func set_layout_style(style_name: String) -> void:
	layout_style = style_name
	custom_minimum_size.x = 300 if style_name == "compact" else (360 if style_name == "structured" else 344)
	if pixel_minimap != null:
		pixel_minimap.custom_minimum_size.y = 104 if style_name == "compact" else 128
	apply_panel_order()


func toggle_pixel_minimap() -> bool:
	pixel_minimap_enabled = not pixel_minimap_enabled
	apply_panel_order()
	if pixel_minimap_enabled and pixel_minimap != null:
		pixel_minimap.refresh()
	return pixel_minimap_enabled


func set_prompt(text: String) -> void:
	if status_prompt == null:
		return
	status_prompt.text = text
	status_prompt.visible = not text.is_empty()


func clear_messages() -> void:
	_log_history.clear()
	if log_container != null:
		for c in log_container.get_children():
			c.queue_free()


func get_log_history() -> Array[Dictionary]:
	return _log_history


func add_message(clock_str: String, text: String, color := VUI.C_LTGRAY) -> void:
	if text.is_empty():
		return
	var col := color
	if "流血" in text or "感染" in text or "咬伤" in text or "辐射病" in text or "尸变" in text or "暴击" in text:
		col = VUI.C_LTRED
	elif "击毙" in text or "拾取" in text or "解剖" in text or "捣烂" in text or "制作" in text or "清洗" in text:
		col = VUI.C_LTGREEN
	elif "诱变" in text or "变异" in text or "辐射" in text:
		col = VUI.C_YELLOW
	_log_history.append({"time": clock_str, "text": text, "color": col})
	if _log_history.size() > 160:
		_log_history.pop_front()
	if log_container == null:
		return
	var lbl := VUI.mk_lbl(log_container, text, 12, col, true)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	while log_container.get_child_count() > 36:
		log_container.get_child(0).queue_free()
	var sc := log_container.get_parent() as ScrollContainer
	if sc != null:
		sc.call_deferred("set_v_scroll", 999999)


func refresh(world: RefCounted, weather: RefCounted, _board: Control, _net_session: RefCounted = null) -> void:
	if world == null or not world.is_cataclysm_pack():
		return
	var st: Dictionary = world.character_status()
	var ccb: Dictionary = world.ccb_status()

	# 1. Mini 7x5 Overmap + 6-limb ASCII HP bars
	if _mini_omt != null:
		_mini_omt.world = world
		_mini_omt.queue_redraw()
	var parts: Array = st.get("part_hp", [84, 84, 84, 84, 84, 84])
	var max_hp := int(st.get("max_part_hp", 84))
	for i in range(mini(6, parts.size())):
		var hp := int(parts[i])
		var bar_info := VUI.curses_hp_bar(hp, max_hp)
		_limb_bars[i].text = str(bar_info["text"])
		_limb_bars[i].add_theme_color_override("font_color", bar_info["color"])
		_limb_nums[i].text = str(hp)
		_limb_nums[i].add_theme_color_override("font_color", bar_info["color"])

	# 2. Needs & Stats
	var pain := int(st.get("pain", 0))
	_pain_lbl.text = "疼痛: 无" if pain <= 0 else ("疼痛: %d" % pain)
	_pain_lbl.add_theme_color_override("font_color", VUI.C_GREEN if pain <= 0 else (VUI.C_YELLOW if pain < 25 else VUI.C_LTRED))
	_hunger_lbl.text = "饥饿: " + str(st.get("hunger_text", "饱足"))
	_thirst_lbl.text = "口渴: " + str(st.get("thirst_text", "不渴"))
	_fatigue_lbl.text = "精力: " + str(st.get("fatigue_text", "清醒"))
	_temp_lbl.text = "体温: " + str(st.get("temp_text", "舒适"))
	var mor := int(st.get("morale", 0))
	_morale_lbl.text = "士气: %s (%+d)" % [":D" if mor >= 20 else (":)" if mor >= 0 else ":("), mor]
	_morale_lbl.add_theme_color_override("font_color", VUI.C_LTGREEN if mor >= 0 else VUI.C_LTRED)

	_stats_line1.text = "力量 %-2d 敏捷 %-2d 智力 %-2d 感知 %-2d" % [
		int(ccb.get("eff_str", 8)), int(ccb.get("eff_dex", 8)),
		int(ccb.get("eff_int", 8)), int(ccb.get("eff_per", 8))
	]
	var safe_on := bool(st.get("safe_mode", true))
	_stats_line2.text = "专注 %-3d  安全:%s  击杀:%d" % [
		int(st.get("focus", 100)), "开" if safe_on else "关", int(world.get_kills())
	]
	_stats_line2.add_theme_color_override("font_color", VUI.C_LTGREEN if safe_on else VUI.C_LTRED)

	# 3. Move / Speed / Stamina
	var mode_cn := str(st.get("move_mode_text", "行走"))
	var spd := maxi(35, 100 + int(ccb.get("speed_mod", 0)) - pain / 2)
	var snd := int(st.get("last_sound", 0))
	_move_line.text = "姿态:[%s]  速度:%d  声响:%d" % [mode_cn, spd, snd]
	var stam_pct := clampi(int(round(float(int(st.get("stamina", 10000))) / 100.0)), 0, 100)
	var spips := clampi(int(round(float(stam_pct) / 10.0)), 0, 10)
	_stam_bar_lbl.text = "耐力: [%s%s] %d%%" % ["|".repeat(spips), ".".repeat(10 - spips), stam_pct]
	_stam_bar_lbl.add_theme_color_override("font_color", VUI.C_LTCYAN if stam_pct >= 50 else (VUI.C_YELLOW if stam_pct >= 25 else VUI.C_LTRED))

	# 4. Place / Date+Time / Weather+Light
	var omt: Vector2i = world.ccb_world_to_omt(world.pos)
	_loc_line.text = "%s  OMT(%d,%d) Z:%d" % [world.location(world.pos), omt.x, omt.y, int(world.floor)]
	var mins := int(world.minutes)
	var day := 1 + mins / 1440
	var hh := (mins % 1440) / 60
	var mm := mins % 60
	var ss := int(world.get_ccb_turn_seconds())
	_time_line.text = "春 第%d天  %02d:%02d:%02d  (回合制)" % [day, hh, mm, ss]
	var w_lbl: String = str(weather.label()) if weather != null else "晴朗"
	var light_cn := "明亮" if (hh >= 6 and hh < 19) else ("黄昏" if hh == 19 else "黑暗")
	_weather_line.text = "天气: %s   光照: %s" % [w_lbl, light_cn]

	# 5. Wielded & Carry Weight / Volume
	var wn := str(ccb.get("wielded_name", "空手"))
	if not str(ccb.get("wielded_id", "")).is_empty():
		_wield_line.text = "手持: %s (钝%d/斩%d/刺%d)" % [wn, int(ccb.get("wielded_bash", 0)), int(ccb.get("wielded_cut", 0)), int(ccb.get("wielded_stab", 0))]
		_wield_line.add_theme_color_override("font_color", VUI.C_YELLOW)
	else:
		_wield_line.text = "手持: 空手"
		_wield_line.add_theme_color_override("font_color", VUI.C_LTGRAY)
	var wg := float(int(ccb.get("carry_weight_g", 0))) / 1000.0
	var wmax := float(int(ccb.get("max_weight_g", 45000))) / 1000.0
	var vl := float(int(ccb.get("carry_vol_ml", 0))) / 1000.0
	var vmax := float(int(ccb.get("max_vol_ml", 10000))) / 1000.0
	_carry_line.text = "负重 %.1f/%.1fkg  容积 %.1f/%.1fL  累赘 %d" % [wg, wmax, vl, vmax, int(ccb.get("encumbrance", 0))]

	# 6. Radiation / Wounds / Mutagen
	var rad := int(ccb.get("rad", 0))
	var cat_v := int(ccb.get("mutagen_catalyst", 0))
	var muts: Array = ccb.get("mutations", [])
	_rad_line.text = "辐射:%dmSv(%s) | 催化:%d 变异:%d" % [rad, str(ccb.get("rad_badge_color", "绿")).left(2), cat_v, muts.size()]
	_rad_line.add_theme_color_override("font_color", VUI.C_LTGREEN if rad < 25 else (VUI.C_YELLOW if rad < 100 else VUI.C_LTRED))
	var wounds: Array = ccb.get("wounds", [])
	if wounds.is_empty():
		_wound_line.text = "伤势: 无流血/咬伤/感染"
		_wound_line.add_theme_color_override("font_color", VUI.C_DKGRAY)
	else:
		var ws := PackedStringArray()
		for w: Dictionary in wounds:
			var tag := "感染!" if bool(w.get("infected", false)) else ("咬伤" if bool(w.get("bite", false)) else "流血")
			ws.append("%s:%s" % [str(w.get("part", "")), tag])
		_wound_line.text = "伤势: " + " ".join(ws)
		_wound_line.add_theme_color_override("font_color", VUI.C_LTRED)

	# 7. 8-Direction Monster Threat Compass
	const DIRS := ["NW", "N", "NE", "W", "@", "E", "SW", "S", "SE"]
	var counts := [0, 0, 0, 0, 0, 0, 0, 0, 0]
	var near_mons: Array = world.monsters_in_rect(Rect2i(world.pos - Vector2i(18, 18), Vector2i(37, 37)))
	for m: Dictionary in near_mons:
		var dp: Vector2i = m.get("pos", world.pos) - world.pos
		var sx := 0 if dp.x < -1 else (2 if dp.x > 1 else 1)
		var sy := 0 if dp.y < -1 else (2 if dp.y > 1 else 1)
		counts[sy * 3 + sx] += 1
	for i in range(9):
		if i == 4:
			_compass_lbls[i].text = "@ (%d)" % near_mons.size()
			_compass_lbls[i].add_theme_color_override("font_color", VUI.C_LTRED if not near_mons.is_empty() else VUI.C_YELLOW)
		elif counts[i] > 0:
			_compass_lbls[i].text = "%s Z×%d" % [DIRS[i], counts[i]]
			_compass_lbls[i].add_theme_color_override("font_color", VUI.C_LTRED)
		else:
			_compass_lbls[i].text = "%s ." % DIRS[i]
			_compass_lbls[i].add_theme_color_override("font_color", VUI.C_DKGRAY)

	# 8. Refresh REAL Local Pixel Minimap!
	if pixel_minimap != null and pixel_minimap.visible:
		pixel_minimap.refresh()
