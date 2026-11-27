extends RefCounted

# Pure Vanilla Cataclysm-Cleanwater-Bomb (CCB) Action Menu, Pause Menu,
# Sidebar Panel Manager ('}'), Look-Around Inspector ('x'/';'), and Help/Missions/Messages.
# Strictly adheres to Cataclysm-Cleanwater-Bomb/src/action.cpp & src/panels.cpp.
# ZERO Cangming/Wuxia leakage!

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const Tiles = preload("res://scripts/undead_tiles.gd")

const LETTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"


# ---------------------------------------------------------------------------
# [Enter] Authentic 7-Category CCB Action Menu (Cataclysm-Cleanwater-Bomb/src/action.cpp:1080)
# ---------------------------------------------------------------------------
static func action_menu_panel(game: Control, contents: VBoxContainer) -> void:
	var cats := [
		{"id": "look", "name": "查看 (Look)", "entries": [
			["环视周围地形与目标详情", "look", "x / ;"],
			["查看大地图 (Overmap)", "map", "m"],
			["列出附近物品、尸体与敌人", "list_nearby", "V"],
			["查看历史消息日志", "messages", "P"],
		]},
		{"id": "interact", "name": "交互 (Interact)", "entries": [
			["检查周围地形 / 家具 / 尸体", "examine", "e"],
			["开门 / 开窗 / 打开柜门", "open", "o"],
			["关门 / 关窗 / 合上柜门", "close", "c"],
			["砸碎门窗家具 / 捣烂丧尸尸体", "smash", "s"],
			["解剖尸体 (原版 Harvest 表)", "dismantle", "B"],
			["抓取 / 松开拖拽家具", "grab", "G"],
			["上楼梯", "stairs_up", "<"],
			["下楼梯", "stairs_down", ">"],
		]},
		{"id": "inventory", "name": "物品栏 (Inventory)", "entries": [
			["打开双栏背包", "inventory", "i"],
			["多选拾取周围物品", "pickup", "g / ,"],
			["双栏高级物品管理器", "advanced_inv", "/"],
			["手持武器 / 物品", "wield", "w"],
			["穿戴装备", "wear", "W"],
			["脱下装备", "take_off", "T"],
			["衣物分层与护甲整理", "armor_layers", "+"],
			["进食 / 饮水 / 服药 / 诱变", "eat", "E"],
			["使用 / 激活工具 (盖革/手电/绷带)", "apply", "a"],
			["丢弃物品到脚下", "drop", "d"],
		]},
		{"id": "combat", "name": "战斗 (Combat)", "entries": [
			["切换移动姿态 (行走/奔跑/潜行)", "move_mode", "\""],
			["开关安全模式 (遇敌提醒)", "safe_mode", "!"],
			["砸碎 / 捣烂尸体防止复活", "smash", "s"],
			["解剖尸体获取材料", "dismantle", "B"],
		]},
		{"id": "craft", "name": "制造 (Craft)", "entries": [
			["打开原版合成制造界面 (2,823配方)", "craft", "&"],
		]},
		{"id": "info", "name": "信息 (Info)", "entries": [
			["角色状态 / 属性 / 累赘 / 变异 / 28技能", "character", "@"],
			["侧边栏面板管理器 (开关/排序/风格)", "sidebar_mgr", "}"],
			["开关像素小地图", "toggle_pixel_minimap", "N"],
			["多人联机合作设置", "multiplayer", "O"],
		]},
		{"id": "misc", "name": "杂项 (Misc)", "entries": [
			["等待指定时间", "wait", "|"],
			["原地睡眠", "sleep", "$"],
			["保存游戏", "save", "S"],
			["键位帮助", "help", "?"],
			["调试菜单 (全物品库/刷怪/辐射测试)", "debug", "K"],
		]},
	]

	var active_cat: String = str(game.get("ccb_action_cat"))
	if active_cat.is_empty():
		active_cat = "look"

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(split)

	# Left column: 7 CCB categories (1-7)
	var left_p := PanelContainer.new()
	left_p.custom_minimum_size.x = 185
	left_p.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 6, 1))
	split.add_child(left_p)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 2)
	left_p.add_child(lbox)
	VUI.mk_lbl(lbox, "分类 (1-7 切换)", 12, VUI.C_YELLOW)
	lbox.add_child(VUI.divider())
	for ci in range(cats.size()):
		var c: Dictionary = cats[ci]
		var cid: String = str(c["id"])
		var num_k := str(ci + 1)
		var is_cur := (cid == active_cat)
		var cb := func():
			game.ccb_action_cat = cid
			game._reopen_overlay("action_menu")
		game.overlay_hotkeys[num_k] = cb
		var btn := Button.new()
		btn.text = "%s%s. %s" % ["» " if is_cur else "  ", num_k, str(c["name"])]
		btn.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(btn, is_cur, VUI.C_WHITE if is_cur else VUI.C_LTGRAY)
		btn.pressed.connect(cb)
		lbox.add_child(btn)

	# Right column: Actions in selected category (a-z)
	var right_p := PanelContainer.new()
	right_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_p.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 8, 6, 1))
	split.add_child(right_p)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 2)
	right_p.add_child(rbox)

	var sel_cat: Dictionary = cats[0]
	for c: Dictionary in cats:
		if str(c["id"]) == active_cat:
			sel_cat = c
			break
	VUI.mk_lbl(rbox, "%s — 按字母键或点击执行" % str(sel_cat["name"]), 13, VUI.C_YELLOW)
	rbox.add_child(VUI.divider())

	var entries: Array = sel_cat["entries"]
	for i in range(entries.size()):
		var ent: Array = entries[i]
		var ltr := LETTERS.substr(i, 1)
		var act_id: String = str(ent[1])
		var run_cb := func():
			game._close_overlay()
			game._run_ccb_action(act_id)
		game.overlay_hotkeys[ltr] = run_cb
		var btn := Button.new()
		btn.text = " %s - %-30s [%s]" % [ltr, str(ent[0]), str(ent[2])]
		btn.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(btn, false, VUI.C_WHITE)
		btn.pressed.connect(run_cb)
		rbox.add_child(btn)


