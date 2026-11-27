extends Control

# Pure Vanilla Cataclysm-Cleanwater-Bomb (CCB) 8-Tab Character Creator
# Faithfully follows Cataclysm-Cleanwater-Bomb/src/newcharacter.cpp:
#  - Pure black #000000 terminal/ImGui style (0px sharp borders, cobalt-blue selection)
#  - 8 Tabs (Tab / Shift+Tab): 点数池 / 出生剧情 / 职业 / 背景爱好 / 属性 / 特性 / 技能 / 描述汇总
#  - REAL Paper-Doll Character Preview (renders unmodified vanilla player_male/female + worn/wielded overlays!)
#  - Presets save & load dialog + Full randomization ('!')

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const Tiles = preload("res://scripts/undead_tiles.gd")
const PRESETS_PATH := "user://ccb_presets.json"

signal character_confirmed(char_cfg: Dictionary)
signal cancelled()

const TABS := [
	{"id": "points", "label": "1.点数池"},
	{"id": "scenario", "label": "2.剧情"},
	{"id": "profession", "label": "3.职业"},
	{"id": "background", "label": "4.爱好"},
	{"id": "stats", "label": "5.属性"},
	{"id": "traits", "label": "6.特性"},
	{"id": "skills", "label": "7.技能"},
	{"id": "summary", "label": "8.描述"},
]

const POOL_MODES := [
	{"id": "multi_pool", "name": "多点数池 (Multi-pool · 原版标准)", "desc": "属性(4点)、特性(0点/负面换取)、技能(2点)各自独立；剧情与职业点数计入综合池。"},
	{"id": "single_pool", "name": "单点数池 (Single-pool)", "desc": "所有剧情、职业、属性、特性与技能共享统一 6 点池。"},
	{"id": "freeform", "name": "自由模式 (Freeform)", "desc": "无点数上限，自由组合任意剧情、职业、属性、特性与技能。"},
]

var _world: RefCounted
var _scenarios: Array = []
var _professions: Array = []
var _hobbies: Array = []
var _traits: Array = []
var _skills: Array = []

var active_tab := "points"
var pool_mode := "multi_pool"
var char_name := "末日幸存者"
var gender := "male"
var age := 25
var scenario_id := "evacuee"
var profession_id := "unemployed"
var selected_hobbies: Array[String] = []
var stats := {"str": 8, "dex": 8, "int": 8, "per": 8}
var selected_traits: Array[String] = []
var skill_levels: Dictionary = {}
var search_filter := ""
var trait_filter := "all"

var _tab_btns: Dictionary = {}
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _points_bar: Label
var _confirm_btn: Button
var _status_lbl: Label
var _presets_modal: PanelContainer = null


class PaperDollPreview extends Control:
	var gender := "male"
	var worn_ids: Array = []
	var wielded_id := ""

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.05, 1.0))
		draw_rect(Rect2(Vector2.ZERO, size), VUI.BORDER, false, 1.0)
		Tiles.set_active_tileset(Tiles.get_preferred_ccb_tileset())
		var side := minf(size.x, size.y) - 10.0
		var origin := (size - Vector2(side, side)) * 0.5
		var base_id := "player_female" if gender == "female" else "player_male"
		if not Tiles.has_tile(base_id):
			base_id = "player_male"
		if Tiles.has_tile(base_id):
			Tiles.draw_at(self, base_id, origin, side)
		for wid in worn_ids:
			var oid := "overlay_worn_" + str(wid)
			if Tiles.has_tile(oid):
				Tiles.draw_at(self, oid, origin, side)
		if not wielded_id.is_empty():
			var woid := "overlay_wielded_" + wielded_id
			if Tiles.has_tile(woid):
				Tiles.draw_at(self, woid, origin, side)


