extends SceneTree

# Comprehensive End-to-End Verification for Pure Vanilla CCB UI, Pixel Minimap,
# Authentic Monster Death Drops + Harvest Tables, Modular Menus, and Cangming Zero-Regression.

const ART_DIR := "C:/Users/ASUS/.gemini/antigravity/brain/62b5805c-1bc3-48d9-80e9-3448fcc306c0"
var failures: Array[String] = []
var checks := 0


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)
		print("[FAIL] ", msg)
	else:
		print("[PASS] ", msg)


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [ART_DIR, name])


func _collect_labels_text(node: Node) -> String:
	var acc := ""
	if node is Label:
		acc += (node as Label).text + "\n"
	elif node is Button:
		acc += (node as Button).text + "\n"
	elif node is RichTextLabel:
		acc += (node as RichTextLabel).text + "\n"
	for c in node.get_children():
		acc += _collect_labels_text(c)
	return acc


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var win := root
	win.size = Vector2i(1440, 860)
	var scene: PackedScene = load("res://main.tscn")
	var game: Control = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame

	# 1. PURE VANILLA MAIN MENU (zh_CN.title + anchored popup submenu)
	_check(game.in_main_menu and game.main_menu.visible, "Main menu opens on startup")
	await _snap("verify_v3_main_menu")

	# 2. CHARACTER CREATOR (0px CCB style + PaperDollPreview)
	game.main_menu.char_creator.open_for_world(game.main_menu.get_active_world())
	game.main_menu.char_creator.active_tab = "profession"
	game.main_menu.char_creator.profession_id = "police_officer"
	game.main_menu.char_creator._rebuild_body()
	await _snap("verify_v3_char_creator")
	game.main_menu.char_creator.visible = false

	# 3. ENTER CATACLYSM CCB WORLD
	var wcfg := {"name": "TestCCB", "pack": "cataclysm", "seed": 20260415, "city_size": 8, "city_spacing": 4, "monster_rate": 1.0}
	var ccfg: Dictionary = game.main_menu.char_creator.build_default_evacuee_config()
	ccfg["profession_id"] = "survivor"
	game.enter_ccb_game(wcfg, ccfg)
	await process_frame
	await process_frame

	var world: Object = game.world
	var db: Dictionary = world.ccb_db_stats()
	_check(int(db.get("monsterdrop_groups", 0)) >= 1500, "Loaded >=1500 vanilla monsterdrop item_groups (%d)" % int(db.get("monsterdrop_groups", 0)))
	_check(int(db.get("harvests", 0)) >= 200, "Loaded >=200 vanilla harvest tables (%d)" % int(db.get("harvests", 0)))
	_check(game.ccb_sidebar.visible and not game.sidebar.visible, "Pure vanilla CCB sidebar active (Cangming sidebar hidden)")
	_check(game.ccb_sidebar.pixel_minimap.visible, "Real local Pixel Minimap visible in CCB sidebar")
	var pm: Dictionary = world.ccb_pixel_minimap_data(36)
	_check(int(pm.get("width", 0)) == 73 and (pm.get("rgba", PackedByteArray()) as PackedByteArray).size() == 73 * 73 * 4, "Pixel minimap renders 73x73 RGBA grid in C++")
	await _snap("verify_v3_shelter")

	# 4. AUTHENTIC VANILLA ZOMBIE DEATH DROPS (mon_zombie + mon_zombie_cop + mon_zombie_fireman) & HARVEST!
	var fake_banned := ["iv_mutagen", "iv_mutagen_beast", "purifier", "prussian_blue", "iodine"]
	var saw_filthy := false
	var saw_fake := false
	var total_z_drops := 0
	world.ccb_give_item("katana", 1)
	world.ccb_wield("katana")

	for trial in range(5):
		var sp: Vector2i = world.pos + Vector2i(1, 0)
		world.ccb_debug_spawn_monster("mon_zombie", sp)
		var killed := false
		for _hit in range(18):
			var r: Dictionary = world.attack_monster_at(sp)
			if bool(r.get("killed", false)):
				killed = true
				var drops: Array = r.get("drop_items", [])
				if trial == 0:
					print("  mon_zombie #1 drops (%d): " % drops.size(), drops.map(func(x): return str(x.get("name", ""))))
				total_z_drops += drops.size()
				for d: Dictionary in drops:
					var iid := str(d.get("id", ""))
					if iid in fake_banned:
						saw_fake = true
					if bool(d.get("filthy", false)):
						saw_filthy = true
				break
		_check(killed, "Killed spawned mon_zombie #%d" % (trial + 1))

	_check(total_z_drops >= 8, "Normal zombies dropped authentic multi-item clothing + pocket gear (%d items across 5 kills)" % total_z_drops)
	_check(saw_filthy, "Zombie clothing drops carry authentic FILTHY flag")
	_check(not saw_fake, "ZERO fake mutagen/purifier/iodine drops on normal mon_zombie!")

	# Test Police Zombie authentic cop death drops!
	var cop_pos: Vector2i = world.pos + Vector2i(-1, 0)
	world.ccb_debug_spawn_monster("mon_zombie_cop", cop_pos)
	var cop_drops: Array = []
	for _hit in range(24):
		var r: Dictionary = world.attack_monster_at(cop_pos)
		if bool(r.get("killed", false)):
			cop_drops = r.get("drop_items", [])
			break
	print("  mon_zombie_cop drops (%d): " % cop_drops.size(), cop_drops.map(func(x): return str(x.get("name", ""))))
	_check(cop_drops.size() >= 3, "mon_zombie_cop dropped authentic police uniform & gear (%d items)" % cop_drops.size())

	# Test FILTHY clothing wear refusal + wash!
	var ground_items: Array = world.ccb_items_at(world.pos + Vector2i(1, 0))
	var filthy_id := ""
	for gi: Dictionary in ground_items:
		if bool(gi.get("filthy", false)):
			filthy_id = str(gi.get("id", ""))
			break
	if not filthy_id.is_empty():
		world.ccb_take_item(world.pos + Vector2i(1, 0), filthy_id)
		var refuse_msg: String = world.ccb_wear(filthy_id)
		_check("脏污" in refuse_msg, "Vanilla refuses wearing FILTHY clothing: " + refuse_msg)
		var wash_msg: String = world.ccb_wash_item(filthy_id)
		_check("清洗干净" in wash_msg, "Washing removes FILTHY status: " + wash_msg)

	# Test Harvest table on corpse butcher!
	var bmsg: String = world.ccb_butcher_at(cop_pos)
	print("  butcher msg: ", bmsg)
	_check("解剖了" in bmsg and ("肉" in bmsg or "骨" in bmsg or "筋" in bmsg), "Butchering uses vanilla harvest.json yields")

	# 5. VERIFY EVERY SINGLE MODULAR CCB MENU & ZERO CANGMING LEAKAGE!
	# [Enter] 7-Category Action Menu
	game._show_overlay("action_menu")
	await _snap("verify_v3_action_menu")
	var act_txt := _collect_labels_text(game.overlay)
	_check(not ("江湖" in act_txt) and not ("内功" in act_txt) and not ("打坐" in act_txt), "[Enter] Action Menu has ZERO Cangming/Wuxia leakage!")
	_check("查看 (Look)" in act_txt and "物品栏 (Inventory)" in act_txt, "[Enter] Action Menu shows authentic 7 CCB categories")

	# [i] Dual-Pane Inventory
	game._show_overlay("inventory")
	await _snap("verify_v3_inventory")
	var inv_txt := _collect_labels_text(game.overlay)
	_check("手持武器" in inv_txt and "已穿戴" in inv_txt and not ("原版全库" in inv_txt), "[i] Dual-pane inventory has Wielded/Worn/Bag & NO cheat catalog tab")

	# [g] Multi-Select Pickup on zombie drop pile
	game.ccb_pickup_sel.clear()
	game.ccb_pickup_sel[0] = true
	game._show_overlay("pickup", world.pos + Vector2i(1, 0))
	await _snap("verify_v3_pickup")
	var pk_txt := _collect_labels_text(game.overlay)
	_check("[+]" in pk_txt and "负重:" in pk_txt and "容积:" in pk_txt, "[g] Multi-select pickup shows [+], weight & volume bar")

	# [@] 5-Pane Character Display
	game._show_overlay("character")
	await _snap("verify_v3_character")
	var ch_txt := _collect_labels_text(game.overlay)
	_check("ENCUMBRANCE" in ch_txt and "SKILLS (28)" in ch_txt, "[@] Character display shows Encumbrance & all 28 skills")

	# [&] Dual-Pane Crafting
	game._show_overlay("craft")
	await _snap("verify_v3_craft")

	# [m] Fog-of-War Interactive Overmap
	var pomt: Vector2i = world.ccb_world_to_omt(world.pos)
	world.ccb_set_overmap_note(pomt + Vector2i(1, 0), "安全屋物资点")
	game.ccb_om_cursor_init = false
	game._show_overlay("map")
	await _snap("verify_v3_overmap")
	var om_slice: Dictionary = world.ccb_overmap_slice(pomt, 14)
	var seen_arr: Array = om_slice.get("seen", [])
	var has_unseen := false
	var has_seen := false
	for row in seen_arr:
		for v in row:
			if bool(v): has_seen = true
			else: has_unseen = true
	_check(has_seen and has_unseen, "[m] Overmap has real fog-of-war (both seen near player and unseen distant OMTs)")

	# [+] Armor Layering & [/] Advanced Inventory & [}] Sidebar Manager
	game._show_overlay("armor_layers")
	await _snap("verify_v3_armor_layers")
	game._show_overlay("advanced_inv")
	await _snap("verify_v3_adv_inv")
	game._show_overlay("sidebar_mgr")
	await _snap("verify_v3_sidebar_mgr")
	game._close_overlay()

	# [x] Look-Around Floating Inspector Box
	game.look_at = world.pos + Vector2i(1, 0)
	game._refresh()
	await _snap("verify_v3_look_around")
	_check(game.ccb_look_panel.visible and "地面物品" in game.ccb_look_lbl.text, "[x] Look-Around displays floating tile/item/corpse inspector box")
	game.look_at = game.NONE

	# 6. CANGMING CORE PACK ZERO-REGRESSION!
	game.enter_pack("cangming", 20260415, "jianghu", "游侠")
	await process_frame
	await process_frame
	_check(game.sidebar.visible and not game.ccb_sidebar.visible, "Cangming restores Cangming sidebar cleanly")
	_check(world.npc_list().size() == 13 and world.list_workstations().size() == 28, "Cangming keeps 13 NPCs & 28 workstations untouched")
	await _snap("verify_v3_cangming_ok")

	print("==============================================")
	if failures.is_empty():
		print("ALL_V3_CHECKS_PASSED (%d/%d, 0 failures)" % [checks, checks])
		quit(0)
	else:
		print("V3_VERIFICATION_FAILED (%d failures out of %d):" % [failures.size(), checks])
		for f in failures:
			print("  - ", f)
		quit(1)
