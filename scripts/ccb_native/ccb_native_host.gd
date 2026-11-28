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
const Viewport3D = preload("res://scripts/ccb_native/ccb_viewport_3d.gd")
const NativeMinimap = preload("res://scripts/ccb_native/ccb_native_minimap.gd")
const CombatAudio = preload("res://scripts/ccb_native/ccb_combat_audio.gd")
const AmbienceAudio = preload("res://scripts/ccb_native/ccb_ambience_audio.gd")
const Tiles = preload("res://scripts/undead_tiles.gd")

const CELL_W_DEFAULT := 8
const CELL_H_DEFAULT := 16
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
var _last_world_gen := -1
var _last_scene3d_gen := -1
var _last_audio_gen := -1
var _last_wsnap: Dictionary = {}
var _world_view_dirty := true
var _tile_trim_accum := 0.0
var _idle_sec := 0.0
var _window_focused := true
var _base_max_fps := 0
var _fps_throttle_disabled := false

# Performance telemetry counters (for automated benchmarking & diagnostics)
var term_polls := 0
var world_polls := 0
var scene3d_polls := 0
var tile_pages_trimmed := 0
var _cell_w := CELL_W_DEFAULT
var _cell_h := CELL_H_DEFAULT
var _grid_cols := 160
var _grid_rows := 43
var _pending_resize := false
var _resize_debounce := 0.0
var _last_terrain_rect := Rect2i()
var _has_terrain := false
var _use_tiles := true
var _last_tileset_key := ""
var _looks_like_loaded := false
var _last_hover_cell := Vector2i(-1, -1)
var _last_hover_ms := 0
var _terrain_unoccluded := false
var _ui_font: Font
var _want_text_input := false
var _manual_ime := false
var _ime_active := false
var _ime_cursor := Vector2i(0, 0)
var _loading_active := false
var _loading_seq := -1
var _loading_anim_t := 0.0
var _loading_img_path := ""
var _loading_img_cache: Dictionary = {}