func build(world: RefCounted) -> void:
	_world = world
	_scenarios = world.ccb_list_scenarios()
	_professions = world.ccb_list_professions(false)
	_hobbies = world.ccb_list_professions(true)
	_traits = world.ccb_list_starting_traits()
	_skills = world.ccb_list_skills()

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = VUI.BG_BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	# --- HEADER ---
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER, 10, 6, 1))
	root.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	head.add_child(hrow)
	var title := VUI.mk_lbl(hrow, "角色创建 · NEW CHARACTER  [Tab / Shift+Tab 切换标签 | ! 随机]", 14, VUI.C_YELLOW)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_points_bar = VUI.mk_lbl(hrow, "", 13, VUI.C_LTCYAN)

	# --- 8 TABS BAR ---
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 3)
	root.add_child(tab_row)
	for t: Dictionary in TABS:
		var tid: String = str(t["id"])
		var tb := Button.new()
		tb.text = str(t["label"])
		tb.focus_mode = Control.FOCUS_NONE
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size.y = 26
		tb.pressed.connect(func():
			active_tab = tid
			search_filter = ""
			_rebuild_body())
		tab_row.add_child(tb)
		_tab_btns[tid] = tb

	# --- SPLIT BODY ---
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.45
	left_panel.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER, 8, 8, 1))
	body.add_child(left_panel)
	_left_box = VBoxContainer.new()
	_left_box.add_theme_constant_override("separation", 4)
	left_panel.add_child(_left_box)

	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	right_panel.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER, 10, 8, 1))
	body.add_child(right_panel)
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(rscroll)
	_right_box = VBoxContainer.new()
	_right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_box.add_theme_constant_override("separation", 5)
	rscroll.add_child(_right_box)

	# --- FOOTER BAR ---
	var foot := PanelContainer.new()
	foot.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER, 8, 6, 1))
	root.add_child(foot)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 6)
	foot.add_child(frow)

	var back_btn := Button.new()
	back_btn.text = "返回主菜单 [Esc]"
	back_btn.focus_mode = Control.FOCUS_NONE
	VUI.style_button(back_btn)
	back_btn.pressed.connect(func(): cancelled.emit())
	frow.add_child(back_btn)

	var rand_btn := Button.new()
	rand_btn.text = "随机 [!]"
	rand_btn.focus_mode = Control.FOCUS_NONE
	VUI.style_button(rand_btn)
	rand_btn.pressed.connect(func():
		randomize_character()
		_rebuild_body())
	frow.add_child(rand_btn)

	var preset_btn := Button.new()
	preset_btn.text = "保存预设"
	preset_btn.focus_mode = Control.FOCUS_NONE
	VUI.style_button(preset_btn)
	preset_btn.pressed.connect(_save_preset)
	frow.add_child(preset_btn)

	_status_lbl = VUI.mk_lbl(frow, "", 12, VUI.C_LTGREEN)
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var prev_btn := Button.new()
	prev_btn.text = "< 上一页"
	prev_btn.focus_mode = Control.FOCUS_NONE
	VUI.style_button(prev_btn)
	prev_btn.pressed.connect(func(): _step_tab(-1))
	frow.add_child(prev_btn)

	var next_btn := Button.new()
	next_btn.text = "下一页 >"
	next_btn.focus_mode = Control.FOCUS_NONE
	VUI.style_button(next_btn)
	next_btn.pressed.connect(func(): _step_tab(1))
	frow.add_child(next_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "完成创建并进入世界 [Enter]"
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	VUI.style_button(_confirm_btn, true)
	_confirm_btn.pressed.connect(_on_confirm)
	frow.add_child(_confirm_btn)

	_rebuild_body()


func open_fresh(start_tab := "points") -> void:
	active_tab = start_tab
	search_filter = ""
	_status_lbl.text = ""
	visible = true
	_rebuild_body()


func open_for_world(_world_cfg: Dictionary) -> void:
	open_fresh("points")


func open_presets_mode(_world_cfg: Dictionary) -> void:
	open_fresh("summary")
	var list := load_presets()
	if list.is_empty():
		_status_lbl.text = "当前暂无已保存预设，可配置后点击「保存预设」。"
		return
	var cfg: Dictionary = list[list.size() - 1]
	apply_config_dict(cfg)
	_status_lbl.text = "已加载最近预设「%s」（共 %d 个预设）。" % [str(cfg.get("name", "")), list.size()]
	_rebuild_body()


func apply_config_dict(cfg: Dictionary) -> void:
	char_name = str(cfg.get("name", "末日幸存者"))
	gender = str(cfg.get("gender", "male"))
	age = int(cfg.get("age", 25))
	pool_mode = str(cfg.get("pool_mode", "multi_pool"))
	scenario_id = str(cfg.get("scenario_id", "evacuee"))
	profession_id = str(cfg.get("profession_id", "unemployed"))
	selected_hobbies.clear()
	for h in cfg.get("hobbies", []):
		selected_hobbies.append(str(h))
	stats = {
		"str": int(cfg.get("str", 8)),
		"dex": int(cfg.get("dex", 8)),
		"int": int(cfg.get("int", 8)),
		"per": int(cfg.get("per", 8)),
	}
	selected_traits.clear()
	for t in cfg.get("traits", []):
		selected_traits.append(str(t))
	skill_levels = (cfg.get("skills", {}) as Dictionary).duplicate()


func randomize_all() -> void:
	randomize_character()
	_rebuild_body()


func randomize_character() -> void:
	if not _scenarios.is_empty():
		scenario_id = str(_scenarios[randi() % _scenarios.size()].get("id", "evacuee"))
	if not _professions.is_empty():
		profession_id = str(_professions[randi() % _professions.size()].get("id", "unemployed"))
	selected_hobbies.clear()
	if not _hobbies.is_empty():
		selected_hobbies.append(str(_hobbies[randi() % _hobbies.size()].get("id", "")))
	gender = "female" if (randi() % 2 == 1) else "male"
	stats = {"str": 8 + (randi() % 3), "dex": 8 + (randi() % 3), "int": 8 + (randi() % 3), "per": 8 + (randi() % 2)}
	selected_traits.clear()
	skill_levels.clear()
	if not bool(calc_points().get("valid", false)):
		pool_mode = "freeform"
	const NAMES := ["亚历克斯", "莎拉", "马库斯", "艾琳", "陈默", "林岚", "大卫", "诺拉"]
	char_name = NAMES[randi() % NAMES.size()]
	_status_lbl.text = "已生成随机角色：%s" % char_name


func build_default_evacuee_config() -> Dictionary:
	return {
		"name": "末日幸存者",
		"gender": "male",
		"age": 25,
		"pool_mode": "multi_pool",
		"scenario_id": "evacuee",
		"profession_id": "unemployed",
		"hobbies": [],
		"str": 9, "dex": 9, "int": 9, "per": 9,
		"traits": [],
		"skills": {},
	}


func build_config() -> Dictionary:
	return build_config_dict()


func build_config_dict() -> Dictionary:
	return {
		"name": char_name.strip_edges() if not char_name.strip_edges().is_empty() else "末日幸存者",
		"gender": gender,
		"age": age,
		"pool_mode": pool_mode,
		"scenario_id": scenario_id,
		"profession_id": profession_id,
		"hobbies": selected_hobbies.duplicate(),
		"str": int(stats["str"]),
		"dex": int(stats["dex"]),
		"int": int(stats["int"]),
		"per": int(stats["per"]),
		"traits": selected_traits.duplicate(),
		"skills": skill_levels.duplicate(),
	}


static func load_presets() -> Array:
	if not FileAccess.file_exists(PRESETS_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESETS_PATH))
	return parsed if parsed is Array else []


