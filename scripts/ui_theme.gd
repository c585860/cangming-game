extends RefCounted

const BG_DEEP := Color("0c110f")
const BG_PANEL := Color("131b17")
const BG_CARD := Color("18221d")
const BG_HEADER := Color("101714")
const BORDER_JADE := Color("344a3f")
const BORDER_GOLD := Color("9f864f")
const BORDER_SOFT := Color("24322b")
const INK_IVORY := Color("eee7d4")
const INK_SOFT := Color("9fb0a4")
const INK_DIM := Color("6e7e74")
const GOLD := Color("e7c878")
const JADE := Color("79d4b0")
const SEAL_RED := Color("a83c32")


static func panel_box(bg: Color, border: Color, radius := 4, pad_x := 10, pad_y := 8, border_w := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


static func accent_card(bg: Color, accent: Color, border: Color = BORDER_SOFT, pad_x := 10, pad_y := 8) -> StyleBoxFlat:
	var box := panel_box(bg, border, 3, pad_x, pad_y, 1)
	box.border_width_left = 3
	box.border_color = border
	# Use a clean subtle border; caller can pair with a left accent bar when distinct color is needed.
	if accent != border:
		box.border_color = accent.lerp(border, 0.45)
	return box


static func pill_box(bg: Color, border: Color, pad_x := 8, pad_y := 2) -> StyleBoxFlat:
	return panel_box(bg, border, 10, pad_x, pad_y, 1)


static func style_button(button: Button, primary := false) -> void:
	var palettes := {
		"normal": [Color("1c2822") if primary else Color("17201c"), BORDER_GOLD if primary else BORDER_JADE],
		"hover": [Color("27362e") if primary else Color("212e28"), GOLD if primary else BORDER_GOLD],
		"pressed": [Color("304137") if primary else Color("2a3931"), GOLD],
		"disabled": [Color("121714"), Color("232c27")],
	}
	for state: String in palettes:
		var pair: Array = palettes[state]
		var box := panel_box(pair[0], pair[1], 3, 10, 5, 1)
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_color", GOLD if primary else INK_IVORY)
	button.add_theme_color_override("font_hover_color", Color("fff6df"))
	button.add_theme_color_override("font_pressed_color", Color("fff6df"))
	button.add_theme_color_override("font_disabled_color", Color("58685e"))


static func style_popup(menu: PopupMenu) -> void:
	menu.add_theme_stylebox_override("panel", panel_box(Color("121a16"), BORDER_GOLD, 4, 6, 6, 1))
	menu.add_theme_stylebox_override("hover", panel_box(Color("22312a"), BORDER_GOLD, 3, 6, 4, 1))
	menu.add_theme_color_override("font_color", INK_IVORY)
	menu.add_theme_color_override("font_hover_color", GOLD)


static func style_item_list(list: ItemList) -> void:
	list.add_theme_stylebox_override("panel", panel_box(Color("0f1512"), BORDER_JADE, 4, 6, 6, 1))
	list.add_theme_stylebox_override("selected", panel_box(Color("22332a"), BORDER_GOLD, 3, 6, 4, 1))
	list.add_theme_stylebox_override("selected_focus", panel_box(Color("22332a"), GOLD, 3, 6, 4, 1))
	list.add_theme_color_override("font_color", INK_IVORY)
	list.add_theme_color_override("font_selected_color", GOLD)
	list.add_theme_color_override("font_hovered_color", Color("fff5dc"))


static func style_line_edit(field: LineEdit) -> void:
	field.add_theme_stylebox_override("normal", panel_box(Color("0e1411"), BORDER_JADE, 3, 8, 6, 1))
	field.add_theme_stylebox_override("focus", panel_box(Color("121b17"), BORDER_GOLD, 3, 8, 6, 1))
	field.add_theme_color_override("font_color", INK_IVORY)
	field.add_theme_color_override("font_placeholder_color", INK_DIM)


static func hairline(vertical := false) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(BORDER_JADE.r, BORDER_JADE.g, BORDER_JADE.b, 0.55)
	if vertical:
		line.custom_minimum_size = Vector2(1, 0)
		line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		line.custom_minimum_size = Vector2(0, 1)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line


static func seal_stamp(parent: Node, glyph := "沧") -> PanelContainer:
	var seal := PanelContainer.new()
	var box := panel_box(Color("8f2d25"), Color("d97a66"), 3, 6, 2, 1)
	seal.add_theme_stylebox_override("panel", box)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = glyph
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("f9e9d2"))
	seal.add_child(label)
	parent.add_child(seal)
	return seal


static func phase_info(sky: Dictionary) -> Array:
	var h: float = sky.hour
	var sunrise: float = sky.sunrise
	var sunset: float = sky.sunset
	if absf(h - sunrise) <= 1.25:
		return ["晨曦", Color("e9b872"), Color("2c2419")]
	if h > sunrise + 1.25 and h < sunset - 1.25:
		return ["晴昼", Color("9cd9b8"), Color("182923")]
	if absf(h - sunset) <= 1.25:
		return ["暮色", Color("e49568"), Color("2c1f1a")]
	return ["星夜", Color("9cb8e8"), Color("18202c")]
