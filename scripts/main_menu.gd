extends Control

# Pure Vanilla Cataclysm-Cleanwater-Bomb (CCB) Main Menu
# Faithfully ported from Cataclysm-Cleanwater-Bomb/src/main_menu.cpp:
#  - Pure black #000000 terminal canvas (NO custom background art!)
#  - Centered 22-line colored ASCII title art from data/title/zh_CN.title + Version line
#  - Single bottom horizontal bar of 7 primary entries:
#      新游戏 <N> | 联机合作 <O> | 载入 <A> | 世界 <W> | 设置 <T> | 其他 <E> | 退出 <Q>
#  - Compact 0px white-bordered popup submenu (w_sub) anchored DIRECTLY ABOVE the selected tab
#    with cobalt-blue highlight cursor ("» ") and full keyboard navigation (Arrows / hjkl / hotkeys)
#  - Clean sharp modal dialogs for Create World, Co-op Host/Join, Options (Tileset/Sidebar), and MOTD
#  - Bottom 2 lines: yellow contextual hint + cyan Tip of the day

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const Tiles = preload("res://scripts/undead_tiles.gd")
const CharCreator = preload("res://scripts/char_creator.gd")
const WORLDS_PATH := "user://ccb_worlds.json"
const TITLE_PATH := "res://packs/cataclysm/vanilla/zh_CN.title"
const MOTD_PATH := "res://packs/cataclysm/vanilla/zh_CN.motd"

signal start_ccb_game_requested(world_cfg: Dictionary, char_cfg: Dictionary)
signal launch_ccb_native_requested()
signal start_pack_requested(pack_id: String, seed_val: int, scenario_id: String, player_name: String)
signal load_save_requested(path: String)
signal host_coop_requested(pack_id: String, port: int, player_name: String)
signal join_coop_requested(address: String, port: int, player_name: String)
signal tileset_changed_requested(tileset_name: String)
signal sidebar_style_changed_requested(style_name: String)
signal toggle_roofs_requested()
signal quit_requested()

const PRIMARY_TABS := [
	{"id": "new",   "label": "新游戏 <N>",   "key": "n", "hint": "在当前选中的世界中创建新幸存者或立即游玩。"},
	{"id": "coop",  "label": "联机合作 <O>", "key": "o", "hint": "主持或加入 ENet 多人合作会话。"},
	{"id": "load",  "label": "载入 <A>",     "key": "a", "hint": "读取已有角色存档继续冒险。"},
	{"id": "world", "label": "世界 <W>",     "key": "w", "hint": "创建、切换、重置或删除世界（支持大灾变 CCB 原版与沧溟修真核心包）。"},
	{"id": "opts",  "label": "设置 <T>",     "key": "t", "hint": "原版材质包、侧边栏风格与小地图选项。"},
	{"id": "other", "label": "其他 <E>",     "key": "e", "hint": "查看每日消息 (MOTD)、按键帮助与制作人员。"},
	{"id": "quit",  "label": "退出 <Q>",     "key": "q", "hint": "退出游戏返回桌面。", "danger": true},
]

const TIPS := [
	"每日提示：击杀丧尸后按 s 捣烂或按 B 解剖尸体，否则数小时后丧尸会重新爬起复活！",
	"每日提示：丧尸掉落的衣物带有 (脏污) 标记，原版规则下需清洗后才能穿戴。",
	"每日提示：按 Enter 打开 7 分类动作菜单，按 ? 查看全部原版按键，按 } 自定义侧边栏面板。",
	"每日提示：按 / 打开双栏高级物品管理器，可在脚下、四周八格与背包之间批量搬运物品。",
	"每日提示：按 + 打开衣物分层管理器，检查各部位覆盖率、累赘与保暖并调整内外层次。",
	"每日提示：在「世界 <W>」中可创建「大灾变 CCB 原版」或「沧溟修真」核心包世界，存档与物品完全隔离。",
]

var _world: RefCounted
var worlds: Array = []
var active_world_idx := 0
var selected_pack := "cataclysm"
var active_tab_idx := 0
var active_tab := "new"
var sub_idx := 0
var sidebar_style := "classic"
var _tip_idx := 0

