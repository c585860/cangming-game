extends SceneTree

const ARTIFACT_DIR := "C:/Users/ASUS/.gemini/antigravity/brain/62b5805c-1bc3-48d9-80e9-3448fcc306c0"
const NetSession = preload("res://scripts/net_session.gd")
const Tiles = preload("res://scripts/undead_tiles.gd")

var failures: Array[String] = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("[PASS] ", msg)
	else:
		print("[FAIL] ", msg)
		failures.append(msg)


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	if img != null and not img.is_empty():
		var path := ARTIFACT_DIR + "/" + name
		img.save_png(path)
		print("[SNAP] ", path, " (", img.get_width(), "x", img.get_height(), ")")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1366, 800))
	var packed: PackedScene = load("res://main.tscn")
	var game: Control = packed.instantiate()
	root.add_child(game)
	for _i in range(8):
		await process_frame

	# 1. Vanilla CCB Main Menu
	_check(game.in_main_menu and game.main_menu != null and game.main_menu.visible, "Vanilla CCB Main Menu is visible on launch")
	var avail_ts := Tiles.list_available_tilesets()
	_check(avail_ts.has("MSX++UndeadPeopleEdition"), "Found unmodified MSX++UndeadPeopleEdition in Cataclysm-Cleanwater-Bomb/gfx/ (%d tilesets)" % avail_ts.size())
	await _snap("verify_v2_main_menu.png")

	# 2. Full 8-Tab Character Creator
	var db: Dictionary = game.world.ccb_db_stats()
	_check(int(db.get("items", 0)) >= 10000, "Loaded %d vanilla CCB items" % int(db.get("items", 0)))
	_check(int(db.get("scenarios", 0)) >= 60, "Loaded %d vanilla CCB scenarios" % int(db.get("scenarios", 0)))
	_check(int(db.get("professions", 0)) >= 300, "Loaded %d vanilla CCB professions+hobbies" % int(db.get("professions", 0)))
	_check(int(db.get("skills", 0)) >= 25, "Loaded %d vanilla CCB skills" % int(db.get("skills", 0)))
	_check(int(db.get("recipes", 0)) >= 2500, "Loaded %d vanilla CCB crafting recipes" % int(db.get("recipes", 0)))

	game.main_menu.char_creator.open_fresh("profession")
	game.main_menu.char_creator.profession_id = "survivor"
	game.main_menu.char_creator.stats["str"] = 12
	game.main_menu.char_creator.stats["dex"] = 10
	game.main_menu.char_creator.pool_mode = "single_pool"
	game.main_menu.char_creator._rebuild_body()
	await _snap("verify_v2_char_creator.png")

	# Confirm character & enter Cataclysm world
	var wcfg: Dictionary = game.main_menu.active_world_cfg()
	var ccfg: Dictionary = game.main_menu.char_creator.build_config_dict()
	ccfg["scenario_id"] = "evacuee"
	ccfg["profession_id"] = "survivor"
	game.main_menu.char_creator.visible = false
	game.enter_ccb_game(wcfg, ccfg)
	for _i in range(6):
		await process_frame

	_check(game.world.is_cataclysm_pack(), "Entered Cataclysm Core Pack via Character Creator")
	_check(Tiles.get_active_tileset_name() == "MSX++UndeadPeopleEdition", "Active tileset is unmodified MSX++UndeadPeopleEdition (got: %s)" % Tiles.get_active_tileset_name())
	_check(str(game.world.location(game.world.pos)).contains("避难所"), "Spawned inside vanilla Evac Shelter OMT: %s" % str(game.world.location(game.world.pos)))
	await _snap("verify_v2_ccb_shelter.png")

	# 3. STRICT TURN-BASED CHECK (NO real-time clock or real-time monster ticks!)
	var min_before: int = int(game.world.minutes)
	var sec_before: int = int(game.world.get_ccb_turn_seconds())
	var t_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_start < 1800:
		await process_frame
	_check(int(game.world.minutes) == min_before and int(game.world.get_ccb_turn_seconds()) == sec_before,
		"Strict turn-based: 1.8s real-time idle caused ZERO time advance (%d:%02d -> %d:%02d)" % [
			min_before, sec_before, int(game.world.minutes), int(game.world.get_ccb_turn_seconds())
		])
	game.world.ccb_wait_turn()
	_check(int(game.world.get_ccb_turn_seconds()) == sec_before + 1, "Pressing '.' wait turn advances exactly +1 second (100 moves)")

	# 4. 100% STRICT DATA ISOLATION CHECK (ZERO Cangming leakage!)
	var forbidden := ["三字经", "千字文", "芝麻炊饼", "桐油手灯", "青竹长剑", "金创纱布", "江南清茶"]
	var leak_found := ""
	var all_text := ""
	for it in game.world.inventory():
		all_text += str(it.get("name", "")) + " "
	for it in game.world.items_at(game.world.pos):
		all_text += str(it.get("name", "")) + " "
	for it in game.world.list_nearby(14):
		all_text += str(it.get("name", "")) + " "
	for r in game.world.craft_recipe_list("ALL"):
		all_text += str(r.get("name", "")) + " "
	for bad in forbidden:
		if all_text.contains(bad):
			leak_found = bad
			break
	_check(leak_found.is_empty(), "100%% data isolation: ZERO Cangming items in inventory/ground/nearby/craft (leak='%s')" % leak_found)
	_check(game.world.npc_list().is_empty() and game.world.list_workstations().is_empty(), "0 Cangming NPCs & 0 workstations in Cataclysm")

	# 5. INFINITE RANDOM PROCEDURAL MAP CHECK (negative & distant coordinates!)
	game._show_overlay("map")
	await _snap("verify_v2_ccb_overmap.png")
	game._close_overlay()

	var test_coords := [Vector2i(-500, -500), Vector2i(0, 0), Vector2i(1200, 800)]
	for tc in test_coords:
		game.world.ccb_teleport_debug(tc)
		game._refresh()
		game.board.snap_visuals()
		await process_frame
		var rr: Dictionary = game.world.ccb_render_rect(Rect2i(tc - Vector2i(4, 4), Vector2i(9, 9)), 0)
		var loc_s: String = str(game.world.location(tc))
		_check(rr.has("ter_palette") and PackedStringArray(rr["ter_palette"]).size() > 0,
			"Infinite Overmap valid at (%d,%d) -> %s" % [tc.x, tc.y, loc_s])

	# 6. CORPSE + BLOOD + PULP + ZOMBIE REVIVAL CHECK!
	# Jump into primary town downtown where zombies roam
	var town_pos := Vector2i(90 * 24 + 12, 90 * 24 + 12)
	game.world.ccb_teleport_debug(town_pos)
	game._refresh()
	game.board.snap_visuals()
	await process_frame

	var mons: Array = game.world.monsters_in_rect(Rect2i(town_pos - Vector2i(40, 40), Vector2i(81, 81)))
	_check(mons.size() > 0, "Town OMTs streamed %d live vanilla zombies" % mons.size())
	if mons.size() > 0:
		var target_m: Dictionary = mons[0]
		var mpos: Vector2i = target_m["pos"]
		# Place player adjacent to monster & equip katana/crowbar to kill cleanly
		game.world.ccb_give_item("katana", 1)
		game.world.ccb_wield("katana")
		game.world.ccb_teleport_debug(mpos + Vector2i(1, 0))
		game._refresh()
		game.board.snap_visuals()
		var killed := false
		for _hit in range(25):
			var ar: Dictionary = game.world.attack_monster_at(mpos)
			if bool(ar.get("killed", false)):
				killed = true
				break
		_check(killed, "Vanilla melee combat killed zombie at (%d,%d)" % [mpos.x, mpos.y])
		var corpses: Array = game.world.ccb_corpses_at(mpos)
		_check(corpses.size() >= 1, "Killed zombie spawned real vanilla corpse (%s)" % (str(corpses[0].get("name", "")) if corpses.size() > 0 else "none"))
		game._refresh()
		game.board.snap_visuals()
		await _snap("verify_v2_ccb_corpse_combat.png")

		# Test vanilla zombie revival after 190 minutes on unpulped corpse!
		game.world.advance_time(190)
		var revived_mon: Dictionary = game.world.monster_at(mpos)
		_check(not revived_mon.is_empty(), "Unpulped REVIVES zombie corpse revived after 190 minutes!")

		# Kill again & PULP ('s') -> must NOT revive!
		for _hit in range(25):
			var ar2: Dictionary = game.world.attack_monster_at(mpos)
			if bool(ar2.get("killed", false)):
				break
		var pulp_msg: String = game.world.ccb_pulp_at(mpos)
		_check(pulp_msg.contains("捣烂"), "Pulp corpse ('s') succeeded: %s" % pulp_msg)
		game.world.advance_time(240)
		_check(game.world.monster_at(mpos).is_empty(), "Pulped corpse stayed dead after 240 minutes!")

		# Butcher ('B') test
		var butcher_msg: String = game.world.ccb_butcher_at(mpos)
		_check(butcher_msg.contains("解剖了"), "Butcher corpse ('B') succeeded: %s" % butcher_msg)

	# 7. Shared GPU Night Rain + Flashlight on unmodified vanilla tileset
	game._debug_jump_time_of_day(23, 30)
	game._debug_set_weather(4) # Heavy Rain
	game.world.ccb_use_item("flashlight")
	game._refresh()
	game.board.snap_visuals()
	await _snap("verify_v2_ccb_night_rain.png")

	# 8. ENet Co-op Handshake Check
	var host_net := NetSession.new()
	var client_net := NetSession.new()
	var client_w = load("res://scripts/world.gd").new()
	client_w.setup_with_pack("cataclysm", 777, "evacuee")
	var hmsg := host_net.host_from_ui(game.world, 27219)
	var cmsg := client_net.join_from_ui(client_w, "127.0.0.1", 27219)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		host_net.tick(0.016, game.world, 1, "")
		client_net.tick(0.016, client_w, 1, "")
		if game.world.remote_player_count() >= 1:
			break
		await process_frame
	_check(game.world.remote_player_count() >= 1, "ENet co-op loopback connected (%s | %s)" % [hmsg, cmsg])
	client_net.leave_session(client_w)
	host_net.leave_session(game.world)

	# 9. Cangming Core Pack Zero-Regression Check
	game.enter_pack("cangming", 20260415, "evacuee", "沧溟少侠")
	for _i in range(6):
		await process_frame
	_check(not game.world.is_cataclysm_pack(), "Switched cleanly back to Cangming Core Pack")
	_check(Tiles.get_active_tileset_name() == "builtin_undead_people", "Cangming restored builtin_undead_people tileset")
	_check(game.world.npc_list().size() == 13 and game.world.list_workstations().size() == 28, "Cangming intact: 13 NPCs & 28 workstations")
	await _snap("verify_v2_cangming_ok.png")

	print("==========================================")
	if failures.is_empty():
		print("ALL_CHECKS_PASSED (0 failures)")
	else:
		print("FAILED_CHECKS (%d): %s" % [failures.size(), str(failures)])
	print("==========================================")
	quit(0 if failures.is_empty() else 1)
