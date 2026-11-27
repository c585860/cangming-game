extends PanelContainer

# Authentic CCB Pixel Minimap dock rendered from live C++ FOV/memory/vehicle/monster RGBA bytes.

var _tex_rect: TextureRect
var _tex: ImageTexture
var enabled := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.96)
	sb.border_color = Color(0.55, 0.55, 0.55, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(2)
	add_theme_stylebox_override("panel", sb)

	_tex_rect = TextureRect.new()
	_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex_rect)
	visible = false


func update_minimap(snap: Dictionary, terrain_rect_px: Rect2) -> void:
	if not enabled or not bool(snap.get("valid", false)):
		visible = false
		return
	var sz := int(snap.get("minimap_size", 0))
	var rgba: PackedByteArray = snap.get("minimap_rgba", PackedByteArray())
	if sz <= 0 or rgba.size() < sz * sz * 4:
		visible = false
		return

	var img := Image.create_from_data(sz, sz, false, Image.FORMAT_RGBA8, rgba)
	if _tex == null or _tex.get_size() != Vector2(sz, sz):
		_tex = ImageTexture.create_from_image(img)
		_tex_rect.texture = _tex
	else:
		_tex.update(img)

	# Dock cleanly in the bottom-left corner of the GPU map viewport so it NEVER overlaps CCB's sidebar or message log!
	var box := clampf(minf(terrain_rect_px.size.x, terrain_rect_px.size.y) * 0.26, 128.0, 168.0)
	position = Vector2(terrain_rect_px.position.x + 8.0, terrain_rect_px.position.y + terrain_rect_px.size.y - box - 8.0)
	size = Vector2(box, box)
	visible = true


func toggle_enabled() -> bool:
	enabled = not enabled
	if not enabled:
		visible = false
	return enabled