func _save_preset() -> void:
	var list := load_presets()
	var cfg := build_config_dict()
	list.append(cfg)
	var f := FileAccess.open(PRESETS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(list, "\t"))
		f.close()
		_status_lbl.text = "已保存预设角色「%s」（共 %d 个预设）。" % [cfg["name"], list.size()]


func _find_scenario(id: String) -> Dictionary:
	for s: Dictionary in _scenarios:
		if str(s.get("id", "")) == id:
			return s
	return _scenarios[0] if not _scenarios.is_empty() else {}


func _find_profession(id: String) -> Dictionary:
	for p: Dictionary in _professions:
		if str(p.get("id", "")) == id:
			return p
	return _professions[0] if not _professions.is_empty() else {}


func _find_trait(id: String) -> Dictionary:
	for t: Dictionary in _traits:
		if str(t.get("id", "")) == id:
			return t
	return {}


static func stat_cost(val: int) -> int:
	return (val - 8) + maxi(0, val - 14)


static func skill_cost(lv: int) -> int:
	var total := 0
	for i in range(1, lv + 1):
		total += maxi(1, (i + 1) / 2)
	return total


func calc_points() -> Dictionary:
	var sc := _find_scenario(scenario_id)
	var pr := _find_profession(profession_id)
	var scen_pts: int = int(sc.get("points", 0))
	var prof_pts: int = int(pr.get("points", 0))
	var hobby_pts := 0
	for hid in selected_hobbies:
		for h: Dictionary in _hobbies:
			if str(h.get("id", "")) == hid:
				hobby_pts += int(h.get("points", 0))
				break
	var stat_spent := stat_cost(stats["str"]) + stat_cost(stats["dex"]) + stat_cost(stats["int"]) + stat_cost(stats["per"])
	var trait_spent := 0
	for tid in selected_traits:
		trait_spent += int(_find_trait(tid).get("points", 0))
	var skill_spent := 0
	for sid: String in skill_levels:
		skill_spent += skill_cost(int(skill_levels[sid]))

	if pool_mode == "freeform":
		return {"valid": true, "mode": "freeform", "summary": "自由模式 (Freeform)"}
	elif pool_mode == "single_pool":
		var rem := 6 - scen_pts - prof_pts - hobby_pts - stat_spent - trait_spent - skill_spent
		return {"valid": rem >= 0, "mode": "single_pool", "rem": rem, "summary": "单池剩余: %d" % rem}
	else:
		var stat_rem := 4 - stat_spent
		var trait_rem := 0 - trait_spent
		var skill_rem := 2 - skill_spent
		var init_rem := 0 - scen_pts - prof_pts - hobby_pts
		var total_rem := stat_rem + trait_rem + skill_rem + init_rem
		var ok := (total_rem >= 0 and stat_rem + maxi(0, init_rem) >= 0 and trait_rem + maxi(0, init_rem) >= 0 and skill_rem + maxi(0, init_rem) >= 0)
		return {
			"valid": ok, "mode": "multi_pool",
			"summary": "多池 | 属性:%d  特性:%d  技能:%d  剧情职业:%+d  总计:%d" % [stat_rem, trait_rem, skill_rem, init_rem, total_rem],
		}


