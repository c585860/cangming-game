extends Control

# Pure Vanilla Cataclysm-Cleanwater-Bomb (CCB) Local Pixel Minimap
# Faithfully ported from Cataclysm-Cleanwater-Bomb/src/pixel_minimap.cpp:
#  - Renders the local reality bubble (e.g. 81x81 tiles around player) as crisp per-tile pixels
#  - Walls (gray), doors (brown), windows (cyan), trees (forest green), pavement (slate),
#    furniture (tan), ground items (yellow highlight), corpses (dark red),
#    hostile monsters (blinking red beacons), player (white/green center crosshair)
#  - Toggleable via 'N' key or '}' Sidebar Manager!

var _world: RefCounted
var _radius := 40
var _tex: ImageTexture = null
var _img: Image = null
var _blink_t := 0.0
var _blink_on := true


func build(world: RefCounted, radius := 40) -> void:
	_world = world
	_radius = clampi(radius, 20, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func refresh() -> void:
	if _world == null or not _world.has_method("ccb_pixel_minimap_data"):
		return
	if not _world.is_cataclysm_pack():
		return
	var d: Dictionary = _world.ccb_pixel_minimap_data(_radius)
	var w: int = int(d.get("width", 0))
	var h: int = int(d.get("height", 0))
	var rgba: PackedByteArray = d.get("rgba", PackedByteArray())
	if w <= 0 or h <= 0 or rgba.size() != w * h * 4:
		return
	if _img == null or _img.get_width() != w or _img.get_height() != h:
		_img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
		_tex = ImageTexture.create_from_image(_img)
	else:
		_img.set_data(w, h, false, Image.FORMAT_RGBA8, rgba)
		_tex.update(_img)
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_blink_t += delta
	if _blink_t >= 0.45:
		_blink_t = 0.0
		_blink_on = not _blink_on
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 1.0))
	if _tex == null:
		return
	var side := floorf(minf(size.x - 4.0, size.y - 4.0))
	if side < 16.0:
		return
	var origin := Vector2((size.x - side) * 0.5, (size.y - side) * 0.5)
	draw_texture_rect(_tex, Rect2(origin, Vector2(side, side)), false)
	# Crisp 1px CCB border around pixel minimap
	draw_rect(Rect2(origin - Vector2.ONE, Vector2(side + 2.0, side + 2.0)), Color(1.0, 1.0, 1.0, 0.48), false, 1.0)
	# Subtle center player reticle blink (exact pixel_minimap.cpp beacon)
	if _blink_on:
		var c := origin + Vector2(side * 0.5, side * 0.5)
		draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 1.0, 0.45, 0.9), false, 1.0)
