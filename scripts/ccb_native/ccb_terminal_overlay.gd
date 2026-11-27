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
var _col_cache: Dictionary = {}
var _glyph_cache: Dictionary = {}


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
	if ui_font != null:
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

	# Pass 2: Crisp glyphs & box-drawing lines (cached colors/strings; skips terrain cutout cells & spaces)
	var im_min_x := cols
	var im_min_y := rows
	var im_max_x := -1
	var im_max_y := -1
	for y in range(rows):
		var py := float(y) * ch
		var row_base := y * cols * CELL_STRIDE
		for x in range(cols):
			var off := row_base + x * CELL_STRIDE
			var flags := cells.decode_u8(off + 13)
			if (flags & FLAG_IMGUI) != 0:
				if x < im_min_x: im_min_x = x
				if y < im_min_y: im_min_y = y
				if x > im_max_x: im_max_x = x
				if y > im_max_y: im_max_y = y
			if (flags & FLAG_CONT) != 0 or (cutout_enabled and (flags & FLAG_TERRAIN) != 0):
				continue
			var cp := cells.decode_u32(off)
			if cp <= 32:
				continue
			var fg_col := _get_cached_color(cells.decode_u32(off + 4))
			var px := float(x) * cw
			if cp >= 0x2500 and cp <= 0x253C and _draw_box_glyph(cp, px, py, fg_col):
				continue
			draw_string(ui_font, Vector2(px, py + baseline), _get_cached_glyph(cp), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, fg_col)

	# Pass 3: Crisp 1px white border around active ImTui modal/popup window without overwriting any text cells
	if im_max_x >= im_min_x and im_max_y >= im_min_y and (im_max_x - im_min_x + 1) < cols:
		var im_rect := Rect2(
			float(im_min_x) * cw,
			float(im_min_y) * ch,
			float(im_max_x - im_min_x + 1) * cw,
			float(im_max_y - im_min_y + 1) * ch
		)
		draw_rect(im_rect, Color(0.82, 0.82, 0.82, 1.0), false, 1.0)
