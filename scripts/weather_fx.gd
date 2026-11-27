extends ColorRect

# GPU-accelerated rain & snow precipitation overlay.
# Runs entirely in weather_fx.gdshader (0.0 ms CPU per frame), while syncing a tiny
# R8 revealed-interior mask texture only when nearby roofs fade open/closed.

const FxShader = preload("res://scripts/weather_fx.gdshader")

var _mat := ShaderMaterial.new()
var _mask_tex: ImageTexture
var _last_interior_sig := -1
var _last_origin := Vector2i(-99999, -99999)
var _last_span := Vector2i.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	color = Color.WHITE
	_mat.shader = FxShader
	material = _mat
	visible = false


func configure(rain_strength: float, snow_strength: float, day_level: float,
		view_world: Vector2, view_span: Vector2, screen_px: Vector2,
		view_origin := Vector2i.ZERO, view_size := Vector2i.ONE, interior := {}) -> void:
	var active := rain_strength > 0.01 or snow_strength > 0.01
	visible = active
	if not active:
		return
	_mat.set_shader_parameter("rain", rain_strength)
	_mat.set_shader_parameter("snow", snow_strength)
	_mat.set_shader_parameter("daylight", day_level)
	_mat.set_shader_parameter("view_world", view_world)
	_mat.set_shader_parameter("view_span", view_span)
	_mat.set_shader_parameter("viewport_px", screen_px.max(Vector2(2.0, 2.0)))
	_sync_interior_mask(view_origin, view_size, interior)


func set_view(view_world: Vector2, view_span: Vector2, screen_px: Vector2) -> void:
	if not visible:
		return
	_mat.set_shader_parameter("view_world", view_world)
	_mat.set_shader_parameter("view_span", view_span)
	_mat.set_shader_parameter("viewport_px", screen_px.max(Vector2(2.0, 2.0)))


# Zero-allocation GPU path: uploads C++-packed R8 interior occlusion bytes directly (zero Dictionary loop!)
func configure_mask_bytes(rain_strength: float, snow_strength: float, day_level: float,
		view_world: Vector2, view_span: Vector2, screen_px: Vector2,
		mask_origin: Vector2i, mask_size: Vector2i, mask_bytes: PackedByteArray, mask_sig: int) -> void:
	var active := rain_strength > 0.01 or snow_strength > 0.01
	visible = active
	if not active:
		return
	_mat.set_shader_parameter("rain", rain_strength)
	_mat.set_shader_parameter("snow", snow_strength)
	_mat.set_shader_parameter("daylight", day_level)
	_mat.set_shader_parameter("view_world", view_world)
	_mat.set_shader_parameter("view_span", view_span)
	_mat.set_shader_parameter("viewport_px", screen_px.max(Vector2(2.0, 2.0)))
	if mask_size.x <= 0 or mask_size.y <= 0 or mask_bytes.size() < mask_size.x * mask_size.y:
		_mat.set_shader_parameter("has_interior_mask", false)
		return
	if mask_sig == _last_interior_sig and mask_origin == _last_origin and mask_size == _last_span and _mask_tex != null:
		return
	_last_interior_sig = mask_sig
	_last_origin = mask_origin
	_last_span = mask_size
	var img := Image.create_from_data(mask_size.x, mask_size.y, false, Image.FORMAT_R8, mask_bytes)
	if _mask_tex == null or _mask_tex.get_size() != Vector2(mask_size):
		_mask_tex = ImageTexture.create_from_image(img)
	else:
		_mask_tex.update(img)
	_mat.set_shader_parameter("interior_mask", _mask_tex)
	_mat.set_shader_parameter("mask_origin", Vector2(mask_origin))
	_mat.set_shader_parameter("mask_size", Vector2(mask_size))
	_mat.set_shader_parameter("has_interior_mask", true)


func _sync_interior_mask(view_origin: Vector2i, view_size: Vector2i, interior: Dictionary) -> void:
	if interior.is_empty():
		if _last_interior_sig != 0:
			_last_interior_sig = 0
			_mat.set_shader_parameter("has_interior_mask", false)
		return
	var sig := interior.size() * 73856093 ^ (view_origin.x * 19349663) ^ (view_origin.y * 83492791)
	if sig == _last_interior_sig and view_origin == _last_origin and view_size == _last_span:
		return
	_last_interior_sig = sig
	_last_origin = view_origin
	_last_span = view_size
	var w := maxi(1, view_size.x + 2)
	var h := maxi(1, view_size.y + 2)
	var mask_origin := view_origin - Vector2i.ONE
	var buf := PackedByteArray()
	buf.resize(w * h)
	var any_set := false
	for p: Vector2i in interior:
		var lx := p.x - mask_origin.x
		var ly := p.y - mask_origin.y
		if lx >= 0 and ly >= 0 and lx < w and ly < h:
			buf[ly * w + lx] = 255
			any_set = true
	if not any_set:
		_mat.set_shader_parameter("has_interior_mask", false)
		return
	var img := Image.create_from_data(w, h, false, Image.FORMAT_R8, buf)
	if _mask_tex == null or _mask_tex.get_size() != Vector2(w, h):
		_mask_tex = ImageTexture.create_from_image(img)
	else:
		_mask_tex.update(img)
	_mat.set_shader_parameter("interior_mask", _mask_tex)
	_mat.set_shader_parameter("mask_origin", Vector2(mask_origin))
	_mat.set_shader_parameter("mask_size", Vector2(w, h))
	_mat.set_shader_parameter("has_interior_mask", true)