var _tab_buttons: Array[Button] = []
var _nav_row: HBoxContainer
var _popup_panel: PanelContainer
var _popup_box: VBoxContainer
var _sub_items: Array = [] # Array of {"label", "key", "hint", "cb", "color"}
var _sub_buttons: Array[Button] = []
var _version_lbl: Label
var _hint_lbl: Label
var _tip_lbl: Label
var _modal_backdrop: ColorRect
var _modal_panel: PanelContainer
var char_creator: CharCreator


func build(world: RefCounted) -> void:
	_world = world
	_load_worlds()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Pure #000000 black CCB background (NO custom backdrop art!)
	var bg := ColorRect.new()
	bg.color = VUI.BG_BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	# --- CENTERED VANILLA zh_CN.title ASCII ART (22 lines) ---
	var title_center := CenterContainer.new()
	title_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(title_center)

	var title_rt := RichTextLabel.new()
	title_rt.bbcode_enabled = true
	title_rt.fit_content = true
	title_rt.scroll_active = false
	title_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_rt.custom_minimum_size = Vector2(780, 0)
	title_rt.add_theme_font_size_override("normal_font_size", 13)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "DejaVu Sans Mono", "Noto Sans Mono CJK SC"])
	title_rt.add_theme_font_override("normal_font", mono)
	title_rt.text = _load_title_bbcode()
	title_center.add_child(title_rt)

	# --- VERSION & ACTIVE WORLD LINE (exact main_menu.cpp) ---
	_version_lbl = VUI.mk_lbl(root, "", 13, VUI.C_LTBLUE)
	_version_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_version_line()

	# Spacer that pushes bottom nav bar to exact CCB lower screen position
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spacer)

	# Crisp 1px separator above primary menu bar
	root.add_child(VUI.divider(VUI.BORDER))

	# --- PRIMARY HORIZONTAL MENU ROW (7 entries) ---
	var nav_center := CenterContainer.new()
	nav_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(nav_center)

	_nav_row = HBoxContainer.new()
	_nav_row.add_theme_constant_override("separation", 6)
	nav_center.add_child(_nav_row)
	_tab_buttons.clear()
	for i in range(PRIMARY_TABS.size()):
		var t: Dictionary = PRIMARY_TABS[i]
		var btn := Button.new()
		btn.text = str(t["label"])
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(106, 28)
		var idx := i
		btn.pressed.connect(func(): _select_primary_tab(idx))
		_nav_row.add_child(btn)
		_tab_buttons.append(btn)

	root.add_child(VUI.divider(VUI.BORDER_DIM))

	# --- BOTTOM 2 LINES: CONTEXT HINT (YELLOW) + TIP OF THE DAY (CYAN) ---
	_hint_lbl = VUI.mk_lbl(root, "", 12, VUI.C_YELLOW)
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_lbl = VUI.mk_lbl(root, TIPS[0], 12, VUI.C_LTCYAN)
	_tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# --- COMMUNITY CREDITS FOOTER ---
	var credits_lbl := VUI.mk_lbl(
		root,
		"本项目灵感来源于CCB，本项目QQ群：1001568760\nCCB群：552610319\n感谢所有玩家的奉献",
		12,
		Color(0.76, 0.86, 0.96)
	)
	credits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# --- COMPACT BUTTON-ANCHORED FLOATING SUBMENU (w_sub, exact main_menu.cpp!) ---
	_popup_panel = PanelContainer.new()
	_popup_panel.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_BRIGHT, 6, 5, 1))
	_popup_panel.visible = false
	add_child(_popup_panel)

	_popup_box = VBoxContainer.new()
	_popup_box.add_theme_constant_override("separation", 2)
	_popup_panel.add_child(_popup_box)

	# --- 8-TAB CHARACTER CREATOR ---
	char_creator = CharCreator.new()
	char_creator.visible = false
	char_creator.build(_world)
	char_creator.character_confirmed.connect(func(cfg: Dictionary):
		char_creator.visible = false
		start_ccb_game_requested.emit(get_active_world(), cfg))
	char_creator.cancelled.connect(func():
		char_creator.visible = false)
	add_child(char_creator)

	resized.connect(_reposition_popup)
	call_deferred("_select_primary_tab", 0)


func _load_title_bbcode() -> String:
	if FileAccess.file_exists(TITLE_PATH):
		var raw := FileAccess.get_file_as_string(TITLE_PATH)
		if not raw.is_empty():
			return VUI.ccb_markup_to_bbcode(raw)
	return "[color=#55ffff]CATACLYSM : CLEANWATER BOMB  |  大灾变：净水炸弹[/color]"


