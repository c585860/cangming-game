extends Control

# Dual-Channel Host Controller for the embedded real Cataclysm-Cleanwater-Bomb (CCB) engine.
# - Spawns ccb_bridge.dll (real 670-file CCB core: Main Menu, 51 Mods, 31 World Options,
#   true Overmap/Mapgen/Spawn, true FOV, vehicles, bionics, mutations, invlets, crafting, Lua).
# - Channel 1: CcbGpuViewport renders unmodified vanilla gfx/ tilesets + Godot 4.5 GPU
#   dynamic lighting, shadows, and rain/snow weather directly inside CCB's w_terrain cutout.
# - Channel 2: CcbTerminalOverlay renders 100% genuine CCB curses + ImTui UI/menus/sidebar.

signal return_to_launcher_requested()

const TerminalOverlay = preload("res://scripts/ccb_native/ccb_terminal_overlay.gd")
const GpuViewport = preload("res://scripts/ccb_native/ccb_gpu_viewport.gd")
const NativeMinimap = preload("res://scripts/ccb_native/ccb_native_minimap.gd")
const Tiles = preload("res://scripts/undead_tiles.gd")

const CELL_W := 8
const CELL_H := 16
const TOP_BAR_H := 26

# CCB special key constants (must match ccb_bridge_api.h / CCB input.h)
const CCB_KEY_ESCAPE := 27
const CCB_KEY_TAB := 9
const CCB_KEY_ENTER := 10
const CCB_KEY_DOWN := 0x102
const CCB_KEY_UP := 0x103
const CCB_KEY_LEFT := 0x104
const CCB_KEY_RIGHT := 0x105
const CCB_KEY_HOME := 0x106
const CCB_KEY_BACKSPACE := 0x107
const CCB_KEY_F0 := 0x108
const CCB_KEY_DC := 0x14A
const CCB_KEY_NPAGE := 0x152
const CCB_KEY_PPAGE := 0x153
const CCB_KEY_BTAB := 0x161
const CCB_KEY_END := 0x168

var engine: RefCounted
var active := false
var _last_gen := -1
var _grid_cols := 160
var _grid_rows := 45
var _last_terrain_rect := Rect2i()
var _has_terrain := false
var _use_tiles := true
var _last_tileset_key := ""
var _looks_like_loaded := false
var _last_hover_cell := Vector2i(-1, -1)
var _last_hover_ms := 0
var _terrain_unoccluded := false
var _ui_font: Font

var _bg: ColorRect
var _top_bar_panel: PanelContainer
var _canvas_root: Control
var _gpu_view: GpuViewport
var _term_overlay: TerminalOverlay
var _minimap: NativeMinimap
var _loading_overlay: ColorRect
var _loading_lbl: Label
var _host_bar: HBoxContainer
var _minimap_btn: Button
var _launcher_btn: Button


