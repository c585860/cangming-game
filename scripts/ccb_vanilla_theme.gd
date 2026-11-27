extends RefCounted

# Pure Vanilla Cataclysm-Cleanwater-Bomb (CCB) Terminal / ImGui Visual Style.
# Strictly matches Cataclysm-Cleanwater-Bomb/data/raw/imgui_styles/default_style.json
# and src/color.cpp:
#  - Pure black #000000 background (ImGuiCol_WindowBg: [0, 0, 0, 1])
#  - 0px sharp rectangular corners (NO rounded cards, NO glassmorphism, NO pills!)
#  - 1px crisp white/50% borders (ImGuiCol_Border: [1, 1, 1, 0.5])
#  - Cobalt-blue selection highlight (ImGuiCol_Header: [0.04, 0.04, 0.86, 0.65])
#  - Exact classic 16-color curses semantic palette + <color_*> markup parser

const BG_BLACK := Color(0.0, 0.0, 0.0, 1.0)
const BG_PANEL := Color(0.0, 0.0, 0.0, 0.98)
const BG_SUB := Color(0.03, 0.03, 0.03, 0.98)
const BG_SELECT := Color(0.04, 0.04, 0.86, 0.65)
const BG_HOVER := Color(0.04, 0.04, 0.86, 0.38)
const BG_ACTIVE := Color(0.07, 0.11, 0.92, 0.85)
const BG_INPUT := Color(0.04, 0.04, 0.04, 1.0)

const BORDER := Color(1.0, 1.0, 1.0, 0.50)
const BORDER_BRIGHT := Color(1.0, 1.0, 1.0, 0.88)
const BORDER_DIM := Color(0.45, 0.45, 0.45, 0.55)
const SEPARATOR := Color(0.55, 0.23, 0.38, 0.80) # exact ImGuiCol_Separator from default_style.json!

# Classic 16-color curses palette (exact CCB color.cpp)
const C_BLACK := Color("000000")
const C_RED := Color("dd2222")
const C_GREEN := Color("00aa00")
const C_BROWN := Color("aa6600")
const C_BLUE := Color("2244dd")
const C_MAGENTA := Color("aa22aa")
const C_CYAN := Color("0099bb")
const C_LTGRAY := Color("cccccc")
const C_DKGRAY := Color("666666")
const C_LTRED := Color("ff5555")
const C_LTGREEN := Color("33ff33")
const C_YELLOW := Color("ffff55")
const C_LTBLUE := Color("5588ff")
const C_PINK := Color("ff77cc")
const C_LTCYAN := Color("55ffff")
const C_WHITE := Color("ffffff")

const TAG_HEX := {
	"color_black": "000000",
	"color_red": "dd2222",
	"color_green": "00aa00",
	"color_brown": "aa6600",
	"color_blue": "3355ee",
	"color_magenta": "bb44bb",
	"color_cyan": "00aacc",
	"color_light_gray": "cccccc",
	"color_dark_gray": "666666",
	"color_light_red": "ff5555",
	"color_light_green": "33ff33",
	"color_yellow": "ffff55",
	"color_light_blue": "5588ff",
	"color_pink": "ff77cc",
	"color_light_cyan": "55ffff",
	"color_white": "ffffff",
}