func _load_worlds() -> void:
	worlds.clear()
	if FileAccess.file_exists(WORLDS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(WORLDS_PATH))
		if parsed is Array and not parsed.is_empty():
			worlds = parsed
	if worlds.is_empty():
		worlds = [
			{"name": "净水炸弹·默认世界", "pack": "cataclysm", "seed": 20260415, "city_size": 8, "city_spacing": 4, "monster_rate": 1.0},
			{"name": "沧溟修真·扬州城", "pack": "cangming", "seed": 20260415, "city_size": 8, "city_spacing": 4, "monster_rate": 1.0},
		]
		_save_worlds()
	active_world_idx = clampi(active_world_idx, 0, worlds.size() - 1)
	selected_pack = str(get_active_world().get("pack", "cataclysm"))


func _save_worlds() -> void:
	var f := FileAccess.open(WORLDS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(worlds, "\t"))


func get_active_world() -> Dictionary:
	if worlds.is_empty():
		return {"name": "默认世界", "pack": "cataclysm", "seed": 20260415, "city_size": 8, "city_spacing": 4, "monster_rate": 1.0}
	return worlds[clampi(active_world_idx, 0, worlds.size() - 1)]


func refresh_status() -> void:
	_refresh_version_line()
	_rebuild_submenu()


func _refresh_version_line() -> void:
	if _version_lbl == null:
		return
	var w := get_active_world()
	var pack_cn := "大灾变 CCB 原版" if str(w.get("pack", "cataclysm")) == "cataclysm" else "沧溟修真"
	_version_lbl.text = "版本：Cataclysm-Cleanwater-Bomb (纯原版核心包)   |   当前世界：%s [%s · 种子 %d]" % [
		str(w.get("name", "默认世界")), pack_cn, int(w.get("seed", 20260415))
	]


func _select_primary_tab(idx: int) -> void:
	active_tab_idx = posmod(idx, PRIMARY_TABS.size())
	active_tab = str(PRIMARY_TABS[active_tab_idx]["id"])
	sub_idx = 0
	for i in range(_tab_buttons.size()):
		var is_sel := (i == active_tab_idx)
		var is_danger := bool(PRIMARY_TABS[i].get("danger", false))
		VUI.style_button(_tab_buttons[i], is_sel, is_danger)
	if active_tab == "quit":
		_popup_panel.visible = false
		_sub_items.clear()
		_hint_lbl.text = str(PRIMARY_TABS[active_tab_idx]["hint"])
		return
	_rebuild_submenu()