var _bg: ColorRect
var _top_bar_panel: PanelContainer
var _canvas_root: Control
var _gpu_view: GpuViewport
var _view_3d: Viewport3D
var _render_3d := false
var _orbit_rmb_down := false
var _orbit_rmb_dragged := false
var _orbit_rmb_start := Vector2.ZERO
var _term_overlay: TerminalOverlay
var _minimap: NativeMinimap
var _menu_credits_panel: PanelContainer
var _combat_audio: CombatAudio
var _ambience_audio: AmbienceAudio
var _loading_overlay: ColorRect
var _loading_tex_rect: TextureRect
var _loading_tip_lbl: Label
var _loading_prog_bar: Control
var _loading_lbl: Label
var _host_bar: HBoxContainer
var _mode3d_btn: Button
var _same_lvl_btn: Button
var _dither_btn: Button
var _reset_cam_btn: Button
var _sfx_btn: Button
var _ime_btn: Button
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

	# Channel 1a: Godot 4.5 2D GPU-lit vanilla tileset viewport (positioned over w_terrain cutout)
	_gpu_view = GpuViewport.new()
	_gpu_view.visible = false
	_canvas_root.add_child(_gpu_view)
	_gpu_view.build(_ui_font)
	_gpu_view.capture_radius_changed.connect(_on_capture_radius_changed)

	# Channel 1b: 3D Viewport is lazily instantiated ONLY when user enables 3D mode (F7), saving RAM/VRAM in 2D!
	_view_3d = null

	# Channel 2: Genuine CCB curses + ImTui terminal layer (w_terrain cells left transparent!)
	_term_overlay = TerminalOverlay.new()
	_term_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_term_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_root.add_child(_term_overlay)
	_term_overlay.configure_font(_ui_font, _cell_w, _cell_h)

	# Native CCB Main Menu Community Credits Footer (auto-shown ONLY on the opening Main Menu, zero overlap!)
	_menu_credits_panel = PanelContainer.new()
	_menu_credits_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_credits_panel.visible = false
	_menu_credits_panel.anchor_left = 0.0
	_menu_credits_panel.anchor_right = 1.0
	_menu_credits_panel.anchor_top = 1.0
	_menu_credits_panel.anchor_bottom = 1.0
	_menu_credits_panel.offset_top = -62
	_menu_credits_panel.offset_bottom = -4
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.02, 0.03, 0.05, 0.82)
	csb.border_color = Color(0.18, 0.36, 0.62, 0.65)
	csb.border_width_top = 1
	csb.content_margin_left = 16
	csb.content_margin_right = 16
	csb.content_margin_top = 4
	csb.content_margin_bottom = 4
	_menu_credits_panel.add_theme_stylebox_override("panel", csb)
	var credits_lbl := Label.new()
	credits_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits_lbl.text = "本项目灵感来源于CCB，本项目QQ群：1001568760\nCCB群：552610319\n感谢所有玩家的奉献"
	credits_lbl.add_theme_font_size_override("font_size", 12)
	credits_lbl.add_theme_color_override("font_color", Color(0.76, 0.88, 1.0))
	credits_lbl.add_theme_constant_override("line_spacing", 1)
	_menu_credits_panel.add_child(credits_lbl)
	_canvas_root.add_child(_menu_credits_panel)

	# Native CCB Pixel Minimap dock (bottom-left of GPU viewport, never overlaps CCB sidebar/log!)
	_minimap = NativeMinimap.new()
	_canvas_root.add_child(_minimap)

	# Realistic 44.1/22.05 kHz Polyphonic Combat & Dynamic World Ambience Audio Engines
	_combat_audio = CombatAudio.new()
	add_child(_combat_audio)
	_ambience_audio = AmbienceAudio.new()
	add_child(_ambience_audio)
	_base_max_fps = Engine.max_fps
	_fps_throttle_disabled = OS.get_cmdline_user_args().has("--no-fps-throttle") or OS.get_cmdline_args().has("--no-fps-throttle") or DisplayServer.get_name() == "headless"

	# Authentic Vanilla CCB Loading Screen (artwork from gfx/loading_screens/ + cyan daily tip + live progress bar!)
	_loading_overlay = ColorRect.new()
	_loading_overlay.color = Color(0.02, 0.025, 0.035, 1.0)
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_root.add_child(_loading_overlay)

	var load_vbox := VBoxContainer.new()
	load_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	load_vbox.add_theme_constant_override("separation", 0)
	_loading_overlay.add_child(load_vbox)

	var art_margin := MarginContainer.new()
	art_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_margin.add_theme_constant_override("margin_left", 24)
	art_margin.add_theme_constant_override("margin_right", 24)
	art_margin.add_theme_constant_override("margin_top", 16)
	art_margin.add_theme_constant_override("margin_bottom", 12)
	load_vbox.add_child(art_margin)

	_loading_tex_rect = TextureRect.new()
	_loading_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_loading_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_loading_tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loading_tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_margin.add_child(_loading_tex_rect)

	var bottom_panel := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.04, 0.05, 0.07, 0.94)
	bsb.border_color = Color(0.22, 0.34, 0.44, 0.75)
	bsb.border_width_top = 1
	bsb.content_margin_left = 28
	bsb.content_margin_right = 28
	bsb.content_margin_top = 12
	bsb.content_margin_bottom = 14
	bottom_panel.add_theme_stylebox_override("panel", bsb)
	load_vbox.add_child(bottom_panel)

	var hud_vbox := VBoxContainer.new()
	hud_vbox.add_theme_constant_override("separation", 8)
	bottom_panel.add_child(hud_vbox)

	_loading_tip_lbl = Label.new()
	_loading_tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loading_tip_lbl.text = ""
	_loading_tip_lbl.add_theme_font_size_override("font_size", 14)
	_loading_tip_lbl.add_theme_color_override("font_color", Color(0.45, 0.90, 0.98))
	hud_vbox.add_child(_loading_tip_lbl)

	_loading_prog_bar = Control.new()
	_loading_prog_bar.custom_minimum_size = Vector2(360.0, 8.0)
	_loading_prog_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loading_prog_bar.draw.connect(_draw_loading_progress_bar)
	hud_vbox.add_child(_loading_prog_bar)

	_loading_lbl = Label.new()
	_loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_lbl.text = "正在启动《大灾变：净水炸弹》原生 C++ 核心引擎..."
	_loading_lbl.add_theme_font_size_override("font_size", 13)
	_loading_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
	hud_vbox.add_child(_loading_lbl)

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

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host_bar.add_child(top_spacer)

	_mode3d_btn = Button.new()
	_mode3d_btn.text = "视角: 2D (F7)"
	_mode3d_btn.focus_mode = Control.FOCUS_NONE
	_mode3d_btn.add_theme_font_size_override("font_size", 11)
	_mode3d_btn.pressed.connect(func():
		toggle_render_3d())
	_host_bar.add_child(_mode3d_btn)

	_same_lvl_btn = Button.new()
	_same_lvl_btn.text = "同层: 关 (z)"
	_same_lvl_btn.visible = false
	_same_lvl_btn.focus_mode = Control.FOCUS_NONE
	_same_lvl_btn.add_theme_font_size_override("font_size", 11)
	_same_lvl_btn.pressed.connect(func():
		toggle_3d_same_level())
	_host_bar.add_child(_same_lvl_btn)

	_dither_btn = Button.new()
	_dither_btn.text = "透视: 开 (Z)"
	_dither_btn.visible = false
	_dither_btn.focus_mode = Control.FOCUS_NONE
	_dither_btn.add_theme_font_size_override("font_size", 11)
	_dither_btn.pressed.connect(func():
		toggle_3d_cursor_dither())
	_host_bar.add_child(_dither_btn)

	_reset_cam_btn = Button.new()
	_reset_cam_btn.text = "重置视角"
	_reset_cam_btn.visible = false
	_reset_cam_btn.focus_mode = Control.FOCUS_NONE
	_reset_cam_btn.add_theme_font_size_override("font_size", 11)
	_reset_cam_btn.pressed.connect(func():
		if _view_3d != null:
			_view_3d.reset_camera())
	_host_bar.add_child(_reset_cam_btn)

	_sfx_btn = Button.new()
	_sfx_btn.text = "音效: 开"
	_sfx_btn.focus_mode = Control.FOCUS_NONE
	_sfx_btn.add_theme_font_size_override("font_size", 11)
	_sfx_btn.pressed.connect(func():
		if _combat_audio != null:
			var m := _combat_audio.toggle_mute()
			if _ambience_audio != null:
				_ambience_audio.set_muted(m)
			_sfx_btn.text = "音效: 静音" if m else "音效: 开")
	_host_bar.add_child(_sfx_btn)

	_ime_btn = Button.new()
	_ime_btn.text = "输入法: 自动 (F8)"
	_ime_btn.focus_mode = Control.FOCUS_NONE
	_ime_btn.add_theme_font_size_override("font_size", 11)
	_ime_btn.pressed.connect(func():
		_manual_ime = not _manual_ime
		_sync_ime_state())
	_host_bar.add_child(_ime_btn)

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