# ---------------------------------------------------------------------------
# [Esc] Authentic CCB In-Game Pause Menu (Cataclysm-Cleanwater-Bomb/src/action.cpp:1293)
# ---------------------------------------------------------------------------
static func pause_menu_panel(game: Control, contents: VBoxContainer) -> void:
	var entries := [
		["?", "帮助与按键一览 (Help)", func(): game._reopen_overlay("help"), VUI.C_LTGRAY],
		["}", "侧边栏选项与面板管理 (Sidebar Options)", func(): game._reopen_overlay("sidebar_mgr"), VUI.C_LTCYAN],
		["n", "开关像素小地图 (Toggle Pixel Minimap)", func():
			game._close_overlay()
			game._run_ccb_action("toggle_pixel_minimap"), VUI.C_LTGRAY],
		["t", "切换原版材质包 (Tileset Options)", func(): game._reopen_overlay("tileset_opts"), VUI.C_LTGRAY],
		["!", "开关安全模式 (Safe Mode)", func():
			game._close_overlay()
			game._run_ccb_action("safe_mode"), VUI.C_LTGRAY],
		["o", "多人联机合作 (Multiplayer Co-op)", func(): game._reopen_overlay("multiplayer"), VUI.C_LTGRAY],
		["a", "动作菜单 (Action Menu [Enter])", func(): game._reopen_overlay("action_menu"), VUI.C_LTGRAY],
		["k", "调试菜单 (Debug Menu — 全物品库/刷怪)", func(): game._reopen_overlay("debug"), VUI.C_YELLOW],
		["s", "快速保存 (Quicksave)", func():
			game._save()
			game._close_overlay(), VUI.C_LTGREEN],
		["q", "保存并返回主菜单 (Save and Quit)", func():
			game._save()
			game._close_overlay()
			game._return_to_main_menu(), VUI.C_YELLOW],
		["x", "继续游戏 (Resume [Esc])", func(): game._close_overlay(), VUI.C_WHITE],
	]
	for e: Array in entries:
		var ltr: String = e[0]
		var cb: Callable = e[2]
		game.overlay_hotkeys[ltr] = cb
		var btn := Button.new()
		btn.text = " [%s]  %s" % [ltr, str(e[1])]
		btn.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(btn, false, e[3])
		btn.pressed.connect(cb)
		contents.add_child(btn)