func _rebuild_submenu() -> void:
	for c in _popup_box.get_children():
		c.queue_free()
	_sub_items.clear()
	_sub_buttons.clear()

	var w := get_active_world()
	var is_ccb := str(w.get("pack", "cataclysm")) == "cataclysm"

	match active_tab:
		"new":
			if is_ccb:
				_add_sub("启动《大灾变：净水炸弹》原生内核（100% 完整原版）<Enter>", "n", "启动完整原生 CCB C++ 核心（真 51 模组/31 世界配置/真地图与出生点/真 FOV/载具/仿生/变异 + Godot GPU 动态光影与原版材质）。", func():
					launch_ccb_native_requested.emit(), VUI.C_LTGREEN)
				_add_sub("踏入「沧溟修真」扬州城（核心包切换）<c>", "c", "直接切换并进入沧溟修真核心包（江湖武学、商铺、工坊、江南烟雨光影与联机）。", func():
					start_pack_requested.emit("cangming", int(w.get("seed", 20260415)), "jianghu", "游侠"), VUI.C_YELLOW)
				_add_sub("轻量预览模式：自定义角色 <u>", "u", "以轻量预览模式打开 8 标签创角。", func():
					char_creator.open_for_world(w))
			else:
				_add_sub("踏入沧溟修真·扬州城 <Enter>", "u", "进入当前沧溟修真世界（完整保留江湖武学、商铺、工坊与光影天气）。", func():
					start_pack_requested.emit("cangming", int(w.get("seed", 20260415)), "jianghu", "游侠"), VUI.C_LTGREEN)
				_add_sub("启动《大灾变：净水炸弹》原生内核 <n>", "n", "切换到大灾变 CCB 完整原生 C++ 内核。", func():
					launch_ccb_native_requested.emit(), VUI.C_LTCYAN)
		"coop":
			_add_sub("主持会话 <h>", "h", "在本机启动 ENet 多人合作主机，等待队友加入。", func():
				_open_coop_modal(true))
			_add_sub("加入会话 <j>", "j", "输入房主 IP 与端口加入联机合作。", func():
				_open_coop_modal(false))
		"load":
			var saves := [
				{"path": "user://save_cataclysm.json", "tag": "大灾变 CCB"},
				{"path": "user://save_cangming.json", "tag": "沧溟修真"},
			]
			var found := false
			for s: Dictionary in saves:
				var sp: String = str(s["path"])
				if FileAccess.file_exists(sp):
					found = true
					var meta: Dictionary = _world.inspect_save_meta(sp)
					var p_name := str(meta.get("player_name", "幸存者"))
					var mins := int(meta.get("minutes", 440))
					var lbl := "%s [%s · 第%d天 %02d:%02d]" % [p_name, str(s["tag"]), 1 + mins / 1440, (mins % 1440) / 60, mins % 60]
					_add_sub(lbl, "", "读取存档文件：" + sp.get_file(), func():
						load_save_requested.emit(sp), VUI.C_LTGREEN)
			if not found:
				_add_sub("(暂无可读取的存档)", "", "先开始新游戏并按 S 保存即可在此载入。", func(): pass, VUI.C_DKGRAY)
		"world":
			_add_sub("创建世界 <c>", "c", "新建「大灾变 CCB 原版」或「沧溟修真」世界并配置种子/城镇规模/怪物倍率。", func():
				_open_create_world_modal(), VUI.C_YELLOW)
			for i in range(worlds.size()):
				var wi: Dictionary = worlds[i]
				var ptag := "大灾变" if str(wi.get("pack", "cataclysm")) == "cataclysm" else "沧溟"
				var mark := "* " if i == active_world_idx else "  "
				var widx := i
				_add_sub("%s%s (%s)" % [mark, str(wi.get("name", "世界")), ptag], "",
					"种子 %d · 城镇规模 %d · 间距 %d · 怪物倍率 %.1fx（点击设为当前世界或管理）" % [
						int(wi.get("seed", 0)), int(wi.get("city_size", 8)), int(wi.get("city_spacing", 4)), float(wi.get("monster_rate", 1.0))
					], func(): _open_world_actions_modal(widx), VUI.C_LTCYAN if i == active_world_idx else VUI.C_LTGRAY)
		"opts":
			_add_sub("选项（材质包 / 侧边栏）<o>", "o", "切换原版 gfx 材质包与侧边栏布局（classic/structured/compact）。", func():
				_open_options_modal())
			_add_sub("键位一览 <y>", "y", "查看大灾变 CCB 完整原版键位表。", func():
				_open_help_modal())
		"other":
			_add_sub("每日消息 (MOTD) <m>", "m", "阅读原版 data/motd/zh_CN.motd 公告。", func():
				_open_motd_modal())
			_add_sub("帮助 <e>", "e", "查看大灾变 CCB 原版操作指南。", func():
				_open_help_modal())
			_add_sub("制作人员 <c>", "c", "查看项目与 CCB 原版致谢信息。", func():
				_open_credits_modal())

	sub_idx = clampi(sub_idx, 0, maxi(0, _sub_items.size() - 1))
	for i in range(_sub_items.size()):
		var item: Dictionary = _sub_items[i]
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(220, 24)
		var ii := i
		btn.pressed.connect(func():
			sub_idx = ii
			_refresh_sub_highlight()
			var cb: Callable = _sub_items[ii]["cb"]
			cb.call())
		btn.mouse_entered.connect(func():
			sub_idx = ii
			_refresh_sub_highlight())
		_popup_box.add_child(btn)
		_sub_buttons.append(btn)

	_popup_panel.visible = not _sub_items.is_empty()
	_refresh_sub_highlight()
	call_deferred("_reposition_popup")


func _add_sub(label: String, key: String, hint: String, cb: Callable, color := VUI.C_LTGRAY) -> void:
	_sub_items.append({"label": label, "key": key, "hint": hint, "cb": cb, "color": color})


