extends RefCounted

# Authentic Cataclysm-Cleanwater-Bomb (CCB) Modern ImGui Visual Theme.
# Exact palette & geometry ported from Cataclysm-Cleanwater-Bomb/src/main_menu.cpp
# and src/adaptive_imgui_dialog.cpp:
#  - Obsidian-slate glass panels (#080d12e8), subtle teal-steel borders (#4a6f7ab4)
#  - 5px rounded corners, crisp cyan hover/active accents (#174d57f5 / #57d1d6eb)
#  - Crimson danger/quit buttons (#3d1717eb -> #7a241ff5)

const BG_SCREEN := Color(0.024, 0.035, 0.047, 1.0)       # #06090c
const BG_PANEL := Color(0.031, 0.051, 0.071, 0.92)       # IM_COL32(8, 13, 18, 234)
const BG_FLOAT := Color(0.027, 0.047, 0.067, 0.95)       # IM_COL32(7, 12, 17, 242)
const BG_HEADER := Color(0.055, 0.086, 0.114, 0.94)      # #0e161d
const BG_CARD := Color(0.047, 0.075, 0.102, 0.92)        # #0c131a
const BG_ROW_HOVER := Color(0.118, 0.396, 0.439, 0.45)   # Teal glass hover
const BG_ROW_ACTIVE := Color(0.090, 0.302, 0.341, 0.96)  # IM_COL32(23, 77, 87, 245)
const BG_INPUT := Color(0.024, 0.039, 0.055, 0.96)       # #060a0e

const BORDER := Color(0.290, 0.435, 0.478, 0.72)         # IM_COL32(74, 111, 122, 184)
const BORDER_BRIGHT := Color(0.380, 0.560, 0.610, 0.88)
const BORDER_CYAN := Color(0.341, 0.820, 0.839, 0.92)    # IM_COL32(87, 209, 214, 235)
const BORDER_EMBER := Color(0.902, 0.420, 0.298, 0.90)   # #e66b4c (Cataclysm accent)
const DIVIDER := Color(0.240, 0.360, 0.400, 0.48)

const BTN_NORMAL := Color(0.070, 0.102, 0.133, 0.92)
const BTN_HOVER := Color(0.122, 0.396, 0.439, 0.96)
const BTN_PRESSED := Color(0.161, 0.498, 0.541, 1.0)
const BTN_DANGER := Color(0.239, 0.090, 0.090, 0.92)
const BTN_DANGER_HOVER := Color(0.478, 0.141, 0.122, 0.98)

const CORNER_RADIUS := 5

# High-contrast CCB semantic palette
const C_WHITE := Color("e8f1f4")
const C_LTGRAY := Color("a9bcc4")
const C_DKGRAY := Color("697d87")
const C_CYAN := Color("57d1d6")
const C_LTCYAN := Color("9ef5f7")
const C_YELLOW := Color("f0d86c")
const C_BROWN := Color("d49852")
const C_GREEN := Color("5ed67e")
const C_LTGREEN := Color("8ef5a8")
const C_RED := Color("e65a5a")
const C_LTRED := Color("ff8278")
const C_EMBER := Color("f07a54")
const C_MAGENTA := Color("d384e8")
const C_BLUE := Color("6ca4f2")


static func box(bg := BG_PANEL, border := BORDER, pad_x := 10, pad_y := 7, border_w := 1, radius := CORNER_RADIUS) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


static func divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = DIVIDER
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


static func style_button(button: Button, highlight := false) -> void:
	var normal_bg := BG_ROW_ACTIVE if highlight else BTN_NORMAL
	var normal_bd := BORDER_CYAN if highlight else BORDER
	var hover_bg := BTN_HOVER
	var hover_bd := C_LTCYAN if highlight else BORDER_CYAN
	button.add_theme_stylebox_override("normal", box(normal_bg, normal_bd, 10, 5, 1, CORNER_RADIUS))
	button.add_theme_stylebox_override("hover", box(hover_bg, hover_bd, 10, 5, 1, CORNER_RADIUS))
	button.add_theme_stylebox_override("pressed", box(BTN_PRESSED, C_YELLOW, 10, 5, 1, CORNER_RADIUS))
	button.add_theme_stylebox_override("disabled", box(Color(0.04, 0.06, 0.08, 0.72), Color(0.18, 0.24, 0.27, 0.45), 10, 5, 1, CORNER_RADIUS))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", C_LTCYAN if highlight else C_WHITE)
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", C_YELLOW)
	button.add_theme_color_override("font_disabled_color", C_DKGRAY)
	button.add_theme_font_size_override("font_size", 13)


