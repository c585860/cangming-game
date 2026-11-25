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
var slice_y0 := 0
var slice_y1 := 0
var draw_chars := true
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
	var y_start := slice_y0 if slice_y1 > slice_y0 else props.position.y
	var y_end := slice_y1 if slice_y1 > slice_y0 else props.end.y
	for y in range(y_start, y_end):
		for x in range(props.position.x, props.end.x):
			var p := Vector2i(x, y)
			if cells.has(p):
				Art.walls(self, cells, p, seed, season)
				Art.detail(self, null, cells, p, seed, season)
	if draw_chars:
		_pass_flags = 128
		for entry: Array in characters:
			var motion: CharacterMotion = entry[4]
			if motion != null:
				motion.draw_character(self, self, entry[1], entry[0], entry[2], entry[3])
			else:
				Art.character(self, entry[3], entry[1], self)
	_pass_flags = 0