func build(font: Font) -> void:
	_ui_font = font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	# Dedicated slim 26px top host strip (ZERO overlap with CCB's top sidebar rows!)
	_build_host_toolbar()

	# CCB dual-channel canvas cleanly below the top host bar (y = TOP_BAR_H .. height)
	_canvas_root = Control.new()
	_canvas_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_root.anchor_left = 0.0
	_canvas_root.anchor_right = 1.0
	_canvas_root.anchor_top = 0.0
	_canvas_root.anchor_bottom = 1.0
	_canvas_root.offset_top = TOP_BAR_H
	add_child(_canvas_root)

	# Channel 1: Godot 4.5 GPU-lit vanilla tileset viewport (positioned over w_terrain cutout)
	_gpu_view = GpuViewport.new()
	_gpu_view.visible = false
	_canvas_root.add_child(_gpu_view)
	_gpu_view.build(_ui_font)

	# Channel 2: Genuine CCB curses + ImTui terminal layer (w_terrain cells left transparent!)
	_term_overlay = TerminalOverlay.new()
	_term_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_term_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_root.add_child(_term_overlay)
	_term_overlay.configure_font(_ui_font, CELL_W, CELL_H)

	# Native CCB Pixel Minimap dock (bottom-left of GPU viewport, never overlaps CCB sidebar/log!)
	_minimap = NativeMinimap.new()
	_canvas_root.add_child(_minimap)

	# Loading curtain while CCB loads static JSON/Lua data (~1-2s on first launch)
	_loading_overlay = ColorRect.new()
	_loading_overlay.color = Color(0.0, 0.0, 0.0, 0.96)
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_root.add_child(_loading_overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.add_child(cc)
	_loading_lbl = Label.new()
	_loading_lbl.text = "正在启动《大灾变：净水炸弹》原生 C++ 核心引擎..."
	_loading_lbl.add_theme_font_size_override("font_size", 16)
	_loading_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	cc.add_child(_loading_lbl)

	resized.connect(_on_resized)
	set_process(true)


func _build_host_toolbar() -> void:
	_top_bar_panel = PanelContainer.new()
	_top_bar_panel.anchor_left = 0.0
	_top_bar_panel.anchor_right = 1.0
	_top_bar_panel.anchor_top = 0.0
	_top_bar_panel.anchor_bottom = 0.0
	_top_bar_panel.offset_bottom = TOP_BAR_H
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.05, 1.0)
	sb.border_color = Color(0.24, 0.24, 0.28, 1.0)
	sb.border_width_bottom = 1
	sb.set_content_margin_all(2)
	_top_bar_panel.add_theme_stylebox_override("panel", sb)
	add_child(_top_bar_panel)

	_host_bar = HBoxContainer.new()
	_host_bar.add_theme_constant_override("separation", 6)
	_top_bar_panel.add_child(_host_bar)

	var brand := Label.new()
	brand.text = " Cataclysm: Cleanwater Bomb 原生内核 · 写实物理光影/全局反射GI · 贴图请在游戏内 [选项 → 图像 → 选择图块集] 切换"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_font_size_override("font_size", 11)
	brand.add_theme_color_override("font_color", Color(0.62, 0.72, 0.82))
	_host_bar.add_child(brand)

	_minimap_btn = Button.new()
	_minimap_btn.text = "小地图 (F9)"
	_minimap_btn.focus_mode = Control.FOCUS_NONE
	_minimap_btn.add_theme_font_size_override("font_size", 11)
	_minimap_btn.pressed.connect(func():
		_minimap.toggle_enabled()
		_last_gen = -1)
	_host_bar.add_child(_minimap_btn)

	_launcher_btn = Button.new()
	_launcher_btn.text = "切换核心包 (F12)"
	_launcher_btn.focus_mode = Control.FOCUS_NONE
	_launcher_btn.add_theme_font_size_override("font_size", 11)
	_launcher_btn.pressed.connect(func():
		deactivate_to_launcher())
	_host_bar.add_child(_launcher_btn)


static func resolve_ccb_root() -> String:
	var proj := ProjectSettings.globalize_path("res://").simplify_path()
	return proj.path_join("../Cataclysm-Cleanwater-Bomb").simplify_path()


static func resolve_ccb_user_dir() -> String:
	var udir := ProjectSettings.globalize_path("user://ccb_native_user").simplify_path()
	DirAccess.make_dir_recursive_absolute(udir)
	return udir


func activate() -> bool:
	if engine == null:
		if not ClassDB.class_exists(&"CcbEngine"):
			_loading_lbl.text = "错误：CcbEngine GDExtension 类未注册（请重新编译 cangling.dll）。"
			visible = true
			return false
		engine = ClassDB.instantiate(&"CcbEngine")

	_compute_grid_size()
	var base_dir := resolve_ccb_root()
	var user_dir := resolve_ccb_user_dir()

	visible = true
	active = true
	_loading_overlay.visible = true
	_loading_lbl.text = "正在载入《大灾变：净水炸弹》原生内核与全部原版模组/数据..."
	_last_gen = -1

	if not engine.is_running():
		var ok: bool = bool(engine.start(base_dir, user_dir, _grid_cols, _grid_rows))
		if not ok:
			_loading_lbl.text = "无法启动 CCB 原生引擎：%s" % str(engine.get_last_error())
			return false
	else:
		engine.resize(_grid_cols, _grid_rows)
		if engine.is_waiting_resume():
			engine.resume_session()

	grab_focus()
	return true