func _step_tab(delta: int) -> void:
	var idx := 0
	for i in range(TABS.size()):
		if TABS[i]["id"] == active_tab:
			idx = i
			break
	idx = posmod(idx + delta, TABS.size())
	active_tab = TABS[idx]["id"]
	search_filter = ""
	_rebuild_body()


func _on_confirm() -> void:
	var pts := calc_points()
	if not bool(pts.get("valid", false)):
		_status_lbl.text = "点数不足！请调整或切到「自由模式」。"
		return
	visible = false
	character_confirmed.emit(build_config_dict())


func _rebuild_body() -> void:
	var pts := calc_points()
	_points_bar.text = str(pts["summary"])
	_points_bar.add_theme_color_override("font_color", VUI.C_LTGREEN if bool(pts["valid"]) else VUI.C_LTRED)
	for tid: String in _tab_btns:
		VUI.style_button(_tab_btns[tid], tid == active_tab)

	for c in _left_box.get_children():
		_left_box.remove_child(c)
		c.queue_free()
	for c in _right_box.get_children():
		_right_box.remove_child(c)
		c.queue_free()

	match active_tab:
		"points": _build_points_tab()
		"scenario": _build_scenario_tab()
		"profession": _build_profession_tab()
		"background": _build_background_tab()
		"stats": _build_stats_tab()
		"traits": _build_traits_tab()
		"skills": _build_skills_tab()
		"summary": _build_summary_tab()

	_build_right_summary(pts)