func _refresh_sub_highlight() -> void:
	for i in range(_sub_buttons.size()):
		var sel := (i == sub_idx)
		var it: Dictionary = _sub_items[i]
		_sub_buttons[i].text = ("» " if sel else "  ") + str(it["label"])
		VUI.style_row_button(_sub_buttons[i], sel, it["color"])
	if sub_idx >= 0 and sub_idx < _sub_items.size():
		_hint_lbl.text = str(_sub_items[sub_idx]["hint"])
	elif active_tab_idx >= 0 and active_tab_idx < PRIMARY_TABS.size():
		_hint_lbl.text = str(PRIMARY_TABS[active_tab_idx]["hint"])


func _reposition_popup() -> void:
	if _popup_panel == null or not _popup_panel.visible or active_tab_idx < 0 or active_tab_idx >= _tab_buttons.size():
		return
	_popup_panel.reset_size()
	var btn := _tab_buttons[active_tab_idx]
	var b_rect := btn.get_global_rect()
	var p_size := _popup_panel.get_combined_minimum_size()
	var px := clampf(b_rect.position.x + (b_rect.size.x - p_size.x) * 0.5, 16.0, size.x - p_size.x - 16.0)
	var py := maxf(24.0, b_rect.position.y - p_size.y - 10.0)
	_popup_panel.position = Vector2(px, py)
	_popup_panel.size = p_size


# ---------------------------------------------------------------------------
# Sharp 0px CCB Modal Dialogs (Create World, World Actions, Co-op, Options, MOTD, Help)
# ---------------------------------------------------------------------------
func _close_modal() -> void:
	if _modal_backdrop != null:
		_modal_backdrop.queue_free()
		_modal_backdrop = null
	if _modal_panel != null:
		_modal_panel.queue_free()
		_modal_panel = null


