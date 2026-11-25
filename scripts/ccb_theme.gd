extends RefCounted

# Authentic Cataclysm-Cleanwater-Bomb (CCB) Classic Dark Terminal UI Theme.
# Sharp 1px borders, pure black/charcoal panels, high-contrast curses palette,
# zero decorative seals or rounded pills.

const BG_SCREEN := Color("080808")
const BG_PANEL := Color("0d0d0d")
const BG_HEADER := Color("141414")
const BG_ROW_HOVER := Color("1c2426")
const BG_ROW_ACTIVE := Color("1e3236")
const BG_INPUT := Color("0a0a0a")

const BORDER := Color("565656")
const BORDER_BRIGHT := Color("8c8c8c")
const BORDER_CYAN := Color("4ca6a6")
const DIVIDER := Color("2d2d2d")

# Authentic CCB curses color palette
const C_WHITE := Color("e4e4e4")
const C_LTGRAY := Color("b6b6b6")
const C_DKGRAY := Color("757575")
const C_CYAN := Color("5cd6d6")
const C_LTCYAN := Color("94f0f0")
const C_YELLOW := Color("ead662")
const C_BROWN := Color("c48a46")
const C_GREEN := Color("5ed45e")
const C_LTGREEN := Color("8cf28c")
const C_RED := Color("e25656")
const C_LTRED := Color("ff7c7c")
const C_MAGENTA := Color("cf7ee0")
const C_BLUE := Color("6298e8")


static func box(bg := BG_PANEL, border := BORDER, pad_x := 8, pad_y := 6, border_w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(0)
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
	var normal_bg := Color("121d1f") if highlight else Color("111111")
	var normal_bd := BORDER_CYAN if highlight else Color("343434")
	var hover_bg := BG_ROW_ACTIVE if highlight else BG_ROW_HOVER
	var hover_bd := C_CYAN if highlight else BORDER_BRIGHT
	button.add_theme_stylebox_override("normal", box(normal_bg, normal_bd, 8, 4, 1))
	button.add_theme_stylebox_override("hover", box(hover_bg, hover_bd, 8, 4, 1))
	button.add_theme_stylebox_override("pressed", box(Color("243c40"), C_YELLOW, 8, 4, 1))
	button.add_theme_stylebox_override("disabled", box(Color("0c0c0c"), Color("222222"), 8, 4, 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", C_LTCYAN if highlight else C_WHITE)
	button.add_theme_color_override("font_hover_color", C_YELLOW)
	button.add_theme_color_override("font_pressed_color", C_YELLOW)
	button.add_theme_color_override("font_disabled_color", C_DKGRAY)
	button.add_theme_font_size_override("font_size", 13)


static func style_line_edit(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", box(BG_INPUT, BORDER, 8, 5, 1))
	edit.add_theme_stylebox_override("focus", box(BG_INPUT, C_CYAN, 8, 5, 1))
	edit.add_theme_color_override("font_color", C_WHITE)
	edit.add_theme_color_override("font_placeholder_color", C_DKGRAY)
	edit.add_theme_color_override("caret_color", C_YELLOW)


static func style_item_list(list: ItemList) -> void:
	list.add_theme_stylebox_override("panel", box(BG_INPUT, BORDER, 4, 4, 1))
	list.add_theme_stylebox_override("selected", box(BG_ROW_ACTIVE, C_CYAN, 6, 3, 1))
	list.add_theme_stylebox_override("selected_focus", box(BG_ROW_ACTIVE, C_YELLOW, 6, 3, 1))
	list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	list.add_theme_color_override("font_color", C_WHITE)
	list.add_theme_color_override("font_selected_color", C_YELLOW)
	list.add_theme_color_override("font_hovered_color", C_LTCYAN)
	list.add_theme_font_size_override("font_size", 13)


static func style_popup(popup: PopupMenu) -> void:
	popup.add_theme_stylebox_override("panel", box(BG_PANEL, BORDER_BRIGHT, 4, 4, 1))
	popup.add_theme_stylebox_override("hover", box(BG_ROW_ACTIVE, C_CYAN, 6, 3, 1))
	popup.add_theme_color_override("font_color", C_WHITE)
	popup.add_theme_color_override("font_hover_color", C_YELLOW)
	popup.add_theme_color_override("font_separator_color", C_CYAN)
	popup.add_theme_font_size_override("font_size", 13)


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
