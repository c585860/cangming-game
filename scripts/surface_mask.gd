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
var _character_pass := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shader_material := ShaderMaterial.new()
	shader_material.shader = MaskShader
	material = shader_material


func surface_id(p: Vector2i) -> Color:
	var id := p - view_origin + Vector2i(2, 2)
	var high := ((id.x >> 8) & 7) + (((id.y >> 8) & 7) << 4)
	if _character_pass:
		high |= 128
	return Color(float(id.x & 255) / 255.0, float(id.y & 255) / 255.0, float(high) / 255.0)


func _draw() -> void:
	_character_pass = false
	for y in range(props.position.y, props.end.y):
		for x in range(props.position.x, props.end.x):
			var p := Vector2i(x, y)
			Art.walls(self, cells, p, seed, season)
			Art.detail(self, null, cells, p, seed, season)
	_character_pass = true
	for entry: Array in characters:
		Art.character(self, entry[0], entry[1], self)
	_character_pass = false