static func style_danger_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(BTN_DANGER, Color(0.62, 0.25, 0.24, 0.85), 10, 5, 1, CORNER_RADIUS))
	button.add_theme_stylebox_override("hover", box(BTN_DANGER_HOVER, C_LTRED, 10, 5, 1, CORNER_RADIUS))
	button.add_theme_stylebox_override("pressed", box(Color(0.58, 0.16, 0.14, 1.0), C_YELLOW, 10, 5, 1, CORNER_RADIUS))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color("ffd2cc"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_font_size_override("font_size", 13)


static func style_line_edit(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", box(BG_INPUT, BORDER, 8, 5, 1, 4))
	edit.add_theme_stylebox_override("focus", box(BG_INPUT, BORDER_CYAN, 8, 5, 1, 4))
	edit.add_theme_color_override("font_color", C_WHITE)
	edit.add_theme_color_override("font_placeholder_color", C_DKGRAY)
	edit.add_theme_color_override("caret_color", C_CYAN)


static func style_item_list(list: ItemList) -> void:
	list.add_theme_stylebox_override("panel", box(BG_INPUT, BORDER, 5, 5, 1, CORNER_RADIUS))
	list.add_theme_stylebox_override("selected", box(BG_ROW_ACTIVE, BORDER_CYAN, 6, 4, 1, 4))
	list.add_theme_stylebox_override("selected_focus", box(BG_ROW_ACTIVE, C_YELLOW, 6, 4, 1, 4))
	list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	list.add_theme_color_override("font_color", C_WHITE)
	list.add_theme_color_override("font_selected_color", C_LTCYAN)
	list.add_theme_color_override("font_hovered_color", C_WHITE)
	list.add_theme_font_size_override("font_size", 13)


static func style_popup(popup: PopupMenu) -> void:
	popup.add_theme_stylebox_override("panel", box(BG_FLOAT, BORDER_BRIGHT, 5, 5, 1, CORNER_RADIUS))
	popup.add_theme_stylebox_override("hover", box(BG_ROW_ACTIVE, BORDER_CYAN, 6, 4, 1, 4))
	popup.add_theme_color_override("font_color", C_WHITE)
	popup.add_theme_color_override("font_hover_color", C_LTCYAN)
	popup.add_theme_color_override("font_separator_color", C_CYAN)
	popup.add_theme_font_size_override("font_size", 13)


static func create_badge(text: String, accent := BORDER_CYAN, bg := Color(0.06, 0.14, 0.17, 0.92)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, accent, 7, 2, 1, 4))
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.45))
	p.add_child(lbl)
	return p


static func create_bar(height := 7.0, fill_color := C_GREEN) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.custom_minimum_size = Vector2(56, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.08, 0.10, 0.95)
	bg.border_color = Color(0.22, 0.34, 0.38, 0.65)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


static func set_bar_color(bar: ProgressBar, fill_color: Color) -> void:
	var sb: StyleBoxFlat = bar.get_theme_stylebox("fill")
	if sb != null:
		sb.bg_color = fill_color


static func hp_bar_text(hp: int, max_hp: int) -> String:
	var ratio := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	var pips := int(round(ratio * 5.0))
	var bar := ""
	for i in range(5):
		bar += "|" if i < pips else "."
	return bar


static func hp_bar_color(hp: int, max_hp: int) -> Color:
	var ratio := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	if ratio >= 0.8:
		return C_LTGREEN
	if ratio >= 0.55:
		return C_GREEN
	if ratio >= 0.30:
		return C_YELLOW
	return C_RED


static func letter_key(index: int) -> String:
	const KEYS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	if index >= 0 and index < KEYS.length():
		return KEYS[index]
	return "-"


static func phase_label_color(sky: Dictionary) -> Array:
	var alt_deg := rad_to_deg(float(sky.get("sun_altitude", 0.0)))
	var hour := float(sky.get("hour", 12.0))
	if alt_deg <= -12.0:
		return ["深夜", C_BLUE]
	if alt_deg <= -2.0:
		return ["拂晓" if hour < 12.0 else "暮色", C_BROWN]
	if alt_deg <= 10.0:
		return ["晨曦" if hour < 12.0 else "黄昏", C_YELLOW]
	if hour < 11.0:
		return ["上午", C_LTCYAN]
	if hour < 14.0:
		return ["正午", C_WHITE]
	return ["午后", C_WHITE]
