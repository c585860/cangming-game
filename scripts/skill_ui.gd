extends RefCounted

# Classic Wuxia MUD 4-Realm Skill Panel (武学 / 武道 / 练气 / 仙道),
# Master NPC Learn Dialog (`learn`), and Multiplayer Session Panel.
# Rules:
#  - Unlearned skills (Lv.0) NEVER appear on the Skill Panel and CANNOT be practiced!
#  - Level 1..179: learn from city masters (costs potential) or slow self-practice (costs kcal/stamina).
#  - Level >= 180: unlocks classic MUD `research` (costs potential to break through grandmaster bottlenecks).

const CCB = preload("res://scripts/ccb_theme.gd")

const REALM_ORDER := ["wuxue", "wudao", "lianqi", "xiandao"]
const CATEGORY_ORDER := ["内功心法", "身法轻功", "护体招架", "空手外功", "兵刃外功", "远程绝技", "文雅杂学", "市井谋生"]


static func _rank_color(level: int) -> Color:
	if level <= 0:
		return CCB.C_DKGRAY
	if level < 10:
		return CCB.C_WHITE
	if level < 35:
		return CCB.C_LTGREEN
	if level < 70:
		return CCB.C_LTCYAN
	if level < 125:
		return CCB.C_YELLOW
	return Color("ffbe4f")


static func _ascii_bar(progress: float, width := 10) -> String:
	var filled := clampi(int(round(progress * float(width))), 0, width)
	return "[" + "█".repeat(filled) + "░".repeat(width - filled) + "]"


