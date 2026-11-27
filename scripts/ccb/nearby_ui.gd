extends RefCounted

# [V] Nearby Items, Corpses & Hostile Monsters + [x]/[;] Look-Around Floating Inspection Box

const VUI = preload("res://scripts/ccb_vanilla_theme.gd")


static func list_nearby(game: Control, contents: VBoxContainer) -> void:
	var world: Object = game.world
	var mons: Array = world.monsters_in_rect(Rect2i(world.pos - Vector2i(20, 20), Vector2i(41, 41)))

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(split)

	var mp := PanelContainer.new()
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 6, 1))
	split.add_child(mp)
	var msc := ScrollContainer.new(); msc.size_flags_vertical = Control.SIZE_EXPAND_FILL; mp.add_child(msc)
	var mbox := VBoxContainer.new(); mbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mbox.add_theme_constant_override("separation", 2); msc.add_child(mbox)
	VUI.mk_lbl(mbox, "[ 周边怪物 (%d) ]" % mons.size(), 13, VUI.C_LTRED)
	if mons.is_empty():
		VUI.mk_lbl(mbox, "视野内暂无敌对目标。", 12, VUI.C_LTGREEN)
	for m: Dictionary in mons:
		var mp2: Vector2i = m.get("pos", world.pos)
		var dist := maxi(abs(mp2.x - world.pos.x), abs(mp2.y - world.pos.y))
		VUI.mk_lbl(mbox, "  %s  HP %d/%d  距离:%d %s" % [
			str(m.get("name", "")), int(m.get("hp", 0)), int(m.get("max_hp", 0)), dist,
			"[警觉!]" if bool(m.get("alerted", false)) else ""
		], 12, VUI.C_LTRED if dist <= 4 else VUI.C_YELLOW)

	var ip := PanelContainer.new()
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip.add_theme_stylebox_override("panel", VUI.box(VUI.BG_BLACK, VUI.BORDER_DIM, 6, 6, 1))
	split.add_child(ip)
	var isc := ScrollContainer.new(); isc.size_flags_vertical = Control.SIZE_EXPAND_FILL; ip.add_child(isc)
	var ibox := VBoxContainer.new(); ibox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ibox.add_theme_constant_override("separation", 2); isc.add_child(ibox)
	VUI.mk_lbl(ibox, "[ 周边物品与尸体 (半径 8) ]", 13, VUI.C_LTCYAN)
	var found := 0
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var p: Vector2i = world.pos + Vector2i(dx, dy)
			var dist := maxi(abs(dx), abs(dy))
			for c: Dictionary in world.ccb_corpses_at(p):
				VUI.mk_lbl(ibox, "  [尸体] %s  距离:%d" % [str(c.get("name", "")), dist], 12, VUI.C_RED)
				found += 1
			for it: Dictionary in world.ccb_items_at(p):
				VUI.mk_lbl(ibox, "  %s ×%d  距离:%d" % [str(it.get("name", "")), int(it.get("count", 1)), dist], 12, VUI.C_LTGRAY)
				found += 1
				if found >= 45: break
		if found >= 45: break
	if found == 0:
		VUI.mk_lbl(ibox, "周围暂无可见物品。", 12, VUI.C_DKGRAY)
