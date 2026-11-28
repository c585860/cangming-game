extends SceneTree

const ART_DIR := "C:/Users/ASUS/.gemini/antigravity/brain/62b5805c-1bc3-48d9-80e9-3448fcc306c0"
var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("[PASS] " + msg)
	else:
		_failures += 1
		printerr("[FAIL] " + msg)


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await process_frame


func _shot(fname: String) -> void:
	await _wait_frames(4)
	var img := root.get_texture().get_image()
	var out_path := ART_DIR.path_join(fname)
	var err := img.save_png(out_path)
	print("[SHOT] %s -> err=%d (%dx%d)" % [fname, err, img.get_width(), img.get_height()])


func _extract_screen_text(frame: Dictionary) -> String:
	var cols := int(frame.get("cols", 0))
	var rows := int(frame.get("rows", 0))
	var cells: PackedByteArray = frame.get("cells", PackedByteArray())
	if cols <= 0 or rows <= 0 or cells.size() < cols * rows * 16:
		return ""
	var lines := PackedStringArray()
	for y in range(rows):
		var s := ""
		var row_off := y * cols * 16
		for x in range(cols):
			var off := row_off + x * 16
			var flags := cells.decode_u8(off + 13)
			if (flags & 0x08) != 0:
				continue
			var cp := cells.decode_u32(off)
			if cp >= 32:
				s += char(cp)
		var stripped := s.strip_edges(false, true)
		if not stripped.is_empty():
			lines.append(stripped)
	return "\n".join(lines)


func _wait_for_gen_change(eng: RefCounted, prev_gen: int, timeout_sec := 10.0) -> int:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < int(timeout_sec * 1000.0):
		await process_frame
		var g := int(eng.get_generation())
		if g > prev_gen:
			await _wait_frames(3)
			return int(eng.get_generation())
	return int(eng.get_generation())


func _send_char(eng: RefCounted, ch: String, prev_gen: int, wait_s := 5.0) -> int:
	eng.send_key(ch.unicode_at(0), ch, false, false, false)
	return await _wait_for_gen_change(eng, prev_gen, wait_s)


func _send_code(eng: RefCounted, code: int, txt: String, prev_gen: int, wait_s := 5.0) -> int:
	eng.send_key(code, txt, false, false, false)
	return await _wait_for_gen_change(eng, prev_gen, wait_s)


func _send_key_shift(eng: RefCounted, ch: String, prev_gen: int, wait_s := 5.0) -> int:
	eng.send_key(ch.unicode_at(0), ch, false, false, true)
	return await _wait_for_gen_change(eng, prev_gen, wait_s)