static func _find_portable_release_root() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir().simplify_path()
	var c1 := exe_dir.path_join("ccb_data").simplify_path()
	if DirAccess.dir_exists_absolute(c1.path_join("data")):
		return exe_dir
	var parent_dir := exe_dir.path_join("..").simplify_path()
	var c2 := parent_dir.path_join("ccb_data").simplify_path()
	if DirAccess.dir_exists_absolute(c2.path_join("data")):
		return parent_dir
	return ""


static func resolve_ccb_root() -> String:
	# 1. Standalone player release package (<release>/ccb_data/)
	var rel_root := _find_portable_release_root()
	if not rel_root.is_empty():
		return rel_root.path_join("ccb_data").simplify_path()
	# 2. Consolidated local repo inside cangling-city/Cataclysm-Cleanwater-Bomb
	var proj := ProjectSettings.globalize_path("res://").simplify_path()
	var local_ccb := proj.path_join("Cataclysm-Cleanwater-Bomb").simplify_path()
	if DirAccess.dir_exists_absolute(local_ccb.path_join("data")):
		return local_ccb
	# 3. Legacy sibling fallback (../Cataclysm-Cleanwater-Bomb)
	return proj.path_join("../Cataclysm-Cleanwater-Bomb").simplify_path()


static func resolve_ccb_user_dir() -> String:
	var rel_root := _find_portable_release_root()
	if not rel_root.is_empty():
		var portable_user := rel_root.path_join("user_data").simplify_path()
		DirAccess.make_dir_recursive_absolute(portable_user)
		return portable_user
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

	if _combat_audio != null:
		_combat_audio.setup(engine)
	if _ambience_audio != null:
		_ambience_audio.setup(engine)

	_compute_grid_size()
	var base_dir := resolve_ccb_root()
	var user_dir := resolve_ccb_user_dir()

	visible = true
	active = true
	_loading_overlay.visible = true
	_ensure_default_loading_artwork()
	_loading_lbl.text = "正在载入《大灾变：净水炸弹》原生内核与全部原版模组/数据..."
	_last_gen = -1
	_last_world_gen = -1
	_last_scene3d_gen = -1
	_last_audio_gen = -1
	_last_wsnap = {}
	_world_view_dirty = true
	_note_activity()

	if not engine.is_running():
		var ok: bool = bool(engine.start(base_dir, user_dir, _grid_cols, _grid_rows))
		if not ok:
			_loading_lbl.text = "无法启动 CCB 原生引擎：%s" % str(engine.get_last_error())
			return false
	else:
		engine.resize(_grid_cols, _grid_rows)
		if engine.is_waiting_resume():
			engine.resume_session()
	if _gpu_view != null:
		var req_rad := _gpu_view.get_required_capture_radius()
		_on_capture_radius_changed(req_rad.x, req_rad.y)

	grab_focus()
	return true


func _ensure_view_3d() -> Viewport3D:
	if _view_3d != null:
		return _view_3d
	_view_3d = Viewport3D.new()
	_view_3d.visible = false
	_canvas_root.add_child(_view_3d)
	if _gpu_view != null and _gpu_view.get_parent() == _canvas_root:
		_canvas_root.move_child(_view_3d, _gpu_view.get_index() + 1)
	_view_3d.build(_ui_font)
	if _ambience_audio != null:
		_view_3d.lightning_flashed.connect(_ambience_audio.trigger_lightning_thunder)
	_sync_terrain_rect()
	return _view_3d


func _on_capture_radius_changed(rad_x: int, rad_y: int) -> void:
	if engine != null and engine.has_method("set_world_capture_radius"):
		engine.set_world_capture_radius(rad_x, rad_y)


func _clear_loading_image_cache() -> void:
	if _loading_tex_rect != null:
		_loading_tex_rect.texture = null
	_loading_img_cache.clear()
	_loading_img_path = ""


func _note_activity() -> void:
	_idle_sec = 0.0
	if not _fps_throttle_disabled and Engine.max_fps != _base_max_fps:
		Engine.max_fps = _base_max_fps


func _update_idle_fps_throttle(delta: float) -> void:
	if _fps_throttle_disabled:
		return
	var busy := false
	if _loading_active or _loading_overlay.visible:
		busy = true
	elif _render_3d and _view_3d != null and _view_3d.has_high_fps_activity():
		busy = true
	elif (not _render_3d) and _gpu_view != null and _gpu_view.has_high_fps_activity():
		busy = true
	if busy:
		_idle_sec = 0.0
	else:
		_idle_sec += delta
	var target_fps := _base_max_fps
	if not _window_focused:
		target_fps = 15
	elif _idle_sec >= 1.5:
		target_fps = 24
	if Engine.max_fps != target_fps:
		Engine.max_fps = target_fps


func deactivate_to_launcher() -> void:
	active = false
	visible = false
	if not _fps_throttle_disabled:
		Engine.max_fps = _base_max_fps
	if _ambience_audio != null:
		_ambience_audio.set_in_world(false)
	_clear_loading_image_cache()
	Tiles.clear_decoded_cache()
	_want_text_input = false
	_manual_ime = false
	_sync_ime_state()
	return_to_launcher_requested.emit()