# ---------------------------------------------------------------------------
# [}] Authentic CCB Sidebar Options / Panel Manager (src/panels.cpp panel_manager::show_adm)
# ---------------------------------------------------------------------------
static func sidebar_manager_panel(game: Control, contents: VBoxContainer) -> void:
	var vsb = game.ccb_sidebar
	if vsb == null:
		VUI.mk_lbl(contents, "侧边栏仅在大灾变核心包中可自定义。", 13, VUI.C_LTGRAY)
		return

	VUI.mk_lbl(contents, "侧边栏布局风格（即时生效）：", 13, VUI.C_YELLOW)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	contents.add_child(srow)
	for st: Array in [["classic", "classic (5x7小地图+血条)"], ["structured", "structured (结构化)"], ["compact", "compact (紧凑)"]]:
		var sid: String = st[0]
		var b := Button.new()
		b.text = st[1]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_button(b, vsb.layout_style == sid)
		b.pressed.connect(func():
			vsb.set_layout_style(sid)
			game._refresh()
			game._reopen_overlay("sidebar_mgr"))
		srow.add_child(b)

	contents.add_child(VUI.divider())
	VUI.mk_lbl(contents, "面板模块开关与排序（按字母键开关，点击 ↑ / ↓ 调整上下位置）：", 13, VUI.C_YELLOW)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(sc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)

	for i in range(vsb.panel_order.size()):
		var entry: Dictionary = vsb.panel_order[i]
		var en: bool = bool(entry.get("enabled", true))
		var ltr := LETTERS.substr(i, 1)
		var idx := i
		var tog := func():
			vsb.panel_order[idx]["enabled"] = not bool(vsb.panel_order[idx].get("enabled", true))
			vsb.apply_panel_order()
			game._refresh()
			game._reopen_overlay("sidebar_mgr")
		game.overlay_hotkeys[ltr] = tog

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var tb := Button.new()
		tb.text = " %s - %s  %s" % [ltr, "[开]" if en else "[关]", str(entry["name"])]
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(tb, false, VUI.C_LTGREEN if en else VUI.C_DKGRAY)
		tb.pressed.connect(tog)
		row.add_child(tb)

		var up_b := Button.new(); up_b.text = "↑"; up_b.focus_mode = Control.FOCUS_NONE; VUI.style_button(up_b)
		up_b.disabled = (i == 0)
		up_b.pressed.connect(func():
			var tmp = vsb.panel_order[idx]
			vsb.panel_order[idx] = vsb.panel_order[idx - 1]
			vsb.panel_order[idx - 1] = tmp
			vsb.apply_panel_order()
			game._reopen_overlay("sidebar_mgr"))
		row.add_child(up_b)

		var dn_b := Button.new(); dn_b.text = "↓"; dn_b.focus_mode = Control.FOCUS_NONE; VUI.style_button(dn_b)
		dn_b.disabled = (i == vsb.panel_order.size() - 1)
		dn_b.pressed.connect(func():
			var tmp = vsb.panel_order[idx]
			vsb.panel_order[idx] = vsb.panel_order[idx + 1]
			vsb.panel_order[idx + 1] = tmp
			vsb.apply_panel_order()
			game._reopen_overlay("sidebar_mgr"))
		row.add_child(dn_b)


# ---------------------------------------------------------------------------
# In-game Tileset Switcher (Unmodified CCB gfx/ packs)
# ---------------------------------------------------------------------------
static func tileset_options_panel(game: Control, contents: VBoxContainer) -> void:
	VUI.mk_lbl(contents, "切换原版 gfx 材质包（直接加载未修改原版素材）：", 13, VUI.C_YELLOW)
	var cur := Tiles.current_tileset_name()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	contents.add_child(grid)
	for ts: String in Tiles.list_vanilla_tilesets():
		var b := Button.new()
		b.text = ("* " if ts == cur else "  ") + ts
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		VUI.style_button(b, ts == cur)
		var ts_name := ts
		b.pressed.connect(func():
			game._switch_tileset(ts_name)
			game._reopen_overlay("tileset_opts"))
		grid.add_child(b)


