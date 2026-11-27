extends RefCounted

# Classic Wuxia MUD 4-Realm Skill Panel (武学 / 武道 / 练气 / 仙道),
# Entry Special Martial Arts + jifa (激发), Master NPC Learn Dialog (`learn`),
# Exert & Dazuo Meditation Panel (`[U]`), and Multiplayer Session Panel (`[O]`).

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
	var filled := clampi(int(round(clampf(progress, 0.0, 1.0) * float(width))), 0, width)
	return "[" + "█".repeat(filled) + "░".repeat(width - filled) + "]"


static func skill_panel(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var realms: Array = world.skill_realms()
	var active_realm: String = str(game.skill_tab) if str(game.skill_tab) in REALM_ORDER else "wuxue"
	var summary: Dictionary = world.skill_summary()
	var st: Dictionary = world.character_status()

	# --- Top Banner ---
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 5, 1))
	contents.add_child(banner)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 2)
	banner.add_child(bcol)
	game._label(bcol, "名号: %s  |  潜能: %d/%d  |  江湖阅历: %d  |  基础技艺: %d/%d  |  特殊武功: %d" % [
		str(world.get_player_name()),
		int(summary.get("potential", 0)),
		int(summary.get("potential_cap", 200)),
		int(summary.get("combat_exp", 0)),
		int(summary.get("learned_count", 0)),
		int(summary.get("base_count", 20)),
		int(summary.get("learned_special_count", 0)),
	], 12, CCB.C_YELLOW)
	var fed_tag := "饱腹(+25%效)" if bool(st.get("well_fed", false)) else ("腹饥禁练" if bool(st.get("starving_for_training", false)) else "尚可")
	game._label(bcol, "部位血量上限: %d  |  内力: %d/%d  |  饱食: %d(%s)  |  耐力: %d%%  |  按 [U] 打坐运功" % [
		int(st.get("max_part_hp", 84)),
		int(st.get("neili", 0)),
		int(st.get("max_neili", 0)),
		int(st.get("kcal", 0)),
		fed_tag,
		int(round(float(st.get("stamina", 10000)) / 100.0)),
	], 11, CCB.C_LTGRAY)

	# --- 4 Classic Path Tabs ---
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
		var suffix := " (%d/%d)" % [int(r.get("count", 0)), int(r.get("total_catalog", 20))] if unlocked else " [未启]"
		var label_txt := "[%d] %s%s" % [i + 1, rname, suffix]
		var cb := func():
			game.skill_tab = rid
			game._reopen_overlay("skills")
		var btn: Button = game._button(tab_row, label_txt, cb, is_cur)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.register_overlay_hotkey(str(i + 1), cb)

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
		game._label(ecol, "江湖规矩：未习得的武学不会显示在面板中，也无法自行练习。请先携带随身潜能，拜访沧灵城各路师傅请教入门：", 12, CCB.C_WHITE, true)
		game._label(ecol, "  · 扬威武馆 · 陈馆主 (西市大街南)：基本内功 / 轻功 / 招架 / 空手六艺（满10级传授入门绝学）", 12, CCB.C_LTCYAN)
		game._label(ecol, "  · 扬威武馆 · 周教头 (兵器堂内)：剑 / 刀 / 杖 / 棍 / 枪 / 鞭 / 基本暗器（满10级传授兵刃绝学）", 12, CCB.C_LTCYAN)
		game._label(ecol, "  · 文昌书院 · 顾夫子 (北大街东)：读书写字（亦售卖各科武谱典籍，按 R 精读涨技艺）", 12, CCB.C_LTGREEN)
		game._label(ecol, "  · 回春堂药铺 · 平大夫 (东关大街北)：基本药学（解锁药坊工位与制药配方）", 12, CCB.C_LTGREEN)
		game._label(ecol, "  · 醉仙楼 · 冼老板 (南大街东)：基本厨艺（解锁后厨工位与热食烹饪）", 12, CCB.C_LTGREEN)
		game._label(ecol, "  · 王记铁匠铺 · 王铁匠 (南大街西)：基本锻造 / 刀法 / 棍法（亦售卖入门兵刃）", 12, CCB.C_LTGREEN)
		game._label(ecol, "  · 水埠码头 · 老船夫 (东关河埠)：基本拳脚 / 轻功启蒙（解锁码头漕运工位）", 12, CCB.C_LTGREEN)
		game._label(ecol, "提示：按 [M] 可查看城中各路师傅、商铺与江湖委托并一键自动寻路。", 12, CCB.C_YELLOW)
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
			var eff: int = int(row.get("effective_level", lv))
			var exp_cur: int = int(row.get("exp", 0))
			var exp_need: int = maxi(1, int(row.get("exp_need", 40)))
			var prog: float = float(exp_cur) / float(exp_need)
			var rank_str: String = str(row.get("rank", "初学乍练"))
			var jifa_name: String = str(row.get("enabled_art_name", ""))
			var sup_jifa: bool = bool(row.get("supports_jifa", false))
			var jifa_tag := ""
			if sup_jifa:
				jifa_tag = " [激发:%s->有效%d]" % [jifa_name, eff] if not jifa_name.is_empty() else " [未激发]"
			var letter := CCB.letter_key(letter_idx)
			letter_idx += 1
			var is_sel: bool = sid == str(game.selected_skill_id)
			var row_txt := "%s - %-6s Lv.%3d %s %s%s" % [
				letter, sname, lv, _ascii_bar(prog, 7), rank_str, jifa_tag
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

	# Right Column: Details, Jifa Switcher, Practice & Research
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
	var sel_eff: int = int(selected_row.get("effective_level", sel_lv))
	var sel_exp: int = int(selected_row.get("exp", 0))
	var sel_next: int = maxi(1, int(selected_row.get("exp_need", 40)))
	var sel_prog: float = float(sel_exp) / float(sel_next)
	var sel_rank: String = str(selected_row.get("rank", "初学乍练"))
	var sel_jifa_name: String = str(selected_row.get("enabled_art_name", ""))
	var sel_sup_jifa: bool = bool(selected_row.get("supports_jifa", false))
	var avail_arts: Array = selected_row.get("available_arts", [])
	var can_research: bool = bool(selected_row.get("can_research", false))
	var res_pot: int = int(selected_row.get("research_pot_cost", 30))

	game._label(dcol, sel_name, 17, CCB.C_YELLOW)
	game._label(dcol, "归属: 武学 · %s  |  传艺师傅: %s" % [
		str(selected_row.get("category", "")),
		str(selected_row.get("mentor_hint", "")),
	], 11, CCB.C_CYAN, true)
	dcol.add_child(CCB.divider())
	game._label(dcol, "基础等级: %d 级（%s）  |  有效等级: %d 级" % [sel_lv, sel_rank, sel_eff], 13, _rank_color(sel_lv))
	game._label(dcol, "熟练进度: %s  %d / %d" % [_ascii_bar(sel_prog, 14), sel_exp, sel_next], 12, CCB.C_LTGRAY)
	dcol.add_child(CCB.divider())
	game._label(dcol, str(selected_row.get("desc", "")), 12, CCB.C_WHITE, true)
	dcol.add_child(CCB.divider())
	game._label(dcol, "[ 激发槽位 (MUD jifa / enable) ]", 12, CCB.C_CYAN)
	if sel_sup_jifa:
		if not sel_jifa_name.is_empty():
			game._label(dcol, "当前已激发：%s（有效等级 %d）" % [sel_jifa_name, sel_eff], 12, CCB.C_LTGREEN, true)
		else:
			game._label(dcol, "当前未激发特殊武功（本项练至 10 级后可向陈馆主/周教头请教入门绝学）。", 11, CCB.C_DKGRAY, true)
		for art: Dictionary in avail_arts:
			var aid: String = str(art.get("id", ""))
			var aname: String = str(art.get("name", ""))
			var alv: int = int(art.get("level", 1))
			var is_en: bool = bool(art.get("enabled", false))
			var jcb := func():
				var res: Dictionary = game.net_session.dispatch_action(world, {
					"type": "jifa",
					"skill_id": sel_id,
					"special_art_id": "" if is_en else aid,
				})
				game._note(str(res.get("message", "")))
				game._refresh()
				game._reopen_overlay("skills")
			var jtxt := "卸下激发：%s (Lv.%d)" % [aname, alv] if is_en else "激发绝学：%s (Lv.%d)" % [aname, alv]
			game._button(dcol, jtxt, jcb, not is_en)
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


static func exert_panel(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var st: Dictionary = world.character_status()
	var neili: int = int(st.get("neili", 0))
	var max_neili: int = int(st.get("max_neili", 0))
	var bonus_cap: int = int(st.get("neili_bonus_cap", 0))
	var jiali: int = int(st.get("jiali", 0))
	var warm_on: bool = bool(st.get("exert_warmth", false))

	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 6, 1))
	contents.add_child(banner)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 3)
	banner.add_child(bcol)
	game._label(bcol, "丹田真气内力: %d / %d（打坐凝炼上限 +%d）  |  出招加力: %d  |  御寒真气: %s" % [
		neili, max_neili, bonus_cap, jiali, "开启中" if warm_on else "未开启"
	], 13, CCB.C_LTCYAN)
	game._label(bcol, "基本内功: %d 级  |  体温: %s  |  耐力: %d%%  |  疼痛: %s" % [
		int(world.skill_level("force")), str(st.get("temp_text", "舒适")),
		int(round(float(st.get("stamina", 10000)) / 100.0)), str(st.get("pain_text", "无痛"))
	], 11, CCB.C_LTGRAY)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	contents.add_child(col)

	var dz_cb := func():
		game._close_overlay()
		game._start_dazuo()
	var b1: Button = game._button(col, "a - 盘膝打坐吐纳 (dazuo)：运周天回复内力；内力满时可凝炼提升内力上限！", dz_cb, max_neili > 0)
	b1.alignment = HORIZONTAL_ALIGNMENT_LEFT
	game.register_overlay_hotkey("a", dz_cb)

	var ex_specs := [
		["b", "recover", "运功调息 (exert recover)：耗 15 内力 → 瞬间回复大量耐力并减疲劳", neili >= 15],
		["c", "heal", "运功疗伤 (exert heal)：耗 25 内力 → 导引真气治疗全身六部位气血并止痛", neili >= 25],
		["d", "warmth", "运功御寒 (exert warmth)：%s纯阳真气护体，抵御雨雪低温" % ("关闭" if warm_on else "开启"), max_neili > 0],
		["e", "jiali_cycle", "调节出招加力 (jiali)：当前 %d → 点击切换 (0 / 5 / 15 / 30)" % jiali, max_neili > 0],
	]
	for spec: Array in ex_specs:
		var k: String = str(spec[0])
		var kind: String = str(spec[1])
		var lbl: String = "%s - %s" % [k, str(spec[2])]
		var ok: bool = bool(spec[3])
		var cb := func():
			var res: Dictionary = game.net_session.dispatch_action(world, {"type": "exert", "kind": kind})
			game._note(str(res.get("message", "")))
			game._play_sfx("meditate")
			game._refresh()
			game._reopen_overlay("exert")
		var btn: Button = game._button(col, lbl, cb, ok)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not ok:
			btn.add_theme_color_override("font_color", CCB.C_DKGRAY)
		game.register_overlay_hotkey(k, cb)

	if max_neili <= 0:
		game._label(col, "提示：你尚未习得「基本内功」，请先前往西市大街南「扬威武馆」向陈馆主请教入门！", 12, CCB.C_YELLOW, true)