func _draw_loading_progress_bar() -> void:
	if _loading_prog_bar == null:
		return
	var sz := _loading_prog_bar.size
	if sz.x <= 4.0 or sz.y <= 1.0:
		return
	var pad := maxf(24.0, sz.x * 0.14)
	var track := Rect2(pad, 1.0, maxf(60.0, sz.x - pad * 2.0), sz.y - 2.0)
	_loading_prog_bar.draw_rect(track, Color(0.10, 0.14, 0.20, 0.95))
	var phase := fmod(_loading_anim_t * 0.72, 1.4)
	var bar_w := track.size.x * 0.28
	var x0 := track.position.x + (phase - 0.2) * (track.size.x + bar_w * 0.4)
	var fill_l := clampf(x0, track.position.x, track.end.x)
	var fill_r := clampf(x0 + bar_w, track.position.x, track.end.x)
	if fill_r > fill_l:
		_loading_prog_bar.draw_rect(Rect2(fill_l, track.position.y, fill_r - fill_l, track.size.y), Color(0.32, 0.82, 0.98, 0.95))
		var core_l := lerpf(fill_l, fill_r, 0.25)
		var core_r := lerpf(fill_l, fill_r, 0.75)
		_loading_prog_bar.draw_rect(Rect2(core_l, track.position.y, core_r - core_l, track.size.y), Color(0.78, 0.96, 1.0, 0.95))
	_loading_prog_bar.draw_rect(track, Color(0.28, 0.44, 0.56, 0.85), false, 1.0)


func _load_loading_texture(img_path: String) -> Texture2D:
	if img_path.is_empty():
		return null
	var cached = _loading_img_cache.get(img_path)
	if cached != null:
		return cached
	var norm_path := img_path.replace("\\", "/")
	if not FileAccess.file_exists(norm_path):
		return null
	var img := Image.new()
	var err := img.load(norm_path)
	if err != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	_loading_img_cache[img_path] = tex
	return tex


func _ensure_default_loading_artwork() -> void:
	if _loading_tex_rect == null or _loading_tex_rect.texture != null:
		return
	var dir_path := resolve_ccb_root().path_join("gfx/loading_screens")
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	var imgs: Array[String] = []
	da.list_dir_begin()
	var fn := da.get_next()
	while not fn.is_empty():
		if not da.current_is_dir() and fn.to_lower().ends_with(".png"):
			imgs.append(dir_path.path_join(fn))
		fn = da.get_next()
	da.list_dir_end()
	if not imgs.is_empty():
		var chosen := imgs[Time.get_ticks_msec() % imgs.size()]
		var tex := _load_loading_texture(chosen)
		if tex != null:
			_loading_tex_rect.texture = tex
			_loading_img_path = chosen


func _update_loading_screen(delta: float) -> bool:
	var ls: Dictionary = engine.get_loading_state() if engine.has_method("get_loading_state") else {}
	var is_loading := bool(ls.get("active", false))
	_loading_active = is_loading
	if not is_loading:
		return false
	_loading_anim_t += delta
	_loading_overlay.visible = true
	if _loading_prog_bar != null:
		_loading_prog_bar.queue_redraw()
	var seq := int(ls.get("seq", 0))
	if seq != _loading_seq:
		_loading_seq = seq
		var ipath := str(ls.get("image_path", ""))
		if not ipath.is_empty() and ipath != _loading_img_path:
			var tex := _load_loading_texture(ipath)
			if tex != null:
				_loading_tex_rect.texture = tex
				_loading_img_path = ipath
		elif _loading_tex_rect.texture == null:
			_ensure_default_loading_artwork()
		var tip := str(ls.get("tip", ""))
		if not tip.is_empty():
			_loading_tip_lbl.text = tip
		var ctx := str(ls.get("context", ""))
		var stp := str(ls.get("step", ""))
		var msg := ("%s %s" % [ctx, stp]).strip_edges()
		if not msg.is_empty():
			_loading_lbl.text = msg
	return true


func _sync_ime_state() -> void:
	var want := active and visible and (_want_text_input or _manual_ime)
	var win := get_window()
	var win_id := win.get_window_id() if win != null else DisplayServer.MAIN_WINDOW_ID
	if want != _ime_active:
		_ime_active = want
		DisplayServer.window_set_ime_active(want, win_id)
		if not want:
			if _term_overlay != null:
				_term_overlay.set_ime_preedit("")
			if engine != null and engine.is_running() and engine.has_method("send_ime_edit"):
				engine.send_ime_edit("")
	if want:
		var xform := get_viewport().get_final_transform()
		var sc := xform.get_scale()
		var ox := xform.origin.x
		var oy := xform.origin.y
		var lx := clampf(float(_ime_cursor.x * _cell_w), 8.0, maxf(8.0, size.x - 40.0))
		var ly := clampf(float((_ime_cursor.y + 1) * _cell_h + TOP_BAR_H), float(TOP_BAR_H + _cell_h), maxf(float(TOP_BAR_H + _cell_h), size.y - 16.0))
		var ime_px := Vector2i(int(round(ox + lx * sc.x)), int(round(oy + ly * sc.y)))
		DisplayServer.window_set_ime_position(ime_px, win_id)
	if _ime_btn != null:
		if _manual_ime:
			_ime_btn.text = "输入法: 中文常开 (F8)"
		elif _want_text_input:
			_ime_btn.text = "输入法: 中文激活 (F8)"
		else:
			_ime_btn.text = "输入法: 自动 (F8)"


func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_IME_UPDATE:
		if not active or not visible or engine == null or not engine.is_running():
			return
		var preedit := DisplayServer.ime_get_text()
		if _term_overlay != null:
			_term_overlay.set_ime_preedit(preedit)
		if engine.has_method("send_ime_edit"):
			engine.send_ime_edit(preedit)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focused = true
		_note_activity()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focused = false
		if _term_overlay != null:
			_term_overlay.set_ime_preedit("")