func _build_points_tab() -> void:
	VUI.mk_lbl(_left_box, "点数池规则 (Point Pool)", 14, VUI.C_YELLOW)
	_left_box.add_child(VUI.divider())
	for pm: Dictionary in POOL_MODES:
		var pid: String = str(pm["id"])
		var b := Button.new()
		b.text = ("» " if pid == pool_mode else "  ") + str(pm["name"])
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(b, pid == pool_mode, VUI.C_WHITE if pid == pool_mode else VUI.C_LTGRAY)
		b.pressed.connect(func(): pool_mode = pid; _rebuild_body())
		_left_box.add_child(b)
		VUI.mk_lbl(_left_box, "    " + str(pm["desc"]), 12, VUI.C_DKGRAY, true)


func _build_scenario_tab() -> void:
	VUI.mk_lbl(_left_box, "出生剧情 (共 %d 项)" % _scenarios.size(), 14, VUI.C_YELLOW)
	_mk_search_bar(_left_box, "搜索剧情名称/ID...")
	var scroll := _mk_scroll(_left_box)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	scroll.add_child(list)
	var q := search_filter.to_lower()
	for sc: Dictionary in _scenarios:
		var sid: String = str(sc.get("id", ""))
		var nm: String = str(sc.get("name", sid))
		if not q.is_empty() and not nm.to_lower().contains(q) and not sid.to_lower().contains(q):
			continue
		var pts: int = int(sc.get("points", 0))
		var b := Button.new()
		b.text = "%s%s  [%+d]  (%s)" % ["» " if sid == scenario_id else "  ", nm, -pts, str(sc.get("start_name", ""))]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(b, sid == scenario_id, VUI.C_WHITE if sid == scenario_id else VUI.C_LTGRAY)
		b.pressed.connect(func(): scenario_id = sid; _rebuild_body())
		list.add_child(b)


func _build_profession_tab() -> void:
	VUI.mk_lbl(_left_box, "职业 (共 %d 项)" % _professions.size(), 14, VUI.C_YELLOW)
	_mk_search_bar(_left_box, "搜索职业名称/ID...")
	var scroll := _mk_scroll(_left_box)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	scroll.add_child(list)
	var q := search_filter.to_lower()
	var shown := 0
	for pr: Dictionary in _professions:
		var pid: String = str(pr.get("id", ""))
		var nm: String = str(pr.get("name", pid))
		if not q.is_empty() and not nm.to_lower().contains(q) and not pid.to_lower().contains(q):
			continue
		var pts: int = int(pr.get("points", 0))
		var b := Button.new()
		b.text = "%s%s  [耗 %d 点]" % ["» " if pid == profession_id else "  ", nm, pts]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(b, pid == profession_id, VUI.C_WHITE if pid == profession_id else VUI.C_LTGRAY)
		b.pressed.connect(func(): profession_id = pid; _rebuild_body())
		list.add_child(b)
		shown += 1
		if shown >= 140:
			break


