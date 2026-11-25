extends Control

const Art = preload("res://scripts/street_art.gd")
const MaskShader = preload("res://scripts/surface_mask.gdshader")
const CharacterMotion = preload("res://scripts/character_motion.gd")

var view_origin := Vector2i.ZERO
var cam_px_offset := Vector2.ZERO
var cell := 32
var cells: Dictionary
var props: Rect2i
var seed: int
var season := "spring"
var characters: Array = [] # [world_pos: Vector2, role: StringName, animated: bool, tile: Vector2i, motion: CharacterMotion]
var _pass_flags := 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shader_material := ShaderMaterial.new()
	shader_material.shader = MaskShader
	material = shader_material


func surface_id(p: Vector2i) -> Color:
	var id := p - view_origin + Vector2i(2, 2)
	var high := ((id.x >> 8) & 7) + (((id.y >> 8) & 7) << 4)
	high |= _pass_flags
	return Color(float(id.x & 255) / 255.0, float(id.y & 255) / 255.0, float(high) / 255.0)


func _draw() -> void:
	_pass_flags = 0
	for y in range(props.position.y, props.end.y):
		for x in range(props.position.x, props.end.x):
			var p := Vector2i(x, y)
			Art.walls(self, cells, p, seed, season)
			Art.detail(self, null, cells, p, seed, season)
	_pass_flags = 128
	for entry: Array in characters:
		var motion: CharacterMotion = entry[4]
		if motion != null:
			motion.draw_character(self, self, entry[1], entry[0], entry[2], entry[3])
		else:
			Art.character(self, entry[3], entry[1], self)
	_pass_flags = 0