func shutdown_engine() -> void:
	active = false
	if not _fps_throttle_disabled:
		Engine.max_fps = _base_max_fps
	if engine != null:
		engine.shutdown()


func _compute_grid_size() -> void:
	var vw := maxi(640, int(size.x))
	var vh := maxi(384, int(size.y) - TOP_BAR_H)
	# Keep crisp legible cell metrics across every resolution / aspect ratio (720p, 1080p, 2K, 4K, 16:10, 21:9)
	var target_ch := clampi(int(round(float(vh) / 43.0)), 14, 22)
	if (target_ch & 1) != 0:
		target_ch -= 1
	@warning_ignore("integer_division")
	var target_cw := maxi(7, target_ch / 2)
	if target_cw != _cell_w or target_ch != _cell_h:
		_cell_w = target_cw
		_cell_h = target_ch
		if _term_overlay != null:
			_term_overlay.configure_font(_ui_font, _cell_w, _cell_h)
	@warning_ignore("integer_division")
	_grid_cols = maxi(80, vw / _cell_w)
	@warning_ignore("integer_division")
	_grid_rows = maxi(24, vh / _cell_h)


func _on_resized() -> void:
	var prev_cols := _grid_cols
	var prev_rows := _grid_rows
	_compute_grid_size()
	if active and engine != null and engine.is_running() and (_grid_cols != prev_cols or _grid_rows != prev_rows):
		_pending_resize = true
		_resize_debounce = 0.055
	_sync_terrain_rect()


func _sync_terrain_rect() -> void:
	if not _use_tiles or not _has_terrain or _last_terrain_rect.size.x <= 0 or _last_terrain_rect.size.y <= 0:
		_gpu_view.visible = false
		if _view_3d != null:
			_view_3d.visible = false
		return
	var px_pos := Vector2(float(_last_terrain_rect.position.x * _cell_w), float(_last_terrain_rect.position.y * _cell_h))
	var px_size := Vector2(float(_last_terrain_rect.size.x * _cell_w), float(_last_terrain_rect.size.y * _cell_h))
	_gpu_view.position = px_pos
	_gpu_view.size = px_size
	if _view_3d != null:
		_view_3d.position = px_pos
		_view_3d.size = px_size
	_gpu_view.visible = not _render_3d
	if _view_3d != null:
		_view_3d.visible = _render_3d


func set_render_3d_enabled(enabled: bool) -> void:
	_render_3d = enabled
	_orbit_rmb_down = false
	_orbit_rmb_dragged = false
	if _render_3d:
		_ensure_view_3d()
	if _view_3d != null:
		_view_3d.set_orbit_dragging(false)
		if not _render_3d:
			_view_3d.release_idle_resources()
	if _mode3d_btn != null:
		_mode3d_btn.text = "视角: 3D (F7)" if _render_3d else "视角: 2D (F7)"
	if _same_lvl_btn != null:
		_same_lvl_btn.visible = _render_3d
	if _dither_btn != null:
		_dither_btn.visible = _render_3d
	if _reset_cam_btn != null:
		_reset_cam_btn.visible = _render_3d
	if engine != null and engine.has_method("set_render3d_mode"):
		engine.set_render3d_mode(_render_3d, _view_3d.same_level_only if _view_3d != null else false)
	_sync_terrain_rect()
	_world_view_dirty = true
	_last_scene3d_gen = -1
	_last_gen = -1
	_note_activity()


func toggle_render_3d() -> void:
	set_render_3d_enabled(not _render_3d)


func toggle_3d_same_level() -> void:
	if _view_3d == null:
		return
	var next := not _view_3d.same_level_only
	_view_3d.set_same_level_only(next)
	if _same_lvl_btn != null:
		_same_lvl_btn.text = "同层: 开 (z)" if next else "同层: 关 (z)"
	if engine != null and engine.has_method("set_render3d_mode"):
		engine.set_render3d_mode(_render_3d, next)
	_last_gen = -1


func toggle_3d_cursor_dither() -> void:
	if _view_3d == null:
		return
	var next := not _view_3d.cursor_dither_enabled
	_view_3d.set_cursor_dither(next)
	if _dither_btn != null:
		_dither_btn.text = "透视: 开 (Z)" if next else "透视: 关 (Z)"


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