func deactivate_to_launcher() -> void:
	active = false
	visible = false
	return_to_launcher_requested.emit()


func shutdown_engine() -> void:
	active = false
	if engine != null:
		engine.shutdown()


func _compute_grid_size() -> void:
	var vw := maxi(640, int(size.x))
	var vh := maxi(384, int(size.y) - TOP_BAR_H)
	@warning_ignore("integer_division")
	_grid_cols = maxi(80, vw / CELL_W)
	@warning_ignore("integer_division")
	_grid_rows = maxi(24, vh / CELL_H)


func _on_resized() -> void:
	_compute_grid_size()
	if active and engine != null and engine.is_running():
		engine.resize(_grid_cols, _grid_rows)
	_sync_terrain_rect()


func _sync_terrain_rect() -> void:
	if not _use_tiles or not _has_terrain or _last_terrain_rect.size.x <= 0 or _last_terrain_rect.size.y <= 0:
		_gpu_view.visible = false
		return
	var px_pos := Vector2(float(_last_terrain_rect.position.x * CELL_W), float(_last_terrain_rect.position.y * CELL_H))
	var px_size := Vector2(float(_last_terrain_rect.size.x * CELL_W), float(_last_terrain_rect.size.y * CELL_H))
	_gpu_view.position = px_pos
	_gpu_view.size = px_size
	_gpu_view.visible = true


func _sync_native_tileset_option() -> void:
	if engine == null or not engine.has_method("get_tileset_config"):
		return
	if not _looks_like_loaded and engine.has_method("get_looks_like_map"):
		var ll_map: Dictionary = engine.get_looks_like_map()
		if not ll_map.is_empty():
			Tiles.set_looks_like_map(ll_map)
			_looks_like_loaded = true
	var cfg: Dictionary = engine.get_tileset_config()
	if not bool(cfg.get("valid", false)):
		return
	var want_tiles := bool(cfg.get("use_tiles", true))
	var ts_name := str(cfg.get("name", ""))
	var ts_dir := str(cfg.get("dir", ""))
	var ts_json := str(cfg.get("json_file", "tile_config.json"))
	var key := "%s|%s|%s|%s" % [str(want_tiles), ts_name, ts_dir, ts_json]
	if key == _last_tileset_key:
		return
	_last_tileset_key = key
	_use_tiles = want_tiles
	if _term_overlay != null and _term_overlay.has_method("set_cutout_enabled"):
		_term_overlay.set_cutout_enabled(_use_tiles)
	if _use_tiles and not ts_dir.is_empty():
		_gpu_view.apply_tileset_dir(ts_dir, ts_json, ts_name)
	_sync_terrain_rect()


func _process(_delta: float) -> void:
	if not active or engine == null:
		return

	if engine.is_waiting_resume():
		deactivate_to_launcher()
		return

	var status := str(engine.get_status())
	if status.begins_with("error:"):
		_loading_overlay.visible = true
		_loading_lbl.text = "CCB 引擎错误：%s" % status
		return

	var gen: int = int(engine.get_generation())
	if gen <= 0:
		_loading_overlay.visible = true
		_loading_lbl.text = "正在载入《大灾变：净水炸弹》原生内核 (%s)..." % status
		return

	if _loading_overlay.visible:
		_loading_overlay.visible = false

	if gen == _last_gen:
		return
	_last_gen = gen

	# Sync native CCB Options -> Graphics -> Tileset (live hot-reload whenever user changes it in CCB Settings!)
	_sync_native_tileset_option()

	var term_frame: Dictionary = engine.poll_terminal_frame()
	if bool(term_frame.get("valid", false)):
		_term_overlay.update_frame(term_frame)
		_has_terrain = bool(term_frame.get("has_terrain", false))
		_last_terrain_rect = term_frame.get("terrain_rect", Rect2i())
		_sync_terrain_rect()

		if _has_terrain and _use_tiles:
			if not _looks_like_loaded and engine.has_method("get_looks_like_map"):
				var ll_map: Dictionary = engine.get_looks_like_map()
				if ll_map.size() > 100:
					Tiles.set_looks_like_map(ll_map)
					_looks_like_loaded = true
			var wsnap: Dictionary = engine.poll_world_snapshot()
			_gpu_view.update_world_snapshot(wsnap)
			var ter_px := Rect2(_gpu_view.position, _gpu_view.size)
			_terrain_unoccluded = _is_terrain_corner_unoccluded(term_frame)
			if _terrain_unoccluded:
				_minimap.update_minimap(wsnap, ter_px)
			else:
				_minimap.visible = false
		else:
			_terrain_unoccluded = false
			_gpu_view.visible = false
			_minimap.visible = false


