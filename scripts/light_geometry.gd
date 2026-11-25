extends RefCounted

const Lighting = preload("res://scripts/lighting.gd")
const REACH := 28
const HEIGHTS := {"Y": 2.49, "g": 0.48, "f": 0.95, "b": 0.40, "c": 0.65,
	"C": 0.65, "t": 0.60, "k": 0.78, "K": 0.96, "q": 0.48, "S": 0.55, "F": 1.63,
	"P": 0.84, "r": 1.50, "l": 0.67, "h": 0.73, "a": 0.94, "u": 0.74, "L": 2.24}
const WOOD_REFLECTANCE := Color(0.76, 0.54, 0.36)
const PLASTER_REFLECTANCE := Color(0.84, 0.78, 0.65)
const STONE_REFLECTANCE := Color(0.64, 0.67, 0.71)
const SURFACE_REFLECTANCE := {
	"m": Color(0.60, 0.62, 0.65),
	"p": Color(0.76, 0.71, 0.60),
	"G": Color(0.76, 0.71, 0.60),
	"j": Color(0.74, 0.71, 0.66),
	"J": Color(0.74, 0.71, 0.66),
	"R": Color(0.84, 0.25, 0.24),
	"d": Color(0.64, 0.50, 0.35),
	"H": PLASTER_REFLECTANCE,
	"N": WOOD_REFLECTANCE,
	"B": STONE_REFLECTANCE,
}
const FURNITURE_REFLECTANCE := {
	"b": Color(0.78, 0.73, 0.64),
	"k": Color(0.76, 0.62, 0.48),
	"K": Color(0.72, 0.58, 0.44),
	"u": Color(0.68, 0.62, 0.52),
	"a": Color(0.62, 0.52, 0.42),
	"h": Color(0.55, 0.42, 0.34),
	"P": Color(0.32, 0.64, 0.30),
}


static func _tile(cells: Dictionary, p: Vector2i, layer: int) -> String:
	if not cells.has(p):
		return " "
	var data: Array = cells[p]
	if layer == 0:
		return data[0]
	var above: PackedStringArray = data[2]
	return above[layer - 1] if layer <= above.size() else " "


static func encode(cells: Dictionary, area: Rect2i, layers: int) -> ImageTexture:
	var image := Image.create_empty(area.size.x * layers, area.size.y, false, Image.FORMAT_RGBA8)
	for layer in range(layers):
		for y in range(area.size.y):
			for x in range(area.size.x):
				var p := area.position + Vector2i(x, y)
				var data: Array = cells[p]
				var tile := _tile(cells, p, layer)
				var height := float(HEIGHTS.get(tile, 0.0))
				var kind := 0
				var axis := 0.0
				if tile in ["#", "D"]:
					height = 0.95 if layer == 0 and data[1] == "G" else 2.5
					kind = 1
				elif tile in ["w", "O", "o"] and not (layer == 0 and data[1] == "G"):
					height = 2.5
					kind = 2 if tile == "w" else 3 if tile == "O" else 4
					axis = float(Lighting.aperture_normal(cells, p, layer).x)
				elif height > 0.0:
					kind = 8 if tile == "L" else 5 if tile == "Y" else 6 if tile in ["g", "f", "P"] else 7
				elif layer == 0:
					var surf: String = data[1]
					if surf in ["m", "p", "G", "j", "J"] or tile == "+":
						axis = 1.0
					elif tile == ":" or surf == "d":
						axis = 0.5
				var flags := (int(data[3]) >> (layer * 2)) & 3
				image.set_pixel(x + layer * area.size.x, y, Color(height / 3.0, float(kind) / 255.0, axis, float(flags) / 3.0))
	return ImageTexture.create_from_image(image)