func _process(delta: float) -> void:
	if not active or engine == null:
		return

	if engine.is_waiting_resume():
		deactivate_to_launcher()
		return

	# Flush debounced resolution-adaptive terminal resize smoothly after window drag settles
	if _pending_resize:
		_resize_debounce -= delta
		if _resize_debounce <= 0.0:
			_pending_resize = false
			if engine.is_running():
				engine.resize(_grid_cols, _grid_rows)

	var status := str(engine.get_status())
	if status.begins_with("error:"):
		_loading_overlay.visible = true
		_loading_lbl.text = "CCB 引擎错误：%s" % status
		return

	# Always render genuine vanilla CCB loading artwork + tip + live progress while world/character loads!
	if _update_loading_screen(delta):
		return

	var gen: int = int(engine.get_generation())
	if gen <= 0:
		_loading_anim_t += delta
		_loading_overlay.visible = true
		_ensure_default_loading_artwork()
		if _loading_prog_bar != null:
			_loading_prog_bar.queue_redraw()
		_loading_lbl.text = "正在载入《大灾变：净水炸弹》原生内核 (%s)..." % status
		return

	if _loading_overlay.visible:
		_loading_overlay.visible = false
		_clear_loading_image_cache()

	# Periodically trim unused tileset texture pages (LRU budget) & expire stale decoded PNG atlases
	_tile_trim_accum += delta
	if _tile_trim_accum >= 20.0:
		_tile_trim_accum = 0.0
		tile_pages_trimmed += Tiles.trim_unused_pages()
		Tiles.finish_frame()

	# Keep decoupled world-space Direct/GI/Weather GPU lightmaps ticking in 3D mode (dawn/dusk/fires/VFX)!
	if _render_3d and _has_terrain and _use_tiles and _view_3d != null and _view_3d.visible:
		_gpu_view.tick_lighting_only(delta, _view_3d.get_active_vfx_lights())
		_view_3d.apply_lighting_bundle(_gpu_view.get_3d_lighting_bundle())

	# Poll audio ring independently only when new audio events were pushed
	if _combat_audio != null and engine.has_method("get_audio_generation"):
		var agen: int = int(engine.get_audio_generation())
		if agen != _last_audio_gen:
			_last_audio_gen = agen
			if engine.has_method("poll_audio_events"):
				_combat_audio.ingest_events(engine.poll_audio_events())

	var wgen: int = int(engine.get_world_generation()) if engine.has_method("get_world_generation") else gen
	var s3gen: int = int(engine.get_scene3d_generation()) if (_render_3d and engine.has_method("get_scene3d_generation")) else _last_scene3d_gen

	var term_changed := (gen != _last_gen)
	var world_changed := (wgen != _last_world_gen)
	var scene3d_changed := (_render_3d and s3gen != _last_scene3d_gen)

	if not term_changed and not world_changed and not scene3d_changed and not _world_view_dirty:
		_update_idle_fps_throttle(delta)
		return

	_note_activity()
	var term_frame: Dictionary = {}
	if term_changed:
		_last_gen = gen
		term_polls += 1
		# Sync native CCB Options -> Graphics -> Tileset (live hot-reload whenever user changes it in CCB Settings!)
		_sync_native_tileset_option()
		term_frame = engine.poll_terminal_frame()
		if bool(term_frame.get("valid", false)):
			_term_overlay.update_frame(term_frame)
			_want_text_input = bool(term_frame.get("want_text_input", false))
			_ime_cursor = term_frame.get("cursor", Vector2i.ZERO)
			_sync_ime_state()
			var prev_has_ter := _has_terrain
			var prev_ter_rect := _last_terrain_rect
			_has_terrain = bool(term_frame.get("has_terrain", false))
			_last_terrain_rect = term_frame.get("terrain_rect", Rect2i())
			if _has_terrain != prev_has_ter or _last_terrain_rect != prev_ter_rect:
				_sync_terrain_rect()
				if _has_terrain:
					_world_view_dirty = true
			if _menu_credits_panel != null:
				var on_main_menu := (not bool(term_frame.get("in_game", false))) and (not _has_terrain) and _is_opening_main_menu(term_frame)
				_menu_credits_panel.visible = on_main_menu
			if _has_terrain and _use_tiles:
				_terrain_unoccluded = _is_terrain_corner_unoccluded(term_frame)
			else:
				_terrain_unoccluded = false

	if _has_terrain and _use_tiles:
		if not _looks_like_loaded and engine.has_method("get_looks_like_map"):
			var ll_map: Dictionary = engine.get_looks_like_map()
			if ll_map.size() > 100:
				Tiles.set_looks_like_map(ll_map)
				_looks_like_loaded = true

		var need_world_poll := world_changed or _last_wsnap.is_empty()
		if need_world_poll:
			_last_world_gen = wgen
			world_polls += 1
			_last_wsnap = engine.poll_world_snapshot()
			if _combat_audio != null:
				_combat_audio.ingest_events(_last_wsnap.get("audio_events", []))

		if need_world_poll or _world_view_dirty or scene3d_changed:
			_world_view_dirty = false
			if _render_3d and engine.has_method("poll_scene3d_snapshot"):
				var v3 := _ensure_view_3d()
				if need_world_poll:
					_gpu_view.update_lighting_only(_last_wsnap)
				if scene3d_changed or need_world_poll:
					_last_scene3d_gen = s3gen
					scene3d_polls += 1
					var s3d: Dictionary = engine.poll_scene3d_snapshot()
					v3.update_snapshots(s3d, _last_wsnap, _gpu_view.get_3d_lighting_bundle())
				_gpu_view.visible = false
				v3.visible = true
			else:
				_gpu_view.update_world_snapshot(_last_wsnap)
				if _view_3d != null:
					_view_3d.visible = false
			if _ambience_audio != null and need_world_poll:
				_ambience_audio.on_world_snapshot(_last_wsnap, _gpu_view.get_3d_lighting_bundle())

		var ter_px := Rect2(_gpu_view.position, _gpu_view.size)
		if _terrain_unoccluded:
			_minimap.update_minimap(_last_wsnap, ter_px)
		else:
			_minimap.visible = false
	else:
		_world_view_dirty = false
		if _ambience_audio != null:
			_ambience_audio.set_in_world(false)
		_terrain_unoccluded = false
		_gpu_view.visible = false
		if _view_3d != null:
			_view_3d.visible = false
		_minimap.visible = false
	_update_idle_fps_throttle(delta)


