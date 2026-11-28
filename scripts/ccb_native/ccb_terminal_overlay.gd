extends Control

# Renders the composite CCB terminal + ImTui cell framebuffer (16 bytes/cell).
# Cells flagged with CCB_CELL_TERRAIN (0x01) are left 100% transparent so the
# Godot 4.5 GPU-lit, shadowed, weather-rendered vanilla tileset world shines through!

const CELL_STRIDE := 16
const FLAG_TERRAIN := 0x01
const FLAG_IMGUI := 0x02
const FLAG_CONT := 0x08

var cols := 0
var rows := 0
var cell_w := 8
var cell_h := 16
var cells := PackedByteArray()
var cursor := Vector2i(-1, -1)
var has_terrain := false
var cutout_enabled := true
var ui_font: Font
var font_size := 14
var font_ascent := 13.0
var ime_preedit := ""
var _col_cache: Dictionary = {}
var _glyph_cache: Dictionary = {}
var _cjk_batch_font: Font = null
var _ascii_batch_ok := false
var _cjk_batch_ok := false
var _ascii_max_run := 8
var _cjk_max_run := 12
var last_draw_string_calls := 0


func set_ime_preedit(text: String) -> void:
	if ime_preedit != text:
		ime_preedit = text
		queue_redraw()


func _get_cached_color(rgba: int) -> Color:
	var c = _col_cache.get(rgba)
	if c != null:
		return c
	var col := _unpack_color(rgba)
	if _col_cache.size() < 512:
		_col_cache[rgba] = col
	return col


func _get_cached_glyph(cp: int) -> String:
	var s = _glyph_cache.get(cp)
	if s != null:
		return s
	var g := char(cp)
	if _glyph_cache.size() < 4096:
		_glyph_cache[cp] = g
	return g


func set_cutout_enabled(enabled: bool) -> void:
	if cutout_enabled != enabled:
		cutout_enabled = enabled
		queue_redraw()