static func bounce_materials(cells: Dictionary, area: Rect2i, season := "spring") -> ImageTexture:
	# Encode physical colored albedo for BOTH indoor and outdoor surfaces so GI reflects rich environmental color!
	var grass_col := Color(0.28, 0.62, 0.25)
	match season:
		"summer": grass_col = Color(0.24, 0.58, 0.22)
		"autumn": grass_col = Color(0.68, 0.50, 0.24)
		"winter": grass_col = Color(0.66, 0.72, 0.78)
	var image := Image.create_empty(area.size.x, area.size.y, false, Image.FORMAT_RGB8)
	for p: Vector2i in cells:
		var data: Array = cells[p]
		var tile: String = data[0]
		var surf: String = data[1]
		if tile == " ":
			continue
		var color := WOOD_REFLECTANCE
		if tile in ["#", "D", "w", "O"]:
			color = STONE_REFLECTANCE if surf == "B" else WOOD_REFLECTANCE if surf == "N" else PLASTER_REFLECTANCE
		elif tile in ["W", "~"]:
			# Shimmering aqua-jade river water reflects cyan-teal caustics onto docks, bridges, and banks!
			color = Color(0.22, 0.72, 0.78) if tile == "~" else Color(0.18, 0.56, 0.72)
		elif tile == "=":
			color = Color(0.76, 0.58, 0.38)
		elif tile in ["s", ":"]:
			color = Color(0.84, 0.72, 0.48)
		elif tile in [".", "g", "Y", "f", "L"] and surf == "":
			color = grass_col
		elif HEIGHTS.has(tile) and tile not in ["Y", "g", "f", "L"]:
			color = FURNITURE_REFLECTANCE.get(tile, WOOD_REFLECTANCE)
		elif SURFACE_REFLECTANCE.has(surf):
			color = SURFACE_REFLECTANCE[surf]
		elif tile == "+":
			color = Color(0.72, 0.68, 0.58)
		image.set_pixelv(p - area.position, color)
	return ImageTexture.create_from_image(image)


static func river_field(cells: Dictionary, area: Rect2i, z: int) -> ImageTexture:
	var image := Image.create_empty(area.size.x, area.size.y, false, Image.FORMAT_RGB8)
	if z != 0:
		return ImageTexture.create_from_image(image)
	var width := area.size.x
	var length := width * area.size.y
	var distance := PackedInt32Array()
	distance.resize(length)
	distance.fill(REACH * 2)
	var shore := PackedInt32Array()
	shore.resize(length)
	shore.fill(REACH * 2)
	var water := PackedByteArray()
	water.resize(length)
	for i in range(length):
		@warning_ignore("integer_division")
		var y := i / width
		@warning_ignore("integer_division")
		var x := i % width
		var tile: String = cells[area.position + Vector2i(x, y)][0]
		if tile in ["W", "~"]:
			water[i] = 255 if tile == "W" else 112
			distance[i] = 0
		else:
			shore[i] = 0
		if x > 0:
			distance[i] = mini(distance[i], distance[i - 1] + 1)
			shore[i] = mini(shore[i], shore[i - 1] + 1)
		if y > 0:
			distance[i] = mini(distance[i], distance[i - width] + 1)
			shore[i] = mini(shore[i], shore[i - width] + 1)
	for i in range(length - 1, -1, -1):
		@warning_ignore("integer_division")
		var y := i / width
		@warning_ignore("integer_division")
		var x := i % width
		if x + 1 < width:
			distance[i] = mini(distance[i], distance[i + 1] + 1)
			shore[i] = mini(shore[i], shore[i + 1] + 1)
		if y + 1 < area.size.y:
			distance[i] = mini(distance[i], distance[i + width] + 1)
			shore[i] = mini(shore[i], shore[i + width] + 1)
		var signed_shore := 0.5 + 0.125 * float(clampi(shore[i] - distance[i], -4, 4))
		image.set_pixel(x, y, Color(1.0 - smoothstep(0.0, float(REACH - 3), float(distance[i])),
			float(water[i]) / 255.0, signed_shore))
	return ImageTexture.create_from_image(image)