func _is_terrain_corner_unoccluded(term_frame: Dictionary) -> bool:
	# Hide pixel minimap automatically whenever a modal dialog (Inventory, Esc menu, etc.) covers the map
	var tcols := int(term_frame.get("cols", 0))
	var trows := int(term_frame.get("rows", 0))
	var tcells: PackedByteArray = term_frame.get("cells", PackedByteArray())
	if tcols <= 0 or trows <= 0 or tcells.size() < tcols * trows * 16:
		return false
	var tr: Rect2i = term_frame.get("terrain_rect", Rect2i())
	if tr.size.x < 24 or tr.size.y < 14:
		return false
	# Check bottom-left area AND center of w_terrain — if covered by a modal, hide minimap
	var check_pts := [
		Vector2i(tr.position.x + 2, tr.position.y + tr.size.y - 2),
		Vector2i(tr.position.x + 18, tr.position.y + tr.size.y - 6),
		Vector2i(tr.position.x + tr.size.x / 2, tr.position.y + tr.size.y / 2),
	]
	for p: Vector2i in check_pts:
		if p.x < 0 or p.y < 0 or p.x >= tcols or p.y >= trows:
			return false
		var off := (p.y * tcols + p.x) * 16
		if (tcells.decode_u8(off + 13) & 0x01) == 0:
			return false
	return true


func _input(event: InputEvent) -> void:
	if not active or not visible or engine == null or not engine.is_running():
		return

	if event is InputEventKey:
		var kev: InputEventKey = event
		if not kev.pressed:
			return
		# F12 returns cleanly to the Core Pack Launcher (so user can switch to Cangming anytime)
		if kev.keycode == KEY_F12:
			deactivate_to_launcher()
			get_viewport().set_input_as_handled()
			return
		# F9 toggles native Pixel Minimap dock
		if kev.keycode == KEY_F9:
			_minimap.toggle_enabled()
			_last_gen = -1
			get_viewport().set_input_as_handled()
			return
		# Ctrl+= / Ctrl+- zooms the GPU tilemap viewport without colliding with CCB keys!
		if kev.ctrl_pressed and (kev.keycode == KEY_EQUAL or kev.keycode == KEY_KP_ADD):
			_gpu_view.adjust_zoom(1)
			get_viewport().set_input_as_handled()
			return
		if kev.ctrl_pressed and (kev.keycode == KEY_MINUS or kev.keycode == KEY_KP_SUBTRACT):
			_gpu_view.adjust_zoom(-1)
			get_viewport().set_input_as_handled()
			return

		var mapped := _translate_godot_key(kev)
		var kc: int = int(mapped[0])
		var txt: String = str(mapped[1])
		if kc != 0 or not txt.is_empty():
			engine.send_key(kc, txt, kev.ctrl_pressed, kev.alt_pressed, kev.shift_pressed)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton:
		var mev: InputEventMouseButton = event
		# Allow top host bar clicks to pass through normally
		if _top_bar_panel.get_global_rect().has_point(mev.global_position):
			return
		if _has_terrain and _use_tiles and _terrain_unoccluded and _gpu_view.visible and _gpu_view.get_global_rect().has_point(mev.global_position):
			if mev.pressed and mev.button_index == MOUSE_BUTTON_WHEEL_UP:
				_gpu_view.adjust_zoom(1)
				get_viewport().set_input_as_handled()
				return
			if mev.pressed and mev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_gpu_view.adjust_zoom(-1)
				get_viewport().set_input_as_handled()
				return
		var cell := _map_mouse_to_ccb_cell(mev.global_position, mev.position)
		var act := -1
		if mev.button_index == MOUSE_BUTTON_LEFT:
			act = 1 if mev.pressed else 2
		elif mev.button_index == MOUSE_BUTTON_RIGHT:
			act = 3 if mev.pressed else 4
		elif mev.pressed and mev.button_index == MOUSE_BUTTON_WHEEL_UP:
			act = 5
		elif mev.pressed and mev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			act = 6
		if act >= 0:
			engine.send_mouse(act, cell.x, cell.y, 0)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _top_bar_panel.get_global_rect().has_point(mm.global_position):
			return
		var cell := _map_mouse_to_ccb_cell(mm.global_position, mm.position)
		if cell != _last_hover_cell:
			# Keep modal/ImTui menu hover instant; throttle free-roam map hover so waving the mouse
			# never floods CCB's worker thread with redundant world snapshots!
			var now_ms := Time.get_ticks_msec()
			if (not _terrain_unoccluded) or (mm.button_mask != 0) or (now_ms - _last_hover_ms >= 90):
				_last_hover_cell = cell
				_last_hover_ms = now_ms
				engine.send_mouse(0, cell.x, cell.y, 0)