static func skill_panel(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var realms: Array = world.skill_realms()
	var active_realm: String = str(game.skill_tab) if str(game.skill_tab) in REALM_ORDER else "wuxue"
	var summary: Dictionary = world.skill_summary()
	var st: Dictionary = world.character_status()

	# --- Top Banner: Potential, Combat Exp, Neili, Dynamic 6-Part HP Cap & Nourishment ---
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 5, 1))
	contents.add_child(banner)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 2)
	banner.add_child(bcol)
	game._label(bcol, "名号: %s  |  潜能: %d/%d  |  江湖阅历: %d  |  已习技艺: %d/%d 门" % [
		str(world.get_player_name()),
		int(summary.get("potential", 0)),
		int(summary.get("potential_cap", 200)),
		int(summary.get("combat_exp", 0)),
		int(summary.get("learned", 0)),
		int(summary.get("total_skills", 20)),
	], 12, CCB.C_YELLOW)
	var fed_tag := "饱腹(+25%效)" if bool(st.get("well_fed", false)) else ("腹饥禁练" if bool(st.get("starving_for_training", false)) else "尚可")
	game._label(bcol, "部位气血上限: %d  |  内力: %d/%d  |  饱食: %d(%s)  |  耐力: %d%%  |  1-4切栏位" % [
		int(st.get("max_part_hp", 84)),
		int(st.get("neili", 0)),
		int(st.get("max_neili", 0)),
		int(st.get("kcal", 0)),
		fed_tag,
		int(round(float(st.get("stamina", 10000)) / 100.0)),
	], 11, CCB.C_LTGRAY)

	# --- 4 Classic Path Tabs: 武学 / 武道 / 练气 / 仙道 ---
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	contents.add_child(tab_row)
	var active_realm_info: Dictionary = {}
	for i in range(realms.size()):
		var r: Dictionary = realms[i]
		var rid: String = str(r.get("id", ""))
		var rname: String = str(r.get("name", ""))
		var unlocked: bool = bool(r.get("unlocked", false))
		var is_cur := rid == active_realm
		if is_cur:
			active_realm_info = r
		var suffix := " (%d/%d)" % [int(r.get("learned_count", 0)), int(r.get("skill_count", 0))] if unlocked else " [未启]"
		var label_txt := "[%d] %s%s" % [i + 1, rname, suffix]
		var cb := func():
			game.skill_tab = rid
			game._reopen_overlay("skills")
		var btn: Button = game._button(tab_row, label_txt, cb, is_cur)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.register_overlay_hotkey(str(i + 1), cb)

	# --- Locked Realm View (武道 / 练气 / 仙道) ---
	if not bool(active_realm_info.get("unlocked", false)):
		var lock_card := PanelContainer.new()
		lock_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lock_card.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 16, 14, 1))
		contents.add_child(lock_card)
		var lcol := VBoxContainer.new()
		lcol.add_theme_constant_override("separation", 10)
		lock_card.add_child(lcol)
		game._label(lcol, "【 %s 】  ——  %s" % [
			str(active_realm_info.get("name", "")),
			str(active_realm_info.get("subtitle", "")),
		], 16, CCB.C_YELLOW)
		lcol.add_child(CCB.divider())
		game._label(lcol, "当前境界尚未开启。", 14, CCB.C_LTRED)
		game._label(lcol, "开启指引：%s" % str(active_realm_info.get("unlock_hint", "")), 13, CCB.C_WHITE, true)
		game._label(lcol, "提示：按 [1] 返回「武学」栏位，先向城中师傅请教入门基础技艺。", 12, CCB.C_CYAN, true)
		return

	# --- Active 武学 Tab: ONLY Learned Skills Appear! ---
	var skills: Array = world.skill_list(active_realm)
	if skills.is_empty():
		var empty_card := PanelContainer.new()
		empty_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_card.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 14, 12, 1))
		contents.add_child(empty_card)
		var ecol := VBoxContainer.new()
		ecol.add_theme_constant_override("separation", 8)
		empty_card.add_child(ecol)
		game._label(ecol, "【 尚未习得任何武学与市井技艺 】", 15, CCB.C_YELLOW)
		ecol.add_child(CCB.divider())
		game._label(ecol, "江湖规矩：未习得的武学不会凭空出现在面板中，也无法自行练习。请先携带随身潜能，拜访沧灵城各路师傅请教入门：", 12, CCB.C_WHITE, true)
		game._label(ecol, "  · 扬威武馆 · 陈馆主 (西市大街南)：基本内功 / 轻功 / 招架 / 空手六艺", 12, CCB.C_LTCYAN)
		game._label(ecol, "  · 扬威武馆 · 周教头 (兵器堂内)：剑 / 刀 / 杖 / 棍 / 枪 / 鞭 / 基本暗器", 12, CCB.C_LTCYAN)
		game._label(ecol, "  · 文昌书院 · 顾夫子 (北大街东)：读书写字（提升学习效率，解锁书院与当铺钱庄工位）", 12, CCB.C_LTGREEN)
		game._label(ecol, "  · 回春堂药铺 · 平大夫 (东关大街北)：基本药学（提升疗伤效果，解锁药坊 4 工位）", 12, CCB.C_LTGREEN)
		game._label(ecol, "  · 醉仙楼 · 冼老板 (南大街东)：基本厨艺（提升饮食收益，解锁后厨 4 工位）", 12, CCB.C_LTGREEN)
		game._label(ecol, "  · 王记铁匠铺 · 王铁匠 (南大街西)：基本锻造 / 刀法 / 棍法（解锁锻造坊 4 工位）", 12, CCB.C_LTGREEN)
		game._label(ecol, "  · 水埠码头 · 老船夫 (东关河埠)：基本拳脚 / 轻功启蒙（解锁码头 4 漕运工位）", 12, CCB.C_LTGREEN)
		game._label(ecol, "提示：按 [M] 可查看城中各路师傅与工坊方位并一键自动寻路。", 12, CCB.C_YELLOW)
		return

	var selected_id: String = str(game.selected_skill_id)
	var selected_row: Dictionary = skills[0]
	for row: Dictionary in skills:
		if str(row.get("id", "")) == selected_id:
			selected_row = row
			break
	game.selected_skill_id = str(selected_row.get("id", ""))

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(split)

	# Left Column: Scrollable list of LEARNED skills only
	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 1.45
	split.add_child(left_scroll)

	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 3)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(list_box)

	var letter_idx := 0
	for cat: String in CATEGORY_ORDER:
		var group: Array = []
		for row: Dictionary in skills:
			if str(row.get("category", "")) == cat:
				group.append(row)
		if group.is_empty():
			continue
		game._label(list_box, "[ %s ]" % cat, 12, CCB.C_CYAN)
		for row: Dictionary in group:
			var sid: String = str(row.get("id", ""))
			var sname: String = str(row.get("name", ""))
			var lv: int = int(row.get("level", 0))
			var rank_str: String = str(row.get("rank", "初学乍练"))
			var prog: float = float(row.get("progress", 0.0))
			var jifa: String = str(row.get("jifa", ""))
			var sup_jifa: bool = bool(row.get("supports_jifa", false))
			var jifa_tag := ""
			if sup_jifa:
				jifa_tag = " [激发:%s]" % jifa if not jifa.is_empty() else " [未激发]"
			var letter := CCB.letter_key(letter_idx)
			letter_idx += 1
			var is_sel: bool = sid == str(game.selected_skill_id)
			var row_txt := "%s - %-6s  Lv.%3d  %s  %-5s%s" % [
				letter, sname, lv, _ascii_bar(prog, 8), rank_str, jifa_tag
			]
			var pick_cb := func():
				game.selected_skill_id = sid
				game._reopen_overlay("skills")
			var btn: Button = game._button(list_box, row_txt, pick_cb, is_sel)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if not is_sel:
				btn.add_theme_color_override("font_color", _rank_color(lv))
			if letter != "-":
				game.register_overlay_hotkey(letter, pick_cb)

	# Right Column: Selected Skill Details, <180 Slow Practice & >=180 Potential Research
	var detail_card := PanelContainer.new()
	detail_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_card.size_flags_stretch_ratio = 1.0
	detail_card.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 10, 10, 1))
	split.add_child(detail_card)

	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 5)
	detail_card.add_child(dcol)

	var sel_id: String = str(selected_row.get("id", ""))
	var sel_name: String = str(selected_row.get("name", ""))
	var sel_lv: int = int(selected_row.get("level", 1))
	var sel_exp: int = int(selected_row.get("exp", 0))
	var sel_next: int = int(selected_row.get("exp_next", 40))
	var sel_prog: float = float(selected_row.get("progress", 0.0))
	var sel_rank: String = str(selected_row.get("rank", "初学乍练"))
	var sel_jifa: String = str(selected_row.get("jifa", ""))
	var sel_sup_jifa: bool = bool(selected_row.get("supports_jifa", false))
	var can_research: bool = bool(selected_row.get("can_research", false))
	var res_pot: int = int(selected_row.get("research_pot_cost", 30))

	game._label(dcol, sel_name, 17, CCB.C_YELLOW)
	game._label(dcol, "归属: %s · %s  |  传艺师傅: %s" % [
		str(selected_row.get("realm_name", "武学")),
		str(selected_row.get("category", "")),
		str(selected_row.get("mentor_hint", "")),
	], 11, CCB.C_CYAN, true)
	dcol.add_child(CCB.divider())
	game._label(dcol, "当前等级: %d 级（%s）" % [sel_lv, sel_rank], 13, _rank_color(sel_lv))
	game._label(dcol, "熟练进度: %s  %d / %d" % [_ascii_bar(sel_prog, 14), sel_exp, sel_next], 12, CCB.C_LTGRAY)
	dcol.add_child(CCB.divider())
	game._label(dcol, "[ 武学要义与身体联动 ]", 12, CCB.C_CYAN)
	game._label(dcol, str(selected_row.get("desc", "")), 12, CCB.C_WHITE, true)
	dcol.add_child(CCB.divider())
	game._label(dcol, "[ 激发槽位 (MUD jifa / enable) ]", 12, CCB.C_CYAN)
	if sel_sup_jifa:
		var jifa_desc := "当前激发：%s" % sel_jifa if not sel_jifa.is_empty() else "当前未激发特殊武功（后续习得门派绝学后可激发至此）"
		game._label(dcol, jifa_desc, 12, CCB.C_LTGREEN if not sel_jifa.is_empty() else CCB.C_DKGRAY, true)
	else:
		game._label(dcol, "此艺属文雅/市井根基，直接生效，无需激发。", 12, CCB.C_DKGRAY, true)

	dcol.add_child(CCB.divider())
	var stage_hint := "当前 < 180 级：可找师傅耗潜能请教，或不耗潜能缓慢自练。" if not can_research else "已达 180 级宗师境：可消耗潜能自主研究突破！"
	game._label(dcol, stage_hint, 11, CCB.C_LTGREEN if can_research else CCB.C_LTGRAY, true)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dcol.add_child(spacer)

	var practice_cb := func():
		var res: Dictionary = game.net_session.dispatch_action(world, {
			"type": "practice_skill",
			"skill_id": sel_id,
		})
		game._note(str(res.get("message", "")))
		game._refresh()
		game._reopen_overlay("skills")
	var pbtn: Button = game._button(dcol, "[Space] 缓慢练习「%s」（不耗潜能，耗饱食/耐力）" % sel_name, practice_cb, not can_research)
	pbtn.custom_minimum_size.y = 30
	game.register_overlay_hotkey(" ", practice_cb)

	var research_cb := func():
		var res: Dictionary = game.net_session.dispatch_action(world, {
			"type": "research_skill",
			"skill_id": sel_id,
		})
		game._note(str(res.get("message", "")))
		game._refresh()
		game._reopen_overlay("skills")
	var rlabel := "[R] 潜心研究「%s」（耗潜能 %d）" % [sel_name, res_pot] if can_research \
		else "[R] 潜心研究（须达 180 级解锁，当前 %d/180）" % sel_lv
	var rbtn: Button = game._button(dcol, rlabel, research_cb, can_research)
	rbtn.custom_minimum_size.y = 30
	if not can_research:
		rbtn.add_theme_color_override("font_color", CCB.C_DKGRAY)
	game.register_overlay_hotkey("R", research_cb)