static func box(bg := BG_BLACK, border := BORDER, pad_x := 8, pad_y := 6, border_w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(0) # STRICT 0px sharp CCB corners!
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


static func divider(col := BORDER_DIM) -> ColorRect:
	var line := ColorRect.new()
	line.color = col
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


static func style_button(button: Button, selected := false, danger := false) -> void:
	var norm_bg := BG_SELECT if selected else BG_BLACK
	var norm_bd := BORDER_BRIGHT if selected else BORDER_DIM
	if danger and not selected:
		norm_bd = Color(0.85, 0.25, 0.25, 0.65)
	button.add_theme_stylebox_override("normal", box(norm_bg, norm_bd, 8, 3, 1))
	button.add_theme_stylebox_override("hover", box(BG_SELECT if selected else BG_HOVER, BORDER_BRIGHT, 8, 3, 1))
	button.add_theme_stylebox_override("pressed", box(BG_ACTIVE, C_WHITE, 8, 3, 1))
	button.add_theme_stylebox_override("disabled", box(BG_BLACK, Color(0.25, 0.25, 0.25, 0.5), 8, 3, 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := C_WHITE if selected else (C_LTRED if danger else C_LTGRAY)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", C_WHITE)
	button.add_theme_color_override("font_pressed_color", C_YELLOW)
	button.add_theme_color_override("font_disabled_color", C_DKGRAY)
	button.add_theme_font_size_override("font_size", 13)


static func style_row_button(button: Button, selected := false, fg := C_LTGRAY) -> void:
	var norm_bg := BG_SELECT if selected else Color(0, 0, 0, 0)
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = norm_bg
	sb_n.set_border_width_all(0)
	sb_n.set_corner_radius_all(0)
	sb_n.content_margin_left = 6
	sb_n.content_margin_right = 6
	sb_n.content_margin_top = 2
	sb_n.content_margin_bottom = 2
	var sb_h := sb_n.duplicate() as StyleBoxFlat
	sb_h.bg_color = BG_SELECT if selected else BG_HOVER
	button.add_theme_stylebox_override("normal", sb_n)
	button.add_theme_stylebox_override("hover", sb_h)
	button.add_theme_stylebox_override("pressed", box(BG_ACTIVE, BORDER_BRIGHT, 6, 2, 0))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", C_WHITE if selected else fg)
	button.add_theme_color_override("font_hover_color", C_WHITE)
	button.add_theme_color_override("font_pressed_color", C_YELLOW)
	button.add_theme_font_size_override("font_size", 13)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT


static func style_line_edit(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", box(BG_INPUT, BORDER, 6, 3, 1))
	edit.add_theme_stylebox_override("focus", box(BG_INPUT, C_LTCYAN, 6, 3, 1))
	edit.add_theme_color_override("font_color", C_WHITE)
	edit.add_theme_color_override("font_placeholder_color", C_DKGRAY)
	edit.add_theme_color_override("caret_color", C_LTCYAN)
	edit.add_theme_font_size_override("font_size", 13)


static func mk_lbl(parent: Node, text: String, size := 13, color := C_LTGRAY, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent != null:
		parent.add_child(l)
	return l


static func ccb_markup_to_bbcode(raw: String) -> String:
	# Converts vanilla CCB <color_light_cyan>...</color> tags (zh_CN.title & zh_CN.motd) to Godot BBCode.
	# Handles unclosed line-end tags cleanly as in Cataclysm-Cleanwater-Bomb/data/title/zh_CN.title!
	var lines := raw.replace("\r\n", "\n").split("\n")
	var out_lines := PackedStringArray()
	for line in lines:
		var s := line.replace("[", "[lb]")
		var open_count := 0
		for tag: String in TAG_HEX:
			var tok := "<%s>" % tag
			while s.find(tok) >= 0:
				s = s.replace(tok, "[color=#%s]" % TAG_HEX[tag])
				open_count += 1
		var close_hits := s.count("</color>")
		s = s.replace("</color>", "[/color]")
		open_count -= close_hits
		while open_count > 0:
			s += "[/color]"
			open_count -= 1
		out_lines.append(s)
	return "\n".join(out_lines)


static func curses_hp_bar(cur: int, max_v: int) -> Dictionary:
	# Exact vanilla CCB 5-pip ASCII limb bar: ||||| (green) -> ||||. -> |||.. -> ||... -> |.... -> .....
	var ratio := clampf(float(cur) / float(maxi(1, max_v)), 0.0, 1.0)
	var pips := int(ceilf(ratio * 5.0))
	if cur <= 0:
		pips = 0
	var bar := "|".repeat(pips) + ".".repeat(5 - pips)
	var col := C_LTGREEN
	if pips <= 1:
		col = C_LTRED
	elif pips == 2:
		col = C_RED
	elif pips == 3:
		col = C_YELLOW
	elif pips == 4:
		col = C_GREEN
	return {"text": bar, "color": col}