func _open_modal(title: String, min_w := 560, min_h := 340) -> VBoxContainer:
	_close_modal()
	_modal_backdrop = ColorRect.new()
	_modal_backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	_modal_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.add_child(center)

	_modal_panel = PanelContainer.new()
	_modal_panel.custom_minimum_size = Vector2(min_w, min_h)
	_modal_panel.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_BRIGHT, 12, 10, 1))
	center.add_child(_modal_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_modal_panel.add_child(col)

	var hrow := HBoxContainer.new()
	col.add_child(hrow)
	var tl := VUI.mk_lbl(hrow, title, 15, VUI.C_YELLOW)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var xb := Button.new()
	xb.text = "[Esc] 关闭"
	xb.focus_mode = Control.FOCUS_NONE
	VUI.style_button(xb)
	xb.pressed.connect(_close_modal)
	hrow.add_child(xb)
	col.add_child(VUI.divider(VUI.BORDER))
	return col


func _open_create_world_modal() -> void:
	var col := _open_modal("创建世界 · CREATE WORLD", 580, 360)
	var chosen_pack := ["cataclysm"]

	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	col.add_child(prow)
	VUI.mk_lbl(prow, "核心包：", 13, VUI.C_WHITE)
	var b_ccb := Button.new()
	var b_cm := Button.new()
	b_ccb.text = "大灾变：净水炸弹 (CCB 纯原版)"
	b_cm.text = "沧溟修真 · 扬州城"
	b_ccb.focus_mode = Control.FOCUS_NONE
	b_cm.focus_mode = Control.FOCUS_NONE
	var sync_p := func():
		VUI.style_button(b_ccb, chosen_pack[0] == "cataclysm")
		VUI.style_button(b_cm, chosen_pack[0] == "cangming")
	b_ccb.pressed.connect(func(): chosen_pack[0] = "cataclysm"; sync_p.call())
	b_cm.pressed.connect(func(): chosen_pack[0] = "cangming"; sync_p.call())
	sync_p.call()
	prow.add_child(b_ccb)
	prow.add_child(b_cm)

	var nrow := HBoxContainer.new()
	col.add_child(nrow)
	VUI.mk_lbl(nrow, "世界名称：", 13, VUI.C_LTGRAY)
	var name_ed := LineEdit.new()
	name_ed.text = "新世界 #%d" % (worlds.size() + 1)
	name_ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VUI.style_line_edit(name_ed)
	nrow.add_child(name_ed)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	col.add_child(srow)
	VUI.mk_lbl(srow, "随机种子：", 13, VUI.C_LTGRAY)
	var seed_ed := LineEdit.new()
	seed_ed.text = str(randi() % 89999999 + 10000000)
	seed_ed.custom_minimum_size.x = 130
	VUI.style_line_edit(seed_ed)
	srow.add_child(seed_ed)
	VUI.mk_lbl(srow, "城镇规模(3-16)：", 13, VUI.C_LTGRAY)
	var cs_ed := LineEdit.new()
	cs_ed.text = "8"
	cs_ed.custom_minimum_size.x = 46
	VUI.style_line_edit(cs_ed)
	srow.add_child(cs_ed)
	VUI.mk_lbl(srow, "怪物倍率：", 13, VUI.C_LTGRAY)
	var mr_ed := LineEdit.new()
	mr_ed.text = "1.0"
	mr_ed.custom_minimum_size.x = 54
	VUI.style_line_edit(mr_ed)
	srow.add_child(mr_ed)

	VUI.mk_lbl(col, "提示：大灾变世界严格采用 180×180 无限随机 Overmap、纯回合制、未修改原版材质与原版怪物掉落表，与沧溟修真完全隔离。", 12, VUI.C_DKGRAY, true)

	var ok := Button.new()
	ok.text = "确认创建并设为当前世界 [Enter]"
	ok.focus_mode = Control.FOCUS_NONE
	VUI.style_button(ok, true)
	ok.pressed.connect(func():
		var wn := name_ed.text.strip_edges()
		if wn.is_empty():
			wn = "世界 #%d" % (worlds.size() + 1)
		worlds.append({
			"name": wn,
			"pack": chosen_pack[0],
			"seed": maxi(1, int(seed_ed.text)),
			"city_size": clampi(int(cs_ed.text), 3, 16),
			"city_spacing": 4,
			"monster_rate": clampf(float(mr_ed.text), 0.25, 4.0),
		})
		active_world_idx = worlds.size() - 1
		selected_pack = chosen_pack[0]
		_save_worlds()
		_close_modal()
		_refresh_version_line()
		_rebuild_submenu())
	col.add_child(ok)


func _open_world_actions_modal(widx: int) -> void:
	if widx < 0 or widx >= worlds.size():
		return
	var w: Dictionary = worlds[widx]
	var col := _open_modal("世界管理：%s" % str(w.get("name", "")), 460, 240)
	var ptag := "大灾变 CCB 原版" if str(w.get("pack", "cataclysm")) == "cataclysm" else "沧溟修真"
	VUI.mk_lbl(col, "核心包：%s  |  种子：%d  |  城镇规模：%d  |  怪物倍率：%.1fx" % [
		ptag, int(w.get("seed", 0)), int(w.get("city_size", 8)), float(w.get("monster_rate", 1.0))
	], 12, VUI.C_LTCYAN)

	var b_use := Button.new()
	b_use.text = "设为当前活动世界"
	b_use.focus_mode = Control.FOCUS_NONE
	VUI.style_button(b_use, true)
	b_use.pressed.connect(func():
		active_world_idx = widx
		selected_pack = str(w.get("pack", "cataclysm"))
		_close_modal()
		_refresh_version_line()
		_rebuild_submenu())
	col.add_child(b_use)

	var b_reroll := Button.new()
	b_reroll.text = "重置世界（生成新随机种子）"
	b_reroll.focus_mode = Control.FOCUS_NONE
	VUI.style_button(b_reroll)
	b_reroll.pressed.connect(func():
		worlds[widx]["seed"] = randi() % 89999999 + 10000000
		_save_worlds()
		_close_modal()
		_refresh_version_line()
		_rebuild_submenu())
	col.add_child(b_reroll)

	if worlds.size() > 1:
		var b_del := Button.new()
		b_del.text = "删除此世界"
		b_del.focus_mode = Control.FOCUS_NONE
		VUI.style_button(b_del, false, true)
		b_del.pressed.connect(func():
			worlds.remove_at(widx)
			active_world_idx = clampi(active_world_idx, 0, worlds.size() - 1)
			selected_pack = str(get_active_world().get("pack", "cataclysm"))
			_save_worlds()
			_close_modal()
			_refresh_version_line()
			_rebuild_submenu())
		col.add_child(b_del)


func _open_coop_modal(is_host: bool) -> void:
	var col := _open_modal("联机合作 · %s" % ("主持会话" if is_host else "加入会话"), 480, 240)
	var r1 := HBoxContainer.new()
	col.add_child(r1)
	VUI.mk_lbl(r1, "玩家昵称：", 13, VUI.C_LTGRAY)
	var name_ed := LineEdit.new()
	name_ed.text = "幸存者"
	name_ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VUI.style_line_edit(name_ed)
	r1.add_child(name_ed)

	var addr_ed: LineEdit = null
	if not is_host:
		var r_ip := HBoxContainer.new()
		col.add_child(r_ip)
		VUI.mk_lbl(r_ip, "主机地址：", 13, VUI.C_LTGRAY)
		addr_ed = LineEdit.new()
		addr_ed.text = "127.0.0.1"
		addr_ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		VUI.style_line_edit(addr_ed)
		r_ip.add_child(addr_ed)

	var r2 := HBoxContainer.new()
	col.add_child(r2)
	VUI.mk_lbl(r2, "ENet 端口：", 13, VUI.C_LTGRAY)
	var port_ed := LineEdit.new()
	port_ed.text = "28460"
	port_ed.custom_minimum_size.x = 90
	VUI.style_line_edit(port_ed)
	r2.add_child(port_ed)

	var go := Button.new()
	go.text = "启动主机并进入当前世界" if is_host else "连接到房主会话"
	go.focus_mode = Control.FOCUS_NONE
	VUI.style_button(go, true)
	go.pressed.connect(func():
		var nm := name_ed.text.strip_edges()
		if nm.is_empty(): nm = "幸存者"
		var port := clampi(int(port_ed.text), 1024, 65535)
		_close_modal()
		if is_host:
			host_coop_requested.emit(str(get_active_world().get("pack", "cataclysm")), port, nm)
		else:
			join_coop_requested.emit(addr_ed.text.strip_edges(), port, nm))
	col.add_child(go)


func _open_options_modal() -> void:
	var col := _open_modal("设置 · OPTIONS（原版材质包 / 侧边栏样式）", 660, 420)
	VUI.mk_lbl(col, "原版 gfx 材质包（直接读取 Cataclysm-Cleanwater-Bomb/gfx/，零修改）：", 13, VUI.C_YELLOW)
	var ts_grid := GridContainer.new()
	ts_grid.columns = 3
	ts_grid.add_theme_constant_override("h_separation", 6)
	ts_grid.add_theme_constant_override("v_separation", 4)
	col.add_child(ts_grid)
	var cur_ts: String = Tiles.current_tileset_name()
	for ts: String in Tiles.list_vanilla_tilesets():
		var b := Button.new()
		b.text = ("* " if ts == cur_ts else "  ") + ts
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		VUI.style_button(b, ts == cur_ts)
		var ts_name := ts
		b.pressed.connect(func():
			tileset_changed_requested.emit(ts_name)
			_open_options_modal())
		ts_grid.add_child(b)

	col.add_child(VUI.divider(VUI.BORDER_DIM))
	VUI.mk_lbl(col, "原版侧边栏布局（游戏中随时可按 } 自定义各面板开关与顺序）：", 13, VUI.C_YELLOW)
	var sb_row := HBoxContainer.new()
	sb_row.add_theme_constant_override("separation", 6)
	col.add_child(sb_row)
	for st: Array in [["classic", "经典 classic (5x7小地图+血条)"], ["structured", "结构化 structured"], ["compact", "紧凑 compact"]]:
		var b := Button.new()
		b.text = st[1]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_button(b, sidebar_style == st[0])
		var s_id: String = st[0]
		b.pressed.connect(func():
			sidebar_style = s_id
			sidebar_style_changed_requested.emit(s_id)
			_open_options_modal())
		sb_row.add_child(b)


func _open_motd_modal() -> void:
	var col := _open_modal("每日消息 · MESSAGE OF THE DAY (zh_CN.motd)", 740, 480)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sc)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 13)
	var raw := FileAccess.get_file_as_string(MOTD_PATH) if FileAccess.file_exists(MOTD_PATH) else "欢迎游玩大灾变：净水炸弹 (CCB)！"
	rt.text = VUI.ccb_markup_to_bbcode(raw)
	sc.add_child(rt)