static func learn_panel(game: Control, contents: VBoxContainer, npc_pos: Vector2i) -> void:
	var world: Object = game.world
	var teach_list: Array = world.npc_teach_list(npc_pos)
	var summary: Dictionary = world.skill_summary()
	var st: Dictionary = world.character_status()

	var npc_name := "师傅"
	var npc_place := ""
	for n: Dictionary in world.npc_list():
		if Vector2i(n.get("pos", Vector2i(-1, -1))) == npc_pos:
			npc_name = str(n.get("name", "师傅"))
			npc_place = str(n.get("place", ""))
			break

	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 6, 1))
	contents.add_child(banner)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 2)
	banner.add_child(bcol)
	game._label(bcol, "授业师傅: %s（%s）  |  当前潜能: %d / %d  |  随身铜钱: %d 文" % [
		npc_name, npc_place,
		int(summary.get("potential", 0)),
		int(summary.get("potential_cap", 200)),
		int(world.coins),
	], 13, CCB.C_YELLOW)
	var lit_lv: int = int(world.skill_level("literate"))
	game._label(bcol, "饱食: %d kcal  |  读书写字加成: +%d%%  |  按对应字母向师傅请教（入门至 1 级后即解锁工位并显示于技能面板 [J]）" % [
		int(st.get("kcal", 0)), lit_lv * 4
	], 11, CCB.C_LTGRAY, true)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 5)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)

	if teach_list.is_empty():
		game._label(list_box, "此位人物目前暂无可传授的技艺。", 12, CCB.C_DKGRAY)
		return

	for i in range(teach_list.size()):
		var row: Dictionary = teach_list[i]
		var sid: String = str(row.get("id", ""))
		var sname: String = str(row.get("name", ""))
		var cur_lv: int = int(row.get("current_level", 0))
		var max_lv: int = int(row.get("max_teach_level", 30))
		var pot_c: int = int(row.get("pot_cost", 10))
		var coin_c: int = int(row.get("coin_cost", 2))
		var can: bool = bool(row.get("can_learn", false))
		var reason: String = str(row.get("reason", ""))
		var letter := CCB.letter_key(i)
		var state_txt := "未习得 → 入门1级" if cur_lv == 0 else "Lv.%d / 上限%d" % [cur_lv, max_lv]
		var cost_txt := "耗潜能%d · %d文" % [pot_c, coin_c] if can else "[%s]" % reason
		var txt := "%s - %-6s [%s]   %s   %s" % [letter, sname, str(row.get("category", "")), state_txt, cost_txt]
		var cb := func():
			var res: Dictionary = game.net_session.dispatch_action(world, {
				"type": "learn_from_npc",
				"target": npc_pos,
				"skill_id": sid,
			})
			game._note(str(res.get("message", "")))
			game._refresh()
			game._reopen_overlay("learn_npc", npc_pos)
		var btn: Button = game._button(list_box, txt, cb, cur_lv == 0 and can)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not can:
			btn.add_theme_color_override("font_color", CCB.C_DKGRAY)
		game._label(list_box, "      %s" % str(row.get("desc", "")), 11, CCB.C_LTGRAY, true)
		if letter != "-":
			game.register_overlay_hotkey(letter, cb)