static func learn_panel(game: Control, contents: VBoxContainer, npc_pos: Vector2i) -> void:
	var world: Object = game.world
	var teach_list: Array = world.npc_teach_list(npc_pos)
	var sp_list: Array = world.npc_special_teach_list(npc_pos)
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
	game._label(bcol, "饱食: %d kcal  |  读书写字加成: +%d%%  |  按对应字母向师傅请教入门或精进" % [
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

	if teach_list.is_empty() and sp_list.is_empty():
		game._label(list_box, "此位人物目前暂无可传授的技艺。", 12, CCB.C_DKGRAY)
		return

	var key_idx := 0
	if not teach_list.is_empty():
		game._label(list_box, "[ 基础技艺传授 ]", 12, CCB.C_CYAN)
		for row: Dictionary in teach_list:
			var sid: String = str(row.get("id", ""))
			var sname: String = str(row.get("name", ""))
			var cur_lv: int = int(row.get("current_level", 0))
			var max_lv: int = int(row.get("max_teach_level", 30))
			var pot_c: int = int(row.get("pot_cost", 10))
			var coin_c: int = int(row.get("coin_cost", 3))
			var can_l: bool = bool(row.get("can_learn", false))
			var reason: String = str(row.get("reason", ""))
			var letter := CCB.letter_key(key_idx)
			key_idx += 1
			var lv_tag := "未学 -> 入门1级" if cur_lv == 0 else ("Lv.%d/%d" % [cur_lv, max_lv])
			var tail := " [潜能-%d, %d文]" % [pot_c, coin_c] if can_l else (" [%s]" % reason)
			var txt := "%s - %s (%s)%s" % [letter, sname, lv_tag, tail]
			var cb := func():
				var res: Dictionary = game.net_session.dispatch_action(world, {
					"type": "learn_from_npc",
					"target": npc_pos,
					"skill_id": sid,
				})
				game._note(str(res.get("message", "")))
				game._refresh()
				game._reopen_overlay("learn", npc_pos)
			var btn: Button = game._button(list_box, txt, cb, can_l)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if not can_l:
				btn.add_theme_color_override("font_color", CCB.C_DKGRAY)
			if letter != "-":
				game.register_overlay_hotkey(letter, cb)

	if not sp_list.is_empty():
		list_box.add_child(CCB.divider())
		game._label(list_box, "[ 沧灵城入门绝学（对应基础满 10 级可学，学会后在 [J] 面板激发） ]", 12, Color("ffbe4f"))
		for row: Dictionary in sp_list:
			var aid: String = str(row.get("id", ""))
			var aname: String = str(row.get("name", ""))
			var bname: String = str(row.get("base_skill_name", ""))
			var cur_lv: int = int(row.get("current_level", 0))
			var max_lv: int = int(row.get("max_teach_level", 30))
			var pot_c: int = int(row.get("pot_cost", 16))
			var coin_c: int = int(row.get("coin_cost", 6))
			var can_l: bool = bool(row.get("can_learn", false))
			var reason: String = str(row.get("reason", ""))
			var letter := CCB.letter_key(key_idx)
			key_idx += 1
			var lv_tag := "未学 -> 入门1级" if cur_lv == 0 else ("Lv.%d/%d" % [cur_lv, max_lv])
			var tail := " [潜能-%d, %d文]" % [pot_c, coin_c] if can_l else (" [%s]" % reason)
			var txt := "%s - ★%s [激发:%s] (%s)%s" % [letter, aname, bname, lv_tag, tail]
			var cb := func():
				var res: Dictionary = game.net_session.dispatch_action(world, {
					"type": "learn_special",
					"target": npc_pos,
					"art_id": aid,
				})
				game._note(str(res.get("message", "")))
				game._refresh()
				game._reopen_overlay("learn", npc_pos)
			var btn: Button = game._button(list_box, txt, cb, can_l)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if not can_l:
				btn.add_theme_color_override("font_color", CCB.C_DKGRAY)
			if letter != "-":
				game.register_overlay_hotkey(letter, cb)


static func multiplayer_panel(game: Control, contents: VBoxContainer) -> void:
	var ns: Object = game.net_session
	var world: Object = game.world
	var info: Dictionary = ns.status_dict(world)
	var mode: String = str(info.get("mode", "OFFLINE"))
	var peers: Array = world.list_remote_players()

	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 6, 1))
	contents.add_child(banner)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 3)
	banner.add_child(bcol)
	game._label(bcol, "联机状态: %s  |  本机节点ID: %d  |  在线同道: %d 人" % [
		mode, int(info.get("local_peer_id", 1)), int(info.get("remote_count", 0))
	], 13, CCB.C_LTCYAN if mode != "OFFLINE" else CCB.C_YELLOW)
	game._label(bcol, "架构说明：所有劳作/制作/请教/切磋动作均经 NetSession.dispatch_action() 统一派发，且 28 处实体工位不设占用锁。", 11, CCB.C_LTGRAY, true)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	contents.add_child(name_row)
	game._label(name_row, "侠客名号:", 12, CCB.C_WHITE)
	var name_edit := LineEdit.new()
	name_edit.text = str(world.get_player_name())
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	game._button(name_row, "应用名号", func():
		world.set_player_name(name_edit.text)
		game._note("侠客名号已设为：%s" % str(world.get_player_name()))
		game._reopen_overlay("multiplayer"), true)

	var addr_row := HBoxContainer.new()
	addr_row.add_theme_constant_override("separation", 6)
	contents.add_child(addr_row)
	game._label(addr_row, "主机地址:", 12, CCB.C_WHITE)
	var host_edit := LineEdit.new()
	host_edit.text = str(info.get("host_address", "127.0.0.1"))
	host_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr_row.add_child(host_edit)
	var port_edit := LineEdit.new()
	port_edit.text = str(info.get("port", 24680))
	port_edit.custom_minimum_size.x = 74
	addr_row.add_child(port_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	contents.add_child(btn_row)
	game._button(btn_row, "创建 ENet 联机房 (HOST)", func():
		var p := int(port_edit.text) if port_edit.text.is_valid_int() else 27015
		game._note(ns.host_from_ui(world, p))
		game._reopen_overlay("multiplayer"), mode == "OFFLINE")
	game._button(btn_row, "加入 ENet 联机房 (CLIENT)", func():
		var p := int(port_edit.text) if port_edit.text.is_valid_int() else 27015
		game._note(ns.join_from_ui(world, host_edit.text, p))
		game._reopen_overlay("multiplayer"))
	game._button(btn_row, "切回单机 (OFFLINE)", func():
		game._note(ns.disconnect_from_ui(world))
		game._reopen_overlay("multiplayer"))

	# Live Co-op Chat box
	contents.add_child(CCB.divider())
	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	contents.add_child(chat_row)
	var chat_edit := LineEdit.new()
	chat_edit.placeholder_text = "输入联机消息按回车发送..."
	chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CCB.style_line_edit(chat_edit)
	chat_row.add_child(chat_edit)
	var send_cb := func():
		if not chat_edit.text.strip_edges().is_empty():
			ns.send_chat(world, chat_edit.text)
			chat_edit.text = ""
			game._reopen_overlay("multiplayer")
	game._button(chat_row, "发送", send_cb, true)
	chat_edit.text_submitted.connect(func(_t: String): send_cb.call())

	if not ns.chat_log.is_empty():
		var cbox := VBoxContainer.new()
		cbox.add_theme_constant_override("separation", 2)
		contents.add_child(cbox)
		for i in range(mini(5, ns.chat_log.size())):
			var cm: Dictionary = ns.chat_log[i]
			game._label(cbox, "[%s] %s" % [str(cm.get("name", "")), str(cm.get("text", ""))], 11, CCB.C_LTCYAN)

	var peer_lbl: String = "[ 当前同步的同道玩家 (%d) ]" % peers.size()
	game._label(contents, peer_lbl, 12, CCB.C_CYAN)
	if peers.is_empty():
		game._label(contents, "  (暂无在线同道；单机模式下可正常体验全部玩法。)", 11, CCB.C_DKGRAY)
	else:
		for p: Dictionary in peers:
			var ppos: Vector2i = p.get("pos", Vector2i.ZERO)
			game._label(contents, "  · %s (ID:%d) @ (%d,%d) Z:%d [%s]" % [
				str(p.get("name", "同道")), int(p.get("peer_id", 0)), ppos.x, ppos.y, int(p.get("floor", 0)), str(p.get("rank_label", ""))
			], 12, CCB.C_LTGREEN)
