extends RefCounted

# Shared item-info formatter and lettered selector helper for scripts/ccb/*.gd

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")
const LETTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"


static func fmt_weight(g: int) -> String:
	return "%.2f kg" % (float(g) / 1000.0)


static func fmt_vol(ml: int) -> String:
	return "%.2f L" % (float(ml) / 1000.0)


static func render_item_info(box: VBoxContainer, it: Dictionary, is_worn := false, is_wielded := false) -> void:
	for c in box.get_children():
		c.queue_free()
	if it.is_empty():
		VUI.mk_lbl(box, "左侧按字母键或点击选择一件物品查看详细参数。", 12, VUI.C_DKGRAY, true)
		return
	var nm := str(it.get("name", it.get("id", "")))
	var tag := " [手持]" if is_wielded else (" [已穿戴]" if is_worn else "")
	VUI.mk_lbl(box, nm + tag, 14, VUI.C_YELLOW, true)
	VUI.mk_lbl(box, "ID: %s  |  类型: %s  |  数量: ×%d" % [
		str(it.get("id", "")), str(it.get("subtype", "")), int(it.get("count", 1))
	], 11, VUI.C_DKGRAY)
	if bool(it.get("filthy", false)):
		VUI.mk_lbl(box, "⚠ 标志: FILTHY (脏污 — 原版规则下需清洗后才可穿戴)", 12, VUI.C_LTRED, true)
	var dmg := int(it.get("damage", 0))
	if dmg > 0:
		const D_NAMES := ["完好", "磨损 (|)", "受损 (\\)", "破损 (/)", "残破 (X)"]
		VUI.mk_lbl(box, "耐久状态: %s" % D_NAMES[clampi(dmg, 0, 4)], 12, VUI.C_BROWN)

	box.add_child(VUI.divider())
	VUI.mk_lbl(box, "重量: %s    体积: %s" % [
		fmt_weight(int(it.get("weight_g", 0))), fmt_vol(int(it.get("vol_ml", 0)))
	], 12, VUI.C_WHITE)

	var bash := int(it.get("bash", 0))
	var cut := int(it.get("cut", 0))
	var stab := int(it.get("stab", 0))
	var th := int(it.get("to_hit", 0))
	if bash > 0 or cut > 0 or stab > 0:
		VUI.mk_lbl(box, "近战伤害: 钝击 %d / 斩击 %d / 穿刺 %d   命中修正: %+d" % [bash, cut, stab, th], 12, VUI.C_LTCYAN)

	var ab := int(it.get("armor_bash", 0))
	var ac := int(it.get("armor_cut", 0))
	var ast := int(it.get("armor_stab", 0))
	var cov := int(it.get("coverage", 0))
	var enc := int(it.get("encumbrance", 0))
	var wrm := int(it.get("warmth", 0))
	var stor := int(it.get("storage_ml", 0))
	if str(it.get("subtype", "")) == "ARMOR" or ab > 0 or ac > 0 or stor > 0:
		VUI.mk_lbl(box, "护甲防护: 钝%d / 斩%d / 刺%d   覆盖率: %d%%" % [ab, ac, ast, cov], 12, VUI.C_LTGREEN)
		VUI.mk_lbl(box, "累赘: %d   保暖: %d   口袋容量: %s" % [enc, wrm, fmt_vol(stor)], 12, VUI.C_LTGRAY)

	var kcal := int(it.get("kcal", 0))
	var quench := int(it.get("quench", 0))
	var fun := int(it.get("fun", 0))
	if str(it.get("subtype", "")) == "COMESTIBLE" or kcal != 0 or quench != 0:
		VUI.mk_lbl(box, "营养: 热量 %d kcal   解渴 %+d   愉悦 %+d" % [kcal, quench, fun], 12, VUI.C_LTGREEN)

	var flags: Array = it.get("flags", [])
	if not flags.is_empty():
		VUI.mk_lbl(box, "标志: " + ", ".join(PackedStringArray(flags)).left(120), 11, VUI.C_CYAN, true)

	box.add_child(VUI.divider())
	var desc := str(it.get("desc", ""))
	if not desc.is_empty():
		VUI.mk_lbl(box, desc, 12, VUI.C_LTGRAY, true)


static func build_letter_selector(game: Control, contents: VBoxContainer, empty_msg: String, rows: Array) -> void:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	sc.add_child(box)
	if rows.is_empty():
		VUI.mk_lbl(box, empty_msg, 13, VUI.C_DKGRAY)
		return
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		var ltr := LETTERS.substr(i, 1) if i < LETTERS.length() else "-"
		var cb: Callable = r["cb"]
		if i < LETTERS.length():
			game.overlay_hotkeys[ltr] = cb
		var b := Button.new()
		b.text = " %s - %s" % [ltr, str(r["label"])]
		b.focus_mode = Control.FOCUS_NONE
		VUI.style_row_button(b, false, r.get("color", VUI.C_WHITE))
		b.pressed.connect(cb)
		box.add_child(b)