func configure_font(f: Font, cw: int, ch: int) -> void:
	ui_font = f
	cell_w = maxi(6, cw)
	cell_h = maxi(12, ch)
	font_size = maxi(10, cell_h - 1)
	_cjk_batch_font = ui_font
	_ascii_batch_ok = false
	_cjk_batch_ok = false
	_ascii_max_run = 8
	_cjk_max_run = 12
	if ui_font != null:
		# Verify strict monospace ASCII advance (A == i == space) and compute drift-bounded batch run length (<=1.5px max drift)
		var a_adv := ui_font.get_string_size("AAAAAAAA", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x / 8.0
		var i_adv := ui_font.get_string_size("iiiiiiii", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x / 8.0
		var sp_adv := ui_font.get_string_size("        ", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x / 8.0
		var is_mono := absf(a_adv - i_adv) <= 0.12 and absf(a_adv - sp_adv) <= 0.12
		var a_err := absf(a_adv - float(cell_w))
		if is_mono and a_err <= 0.40:
			_ascii_batch_ok = true
			_ascii_max_run = clampi(int(floor(1.6 / maxf(0.02, a_err))), 4, 48)

		# Build integer glyph-padded FontVariation for CJK double-width cells (e.g. 15px + 1px = 16px == 2 * cell_w!)
		var c0 := ui_font.get_string_size("中中中中", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x / 4.0
		var c_pad := int(round(float(cell_w * 2) - c0))
		if c_pad != 0:
			var fv := FontVariation.new()
			fv.base_font = ui_font
			fv.spacing_glyph = c_pad
			_cjk_batch_font = fv
		var c_adv := _cjk_batch_font.get_string_size("中中中中中中中中", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x / 8.0
		var c_err := absf(c_adv - float(cell_w * 2))
		if c_err <= 0.40:
			_cjk_batch_ok = true
			_cjk_max_run = clampi(int(floor(1.6 / maxf(0.02, c_err))), 4, 24)
		font_ascent = ui_font.get_ascent(font_size)
	else:
		font_ascent = float(cell_h) * 0.82
	queue_redraw()


func update_frame(frame: Dictionary) -> void:
	if not bool(frame.get("valid", false)):
		return
	cols = int(frame.get("cols", 0))
	rows = int(frame.get("rows", 0))
	cells = frame.get("cells", PackedByteArray())
	cursor = frame.get("cursor", Vector2i(-1, -1))
	has_terrain = bool(frame.get("has_terrain", false))
	queue_redraw()


static func _unpack_color(rgba: int) -> Color:
	var r := float(rgba & 0xFF) / 255.0
	var g := float((rgba >> 8) & 0xFF) / 255.0
	var b := float((rgba >> 16) & 0xFF) / 255.0
	var a := float((rgba >> 24) & 0xFF) / 255.0
	return Color(r, g, b, a)


func _draw_box_glyph(cp: int, px: float, py: float, col: Color) -> bool:
	var cw := float(cell_w)
	var ch := float(cell_h)
	var mx := floorf(px + cw * 0.5)
	var my := floorf(py + ch * 0.5)
	match cp:
		0x2500: # ─
			draw_rect(Rect2(px, my, cw, 1.0), col)
			return true
		0x2502: # │
			draw_rect(Rect2(mx, py, 1.0, ch), col)
			return true
		0x250C: # ┌
			draw_rect(Rect2(mx, my, cw - (mx - px), 1.0), col)
			draw_rect(Rect2(mx, my, 1.0, ch - (my - py)), col)
			return true
		0x2510: # ┐
			draw_rect(Rect2(px, my, (mx - px) + 1.0, 1.0), col)
			draw_rect(Rect2(mx, my, 1.0, ch - (my - py)), col)
			return true
		0x2514: # └
			draw_rect(Rect2(mx, py, 1.0, (my - py) + 1.0), col)
			draw_rect(Rect2(mx, my, cw - (mx - px), 1.0), col)
			return true
		0x2518: # ┘
			draw_rect(Rect2(mx, py, 1.0, (my - py) + 1.0), col)
			draw_rect(Rect2(px, my, (mx - px) + 1.0, 1.0), col)
			return true
		0x251C: # ├
			draw_rect(Rect2(mx, py, 1.0, ch), col)
			draw_rect(Rect2(mx, my, cw - (mx - px), 1.0), col)
			return true
		0x2524: # ┤
			draw_rect(Rect2(mx, py, 1.0, ch), col)
			draw_rect(Rect2(px, my, (mx - px) + 1.0, 1.0), col)
			return true
		0x252C: # ┬
			draw_rect(Rect2(px, my, cw, 1.0), col)
			draw_rect(Rect2(mx, my, 1.0, ch - (my - py)), col)
			return true
		0x2534: # ┴
			draw_rect(Rect2(px, my, cw, 1.0), col)
			draw_rect(Rect2(mx, py, 1.0, (my - py) + 1.0), col)
			return true
		0x253C: # ┼
			draw_rect(Rect2(px, my, cw, 1.0), col)
			draw_rect(Rect2(mx, py, 1.0, ch), col)
			return true
		_:
			return false


func _draw() -> void:
	var expected := cols * rows * CELL_STRIDE
	if cols <= 0 or rows <= 0 or cells.size() < expected or ui_font == null:
		return

	var cw := float(cell_w)
	var ch := float(cell_h)
	var baseline := floorf((ch - float(font_size)) * 0.5 + font_ascent)
	if baseline > ch - 1.0:
		baseline = ch - 2.0

	# Pass 1: Batched horizontal background runs (skipping terrain cutout cells!)
	for y in range(rows):
		var py := float(y) * ch
		var row_base := y * cols * CELL_STRIDE
		var run_start := -1
		var run_bg := 0
		for x in range(cols):
			var off := row_base + x * CELL_STRIDE
			var flags := cells.decode_u8(off + 13)
			if cutout_enabled and (flags & FLAG_TERRAIN) != 0:
				if run_start >= 0:
					draw_rect(Rect2(float(run_start) * cw, py, float(x - run_start) * cw, ch), _get_cached_color(run_bg))
					run_start = -1
				continue
			var bg := cells.decode_u32(off + 8)
			if run_start < 0:
				run_start = x
				run_bg = bg
			elif bg != run_bg:
				draw_rect(Rect2(float(run_start) * cw, py, float(x - run_start) * cw, ch), _get_cached_color(run_bg))
				run_start = x
				run_bg = bg
		if run_start >= 0:
			draw_rect(Rect2(float(run_start) * cw, py, float(cols - run_start) * cw, ch), _get_cached_color(run_bg))

	# Pass 2: Batched horizontal text runs + horizontal box-line coalescing (8-15x fewer draw_string calls!)
	var im_min_x := cols
	var im_min_y := rows
	var im_max_x := -1
	var im_max_y := -1
	var ds_calls := 0
	var cjk_font := _cjk_batch_font if _cjk_batch_font != null else ui_font
	for y in range(rows):
		var py := float(y) * ch
		var baseline_y := py + baseline
		var row_base := y * cols * CELL_STRIDE
		var run_text := ""
		var run_x := -1
		var run_next_x := -1
		var run_fg := 0
		var run_kind := 0 # 1 = ASCII batch, 2 = CJK batch
		var hline_start := -1
		var hline_fg := 0

		for x in range(cols):
			var off := row_base + x * CELL_STRIDE
			var flags := cells.decode_u8(off + 13)
			if (flags & FLAG_IMGUI) != 0:
				if x < im_min_x: im_min_x = x
				if y < im_min_y: im_min_y = y
				if x > im_max_x: im_max_x = x
				if y > im_max_y: im_max_y = y
			if (flags & FLAG_CONT) != 0:
				continue
			if cutout_enabled and (flags & FLAG_TERRAIN) != 0:
				if run_x >= 0:
					draw_string(cjk_font if run_kind == 2 else ui_font, Vector2(float(run_x) * cw, baseline_y), run_text.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _get_cached_color(run_fg))
					ds_calls += 1
					run_x = -1
					run_text = ""
				if hline_start >= 0:
					draw_rect(Rect2(float(hline_start) * cw, floorf(py + ch * 0.5), float(x - hline_start) * cw, 1.0), _get_cached_color(hline_fg))
					hline_start = -1
				continue

			var cp := cells.decode_u32(off)
			if cp <= 32:
				if hline_start >= 0:
					draw_rect(Rect2(float(hline_start) * cw, floorf(py + ch * 0.5), float(x - hline_start) * cw, 1.0), _get_cached_color(hline_fg))
					hline_start = -1
				# Keep single spaces inside an active ASCII run so whole words draw in ONE call!
				if cp == 32 and run_x >= 0 and run_kind == 1 and x == run_next_x and run_text.length() < _ascii_max_run:
					run_text += " "
					run_next_x = x + 1
				elif run_x >= 0:
					draw_string(cjk_font if run_kind == 2 else ui_font, Vector2(float(run_x) * cw, baseline_y), run_text.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _get_cached_color(run_fg))
					ds_calls += 1
					run_x = -1
					run_text = ""
				continue

			var fg_rgba := cells.decode_u32(off + 4)

			# Coalesce horizontal ─ (0x2500) box-drawing lines into a single draw_rect!
			if cp == 0x2500:
				if run_x >= 0:
					draw_string(cjk_font if run_kind == 2 else ui_font, Vector2(float(run_x) * cw, baseline_y), run_text.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _get_cached_color(run_fg))
					ds_calls += 1
					run_x = -1
					run_text = ""
				if hline_start < 0:
					hline_start = x
					hline_fg = fg_rgba
				elif fg_rgba != hline_fg:
					draw_rect(Rect2(float(hline_start) * cw, floorf(py + ch * 0.5), float(x - hline_start) * cw, 1.0), _get_cached_color(hline_fg))
					hline_start = x
					hline_fg = fg_rgba
				continue
			if hline_start >= 0:
				draw_rect(Rect2(float(hline_start) * cw, floorf(py + ch * 0.5), float(x - hline_start) * cw, 1.0), _get_cached_color(hline_fg))
				hline_start = -1

			if cp >= 0x2502 and cp <= 0x253C:
				if run_x >= 0:
					draw_string(cjk_font if run_kind == 2 else ui_font, Vector2(float(run_x) * cw, baseline_y), run_text.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _get_cached_color(run_fg))
					ds_calls += 1
					run_x = -1
					run_text = ""
				if _draw_box_glyph(cp, float(x) * cw, py, _get_cached_color(fg_rgba)):
					continue

			var cwidth := cells.decode_u8(off + 12)
			var is_batch_ascii := _ascii_batch_ok and cwidth == 1 and cp >= 33 and cp <= 126
			var is_batch_cjk := _cjk_batch_ok and cwidth == 2 and cp >= 0x4E00 and cp <= 0x9FFF
			if is_batch_ascii or is_batch_cjk:
				var kind := 1 if is_batch_ascii else 2
				var step := 1 if is_batch_ascii else 2
				var max_len := _ascii_max_run if is_batch_ascii else _cjk_max_run
				if run_x >= 0 and run_kind == kind and run_fg == fg_rgba and x == run_next_x and run_text.length() < max_len:
					run_text += _get_cached_glyph(cp)
					run_next_x = x + step
				else:
					if run_x >= 0:
						draw_string(cjk_font if run_kind == 2 else ui_font, Vector2(float(run_x) * cw, baseline_y), run_text.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _get_cached_color(run_fg))
						ds_calls += 1
					run_x = x
					run_next_x = x + step
					run_fg = fg_rgba
					run_kind = kind
					run_text = _get_cached_glyph(cp)
			else:
				if run_x >= 0:
					draw_string(cjk_font if run_kind == 2 else ui_font, Vector2(float(run_x) * cw, baseline_y), run_text.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _get_cached_color(run_fg))
					ds_calls += 1
					run_x = -1
					run_text = ""
				draw_string(ui_font, Vector2(float(x) * cw, baseline_y), _get_cached_glyph(cp), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _get_cached_color(fg_rgba))
				ds_calls += 1

		if run_x >= 0:
			draw_string(cjk_font if run_kind == 2 else ui_font, Vector2(float(run_x) * cw, baseline_y), run_text.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _get_cached_color(run_fg))
			ds_calls += 1
		if hline_start >= 0:
			draw_rect(Rect2(float(hline_start) * cw, floorf(py + ch * 0.5), float(cols - hline_start) * cw, 1.0), _get_cached_color(hline_fg))
	last_draw_string_calls = ds_calls

	# Pass 3: Crisp 1px white border around active ImTui modal/popup window without overwriting any text cells
	if im_max_x >= im_min_x and im_max_y >= im_min_y and (im_max_x - im_min_x + 1) < cols:
		var im_rect := Rect2(
			float(im_min_x) * cw,
			float(im_min_y) * ch,
			float(im_max_x - im_min_x + 1) * cw,
			float(im_max_y - im_min_y + 1) * ch
		)
		draw_rect(im_rect, Color(0.82, 0.82, 0.82, 1.0), false, 1.0)

	# Pass 4: Live Chinese IME composition preedit pill right at the CCB text cursor
	if not ime_preedit.is_empty():
		var cx := clampi(cursor.x, 0, maxi(0, cols - 1))
		var cy := clampi(cursor.y, 0, maxi(0, rows - 1))
		var px := float(cx) * cw
		var py := float(cy) * ch
		var text_sz := ui_font.get_string_size(ime_preedit, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var pill_w := maxf(cw * 2.0, text_sz.x + 10.0)
		var pill_h := ch + 4.0
		if px + pill_w > size.x - 4.0:
			px = maxf(4.0, size.x - pill_w - 4.0)
		var pill := Rect2(px, maxf(0.0, py - 2.0), pill_w, pill_h)
		draw_rect(pill, Color(0.08, 0.14, 0.24, 0.96))
		draw_rect(pill, Color(0.45, 0.82, 1.0, 0.95), false, 1.2)
		draw_string(ui_font, Vector2(px + 5.0, maxf(0.0, py - 2.0) + baseline + 1.0), ime_preedit, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.96, 0.98, 1.0))