func _build_background_tab() -> void:
	VUI.mk_lbl(_left_box, "背景 / 爱好 (共 %d 项，可多选)" % _hobbies.size(), 14, VUI.C_YELLOW)
	_mk_search_bar(_left_box, "搜索背景/爱好...")
	var scroll := _mk_scroll(_left_box)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	scroll.add_child(list)
	var q := search_filter.to_lower()
	for hb: Dictionary in _hobbies:
		var hid: String = str(hb.get("id", ""))
		var nm: String = str(hb.get("name", hid))
		if not q.is_empty() and not nm.to_lower().contains(q) and not hid.to_lower().contains(q):
			continue
		var picked := selected_hobbies.has(hid)
		var b := Button.new()
		b.text = "%s %s  [%+d]" % ["[+]" if picked else "[ ]", nm, -int(hb.get("points", 0))]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(b, picked, VUI.C_LTGREEN if picked else VUI.C_LTGRAY)
		b.pressed.connect(func():
			if selected_hobbies.has(hid): selected_hobbies.erase(hid)
			else: selected_hobbies.append(hid)
			_rebuild_body())
		list.add_child(b)


func _build_stats_tab() -> void:
	VUI.mk_lbl(_left_box, "属性分配 (基础 8；8-14 每点 1 点，15-20 每点 2 点)", 14, VUI.C_YELLOW)
	_left_box.add_child(VUI.divider())
	const DEFS := [
		{"k": "str", "name": "力量 (STR)", "desc": "近战钝击伤害、负重上限、最大生命值、破门砸碎。"},
		{"k": "dex", "name": "敏捷 (DEX)", "desc": "近战命中、闪避、远程精准、精细操作。"},
		{"k": "int", "name": "智力 (INT)", "desc": "阅读速度、合成成功率、电脑与仿生体安装。"},
		{"k": "per", "name": "感知 (PER)", "desc": "夜视辨识、侦测陷阱、弱点暴击与射击视野。"},
	]
	for d: Dictionary in DEFS:
		var k: String = d["k"]
		var val: int = int(stats[k])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_left_box.add_child(row)
		var nl := VUI.mk_lbl(row, d["name"], 13, VUI.C_WHITE)
		nl.custom_minimum_size.x = 110
		var b_dec := Button.new(); b_dec.text = " - "; b_dec.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_dec)
		b_dec.pressed.connect(func(): stats[k] = maxi(4, int(stats[k]) - 1); _rebuild_body())
		row.add_child(b_dec)
		var vl := VUI.mk_lbl(row, "%2d" % val, 15, VUI.C_LTCYAN)
		vl.custom_minimum_size.x = 34
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var b_inc := Button.new(); b_inc.text = " + "; b_inc.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_inc)
		b_inc.pressed.connect(func(): stats[k] = mini(20, int(stats[k]) + 1); _rebuild_body())
		row.add_child(b_inc)
		VUI.mk_lbl(row, "耗 %+d 点 | %s" % [stat_cost(val), d["desc"]], 12, VUI.C_LTGRAY, true)


func _build_traits_tab() -> void:
	VUI.mk_lbl(_left_box, "先天特性 (共 %d 项)" % _traits.size(), 14, VUI.C_YELLOW)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 4)
	_left_box.add_child(frow)
	for ft in [["all", "全部"], ["pos", "正面 (+)"], ["neg", "负面 (-)"]]:
		var fb := Button.new(); fb.text = ft[1]; fb.focus_mode = Control.FOCUS_NONE
		VUI.style_button(fb, trait_filter == ft[0])
		var k: String = ft[0]
		fb.pressed.connect(func(): trait_filter = k; _rebuild_body())
		frow.add_child(fb)
	_mk_search_bar(_left_box, "搜索特性名称/ID...")
	var scroll := _mk_scroll(_left_box)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	scroll.add_child(list)
	var q := search_filter.to_lower()
	var shown := 0
	for tr: Dictionary in _traits:
		var tid: String = str(tr.get("id", ""))
		var nm: String = str(tr.get("name", tid))
		var pts: int = int(tr.get("points", 0))
		if trait_filter == "pos" and pts <= 0: continue
		if trait_filter == "neg" and pts >= 0: continue
		if not q.is_empty() and not nm.to_lower().contains(q) and not tid.to_lower().contains(q): continue
		var picked := selected_traits.has(tid)
		var b := Button.new()
		b.text = "%s %s [%+d] — %s" % ["[+]" if picked else "[ ]", nm, -pts, str(tr.get("desc", "")).left(38)]
		b.focus_mode = Control.FOCUS_NONE
		var fg := VUI.C_LTGREEN if pts > 0 else (VUI.C_LTRED if pts < 0 else VUI.C_LTGRAY)
		VUI.style_row_button(b, picked, fg)
		b.pressed.connect(func():
			if selected_traits.has(tid): selected_traits.erase(tid)
			else:
				for c in tr.get("cancels", []): selected_traits.erase(str(c))
				selected_traits.append(tid)
			_rebuild_body())
		list.add_child(b)
		shown += 1
		if shown >= 120: break