func _dismiss_debugmsg_if_any(eng: RefCounted) -> int:
	var gen := int(eng.get_generation())
	for _k in range(5):
		var txt := _extract_screen_text(eng.poll_terminal_frame())
		if "游戏出错了" in txt or "DEBUG :" in txt:
			print("[INFO] Dismissing upstream CCB debugmsg popup with 'I'...")
			gen = await _send_char(eng, "i", gen, 2.0)
			await _wait_frames(3)
			var txt2 := _extract_screen_text(eng.poll_terminal_frame())
			if "游戏出错了" in txt2 or "DEBUG :" in txt2:
				gen = await _send_code(eng, 32, " ", gen, 2.0)
				await _wait_frames(3)
		else:
			break
	return gen


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _wait_frames(3)

	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		printerr("Failed loading res://main.tscn")
		quit(1)
		return
	var main: Control = scene.instantiate()
	root.add_child(main)
	await _wait_frames(6)

	var host = main.ccb_native_host
	_check(host != null, "ccb_native_host instantiated")
	if host == null:
		quit(1)
		return

	# Temporarily bind '`' to CCB Debug Menu in test user_dir so we can verify wishitem, Chinese IME, fd_blood & gunfire!
	var kb_path := ProjectSettings.globalize_path("user://ccb_native_user/config/keybindings.json")
	DirAccess.make_dir_recursive_absolute(kb_path.get_base_dir())
	var kb_had_orig := FileAccess.file_exists(kb_path)
	var kb_orig_text := FileAccess.get_file_as_string(kb_path) if kb_had_orig else ""
	var kb_f := FileAccess.open(kb_path, FileAccess.WRITE)
	if kb_f != null:
		kb_f.store_string('[{"type":"keybinding","category":"DEFAULTMODE","id":"debug","bindings":[{"input_method":"keyboard_char","key":"`"},{"input_method":"keyboard_code","key":"`"}]}]')
		kb_f.close()

	if not host.active:
		host.activate()

	var eng: RefCounted = host.engine
	_check(eng != null and eng.is_library_loaded(), "ccb_bridge.dll loaded via CcbEngine GDExtension")
	if eng == null or not eng.is_library_loaded():
		printerr("Load error: ", eng.get_last_error() if eng != null else "null")
		quit(1)
		return

	# 1. Wait for CCB static data load + real Main Menu frame
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < 35000:
		await process_frame
		var st := str(eng.get_status())
		if st.begins_with("error:"):
			printerr("CCB worker error: ", st)
			break
		if int(eng.get_generation()) > 0 and st == "ready":
			break
	await _wait_frames(6)

	var gen := int(eng.get_generation())
	var f1: Dictionary = eng.poll_terminal_frame()
	var txt1 := _extract_screen_text(f1)
	print("[INFO] Main menu status=%s gen=%d cols=%d rows=%d text_len=%d" % [
		str(eng.get_status()), gen, int(f1.get("cols", 0)), int(f1.get("rows", 0)), txt1.length()
	])
	_check(gen > 0 and bool(f1.get("valid", false)) and txt1.length() > 100, "Real CCB Main Menu rendered")
	var ts_cfg: Dictionary = eng.get_tileset_config()
	print("[INFO] Native CCB tileset_config=%s" % str(ts_cfg))
	_check(bool(ts_cfg.get("valid", false)) and not str(ts_cfg.get("dir", "")).is_empty(), "CCB native TILES option resolves real gfx/ directory")
	await _shot("verify_native_01_main_menu.png")

	# 1b. Verify native CCB Settings ([T设置] -> [O选项] -> Graphics tab -> Tileset Options!)
	# Navigate cleanly to [T设置] via Right Arrow until "O选项" is visible, then Enter!
	for _nav_t in range(6):
		var cm := _extract_screen_text(eng.poll_terminal_frame())
		if "O选项" in cm:
			break
		gen = await _send_code(eng, 0x105, "", gen, 2.0) # Right arrow
		await _wait_frames(3)
	gen = await _send_code(eng, 10, "\n", gen, 4.0) # Enter -> open [O选项] Options!
	await _wait_frames(5)
	# Press Tab twice to switch General -> Interface -> Graphics (图像) tab
	gen = await _send_code(eng, 9, "\t", gen, 3.0)
	gen = await _send_code(eng, 9, "\t", gen, 3.0)
	await _wait_frames(4)
	# Scroll down to Tileset options group ("图块集选项" -> "使用图块" / "选择图块集")
	for _pg in range(3):
		gen = await _send_code(eng, 0x152, "", gen, 2.0) # PageDown
	await _wait_frames(5)
	var txt_opts := _extract_screen_text(eng.poll_terminal_frame())
	print("[INFO] Options->Graphics screen len=%d has_tileset=%s" % [txt_opts.length(), str(("图块" in txt_opts) or ("Tileset" in txt_opts) or ("UNDEAD" in txt_opts))])
	_check(("图块" in txt_opts) or ("Tileset" in txt_opts) or ("UNDEAD" in txt_opts), "CCB native Settings -> Graphics exposes Tileset option")
	await _shot("verify_native_01b_options_tileset.png")
	gen = await _send_code(eng, 27, "", gen, 4.0) # Esc back to main menu
	await _wait_frames(5)
	# Move left once from [T设置] back onto [A读取] so step 2 works identically
	gen = await _send_code(eng, 0x104, "", gen, 2.0) # Left -> [W世界]
	await _wait_frames(3)
	# Refresh txt1 for step 2
	txt1 = _extract_screen_text(eng.poll_terminal_frame())

	# 2. We're on [W世界] submenu where first item is "创建世界" -> press Enter!
	if not ("创建世界" in txt1):
		gen = await _send_code(eng, 0x105, "", gen, 3.0)
		await _wait_frames(3)
	# On [W 世界] submenu, first item is "创建世界" -> press Enter!
	gen = await _send_code(eng, 10, "\n", gen, 6.0)
	await _wait_frames(6)
	var f_wg: Dictionary = eng.poll_terminal_frame()
	var txt_wg := _extract_screen_text(f_wg)
	print("[INFO] Worldgen screen len=%d has_create=%s" % [txt_wg.length(), str("创建世界" in txt_wg)])
	_check("创建世界" in txt_wg or "World" in txt_wg, "Real CCB Worldgen screen opened")
	await _shot("verify_native_02_worldgen_mods.png")

	# Open real CCB Mod Manager ('m') to verify all 51 mods, then 's' + Esc back to Create World
	gen = await _send_char(eng, "m", gen, 5.0)
	await _wait_frames(6)
	var txt_mods := _extract_screen_text(eng.poll_terminal_frame())
	print("[INFO] Mod Manager screen len=%d has_magiclysm=%s" % [txt_mods.length(), str("magiclysm" in txt_mods)])
	_check("magiclysm" in txt_mods or "模组" in txt_mods, "Real CCB 51-Mod Manager opened")
	await _shot("verify_native_02b_mod_manager.png")
	gen = await _send_code(eng, 27, "", gen, 4.0) # Esc back to Create World
	await _wait_frames(6)

	# Press 'f' ([f][ 完成 ]) -> pops up "Are you SURE you're finished?" -> press 'y' / 'Y' to confirm!
	gen = await _send_char(eng, "f", gen, 4.0)
	await _wait_frames(6)
	var txt_confirm := _extract_screen_text(eng.poll_terminal_frame())
	print("[INFO] After 'f' popup check: has_Y=%s" % str("[Y]" in txt_confirm or "确定" in txt_confirm))
	await _shot("verify_native_02c_confirm_popup.png")
	# Confirm world creation (case-sensitive 'Y'!)
	gen = await _send_code(eng, ord("Y"), "Y", gen, 6.0)
	await _wait_frames(6)
	# Dismiss any "World created" banner ONLY if still not back on Main Menu
	var after_y_txt := _extract_screen_text(eng.poll_terminal_frame())
	if not ("N新游戏" in after_y_txt) or ("世界名称" in after_y_txt):
		gen = await _send_code(eng, 27, "", gen, 3.0)
		await _wait_frames(4)

	# 3. Navigate cleanly to [N 新游戏] -> select Play Now! -> Real Overmap + Mapgen + Evac Shelter Spawn!
	for _dismiss in range(4):
		var cur_m := _extract_screen_text(eng.poll_terminal_frame())
		if "N新游戏" in cur_m and not ("确认" in cur_m) and not ("[Y]" in cur_m) and not ("世界名称" in cur_m):
			break
		gen = await _send_code(eng, 27, "", gen, 2.0)
		await _wait_frames(3)
	for _nav in range(10):
		var cur_m := _extract_screen_text(eng.poll_terminal_frame())
		if "新角色" in cur_m or "直接游戏" in cur_m or "Play Now" in cur_m:
			break
		if "世界名称" in cur_m or "确认" in cur_m or "[Y]" in cur_m:
			gen = await _send_code(eng, 27, "", gen, 2.0)
		else:
			gen = await _send_code(eng, 0x104, "", gen, 2.0) # Left arrow toward [N 新游戏]
		await _wait_frames(3)
	var txt_new := _extract_screen_text(eng.poll_terminal_frame())
	print("[INFO] Before Play Now: has_direct=%s" % str("D直接游戏" in txt_new))
	# Use Down x3 + Enter so it works regardless of zh_CN uppercase-only hotkey!
	gen = await _send_code(eng, 0x102, "", gen, 2.0) # Down -> Preset
	gen = await _send_code(eng, 0x102, "", gen, 2.0) # Down -> Random
	gen = await _send_code(eng, 0x102, "", gen, 2.0) # Down -> Play Now! (Default Scenario)
	gen = await _send_code(eng, 10, "\n", gen, 4.0) # Enter -> Pick world / Generate Overmap & Spawn!
	await _wait_frames(5)
	# If multiple worlds exist, CCB pops up a "Choose World" menu -> press Enter to pick the first world!
	var txt_pick := _extract_screen_text(eng.poll_terminal_frame())
	if "选择" in txt_pick or "(0)" in txt_pick or "(1)" in txt_pick or "世界" in txt_pick:
		if not bool(eng.poll_terminal_frame().get("has_terrain", false)):
			gen = await _send_code(eng, 10, "\n", gen, 6.0)

	# Wait up to 35s for real CCB overmap + mapgen + spawn to finish (and capture authentic Loading Screen!)
	var t_spawn := Time.get_ticks_msec()
	var in_game_ok := false
	var saw_loading_ui := false
	var loading_shot_taken := false
	var last_nudge := 0
	while (Time.get_ticks_msec() - t_spawn) < 35000:
		await _wait_frames(2)
		var lstate: Dictionary = eng.get_loading_state() if eng.has_method("get_loading_state") else {}
		if bool(lstate.get("active", false)):
			var lctx := str(lstate.get("context", ""))
			var lstp := str(lstate.get("step", ""))
			var limg := str(lstate.get("image_path", ""))
			if not saw_loading_ui:
				saw_loading_ui = true
				print("[INFO] Loading UI active: img=%s tip_len=%d msg=%s %s tex_ok=%s" % [
					limg.get_file(), str(lstate.get("tip", "")).length(), lctx, lstp,
					str(host._loading_tex_rect != null and host._loading_tex_rect.texture != null)
				])
			if not loading_shot_taken and host._loading_overlay.visible and host._loading_tex_rect != null and host._loading_tex_rect.texture != null:
				loading_shot_taken = true
				await _shot("verify_native_02d_loading_screen.png")
		var tf: Dictionary = eng.poll_terminal_frame()
		if bool(tf.get("has_terrain", false)):
			var ws: Dictionary = eng.poll_world_snapshot()
			if bool(ws.get("valid", false)):
				in_game_ok = true
				break
		var elapsed := Time.get_ticks_msec() - t_spawn
		if elapsed > 2000 and (elapsed - last_nudge) > 2000:
			last_nudge = elapsed
			var cur_txt := _extract_screen_text(tf)
			print("[INFO] Spawn wait t=%dms loading=%s tail=%s" % [elapsed, str(bool(lstate.get("active", false))), cur_txt.substr(maxi(0, cur_txt.length() - 140)).replace("\n", " | ")])
			if "游戏出错了" in cur_txt or "DEBUG :" in cur_txt:
				eng.send_key(ord("i"), "i", false, false, false)
			elif "[Y]" in cur_txt:
				eng.send_key(ord("Y"), "Y", false, false, true)
			elif "D直接游戏" in cur_txt:
				eng.send_key(ord("D"), "D", false, false, true)
			elif "选择" in cur_txt or "(0)" in cur_txt or "(1)" in cur_txt:
				eng.send_key(10, "\n", false, false, false)
			elif "按" in cur_txt or "Space" in cur_txt or "空格" in cur_txt:
				eng.send_key(32, " ", false, false, false)

	_check(saw_loading_ui, "Vanilla CCB loading screen with artwork & live progress displayed during world/character load")

	await _wait_frames(8)
	# Dismiss any stray modal (e.g. Action Menu) if opened during spawn transition
	for _clean in range(3):
		var cur_gtxt := _extract_screen_text(eng.poll_terminal_frame())
		if "查看周围地形" in cur_gtxt or "主菜单" in cur_gtxt:
			gen = await _send_code(eng, 27, "", int(eng.get_generation()), 2.0)
			await _wait_frames(4)
		else:
			break
	var tf_game: Dictionary = eng.poll_terminal_frame()
	var ws_game: Dictionary = eng.poll_world_snapshot()
	print("[INFO] In-game check: has_terrain=%s valid=%s player=%s turn=%d strings=%d critters=%d lights=%d weather=%s mm=%d" % [
		str(tf_game.get("has_terrain", false)), str(ws_game.get("valid", false)),
		str(ws_game.get("player", Vector2i.ZERO)), int(ws_game.get("turn", -1)),
		(ws_game.get("strings", PackedStringArray()) as PackedStringArray).size(),
		(ws_game.get("creatures", []) as Array).size(),
		(ws_game.get("lights", []) as Array).size(),
		str(ws_game.get("weather", "")),
		int(ws_game.get("minimap_size", 0))
	])
	_check(in_game_ok, "Real CCB world generated and player spawned with GPU terrain cutout + snapshot")
	var ll_map: Dictionary = eng.get_looks_like_map()
	print("[INFO] World-loaded looks_like catalog entries=%d" % ll_map.size())
	_check(ll_map.size() > 500, "CCB looks_like fallback catalog loaded (%d entries)" % ll_map.size())

	# Verify ALL CCB vehicle #variant parts & monster IDs resolve cleanly to real tileset sprites (zero invisible cars!)
	const TilesCls = preload("res://scripts/undead_tiles.gd")
	var vp_samples := [
		"vp_frame#cover", "vp_frame#horizontal", "vp_board#horizontal", "vp_board#ne",
		"vp_quarterpanel#ne", "vp_quarterpanel#nw", "vp_windshield#horizontal_front",
		"vp_door#vertical_left", "vp_wheel_wide#cover", "vp_hood#cover", "vp_seat", "vp_headlight",
		"mon_zombie", "mon_zombie_tough", "mon_dog", "mon_zombie_synthetic_fallback_test"
	]
	var vp_missing: Array[String] = []
	for sid in vp_samples:
		var r := TilesCls.resolve_tile_id(sid, "spring", true)
		if r.is_empty():
			vp_missing.append(sid)
	print("[INFO] Vehicle/Monster sprite resolution check: tested=%d missing=%s" % [vp_samples.size(), str(vp_missing)])
	_check(vp_missing.is_empty(), "All vehicle #variant parts & monster sprites resolve cleanly (%d/%d)" % [vp_samples.size() - vp_missing.size(), vp_samples.size()])

	_check((ws_game.get("strings", PackedStringArray()) as PackedStringArray).size() >= 5, "Real CCB terrain/furniture/item IDs captured")
	_check((ws_game.get("geom_rgba", PackedByteArray()) as PackedByteArray).size() > 0, "C++ pre-packed GPU geom_rgba/mat_rgba/vis_rgba/rain_mask buffers populated")
	_check(int(ws_game.get("minimap_size", 0)) == 121, "Real CCB 121x121 pixel minimap RGBA captured")
	await _shot("verify_native_03_gameplay_gpu_lit.png")

	if in_game_ok:
		var p0: Vector2i = ws_game.get("player", Vector2i.ZERO)
		var turn0: int = int(ws_game.get("turn", 0))
		gen = int(eng.get_generation())
		# Verify REAL Shift+1 ('!' WITH shift_pressed=true, matching live Godot keyboard input!) toggles Safe Mode!
		var txt_pre_safe := _extract_screen_text(eng.poll_terminal_frame())
		eng.send_key(ord("!"), "!", false, false, true)
		gen = await _wait_for_gen_change(eng, gen, 2.5)
		await _wait_frames(3)
		var txt_post_safe := _extract_screen_text(eng.poll_terminal_frame())
		var safe_toggled := ("安全模式: 关" in txt_post_safe) or ("安全模式关闭" in txt_post_safe) or ("Safe Mode" in txt_post_safe and txt_post_safe != txt_pre_safe)
		print("[INFO] Shift+1 Safe Mode toggle check: toggled=%s" % str(safe_toggled))
		_check(safe_toggled, "Shift+1 ('!' with shift=true) cleanly toggles CCB Safe Mode instead of SHIFT-!")
		gen = await _dismiss_debugmsg_if_any(eng)
		# 4. Step player & walk east/outside so we capture BOTH shelter interior volumetric beams AND outdoor yard/trees/road!
		gen = await _send_char(eng, "l", gen, 3.0)
		gen = await _dismiss_debugmsg_if_any(eng)
		gen = await _send_char(eng, "j", gen, 3.0)
		gen = await _dismiss_debugmsg_if_any(eng)
		gen = await _send_char(eng, ".", gen, 3.0)
		gen = await _dismiss_debugmsg_if_any(eng)
		await _wait_frames(6)
		var ws_after: Dictionary = eng.poll_world_snapshot()
		var p1: Vector2i = ws_after.get("player", p0)
		var turn1: int = int(ws_after.get("turn", turn0))
		print("[INFO] Movement check: player %s -> %s, turn %d -> %d" % [str(p0), str(p1), turn0, turn1])
		_check(turn1 > turn0, "Real CCB turn loop advanced strictly on player action")

		# Walk east toward shelter front door/window, open it if closed ('o' + 'l'), and step outside onto yard/sidewalk!
		for _step in range(18):
			var prev_p: Vector2i = eng.poll_world_snapshot().get("player", Vector2i.ZERO)
			gen = await _send_char(eng, "l", gen, 2.0)
			gen = await _dismiss_debugmsg_if_any(eng)
			var cur_p: Vector2i = eng.poll_world_snapshot().get("player", prev_p)
			if cur_p == prev_p:
				# Closed door or curtained window ahead — try opening east ('o' -> 'l') twice (curtain + window!)
				gen = await _send_char(eng, "o", gen, 2.0)
				gen = await _send_char(eng, "l", gen, 2.0)
				gen = await _dismiss_debugmsg_if_any(eng)
				# If still blocked (solid wall), step south ('j') to find the open doorway/window!
				gen = await _send_char(eng, "l", gen, 2.0)
				if eng.poll_world_snapshot().get("player", prev_p) == prev_p:
					gen = await _send_char(eng, "j", gen, 2.0)
					gen = await _dismiss_debugmsg_if_any(eng)
		await _wait_frames(10)
		var ws_03b: Dictionary = eng.poll_world_snapshot()
		print("[INFO] 03b snapshot: player=%s min=%d weather=%s lights=%s" % [
			str(ws_03b.get("player", Vector2i.ZERO)), int(ws_03b.get("minutes", 0)),
			str(ws_03b.get("weather", "")), str(ws_03b.get("lights", []))
		])
		await _shot("verify_native_03b_outdoor_volumetric_ao.png")

		# 4b. Test Wait ('|' -> optional 'w' if wearing wristwatch -> '3' Wait 5 minutes = 300 turns!) advancing time AUTOMATICALLY!
		gen = await _dismiss_debugmsg_if_any(eng)
		var ws_pre_wait: Dictionary = eng.poll_world_snapshot()
		var turn_pre_wait: int = int(ws_pre_wait.get("turn", 0))
		gen = await _send_char(eng, "|", gen, 3.0)
		await _wait_frames(4)
		var wait_menu_txt := _extract_screen_text(eng.poll_terminal_frame())
		print("[INFO] Wait menu snippet=%s" % wait_menu_txt.substr(maxi(0, wait_menu_txt.length() - 220)).replace("\n", " | "))
		if "闹钟" in wait_menu_txt or "等一会儿" in wait_menu_txt or "Wait for" in wait_menu_txt:
			gen = await _send_char(eng, "w", gen, 3.0)
			await _wait_frames(4)
		# Select option '3' (Wait 5 minutes = 300 turns) and DO NOT press any more keys!
		gen = await _send_char(eng, "3", gen, 3.0)
		var t_wait0 := Time.get_ticks_msec()
		var turn_post_wait := turn_pre_wait
		while (Time.get_ticks_msec() - t_wait0) < 8000:
			await _wait_frames(4)
			var ws_w: Dictionary = eng.poll_world_snapshot()
			turn_post_wait = int(ws_w.get("turn", turn_pre_wait))
			if turn_post_wait >= turn_pre_wait + 280:
				break
		print("[INFO] Wait auto-advance check: turn %d -> %d (delta=%d in %dms, zero keypresses!)" % [
			turn_pre_wait, turn_post_wait, turn_post_wait - turn_pre_wait, Time.get_ticks_msec() - t_wait0
		])
		_check(turn_post_wait >= turn_pre_wait + 200, "Wait ('|') auto-advances time without requiring player keypresses")
		gen = await _dismiss_debugmsg_if_any(eng)

		# 4c. Test mouse click-to-walk destination preview route (1st click) AND active auto-move (2nd click)!
		var ws_pre_route: Dictionary = eng.poll_world_snapshot()
		var p_route0: Vector2i = ws_pre_route.get("player", Vector2i.ZERO)
		var tf_cur: Dictionary = eng.poll_terminal_frame()
		var tr_cur: Rect2i = tf_cur.get("terrain_rect", Rect2i())
		# Player is standing against the east wall of the shelter, so west (-4, 0) is guaranteed open visible floor!
		var offsets: Array[Vector2i] = [Vector2i(-4, 0), Vector2i(-3, -1), Vector2i(4, 0), Vector2i(0, 3), Vector2i(0, -3)]
		var click_cx := 0
		var click_cy := 0
		var route_pts: Array = []
		var chosen_off := Vector2i(-4, 0)
		for off: Vector2i in offsets:
			@warning_ignore("integer_division")
			click_cx = tr_cur.position.x + tr_cur.size.x / 2 + off.x
			@warning_ignore("integer_division")
			click_cy = tr_cur.position.y + tr_cur.size.y / 2 + off.y
			chosen_off = off
			eng.send_mouse(1, click_cx, click_cy, 0)
			await _wait_frames(3)
			eng.send_mouse(2, click_cx, click_cy, 0)
			await _wait_frames(12)
			var ws_route: Dictionary = eng.poll_world_snapshot()
			route_pts = ws_route.get("path_points", [])
			var tf_dbg: Dictionary = eng.poll_terminal_frame()
			var c_dbg: PackedByteArray = tf_dbg.get("cells", PackedByteArray())
			var dcols: int = int(tf_dbg.get("cols", 0))
			var cell_info := ""
			if dcols > 0 and click_cy * dcols + click_cx < c_dbg.size() / 16:
				var co := (click_cy * dcols + click_cx) * 16
				cell_info = "cp=%d('%s') fg=0x%08x bg=0x%08x fl=0x%02x" % [
					c_dbg.decode_u32(co), char(c_dbg.decode_u32(co)),
					c_dbg.decode_u32(co + 4), c_dbg.decode_u32(co + 8), c_dbg.decode_u8(co + 13)
				]
			print("[INFO] Route preview try offset=%s cell=(%d,%d) tr=%s -> path_points=%d [%s]" % [
				str(off), click_cx, click_cy, str(tr_cur), route_pts.size(), cell_info
			])
			if route_pts.size() >= 2:
				break
		_check(route_pts.size() >= 2, "Auto-move route preview captured and rendered (%d points)" % route_pts.size())
		var ws_03c: Dictionary = eng.poll_world_snapshot()
		print("[INFO] 03c snapshot: player=%s min=%d weather=%s lights=%s" % [
			str(ws_03c.get("player", Vector2i.ZERO)), int(ws_03c.get("minutes", 0)),
			str(ws_03c.get("weather", "")), str(ws_03c.get("lights", []))
		])
		await _shot("verify_native_03c_automove_route.png")

		# Second left-click on SAME tile (or (-4, 0) if preview wasn't detected): starts active auto-move!
		if route_pts.size() < 2:
			@warning_ignore("integer_division")
			click_cx = tr_cur.position.x + tr_cur.size.x / 2 - 4
			@warning_ignore("integer_division")
			click_cy = tr_cur.position.y + tr_cur.size.y / 2
			eng.send_mouse(1, click_cx, click_cy, 0)
			await _wait_frames(2)
			eng.send_mouse(2, click_cx, click_cy, 0)
			await _wait_frames(8)
		eng.send_mouse(1, click_cx, click_cy, 0)
		await _wait_frames(2)
		eng.send_mouse(2, click_cx, click_cy, 0)
		var t_am0 := Time.get_ticks_msec()
		var p_route1 := p_route0
		while (Time.get_ticks_msec() - t_am0) < 4000:
			await _wait_frames(4)
			var ws_am: Dictionary = eng.poll_world_snapshot()
			p_route1 = ws_am.get("player", p_route0)
			if p_route1.distance_to(p_route0) >= 3.0:
				break
		print("[INFO] Active auto-move check (2nd click off=%s): player %s -> %s in %dms (zero keypresses!)" % [
			str(chosen_off), str(p_route0), str(p_route1), Time.get_ticks_msec() - t_am0
		])
		_check(p_route1 != p_route0, "Active auto-move walks player automatically without extra keypresses")
		gen = await _dismiss_debugmsg_if_any(eng)

		# 4d. Test waiting until REAL DUSK/SUNSET (minutes_of_day >= 1135, ~18:55-19:30) + measure steady FPS!
		# Real CCB Wait menu keys: '8' = 6 hours, '7' = 3 hours, '6' = 2 hours, '5' = 1 hour, 'k' = Wait until dusk/night!
		var turn_before_dusk := int(eng.poll_world_snapshot().get("turn", 0))
		var mins_dusk := int(eng.poll_world_snapshot().get("minutes", 480))
		var t_dusk_budget := Time.get_ticks_msec()
		for _wtry in range(8):
			if mins_dusk >= 1135 or (Time.get_ticks_msec() - t_dusk_budget) > 26000:
				break
			gen = await _send_char(eng, "|", int(eng.get_generation()), 3.0)
			await _wait_frames(3)
			var dusk_menu := _extract_screen_text(eng.poll_terminal_frame())
			if "闹钟" in dusk_menu or "等一会儿" in dusk_menu or "Wait for" in dusk_menu:
				gen = await _send_char(eng, "w", gen, 3.0)
				await _wait_frames(3)
			# '8' = 6h (before 13:00), '7' = 3h (13:00-16:00), '6' = 2h (16:00-17:15), '5' = 1h (17:15-18:15), '4' = 30m (18:15-18:55)
			var pick_key := "8" if mins_dusk < 780 else ("7" if mins_dusk < 960 else ("6" if mins_dusk < 1035 else ("5" if mins_dusk < 1095 else "4")))
			gen = await _send_char(eng, pick_key, gen, 3.0)
			var t_seg := Time.get_ticks_msec()
			var last_turn_seen := int(eng.poll_world_snapshot().get("turn", 0))
			var stale_frames := 0
			while (Time.get_ticks_msec() - t_seg) < 7500 and (Time.get_ticks_msec() - t_dusk_budget) < 26000:
				await _wait_frames(5)
				var tf_w: Dictionary = eng.poll_terminal_frame()
				var txt_w := _extract_screen_text(tf_w)
				if "确定" in txt_w or "继续" in txt_w or "(Y/N)" in txt_w or "[Y]" in txt_w:
					eng.send_key(ord("y"), "y", false, false, false)
					await _wait_frames(3)
				var ws_d: Dictionary = eng.poll_world_snapshot()
				mins_dusk = int(ws_d.get("minutes", mins_dusk))
				var cur_t := int(ws_d.get("turn", last_turn_seen))
				if mins_dusk >= 1135:
					break
				if cur_t == last_turn_seen:
					stale_frames += 1
					if stale_frames >= 6:
						break
				else:
					stale_frames = 0
					last_turn_seen = cur_t
			# Ensure any lingering wait menu is dismissed before next segment
			if "等待多久" in _extract_screen_text(eng.poll_terminal_frame()):
				gen = await _send_code(eng, 27, "", int(eng.get_generation()), 2.0)
		# Let smooth 60fps dusk interpolation settle completely before benchmarking true idle GPU dispatch count
		await _wait_frames(45)
		var ws_dusk: Dictionary = eng.poll_world_snapshot()
		var fps_dusk := Engine.get_frames_per_second()
		var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var light_pipe = host._gpu_view._lighting
		var w_disp: int = light_pipe.world_light_dispatches if light_pipe != null else -1
		var s_disp: int = light_pipe.sight_dispatches if light_pipe != null else -1
		# Verify 30 idle frames trigger ZERO extra world lightmap or sight GPU dispatches!
		# Let smooth 60fps dusk interpolation settle completely before benchmarking true idle GPU dispatch count
		await _wait_frames(45)
		var w_disp2: int = light_pipe.world_light_dispatches if light_pipe != null else -1
		var s_disp2: int = light_pipe.sight_dispatches if light_pipe != null else -1
		var dm := int(ws_dusk.get("minutes", 0))
		print("[INFO] Dusk & Perf telemetry: %02d:%02d turn_delta=%d weather=%s fps=%d cpu_proc=%.2fms idle_light_dispatches=%d->%d idle_sight=%d->%d" % [
			floori(float(dm) / 60.0), dm % 60,
			int(ws_dusk.get("turn", 0)) - turn_before_dusk,
			str(ws_dusk.get("weather", "")), fps_dusk, proc_ms, w_disp, w_disp2, s_disp, s_disp2
		])
		_check(w_disp2 == w_disp and s_disp2 == s_disp, "Zero redundant GPU lightmap/sight dispatches when idle (%d -> %d)" % [w_disp, w_disp2])
		await _shot("verify_native_03d_dusk_smooth.png")
		gen = await _dismiss_debugmsg_if_any(eng)

		# 5. Pause / Main Menu ('Esc' — uilist ImTui menu! Verifies ALL unselected items are bright & visible!)
		gen = await _send_code(eng, 27, "", gen, 4.0)
		await _shot("verify_native_04b_esc_menu.png")
		gen = await _send_code(eng, 27, "", gen, 3.0)

		# 5b. Inventory ('i')
		gen = await _send_char(eng, "i", gen, 4.0)
		await _shot("verify_native_04_inventory.png")
		gen = await _send_code(eng, 27, "", gen, 3.0)

		# 6. Overmap ('m')
		gen = await _send_char(eng, "m", gen, 4.0)
		await _shot("verify_native_05_overmap.png")
		gen = await _send_code(eng, 27, "", gen, 3.0)

		# 7. Crafting ('&' — ImTui Dear ImGui screen!)
		gen = await _send_char(eng, "&", gen, 5.0)
		await _shot("verify_native_06_crafting_imtui.png")
		gen = await _send_code(eng, 27, "", gen, 3.0)

		# 8. Look-around ('x' + step right)
		gen = await _send_char(eng, "x", gen, 4.0)
		gen = await _send_char(eng, "l", gen, 3.0)
		await _shot("verify_native_07_look_around.png")
		gen = await _send_code(eng, 27, "", gen, 3.0)

		# 8b. Verify fd_blood multitile resolution (unconnected/edge/corner/center -> NEVER solid red square!)
		var blood_id := TilesCls.resolve_field_tile_id("fd_blood", 1, "spring")
		var blood_ent := TilesCls.get_tile_entry(blood_id)
		var blood_joins: Dictionary = blood_ent.get("joins", {})
		print("[INFO] fd_blood resolved=%s joins=%s" % [blood_id, str(blood_joins.keys())])
		_check(not blood_id.is_empty() and blood_joins.has("unconnected"), "fd_blood resolves with genuine multitile unconnected/connection sprites")

		# 8c. Open Debug Menu ('`') -> Spawning ('s') -> Wish Item ('w'):
		#     Verifies (a) full-height multi-row ImGui uilist + right info pane (NOT 4 rows!),
		#     (b) Chinese IME text input ('格洛克') inside ImGui filter popup,
		#     (c) Spawning a loaded Glock pistol -> Bleed self (real fd_blood) -> Real gunfire muzzle flash + tracer + HDR light!
		gen = await _send_char(eng, "`", int(eng.get_generation()), 4.0)
		await _wait_frames(4)
		var dbg_txt := _extract_screen_text(eng.poll_terminal_frame())
		print("[INFO] Debug menu opened len=%d has_spawn=%s" % [dbg_txt.length(), str("生成" in dbg_txt or "Spawning" in dbg_txt)])
		if "生成" in dbg_txt or "Spawning" in dbg_txt or "玩家" in dbg_txt:
			gen = await _send_char(eng, "s", gen, 4.0)
			await _wait_frames(4)
			gen = await _send_char(eng, "w", gen, 5.0)
			await _wait_frames(6)
			var wish_txt := _extract_screen_text(eng.poll_terminal_frame())
			var wish_lines := wish_txt.split("\n", false)
			# Verify non-input wishitem screen does NOT wrongly auto-activate IME!
			var wish_ime_before := bool(eng.poll_terminal_frame().get("want_text_input", false))
			print("[INFO] Wishitem full-screen menu lines=%d len=%d ime_before_filter=%s" % [wish_lines.size(), wish_txt.length(), str(wish_ime_before)])
			_check(wish_lines.size() >= 18, "Debug wishitem uilist renders full screen height (%d rows, NOT truncated to 4 rows)" % wish_lines.size())
			_check(not wish_ime_before, "OS IME stays off on non-text menus so hotkeys never collide")
			await _shot("verify_native_09_debug_wishitem.png")

			# Test Chinese IME input inside wishitem filter ('/')!
			gen = await _send_char(eng, "/", gen, 4.0)
			await _wait_frames(5)
			var tf_ime: Dictionary = eng.poll_terminal_frame()
			var want_ime := bool(tf_ime.get("want_text_input", false))
			eng.send_text_input("突击步枪")
			await _wait_frames(8)
			var ime_txt := _extract_screen_text(eng.poll_terminal_frame())
			print("[INFO] Chinese IME filter check: want_text_input=%s has_cn=%s" % [str(want_ime), str("突击步枪" in ime_txt)])
			_check(want_ime and ("突击步枪" in ime_txt), "Chinese IME text input works inside CCB ImGui filter popup ('突击步枪')")
			await _shot("verify_native_09b_wishitem_chinese_ime.png")
			# Dismiss wishitem cleanly back to gameplay before running blood test (so spawned gear stays at our feet later!)
			for _esc in range(4):
				var tfe: Dictionary = eng.poll_terminal_frame()
				var txte := _extract_screen_text(tfe)
				if bool(tfe.get("has_terrain", false)) and not ("查找" in txte or "Find" in txte or "容器" in txte):
					break
				gen = await _send_code(eng, 27, "", int(eng.get_generation()), 3.0)
				await _wait_frames(4)
			gen = await _dismiss_debugmsg_if_any(eng)

			# Trigger real fd_blood via Debug -> Player ('p') -> Bleed self ('b') -> Torso ('q') -> wait turns & step right!
			gen = await _send_char(eng, "`", int(eng.get_generation()), 4.0)
			await _wait_frames(4)
			gen = await _send_char(eng, "p", gen, 4.0)
			await _wait_frames(4)
			gen = await _send_char(eng, "b", gen, 4.0)
			await _wait_frames(4)
			gen = await _send_char(eng, "q", gen, 4.0) # Torso
			await _wait_frames(4)
			var bld_tf: Dictionary = eng.poll_terminal_frame()
			var bld_prompt := _extract_screen_text(bld_tf)
			if not bool(bld_tf.get("has_terrain", false)) or bool(bld_tf.get("want_text_input", false)) or "强度" in bld_prompt or "intensity" in bld_prompt:
				eng.send_key(ord("2"), "2", false, false, false)
				eng.send_key(ord("5"), "5", false, false, false)
				await _wait_frames(3)
				gen = await _send_code(eng, 10, "\n", int(eng.get_generation()), 3.0)
				await _wait_frames(4)
			for _besc in range(3):
				var btfe: Dictionary = eng.poll_terminal_frame()
				if bool(btfe.get("has_terrain", false)) and not ("主菜单" in _extract_screen_text(btfe)):
					break
				gen = await _send_code(eng, 27, "", int(eng.get_generation()), 2.0)
				await _wait_frames(3)
			# Wait 10 turns ('.') + step right so severe bleeding drips visible fd_blood pools onto adjacent tiles!
			for _bt in range(10):
				gen = await _send_char(eng, ".", int(eng.get_generation()), 2.0)
				gen = await _dismiss_debugmsg_if_any(eng)
			gen = await _send_char(eng, "l", int(eng.get_generation()), 3.0)
			for _bt2 in range(4):
				gen = await _send_char(eng, ".", int(eng.get_generation()), 2.0)
			gen = await _send_char(eng, "l", int(eng.get_generation()), 3.0)
			await _wait_frames(8)
			var ws_bld: Dictionary = eng.poll_world_snapshot()
			var bld_strs: PackedStringArray = ws_bld.get("strings", PackedStringArray())
			var has_blood_tile := false
			for s in bld_strs:
				if "fd_blood" in s:
					has_blood_tile = true
					break
			print("[INFO] Real fd_blood on map=%s" % str(has_blood_tile))
			_check(has_blood_tile, "Real fd_blood field spawned on map with autotile splatter rendering")
			await _shot("verify_native_10_blood_splatter.png")

			# 8d. Verify 44.1 kHz Stereo C++ Physical Acoustic Synthesizer across gunshots, spaces, hits & explosions!
			var pcm_t0 := Time.get_ticks_usec()
			var pcm_rifle: PackedByteArray = eng.synthesize_combat_pcm(1, 3, 0, 0, false, 1.0)
			var pcm_burst_mid: PackedByteArray = eng.synthesize_combat_pcm(1, 3, 1, 1, false, 0.6)
			var pcm_expl: PackedByteArray = eng.synthesize_combat_pcm(2, 3, 0, 2, false, 1.0)
			var pcm_us := Time.get_ticks_usec() - pcm_t0
			var peak_rifle := 0
			for bi in range(0, mini(pcm_rifle.size() - 2, 16000), 2):
				peak_rifle = maxi(peak_rifle, absi(pcm_rifle.decode_s16(bi)))
			var peak_expl := 0
			for bi in range(0, mini(pcm_expl.size() - 2, 32000), 2):
				peak_expl = maxi(peak_expl, absi(pcm_expl.decode_s16(bi)))
			print("[INFO] C++ 44.1kHz Stereo Acoustic Synth: rifle=%dB(peak=%d) mid=%dB expl=%dB(peak=%d) time=%.2fms" % [
				pcm_rifle.size(), peak_rifle, pcm_burst_mid.size(), pcm_expl.size(), peak_expl, float(pcm_us) * 0.001
			])
			_check(pcm_rifle.size() > 80000 and peak_rifle > 12000 and pcm_expl.size() > 200000 and peak_expl > 14000,
				"44.1kHz stereo physical acoustic synth produces realistic high-dynamic-range gunshot & explosion PCM")

			# Now spawn M4A1 carbine + loaded STANAG mag + frag grenade right at our current tile (fresh wishitem per item = 0 filter residue!)
			var wish_specs := [
				{"query": "M4A1", "expect_id": "modular_m4_carbine", "container": true},
				{"query": "STANAG 30", "expect_id": "stanag30", "container": true},
				{"query": "frag grenade", "expect_id": "grenade", "container": false},
			]
			for spec in wish_specs:
				gen = await _send_char(eng, "`", int(eng.get_generation()), 4.0)
				await _wait_frames(3)
				gen = await _send_char(eng, "s", gen, 4.0)
				await _wait_frames(3)
				gen = await _send_char(eng, "w", gen, 5.0)
				await _wait_frames(5)
				if bool(spec["container"]):
					gen = await _send_char(eng, "f", int(eng.get_generation()), 3.0) # [f] Container (spawn loaded!)
					await _wait_frames(3)
				gen = await _send_char(eng, "/", int(eng.get_generation()), 4.0)
				await _wait_frames(4)
				eng.send_text_input(str(spec["query"]))
				await _wait_frames(5)
				gen = await _send_code(eng, 10, "\n", int(eng.get_generation()), 4.0)
				await _wait_frames(5)
				var eid: String = spec["expect_id"]
				for _sk in range(16):
					var fhead := _extract_screen_text(eng.poll_terminal_frame())
					if (": " + eid + "\n") in fhead or (": " + eid + " ") in fhead or (": " + eid + " (") in fhead:
						break
					gen = await _send_code(eng, 0x102, "", int(eng.get_generation()), 2.0)
					await _wait_frames(2)
				var sel_txt := _extract_screen_text(eng.poll_terminal_frame())
				var first_ln := sel_txt.split("\n")[0] if not sel_txt.is_empty() else ""
				print("[INFO] Wishitem spawning q='%s' expect='%s' -> head='%s'" % [str(spec["query"]), eid, first_ln])
				gen = await _send_code(eng, 10, "\n", int(eng.get_generation()), 4.0) # select item
				await _wait_frames(4)
				gen = await _send_code(eng, 10, "\n", int(eng.get_generation()), 4.0) # How many? -> 1
				await _wait_frames(4)
				for _esw in range(3):
					var tfe: Dictionary = eng.poll_terminal_frame()
					if bool(tfe.get("has_terrain", false)) and not ("容器" in _extract_screen_text(tfe)):
						break
					gen = await _send_code(eng, 27, "", int(eng.get_generation()), 3.0)
					await _wait_frames(3)
				gen = await _dismiss_debugmsg_if_any(eng)

			# 8e. Wield M4A1 ('w') -> Reload ('r') -> Switch to Burst/Auto ('F') -> Fire Burst ('f' -> aim east -> 'f')!
			gen = await _send_char(eng, "w", int(eng.get_generation()), 4.0)
			await _wait_frames(5)
			var wtxt := _extract_screen_text(eng.poll_terminal_frame())
			var gun_invlet := ""
			for wline in wtxt.split("\n", false):
				if "M4A1" in wline or "carbine" in wline.to_lower() or "卡宾枪" in wline:
					var trimmed := wline.strip_edges()
					if trimmed.length() >= 3 and trimmed[1] == " ":
						gun_invlet = trimmed[0]
						break
			print("[INFO] Wield menu M4A1 invlet='%s' sample=%s" % [gun_invlet, wtxt.substr(0, mini(260, wtxt.length())).replace("\n", " | ")])
			if not gun_invlet.is_empty():
				gen = await _send_char(eng, gun_invlet, int(eng.get_generation()), 4.0)
				await _wait_frames(5)
			for _esc2 in range(3):
				var ws_w: Dictionary = eng.poll_world_snapshot()
				var wid_now := str(ws_w.get("wielded", ""))
				if bool(eng.poll_terminal_frame().get("has_terrain", false)) and ("m4" in wid_now or "carbine" in wid_now):
					break
				gen = await _send_code(eng, 27, "", int(eng.get_generation()), 2.0)
				await _wait_frames(3)
			var ws_gun: Dictionary = eng.poll_world_snapshot()
			var wielded_gun := str(ws_gun.get("wielded", ""))
			print("[INFO] Wielded weapon for burst gunfire test: '%s'" % wielded_gun)
			if "m4" in wielded_gun or "carbine" in wielded_gun:
				# Reload M4A1 with the spawned loaded STANAG magazine ('r' + confirm if menu opens)
				gen = await _send_char(eng, "r", int(eng.get_generation()), 4.0)
				await _wait_frames(5)
				var rtxt := _extract_screen_text(eng.poll_terminal_frame())
				if "弹匣" in rtxt or "STANAG" in rtxt or "Reload" in rtxt or "选择" in rtxt or not bool(eng.poll_terminal_frame().get("has_terrain", false)):
					gen = await _send_code(eng, 10, "\n", int(eng.get_generation()), 4.0)
					await _wait_frames(6)
				# Wait out reload activity
				for _rw in range(30):
					await _wait_frames(2)
					if bool(eng.poll_terminal_frame().get("has_terrain", false)):
						var rltxt := _extract_screen_text(eng.poll_terminal_frame())
						if not ("装填" in rltxt and "%" in rltxt):
							break
				# Switch firing mode from semi -> burst/auto ('F') so we verify REAL burst cadence & continuous burst audio!
				gen = await _send_key_shift(eng, "F", int(eng.get_generation()), 3.0)
				await _wait_frames(4)
				# Open Aim ('f'), aim 6 tiles east, and fire burst ('f')!
				gen = await _send_char(eng, "f", int(eng.get_generation()), 4.0)
				await _wait_frames(4)
				for _aim in range(6):
					gen = await _send_char(eng, "l", int(eng.get_generation()), 2.0)
				var guns_before: int = int(host._combat_audio.total_gunshots_played)
				eng.send_key(ord("f"), "f", false, false, false)
				# Poll over 50 frames (~800ms) to capture live photorealistic muzzle flash + burst audio continuity!
				var saw_vfx_types: Array[int] = []
				var saw_vfx_light := false
				var gun_shot_taken := false
				var burst_delays: Array[int] = []
				for _f in range(50):
					await process_frame
					var ws_v: Dictionary = eng.poll_world_snapshot()
					for ve_var in ws_v.get("vfx_events", []):
						var vd: Dictionary = ve_var
						var vk := int(vd.get("kind", 0))
						if not saw_vfx_types.has(vk):
							saw_vfx_types.append(vk)
						if vk == 1:
							var dms := int(vd.get("delay_ms", 0))
							if not burst_delays.has(dms):
								burst_delays.append(dms)
					var fx_lights: Array = host._gpu_view._effects.get_active_vfx_lights()
					if not fx_lights.is_empty():
						saw_vfx_light = true
						if not gun_shot_taken:
							gun_shot_taken = true
							var img_g := root.get_texture().get_image()
							img_g.save_png(ART_DIR.path_join("verify_native_11_gunfire_muzzle_flash.png"))
							print("[SHOT] verify_native_11_gunfire_muzzle_flash.png -> lights=%d vfx=%s" % [fx_lights.size(), str(saw_vfx_types)])
				var guns_played: int = int(host._combat_audio.total_gunshots_played) - guns_before
				var btimes: Array = host._combat_audio.last_burst_shot_times
				var intervals_ms: Array[int] = []
				for bi in range(1, btimes.size()):
					intervals_ms.append(int(round((float(btimes[bi]) - float(btimes[bi - 1])) * 1000.0)))
				print("[INFO] Burst Gunfire VFX & Audio telemetry: vfx=%s delays_ms=%s hdr_light=%s shots_played=%d burst_intervals_ms=%s" % [
					str(saw_vfx_types), str(burst_delays), str(saw_vfx_light), guns_played, str(intervals_ms)
				])
				_check(saw_vfx_types.has(1) and saw_vfx_light, "Weapon burst emits photorealistic muzzle flash, tracer VFX & live HDR GPU muzzle light")
				_check(guns_played >= 2 and intervals_ms.size() >= 1 and intervals_ms[0] >= 40 and intervals_ms[0] <= 260,
					"Burst gunfire plays continuous polyphonic gunshot audio with authentic cyclic RPM intervals (%s ms)" % str(intervals_ms))
			else:
				_check(false, "Failed to wield M4A1 for burst gunfire test (wielded='%s')" % wielded_gun)

			# 8f. Real CCB Grenade Explosion test: activate ('a') frag grenade -> throw ('t') 7 tiles east -> wait for detonation!
			gen = await _dismiss_debugmsg_if_any(eng)
			var blasts_before: int = int(host._gpu_view._effects.total_blasts)
			var expl_sfx_before: int = int(host._combat_audio.total_explosions_played)
			gen = await _send_char(eng, "a", int(eng.get_generation()), 4.0)
			await _wait_frames(5)
			var atxt := _extract_screen_text(eng.poll_terminal_frame())
			var gren_invlet := ""
			for aline in atxt.split("\n", false):
				if "手榴弹" in aline or "grenade" in aline.to_lower() or "M67" in aline:
					var tr := aline.strip_edges()
					if tr.length() >= 3 and tr[1] == " ":
						gren_invlet = tr[0]
						break
			print("[INFO] Activate menu grenade invlet='%s' sample=%s" % [gren_invlet, atxt.substr(0, mini(240, atxt.length())).replace("\n", " | ")])
			if not gren_invlet.is_empty():
				gen = await _send_char(eng, gren_invlet, int(eng.get_generation()), 4.0)
				await _wait_frames(4)
				var ptxt := _extract_screen_text(eng.poll_terminal_frame())
				if "Y" in ptxt or "拔" in ptxt or "引爆" in ptxt or "pull" in ptxt.to_lower() or "扔" in ptxt:
					gen = await _send_char(eng, "y", int(eng.get_generation()), 3.0)
					await _wait_frames(4)
				# If pulling the pin immediately opened throwing target mode ('Throw where?'), aim 7 tiles east and Enter; else press 't'!
				var tmode_txt := _extract_screen_text(eng.poll_terminal_frame())
				if not ("扔" in tmode_txt or "投掷" in tmode_txt or "Throw" in tmode_txt):
					gen = await _send_char(eng, "t", int(eng.get_generation()), 4.0)
					await _wait_frames(5)
					var ttxt := _extract_screen_text(eng.poll_terminal_frame())
					var act_invlet := ""
					for tline in ttxt.split("\n", false):
						if "手榴弹" in tline or "grenade" in tline.to_lower() or "M67" in tline:
							var tr := tline.strip_edges()
							if tr.length() >= 3 and tr[1] == " ":
								act_invlet = tr[0]
								break
					if not act_invlet.is_empty():
						gen = await _send_char(eng, act_invlet, int(eng.get_generation()), 4.0)
						await _wait_frames(4)
				for _th in range(6):
					gen = await _send_char(eng, "l", int(eng.get_generation()), 2.0)
				gen = await _send_code(eng, 10, "\n", int(eng.get_generation()), 4.0)
				await _wait_frames(4)
				# Step back 2 tiles west ('h') and wait '.' turn by turn until the grenade detonates!
				gen = await _send_char(eng, "h", int(eng.get_generation()), 3.0)
				gen = await _send_char(eng, "h", int(eng.get_generation()), 3.0)
				var expl_shot_taken := false
				for _fuse in range(10):
					eng.send_key(ord("."), ".", false, false, false)
					for _pf in range(14):
						await process_frame
						if int(host._gpu_view._effects.total_blasts) > blasts_before:
							# Advance 4 frames (~65ms) so turbulent fireballs + shockwave + billowing smoke + flying embers are at peak drama!
							await _wait_frames(4)
							if not expl_shot_taken:
								expl_shot_taken = true
								var img_e := root.get_texture().get_image()
								img_e.save_png(ART_DIR.path_join("verify_native_12_explosion_vfx.png"))
								print("[SHOT] verify_native_12_explosion_vfx.png -> blasts=%d expl_sfx=%d" % [
									int(host._gpu_view._effects.total_blasts) - blasts_before,
									int(host._combat_audio.total_explosions_played) - expl_sfx_before
								])
							break
					if expl_shot_taken:
						break
					gen = await _dismiss_debugmsg_if_any(eng)
				var blasts_seen: int = int(host._gpu_view._effects.total_blasts) - blasts_before
				var expl_sfx_seen: int = int(host._combat_audio.total_explosions_played) - expl_sfx_before
				print("[INFO] Real Grenade Explosion telemetry: blasts=%d expl_sfx=%d" % [blasts_seen, expl_sfx_seen])
				_check(blasts_seen >= 1 and expl_sfx_seen >= 1, "Real CCB grenade detonation triggers photorealistic fireball/smoke/shockwave VFX + explosion audio")
			else:
				_check(false, "Failed to find spawned frag grenade in activate menu")
		else:
			_check(false, "Debug menu failed to open via temporary test keybind")

	# 9. Switch back to Launcher -> enter Cangming (zero regression check!)
	host.deactivate_to_launcher()
	await _wait_frames(4)
	main.enter_pack("cangming", 20260415, "jianghu", "游侠")
	await _wait_frames(10)
	_check(not main.world.is_cataclysm_pack() and main.sidebar.visible, "Cangming core pack works cleanly with zero regression")
	await _shot("verify_native_08_cangming_ok.png")

	# Clean shutdown of CCB worker thread & restore user keybindings.json
	host.shutdown_engine()
	await _wait_frames(3)
	_check(not eng.is_running(), "CCB worker thread shut down cleanly")
	if kb_had_orig:
		var rf := FileAccess.open(kb_path, FileAccess.WRITE)
		if rf != null:
			rf.store_string(kb_orig_text)
			rf.close()
	elif FileAccess.file_exists(kb_path):
		DirAccess.remove_absolute(kb_path)

	if _failures == 0:
		print("ALL_NATIVE_CCB_CHECKS_PASSED")
		quit(0)
	else:
		printerr("NATIVE_CCB_CHECKS_FAILED: %d failures" % _failures)
		quit(1)