func _is_opening_main_menu(term_frame: Dictionary) -> bool:
	var tcols := int(term_frame.get("cols", 0))
	var trows := int(term_frame.get("rows", 0))
	var tcells: PackedByteArray = term_frame.get("cells", PackedByteArray())
	if tcols <= 0 or trows <= 0 or tcells.size() < tcols * trows * 16:
		return false
	# Scan lower portion of screen for CCB's opening menu row ("[ N新游戏 ]" / "[ Q退出 ]" or "[ New Game ]" / "[ Quit ]")
	var start_y := maxi(0, trows - 14)
	var text := ""
	for y in range(start_y, trows):
		var row_off := y * tcols * 16
		for x in range(tcols):
			var off := row_off + x * 16
			if (tcells.decode_u8(off + 13) & 0x08) != 0:
				continue
			var cp := tcells.decode_u32(off)
			if cp >= 32:
				text += char(cp)
	return (("新游戏" in text and "退出" in text) or ("New Game" in text and "Quit" in text))


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
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_note_activity()

	if event is InputEventKey:
		var kev: InputEventKey = event
		if not kev.pressed:
			return
		# F11 or Alt+Enter toggles borderless fullscreen smoothly with adaptive UI scaling
		if kev.keycode == KEY_F11 or (kev.alt_pressed and (kev.keycode == KEY_ENTER or kev.keycode == KEY_KP_ENTER)):
			var cur_mode := DisplayServer.window_get_mode()
			if cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()
			return
		# F12 returns cleanly to the Core Pack Launcher (so user can switch to Cangming anytime)
		if kev.keycode == KEY_F12:
			deactivate_to_launcher()
			get_viewport().set_input_as_handled()
			return
		# F7 toggles Godot 3D rendering mode (driven by CCB's multi-Z 3D logic!)
		if kev.keycode == KEY_F7:
			toggle_render_3d()
			get_viewport().set_input_as_handled()
			return
		# F8 toggles forced Chinese IME activation on any screen
		if kev.keycode == KEY_F8:
			_manual_ime = not _manual_ime
			_sync_ime_state()
			get_viewport().set_input_as_handled()
			return
		# F9 toggles native Pixel Minimap dock
		if kev.keycode == KEY_F9:
			_minimap.toggle_enabled()
			_last_gen = -1
			get_viewport().set_input_as_handled()
			return
		# Ctrl+= / Ctrl+- zooms the GPU tilemap or 3D camera without colliding with CCB keys!
		if kev.ctrl_pressed and (kev.keycode == KEY_EQUAL or kev.keycode == KEY_KP_ADD):
			if _render_3d and _view_3d != null:
				_view_3d.note_mouse_wheel(1.5)
			else:
				_gpu_view.adjust_zoom(1)
			get_viewport().set_input_as_handled()
			return
		if kev.ctrl_pressed and (kev.keycode == KEY_MINUS or kev.keycode == KEY_KP_SUBTRACT):
			if _render_3d and _view_3d != null:
				_view_3d.note_mouse_wheel(-1.5)
			else:
				_gpu_view.adjust_zoom(-1)
			get_viewport().set_input_as_handled()
			return

		# Exact CCB 3D display toggles ('z' = same-level cutaway, 'Z' = cursor peek dither) when unoccluded on 3D map
		if _render_3d and _view_3d != null and _has_terrain and _terrain_unoccluded and (not _want_text_input) and (not kev.ctrl_pressed) and (not kev.alt_pressed):
			if kev.keycode == KEY_Z:
				if kev.shift_pressed:
					toggle_3d_cursor_dither()
				else:
					toggle_3d_same_level()
				get_viewport().set_input_as_handled()
				return

		# Committed Chinese / CJK / Unicode characters from Windows IME -> dedicated UTF-8 text input channel!
		if kev.unicode > 127 and not kev.ctrl_pressed and not kev.alt_pressed:
			var ch_u := char(kev.unicode)
			if _term_overlay != null:
				_term_overlay.set_ime_preedit("")
			if engine.has_method("send_text_input"):
				engine.send_text_input(ch_u)
			else:
				engine.send_key(kev.unicode, ch_u, false, false, false)
			get_viewport().set_input_as_handled()
			return

		# While OS IME is mid-composition (Pinyin preedit non-empty), avoid forwarding raw ASCII letters to CCB
		if _ime_active and not DisplayServer.ime_get_text().is_empty() and kev.keycode != KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			return

		# Exact CCB camera_screen_to_map_delta(): rotate movement keys by 3D camera forward octant when on map!
		if _render_3d and _view_3d != null and _has_terrain and _terrain_unoccluded and (not _want_text_input) and (not kev.ctrl_pressed) and (not kev.alt_pressed) and (not _view_3d.is_controlling_vehicle()):
			var remapped := _remap_3d_direction_key(kev)
			if not remapped.is_empty():
				engine.send_key(int(remapped[0]), str(remapped[1]), false, false, false)
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
		var in_active_map := _has_terrain and _use_tiles and _terrain_unoccluded and (
			(_render_3d and _view_3d != null and _view_3d.visible and _view_3d.get_global_rect().has_point(mev.global_position)) or
			((not _render_3d) and _gpu_view.visible and _gpu_view.get_global_rect().has_point(mev.global_position))
		)
		if _render_3d and _view_3d != null and mev.button_index == MOUSE_BUTTON_RIGHT:
			if mev.pressed and in_active_map:
				_orbit_rmb_down = true
				_orbit_rmb_dragged = false
				_orbit_rmb_start = mev.global_position
				_view_3d.set_orbit_dragging(true)
				get_viewport().set_input_as_handled()
				return
			elif (not mev.pressed) and _orbit_rmb_down:
				_orbit_rmb_down = false
				_view_3d.set_orbit_dragging(false)
				if _orbit_rmb_dragged:
					_orbit_rmb_dragged = false
					get_viewport().set_input_as_handled()
					return
				# Quick right-click (no drag) still forwards as normal CCB right-click!
				var rcell := _map_mouse_to_ccb_cell(mev.global_position, mev.position)
				engine.send_mouse(3, rcell.x, rcell.y, 0)
				engine.send_mouse(4, rcell.x, rcell.y, 0)
				get_viewport().set_input_as_handled()
				return
		if in_active_map:
			if mev.pressed and mev.button_index == MOUSE_BUTTON_WHEEL_UP:
				if _render_3d and _view_3d != null:
					_view_3d.note_mouse_wheel(1.0)
				else:
					_gpu_view.adjust_zoom(1)
				get_viewport().set_input_as_handled()
				return
			if mev.pressed and mev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if _render_3d and _view_3d != null:
					_view_3d.note_mouse_wheel(-1.0)
				else:
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
		if _render_3d and _view_3d != null and _orbit_rmb_down:
			if not _orbit_rmb_dragged and mm.global_position.distance_to(_orbit_rmb_start) >= 4.0:
				_orbit_rmb_dragged = true
			_view_3d.note_mouse_look(mm.relative.x, mm.relative.y)
			get_viewport().set_input_as_handled()
			return
		if _top_bar_panel.get_global_rect().has_point(mm.global_position):
			return
		if _render_3d and _view_3d != null and _view_3d.visible and _terrain_unoccluded:
			_view_3d.note_mouse_global(mm.global_position)
		elif (not _render_3d) and _gpu_view != null and _gpu_view.visible and _terrain_unoccluded:
			_gpu_view.note_mouse_global(mm.global_position)
		var cell := _map_mouse_to_ccb_cell(mm.global_position, mm.position)
		if cell != _last_hover_cell:
			# Keep modal/ImTui menu hover instant; throttle free-roam map hover so waving the mouse
			# never floods CCB's worker thread with redundant world snapshots!
			var now_ms := Time.get_ticks_msec()
			if (not _terrain_unoccluded) or (mm.button_mask != 0) or (now_ms - _last_hover_ms >= 90):
				_last_hover_cell = cell
				_last_hover_ms = now_ms
				engine.send_mouse(0, cell.x, cell.y, 0)