func _map_mouse_to_ccb_cell(global_pos: Vector2, local_pos: Vector2) -> Vector2i:
	# When hovering/clicking directly on the GPU tilemap with no modal covering it,
	# map GPU tile coords -> exact w_terrain curses cell so click-to-walk & path preview match 1:1!
	if _has_terrain and _use_tiles and _terrain_unoccluded and _gpu_view.visible and _gpu_view.get_global_rect().has_point(global_pos):
		var world_tile := _gpu_view.screen_to_world_tile(global_pos)
		var center_tile := _gpu_view.get_view_center_tile()
		@warning_ignore("integer_division")
		var posx := _last_terrain_rect.size.x / 2
		@warning_ignore("integer_division")
		var posy := _last_terrain_rect.size.y / 2
		var tx := _last_terrain_rect.position.x + posx + (world_tile.x - center_tile.x)
		var ty := _last_terrain_rect.position.y + posy + (world_tile.y - center_tile.y)
		return Vector2i(
			clampi(tx, _last_terrain_rect.position.x, _last_terrain_rect.end.x - 1),
			clampi(ty, _last_terrain_rect.position.y, _last_terrain_rect.end.y - 1)
		)
	var lp := local_pos - Vector2(0.0, float(TOP_BAR_H))
	@warning_ignore("integer_division")
	var cx := clampi(int(lp.x) / CELL_W, 0, maxi(0, _grid_cols - 1))
	@warning_ignore("integer_division")
	var cy := clampi(int(lp.y) / CELL_H, 0, maxi(0, _grid_rows - 1))
	return Vector2i(cx, cy)