func _open_help_modal() -> void:
	var col := _open_modal("大灾变 CCB 原版按键帮助", 680, 440)
	var txt := """移动与等待：方向键 / 小键盘 1-9 / h j k l y u b n 移动；. 或 5 等待一回合；| 等待指定时间；$ 睡觉
物品与装备：i 双栏背包；g / , 多选拾取；/ 双栏高级物品管理；w 手持；W 穿戴；T 脱下；+ 衣物分层管理；d 丢弃；E 饮食服药；a 激活使用；R 阅读
战斗与尸体：撞击丧尸近战；s 砸碎家具/捣烂尸体；B 解剖尸体（原版 harvest 表）；! 开关安全模式；\" 切换走/跑/潜行
探索与界面：m 无限大地图（含迷雾/笔记/搜索/自动旅行）；x 或 ; 环视检视详情框；V 附近物品与敌人；e 检查/交互；o 开门；c 关门；& 制作；@ 多宫格角色状态；} 侧边栏面板管理；N 切换像素小地图；Enter 7类动作菜单；Esc 暂停菜单"""
	VUI.mk_lbl(col, txt, 13, VUI.C_LTGRAY, true)


func _open_credits_modal() -> void:
	var col := _open_modal("制作人员 · CREDITS", 520, 220)
	VUI.mk_lbl(col, "Cataclysm: Cleanwater Bomb (CCB) 原版数据、材质、逻辑与简体中文本地化均源自 CCB 开源社区。\n本客户端以 Godot 4.5 + C++ GDExtension 双核心包架构承载纯原版 CCB 与沧溟修真，并提供动态 GPU 光影天气、多线程区块烘焙与 ENet 联机支持。", 13, VUI.C_LTGRAY, true)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or (char_creator != null and char_creator.visible):
		return
	if not event is InputEventKey or not event.pressed:
		return
	var ke := event as InputEventKey
	if _modal_panel != null:
		if ke.physical_keycode == KEY_ESCAPE:
			_close_modal()
			get_viewport().set_input_as_handled()
		return

	var pk: Key = ke.physical_keycode
	if pk == KEY_LEFT or pk == KEY_H:
		_select_primary_tab(active_tab_idx - 1)
		get_viewport().set_input_as_handled()
		return
	if pk == KEY_RIGHT or pk == KEY_L:
		_select_primary_tab(active_tab_idx + 1)
		get_viewport().set_input_as_handled()
		return
	if pk == KEY_UP or pk == KEY_K:
		if not _sub_items.is_empty():
			sub_idx = posmod(sub_idx - 1, _sub_items.size())
			_refresh_sub_highlight()
		get_viewport().set_input_as_handled()
		return
	if pk == KEY_DOWN or pk == KEY_J:
		if not _sub_items.is_empty():
			sub_idx = posmod(sub_idx + 1, _sub_items.size())
			_refresh_sub_highlight()
		get_viewport().set_input_as_handled()
		return
	if pk == KEY_ENTER or pk == KEY_KP_ENTER:
		if active_tab == "quit":
			quit_requested.emit()
		elif sub_idx >= 0 and sub_idx < _sub_items.size():
			var cb: Callable = _sub_items[sub_idx]["cb"]
			cb.call()
		get_viewport().set_input_as_handled()
		return
	if pk == KEY_TAB:
		_tip_idx = (_tip_idx + 1) % TIPS.size()
		_tip_lbl.text = TIPS[_tip_idx]
		get_viewport().set_input_as_handled()
		return

	if event.unicode > 0 and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed):
		var ch := char(event.unicode).to_lower()
		# Check submenu hotkeys first
		for i in range(_sub_items.size()):
			var sk: String = str(_sub_items[i].get("key", ""))
			if not sk.is_empty() and sk == ch:
				sub_idx = i
				_refresh_sub_highlight()
				var cb: Callable = _sub_items[i]["cb"]
				cb.call()
				get_viewport().set_input_as_handled()
				return
		# Then check primary tab hotkeys
		for i in range(PRIMARY_TABS.size()):
			if str(PRIMARY_TABS[i]["key"]) == ch:
				if str(PRIMARY_TABS[i]["id"]) == "quit":
					quit_requested.emit()
				else:
					_select_primary_tab(i)
				get_viewport().set_input_as_handled()
				return