static func multiplayer_panel(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var net: RefCounted = game.net_session
	var st: Dictionary = net.status_dict(world)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 10, 8, 1))
	contents.add_child(card)
	var scol := VBoxContainer.new()
	scol.add_theme_constant_override("separation", 3)
	card.add_child(scol)
	game._label(scol, "联机状态: %s  |  协议版本: v%d  |  本机 PeerID: %d" % [
		str(st.get("mode_label", "")),
		int(st.get("protocol_version", 1)),
		int(st.get("local_peer_id", 1)),
	], 13, CCB.C_YELLOW)
	game._label(scol, "角色名号: %s  |  已同步远端同道: %d 人  |  底层接口: ENet / Snapshot Ready（工位免锁自由协作）" % [
		str(st.get("player_name", "")),
		int(st.get("remote_count", 0)),
	], 12, CCB.C_CYAN)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 8)
	form.add_theme_constant_override("v_separation", 6)
	contents.add_child(form)

	game._label(form, "江湖名号:", 12, CCB.C_LTGRAY)
	var name_edit := LineEdit.new()
	name_edit.text = str(world.get_player_name())
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CCB.style_line_edit(name_edit)
	form.add_child(name_edit)

	game._label(form, "服务器地址:", 12, CCB.C_LTGRAY)
	var addr_edit := LineEdit.new()
	addr_edit.text = str(st.get("host_address", "127.0.0.1"))
	addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CCB.style_line_edit(addr_edit)
	form.add_child(addr_edit)

	game._label(form, "端口 (Port):", 12, CCB.C_LTGRAY)
	var port_edit := LineEdit.new()
	port_edit.text = str(int(st.get("port", 27015)))
	port_edit.max_length = 5
	port_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CCB.style_line_edit(port_edit)
	form.add_child(port_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	contents.add_child(btn_row)
	game._button(btn_row, "保存名号", func():
		world.set_player_name(name_edit.text)
		game._note("名号已更改为「%s」。" % str(world.get_player_name()))
		game._reopen_overlay("multiplayer"))
	game._button(btn_row, "开启房主 (Host)", func():
		world.set_player_name(name_edit.text)
		var res: Dictionary = net.host_session(int(port_edit.text), 8, game.get_tree().get_multiplayer())
		game._note(str(res.get("message", "")))
		game._reopen_overlay("multiplayer"), true)
	game._button(btn_row, "加入联机 (Join)", func():
		world.set_player_name(name_edit.text)
		var res: Dictionary = net.join_session(addr_edit.text, int(port_edit.text), game.get_tree().get_multiplayer())
		game._note(str(res.get("message", "")))
		game._reopen_overlay("multiplayer"))
	game._button(btn_row, "回到单人离线", func():
		net.leave_session(game.get_tree().get_multiplayer(), world)
		game.board.player_layer.queue_redraw()
		game._note("已切换回单人离线模式。")
		game._reopen_overlay("multiplayer"))

	contents.add_child(CCB.divider())
	game._label(contents, "[ 已同步远端玩家 / 联机渲染测试 ]", 12, CCB.C_CYAN)
	var peers: Array = world.list_remote_players()
	if peers.is_empty():
		game._label(contents, "  (当前无远端玩家连接。已预留 C++ 状态快照、空间查询与指令同步接口，可直接接入多人联机。)", 12, CCB.C_DKGRAY, true)
	else:
		for rp: Dictionary in peers:
			var rpos: Vector2i = rp.get("pos", Vector2i.ZERO)
			game._label(contents, "  · Peer#%d  %s  (%s)  @ (%d,%d) Z:%d" % [
				int(rp.get("peer_id", 0)),
				str(rp.get("name", "同道")),
				str(rp.get("rank_label", "初入江湖")),
				rpos.x, rpos.y, int(rp.get("floor", 0)),
			], 12, CCB.C_LTGREEN)

	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 6)
	contents.add_child(test_row)
	game._button(test_row, "生成模拟联机同道（验同步渲染）", func():
		var spawn_p: Vector2i = world.pos + Vector2i(1, 0)
		net.spawn_mock_peer(1002, "苏青衫", spawn_p, world)
		game.board.player_layer.queue_redraw()
		game._note("联机测试: 已同步模拟同道「苏青衫」至 (%d,%d)。" % [spawn_p.x, spawn_p.y])
		game._reopen_overlay("multiplayer"))
	game._button(test_row, "清除模拟同道", func():
		world.clear_remote_players()
		game.board.player_layer.queue_redraw()
		game._note("联机测试: 已清除模拟远端同道。")
		game._reopen_overlay("multiplayer"))
