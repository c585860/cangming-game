extends Control

const Art = preload("res://scripts/street_art.gd")
const MaskShader = preload("res://scripts/surface_mask.gdshader")

var view_origin := Vector2i.ZERO
var cell := 32
var cells: Dictionary
var props: Rect2i
var seed: int
var season := "spring"
var characters: Array = []
var roof_tiles: Dictionary = {}
var _pass_flags := 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shader_material := ShaderMaterial.new()
	shader_material.shader = MaskShader
	material = shader_material


func surface_id(p: Vector2i) -> Color:
	var id := p - view_origin + Vector2i(2, 2)
	# Low bits store high-order tile offset; bit 6 (64) = roof cover, bit 7 (128) = character.
	var high := ((id.x >> 8) & 3) + (((id.y >> 8) & 3) << 4)
	high |= _pass_flags
	return Color(float(id.x & 255) / 255.0, float(id.y & 255) / 255.0, float(high) / 255.0)


func _draw() -> void:
	_pass_flags = 0
	for y in range(props.position.y, props.end.y):
		for x in range(props.position.x, props.end.x):
			var p := Vector2i(x, y)
			if roof_tiles.has(p):
				continue
			Art.walls(self, cells, p, seed, season)
			Art.detail(self, null, cells, p, seed, season)
	if not roof_tiles.is_empty():
		_pass_flags = 64
		for p: Vector2i in roof_tiles:
			if props.has_point(p):
				var o := Vector2((p - view_origin) * cell)
				draw_rect(Rect2(o, Vector2.ONE * float(cell)), surface_id(p))
	_pass_flags = 128
	for entry: Array in characters:
		Art.character(self, entry[0], entry[1], self)
	_pass_flags = 0