func _remap_3d_direction_key(ev: InputEventKey) -> Array:
	var scr_d := Vector2i.ZERO
	match ev.keycode:
		KEY_UP, KEY_KP_8:    scr_d = Vector2i(0, -1)
		KEY_DOWN, KEY_KP_2:  scr_d = Vector2i(0, 1)
		KEY_LEFT, KEY_KP_4:  scr_d = Vector2i(-1, 0)
		KEY_RIGHT, KEY_KP_6: scr_d = Vector2i(1, 0)
		KEY_KP_7:            scr_d = Vector2i(-1, -1)
		KEY_KP_9:            scr_d = Vector2i(1, -1)
		KEY_KP_1:            scr_d = Vector2i(-1, 1)
		KEY_KP_3:            scr_d = Vector2i(1, 1)
		_:
			if not ev.shift_pressed:
				match ev.keycode:
					KEY_K: scr_d = Vector2i(0, -1)
					KEY_J: scr_d = Vector2i(0, 1)
					KEY_H: scr_d = Vector2i(-1, 0)
					KEY_L: scr_d = Vector2i(1, 0)
					KEY_Y: scr_d = Vector2i(-1, -1)
					KEY_U: scr_d = Vector2i(1, -1)
					KEY_B: scr_d = Vector2i(-1, 1)
					KEY_N: scr_d = Vector2i(1, 1)
					_: return []
			else:
				return []
	var map_d := _view_3d.screen_delta_to_map_delta(scr_d)
	# Translate rotated map delta to standard numpad digit ('1'..'9') accepted identically everywhere in CCB!
	var ch := ""
	if map_d == Vector2i(0, -1):   ch = "8"
	elif map_d == Vector2i(1, -1): ch = "9"
	elif map_d == Vector2i(1, 0):  ch = "6"
	elif map_d == Vector2i(1, 1):  ch = "3"
	elif map_d == Vector2i(0, 1):  ch = "2"
	elif map_d == Vector2i(-1, 1): ch = "1"
	elif map_d == Vector2i(-1, 0): ch = "4"
	elif map_d == Vector2i(-1, -1): ch = "7"
	if ch.is_empty():
		return []
	return [ord(ch), ch]


func _map_mouse_to_ccb_cell(global_pos: Vector2, local_pos: Vector2) -> Vector2i:
	# When hovering/clicking directly on the 2D or 3D map with no modal covering it,
	# map world tile coords -> exact w_terrain curses cell so click-to-walk & path preview match 1:1!
	if _has_terrain and _use_tiles and _terrain_unoccluded:
		var world_tile := Vector2i(-99999, -99999)
		var center_tile := Vector2i.ZERO
		if _render_3d and _view_3d != null and _view_3d.visible and _view_3d.get_global_rect().has_point(global_pos):
			world_tile = _view_3d.screen_to_world_tile(global_pos)
			center_tile = _view_3d.get_view_center_tile()
		elif (not _render_3d) and _gpu_view.visible and _gpu_view.get_global_rect().has_point(global_pos):
			world_tile = _gpu_view.screen_to_world_tile(global_pos)
			center_tile = _gpu_view.get_view_center_tile()
		if world_tile.x > -90000:
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
	var cx := clampi(int(lp.x) / _cell_w, 0, maxi(0, _grid_cols - 1))
	@warning_ignore("integer_division")
	var cy := clampi(int(lp.y) / _cell_h, 0, maxi(0, _grid_rows - 1))
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