func _build_skills_tab() -> void:
	VUI.mk_lbl(_left_box, "初始技能 (共 %d 项)" % _skills.size(), 14, VUI.C_YELLOW)
	var scroll := _mk_scroll(_left_box)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for sk: Dictionary in _skills:
		var sid: String = str(sk.get("id", ""))
		var nm: String = str(sk.get("name", sid))
		var lv: int = int(skill_levels.get(sid, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list.add_child(row)
		var nl := VUI.mk_lbl(row, nm, 12, VUI.C_LTCYAN if lv > 0 else VUI.C_WHITE)
		nl.custom_minimum_size.x = 120
		var b_dec := Button.new(); b_dec.text = "-"; b_dec.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_dec)
		b_dec.pressed.connect(func():
			if lv > 0:
				skill_levels[sid] = lv - 1
				if skill_levels[sid] <= 0: skill_levels.erase(sid)
				_rebuild_body())
		row.add_child(b_dec)
		var vl := VUI.mk_lbl(row, "Lv.%d" % lv, 12, VUI.C_YELLOW if lv > 0 else VUI.C_LTGRAY)
		vl.custom_minimum_size.x = 42
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var b_inc := Button.new(); b_inc.text = "+"; b_inc.focus_mode = Control.FOCUS_NONE; VUI.style_button(b_inc)
		b_inc.pressed.connect(func():
			if lv < 10: skill_levels[sid] = lv + 1; _rebuild_body())
		row.add_child(b_inc)
		VUI.mk_lbl(row, str(sk.get("desc", "")).left(48), 11, VUI.C_DKGRAY)


func _build_summary_tab() -> void:
	VUI.mk_lbl(_left_box, "角色身份与确认 (Description)", 14, VUI.C_YELLOW)
	_left_box.add_child(VUI.divider())
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	_left_box.add_child(nrow)
	VUI.mk_lbl(nrow, "姓名:", 13, VUI.C_WHITE)
	var ned := LineEdit.new()
	ned.text = char_name
	ned.custom_minimum_size.x = 180
	VUI.style_line_edit(ned)
	ned.text_changed.connect(func(v: String): char_name = v)
	nrow.add_child(ned)
	VUI.mk_lbl(nrow, "性别:", 13, VUI.C_WHITE)
	for g in [["male", "男"], ["female", "女"]]:
		var gb := Button.new(); gb.text = g[1]; gb.focus_mode = Control.FOCUS_NONE
		VUI.style_button(gb, gender == g[0])
		var gv: String = g[0]
		gb.pressed.connect(func(): gender = gv; _rebuild_body())
		nrow.add_child(gb)

	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	_left_box.add_child(arow)
	VUI.mk_lbl(arow, "年龄: %d 岁" % age, 13, VUI.C_WHITE)
	var b1 := Button.new(); b1.text = "-1"; b1.focus_mode = Control.FOCUS_NONE; VUI.style_button(b1)
	b1.pressed.connect(func(): age = maxi(16, age - 1); _rebuild_body())
	var b2 := Button.new(); b2.text = "+1"; b2.focus_mode = Control.FOCUS_NONE; VUI.style_button(b2)
	b2.pressed.connect(func(): age = mini(75, age + 1); _rebuild_body())
	arow.add_child(b1); arow.add_child(b2)


func _build_right_summary(pts: Dictionary) -> void:
	var sc := _find_scenario(scenario_id)
	var pr := _find_profession(profession_id)

	# REAL Vanilla Paper-Doll Preview (render_character_preview from newcharacter.cpp!)
	var top_prev := HBoxContainer.new()
	top_prev.add_theme_constant_override("separation", 10)
	_right_box.add_child(top_prev)
	var doll := PaperDollPreview.new()
	doll.gender = gender
	doll.worn_ids = pr.get("worn_ids", [])
	doll.wielded_id = str(pr.get("wielded", ""))
	doll.custom_minimum_size = Vector2(96, 96)
	top_prev.add_child(doll)

	var id_col := VBoxContainer.new()
	id_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_col.add_theme_constant_override("separation", 3)
	top_prev.add_child(id_col)
	VUI.mk_lbl(id_col, "%s (%s · %d岁)" % [char_name, "男" if gender == "male" else "女", age], 14, VUI.C_WHITE)
	VUI.mk_lbl(id_col, "力量 %d  敏捷 %d  智力 %d  感知 %d" % [stats["str"], stats["dex"], stats["int"], stats["per"]], 12, VUI.C_YELLOW)
	VUI.mk_lbl(id_col, str(pts["summary"]), 11, VUI.C_LTGREEN if bool(pts["valid"]) else VUI.C_LTRED, true)

	_right_box.add_child(VUI.divider())
	VUI.mk_lbl(_right_box, "[出生剧情] %s (%s)" % [str(sc.get("name", "")), str(sc.get("start_name", ""))], 13, VUI.C_YELLOW)
	VUI.mk_lbl(_right_box, str(sc.get("desc", "")), 11, VUI.C_LTGRAY, true)
	VUI.mk_lbl(_right_box, "[职业] %s (耗 %d 点)" % [str(pr.get("name", "")), int(pr.get("points", 0))], 13, VUI.C_LTCYAN)
	VUI.mk_lbl(_right_box, str(pr.get("desc", "")), 11, VUI.C_LTGRAY, true)
	var worn_names: Array = pr.get("worn_names", [])
	var bag_names: Array = pr.get("bag_names", [])
	if not worn_names.is_empty():
		VUI.mk_lbl(_right_box, "初始穿戴: " + "、".join(PackedStringArray(worn_names)), 11, VUI.C_WHITE, true)
	if not bag_names.is_empty():
		VUI.mk_lbl(_right_box, "初始携带: " + "、".join(PackedStringArray(bag_names)), 11, VUI.C_WHITE, true)
	if not selected_traits.is_empty():
		var tnames: PackedStringArray = []
		for tid in selected_traits: tnames.append(str(_find_trait(tid).get("name", tid)))
		VUI.mk_lbl(_right_box, "[特性] " + "、".join(tnames), 11, VUI.C_LTGREEN, true)
	if not skill_levels.is_empty():
		var sks: PackedStringArray = []
		for sid: String in skill_levels: sks.append("%s+%d" % [sid, int(skill_levels[sid])])
		VUI.mk_lbl(_right_box, "[技能] " + ", ".join(sks), 11, VUI.C_LTCYAN, true)


func _mk_search_bar(parent: Node, placeholder: String) -> LineEdit:
	var ed := LineEdit.new()
	ed.placeholder_text = placeholder
	ed.text = search_filter
	VUI.style_line_edit(ed)
	ed.text_submitted.connect(func(v: String): search_filter = v.strip_edges(); _rebuild_body())
	parent.add_child(ed)
	return ed


func _mk_scroll(parent: Node) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sc)
	return sc


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancelled.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB:
			_step_tab(-1 if event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
		elif event.unicode == 33: # '!'
			randomize_character()
			_rebuild_body()
			get_viewport().set_input_as_handled()
