extends RefCounted

# [@] Authentic Multi-Pane Character Display (Cataclysm-Cleanwater-Bomb/src/player_display.cpp)

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")


static func build(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var ccb: Dictionary = world.ccb_status()
	var st: Dictionary = world.character_status()

	var hstr := "姓名: %s  |  性别: %s  |  年龄: %d  |  职业: %s  |  剧情: %s  |  击杀: %d" % [
		str(world.get_player_name()),
		"男" if str(ccb.get("gender", "male")) == "male" else "女",
		int(ccb.get("age", 25)),
		str(ccb.get("profession_name", "无业")),
		str(ccb.get("scenario_name", "避难所")),
		int(world.get_kills()),
	]
	VUI.mk_lbl(contents, hstr, 13, VUI.C_YELLOW)
	contents.add_child(VUI.divider())

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(grid)

	# COL 1: STATS + SPEED + EFFECTS/RADIATION/MUTAGEN
	var c1 := VBoxContainer.new()
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c1.size_flags_stretch_ratio = 0.95
	c1.add_theme_constant_override("separation", 6)
	grid.add_child(c1)

	var p_stats := PanelContainer.new()
	p_stats.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 5, 1))
	c1.add_child(p_stats)
	var sb_col := VBoxContainer.new(); sb_col.add_theme_constant_override("separation", 2); p_stats.add_child(sb_col)
	VUI.mk_lbl(sb_col, "[ 属性 STATS ]", 12, VUI.C_YELLOW)
	VUI.mk_lbl(sb_col, "力量 STR: %2d   (基础 %d)" % [int(ccb.get("eff_str", 8)), int(st.get("str", 8))], 12, VUI.C_WHITE)
	VUI.mk_lbl(sb_col, "敏捷 DEX: %2d   (基础 %d)" % [int(ccb.get("eff_dex", 8)), int(st.get("dex", 8))], 12, VUI.C_WHITE)
	VUI.mk_lbl(sb_col, "智力 INT: %2d   (基础 %d)" % [int(ccb.get("eff_int", 8)), int(st.get("int", 8))], 12, VUI.C_WHITE)
	VUI.mk_lbl(sb_col, "感知 PER: %2d   (基础 %d)" % [int(ccb.get("eff_per", 8)), int(st.get("per", 8))], 12, VUI.C_WHITE)

	var p_spd := PanelContainer.new()
	p_spd.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 5, 1))
	c1.add_child(p_spd)
	var sp_col := VBoxContainer.new(); sp_col.add_theme_constant_override("separation", 2); p_spd.add_child(sp_col)
	VUI.mk_lbl(sp_col, "[ 速度 SPEED ]", 12, VUI.C_YELLOW)
	var pain := int(st.get("pain", 0))
	var spd := maxi(35, 100 + int(ccb.get("speed_mod", 0)) - pain / 2)
	VUI.mk_lbl(sp_col, "基础速度: 100", 12, VUI.C_LTGRAY)
	VUI.mk_lbl(sp_col, "变异修正: %+d   疼痛惩罚: -%d" % [int(ccb.get("speed_mod", 0)), pain / 2], 12, VUI.C_LTGRAY)
	VUI.mk_lbl(sp_col, "当前速度: %d   专注: %d" % [spd, int(st.get("focus", 100))], 12, VUI.C_LTCYAN)

	var p_eff := PanelContainer.new()
	p_eff.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p_eff.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 5, 1))
	c1.add_child(p_eff)
	var ef_col := VBoxContainer.new(); ef_col.add_theme_constant_override("separation", 2); p_eff.add_child(ef_col)
	VUI.mk_lbl(ef_col, "[ 效果 / 辐射 / 诱变 EFFECTS ]", 12, VUI.C_YELLOW)
	var rad := int(ccb.get("rad", 0))
	VUI.mk_lbl(ef_col, "辐射剂量: %d mSv  (徽章:%s)" % [rad, str(ccb.get("rad_badge_color", "绿"))], 12,
		VUI.C_LTGREEN if rad < 25 else (VUI.C_YELLOW if rad < 100 else VUI.C_LTRED))
	if int(ccb.get("iodine_min", 0)) > 0:
		VUI.mk_lbl(ef_col, "碘片防护: 剩余 %d 分" % int(ccb.get("iodine_min", 0)), 11, VUI.C_LTCYAN)
	if int(ccb.get("pblue_min", 0)) > 0:
		VUI.mk_lbl(ef_col, "普鲁士蓝排毒: 剩余 %d 分" % int(ccb.get("pblue_min", 0)), 11, VUI.C_LTCYAN)
	var cat_v := int(ccb.get("mutagen_catalyst", 0))
	VUI.mk_lbl(ef_col, "诱变催化剂: %d / 2500 %s" % [cat_v, "[异变中!]" if bool(ccb.get("changing", false)) else ""], 12,
		VUI.C_PINK if cat_v >= 450 else VUI.C_LTGRAY)
	for w: Dictionary in ccb.get("wounds", []):
		var wt := "感染!" if bool(w.get("infected", false)) else ("深度咬伤" if bool(w.get("bite", false)) else "流血")
		VUI.mk_lbl(ef_col, "伤势: %s - %s" % [str(w.get("part", "")), wt], 12, VUI.C_LTRED)
	var vits: Dictionary = ccb.get("vitamins", {})
	for vk: String in vits:
		if vk != "mutagen" and int(vits[vk]) > 0:
			VUI.mk_lbl(ef_col, "引物 %s: %d" % [vk, int(vits[vk])], 11, VUI.C_MAGENTA)

	# COL 2: ENCUMBRANCE AND WARMTH + TRAITS
	var c2 := VBoxContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c2.size_flags_stretch_ratio = 1.05
	c2.add_theme_constant_override("separation", 6)
	grid.add_child(c2)

	var p_enc := PanelContainer.new()
	p_enc.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 5, 1))
	c2.add_child(p_enc)
	var enc_col := VBoxContainer.new(); enc_col.add_theme_constant_override("separation", 2); p_enc.add_child(enc_col)
	VUI.mk_lbl(enc_col, "[ 累赘与保暖 ENCUMBRANCE & WARMTH ]", 12, VUI.C_YELLOW)
	for bp: Dictionary in ccb.get("body_parts", []):
		var tot_e := int(bp.get("total_encumbrance", 0))
		var col := VUI.C_LTGRAY if tot_e < 15 else (VUI.C_YELLOW if tot_e < 35 else VUI.C_LTRED)
		VUI.mk_lbl(enc_col, "%-4s  %2d + %-2d   保暖(%3d)  甲 %d/%d/%d" % [
			str(bp.get("name", "")), int(bp.get("encumbrance", 0)), int(bp.get("layer_penalty", 0)),
			int(bp.get("warmth", 0)), int(bp.get("armor_bash", 0)), int(bp.get("armor_cut", 0)), int(bp.get("armor_stab", 0))
		], 11, col)

	var p_tr := PanelContainer.new()
	p_tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p_tr.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 5, 1))
	c2.add_child(p_tr)
	var tsc := ScrollContainer.new(); tsc.size_flags_vertical = Control.SIZE_EXPAND_FILL; p_tr.add_child(tsc)
	var tr_col := VBoxContainer.new(); tr_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tr_col.add_theme_constant_override("separation", 2); tsc.add_child(tr_col)
	var muts: Array = ccb.get("mutations", [])
	VUI.mk_lbl(tr_col, "[ 特性与变异 TRAITS (%d) ]" % muts.size(), 12, VUI.C_YELLOW)
	if muts.is_empty():
		VUI.mk_lbl(tr_col, "(无先天特性或变异)", 11, VUI.C_DKGRAY)
	for m: Dictionary in muts:
		var pts := int(m.get("points", 0))
		var mcol := VUI.C_MAGENTA if bool(m.get("threshold", false)) else (VUI.C_LTGREEN if pts > 0 else (VUI.C_LTRED if pts < 0 else VUI.C_LTCYAN))
		VUI.mk_lbl(tr_col, "%s: %s" % [str(m.get("name", "")), str(m.get("desc", "")).left(42)], 11, mcol, true)

	# COL 3: ALL 28 VANILLA SKILLS
	var p_sk := PanelContainer.new()
	p_sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_sk.size_flags_stretch_ratio = 1.0
	p_sk.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 5, 1))
	grid.add_child(p_sk)
	var sk_sc := ScrollContainer.new(); sk_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; p_sk.add_child(sk_sc)
	var sk_col := VBoxContainer.new(); sk_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sk_col.add_theme_constant_override("separation", 1); sk_sc.add_child(sk_col)
	var all_sk: Array = ccb.get("all_skills", [])
	VUI.mk_lbl(sk_col, "[ 技能 SKILLS (%d) ]" % all_sk.size(), 12, VUI.C_YELLOW)
	for sk: Dictionary in all_sk:
		var lv := int(sk.get("level", 0))
		VUI.mk_lbl(sk_col, "%-12s  Lv.%-2d" % [str(sk.get("name", "")), lv], 12, VUI.C_LTGREEN if lv > 0 else VUI.C_DKGRAY)