# ---------------------------------------------------------------------------
# [x] / [;] Look-Around Floating Inspection Box (exact CCB game::look_around!)
# ---------------------------------------------------------------------------
static func build_look_inspector_text(world: RefCounted, target: Vector2i) -> String:
	var d: Dictionary = world.ccb_inspect_tile(target)
	var lines := PackedStringArray()
	lines.append("【环视检视】 %s  坐标:(%d, %d)  距离:%d" % [
		str(d.get("location", "")), target.x, target.y, int(d.get("distance", 0))
	])
	var ter := str(d.get("terrain_id", ""))
	var furn := str(d.get("furniture_id", ""))
	lines.append("地形: %s%s  |  可通行: %s" % [
		ter,
		("  |  家具: " + furn) if not furn.is_empty() else "",
		"是" if bool(d.get("walkable", true)) else "否",
	])
	var rad := float(d.get("radiation", 0.0))
	if rad > 0.01:
		lines.append("⚠ 环境辐射: %.1f mSv/分" % rad)

	var mon: Dictionary = d.get("monster", {})
	if not mon.is_empty():
		var hp := int(mon.get("hp", 0))
		var mhp := maxi(1, int(mon.get("max_hp", 1)))
		var pct := float(hp) / float(mhp)
		var hp_desc := "完好无损" if pct > 0.85 else ("轻伤" if pct > 0.55 else ("重伤" if pct > 0.25 else "濒死"))
		lines.append("敌对目标: %s [%s %d/%d HP]" % [str(mon.get("name", "")), hp_desc, hp, mhp])

	var corpses: Array = d.get("corpses", [])
	if not corpses.is_empty():
		var cnames := PackedStringArray()
		for c: Dictionary in corpses:
			cnames.append(str(c.get("name", "尸体")))
		lines.append("尸体(%d): %s" % [corpses.size(), "、".join(cnames)])

	var items: Array = d.get("items", [])
	if not items.is_empty():
		var inames := PackedStringArray()
		for i in range(mini(6, items.size())):
			var it: Dictionary = items[i]
			inames.append("%s×%d" % [str(it.get("name", "")), int(it.get("count", 1))])
		if items.size() > 6:
			inames.append("...共%d项" % items.size())
		lines.append("地面物品: " + "、".join(inames))
	else:
		lines.append("地面物品: 无")
	lines.append("[方向键/hjkl 移动光标 | Esc 退出环视]")
	return "\n".join(lines)


static func help_panel(_game: Control, contents: VBoxContainer) -> void:
	var txt := """【移动与回合】
  方向键 / 小键盘 1-9 / h j k l y u b n ：8方向移动（撞击丧尸自动近战）
  . 或 5 ：原地等待一回合        | ：等待指定分钟        $ ：睡眠
  \" ：切换移动姿态 (行走/奔跑/潜行)       ! ：开关安全模式

【物品与装备】
  i ：双栏背包（左栏 a-z 分组选择 + 右栏完整属性详情与操作）
  g / , ：多选勾选拾取（支持全选、负重与容积条、尸体操作）
  / ：双栏高级物品管理器（背包 / 脚下 / 周边 8 格快速批量搬运）
  + ：衣物分层与护甲管理器（检查各部位累赘保暖、调整穿戴内外顺序）
  w 手持 | W 穿戴 | T 脱下 | E 饮食/服药/诱变 | a 激活工具 | d 丢弃

【探索、战斗与界面】
  m ：无限大地图 Overmap（含探索迷雾、hjkl移光标、N记笔记、f搜索、W自动旅行）
  x / ; ：环视检视（弹出详细地形/怪物/尸体/物品检视窗）
  V ：附近物品、尸体与敌人双栏列表      e ：检查/交互      o/c ：开关门窗
  s ：砸碎门窗或捣烂尸体（防复活）      B ：原版 Harvest 表解剖尸体
  & ：双栏原版制造（2,823配方 + 批量制作）   @ ：多宫格角色状态与 28 技能
  } ：侧边栏面板管理器（开关/排序/切换风格）   N ：开关像素小地图
  Enter ：7 分类原版动作菜单             Esc ：系统暂停菜单             K ：调试菜单"""
	VUI.mk_lbl(contents, txt, 12, VUI.C_LTGRAY, true)


static func missions_panel(_game: Control, contents: VBoxContainer) -> void:
	VUI.mk_lbl(contents, "当前任务列表 (Missions)", 14, VUI.C_YELLOW)
	contents.add_child(VUI.divider())
	VUI.mk_lbl(contents, "当前没有进行中的原版任务。\n提示：在无限随机新英格兰大地图中探索避难所、药房、超市、警局、五金店与核废料场，收集补给并生存下去。", 13, VUI.C_LTGRAY, true)