static func _translate_godot_key(ev: InputEventKey) -> Array:
	match ev.keycode:
		KEY_ESCAPE:    return [CCB_KEY_ESCAPE, ""]
		KEY_ENTER:     return [CCB_KEY_ENTER, "\n"]
		KEY_KP_ENTER:  return [CCB_KEY_ENTER, "\n"]
		KEY_TAB:       return [CCB_KEY_BTAB if ev.shift_pressed else CCB_KEY_TAB, "\t"]
		KEY_BACKSPACE: return [CCB_KEY_BACKSPACE, ""]
		KEY_DELETE:    return [CCB_KEY_DC, ""]
		KEY_UP:        return [CCB_KEY_UP, ""]
		KEY_DOWN:      return [CCB_KEY_DOWN, ""]
		KEY_LEFT:      return [CCB_KEY_LEFT, ""]
		KEY_RIGHT:     return [CCB_KEY_RIGHT, ""]
		KEY_HOME:      return [CCB_KEY_HOME, ""]
		KEY_END:       return [CCB_KEY_END, ""]
		KEY_PAGEUP:    return [CCB_KEY_PPAGE, ""]
		KEY_PAGEDOWN:  return [CCB_KEY_NPAGE, ""]
		KEY_KP_0:      return [ord("0"), "0"]
		KEY_KP_1:      return [ord("1"), "1"]
		KEY_KP_2:      return [ord("2"), "2"]
		KEY_KP_3:      return [ord("3"), "3"]
		KEY_KP_4:      return [ord("4"), "4"]
		KEY_KP_5:      return [ord("5"), "5"]
		KEY_KP_6:      return [ord("6"), "6"]
		KEY_KP_7:      return [ord("7"), "7"]
		KEY_KP_8:      return [ord("8"), "8"]
		KEY_KP_9:      return [ord("9"), "9"]
		KEY_KP_PERIOD: return [ord("."), "."]
		KEY_KP_ADD:    return [ord("+"), "+"]
		KEY_KP_SUBTRACT: return [ord("-"), "-"]
		KEY_KP_MULTIPLY: return [ord("*"), "*"]
		KEY_KP_DIVIDE: return [ord("/"), "/"]
		_:
			pass

	if ev.keycode >= KEY_F1 and ev.keycode <= KEY_F11:
		return [CCB_KEY_F0 + (ev.keycode - KEY_F1 + 1), ""]

	# Ctrl+A..Z control codes (1..26)
	if ev.ctrl_pressed and ev.keycode >= KEY_A and ev.keycode <= KEY_Z:
		return [ev.keycode - KEY_A + 1, ""]

	if ev.unicode > 0:
		var ch_s := char(ev.unicode)
		return [ev.unicode, ch_s]

	# Fallback when OS/IME reports unicode==0 on Shift+digit/symbol/letter (e.g. Shift+1 -> '!')
	if not ev.ctrl_pressed and not ev.alt_pressed:
		if ev.shift_pressed:
			match ev.keycode:
				KEY_1: return [ord("!"), "!"]
				KEY_2: return [ord("@"), "@"]
				KEY_3: return [ord("#"), "#"]
				KEY_4: return [ord("$"), "$"]
				KEY_5: return [ord("%"), "%"]
				KEY_6: return [ord("^"), "^"]
				KEY_7: return [ord("&"), "&"]
				KEY_8: return [ord("*"), "*"]
				KEY_9: return [ord("("), "("]
				KEY_0: return [ord(")"), ")"]
				KEY_MINUS: return [ord("_"), "_"]
				KEY_EQUAL: return [ord("+"), "+"]
				KEY_BRACKETLEFT: return [ord("{"), "{"]
				KEY_BRACKETRIGHT: return [ord("}"), "}"]
				KEY_BACKSLASH: return [ord("|"), "|"]
				KEY_SEMICOLON: return [ord(":"), ":"]
				KEY_APOSTROPHE: return [ord("\""), "\""]
				KEY_COMMA: return [ord("<"), "<"]
				KEY_PERIOD: return [ord(">"), ">"]
				KEY_SLASH: return [ord("?"), "?"]
				KEY_QUOTELEFT: return [ord("~"), "~"]
				_:
					if ev.keycode >= KEY_A and ev.keycode <= KEY_Z:
						var uc := ord("A") + (ev.keycode - KEY_A)
						return [uc, char(uc)]
		elif ev.keycode >= KEY_A and ev.keycode <= KEY_Z:
			var lc := ord("a") + (ev.keycode - KEY_A)
			return [lc, char(lc)]
		elif ev.keycode >= KEY_0 and ev.keycode <= KEY_9:
			var dc := ord("0") + (ev.keycode - KEY_0)
			return [dc, char(dc)]

	return [0, ""]
