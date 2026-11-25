extends RefCounted

# Port of the CCB lightmap passes (lightmap.cpp / calendar.cpp, CC BY-SA 3.0).
# City tiles replace CCB's floor and transparency caches. Rendering uses its per-tile mode.
const AMBIENT_LOW := 3.5
const AMBIENT_MINIMAL := 3.7
const AMBIENT_DIM := 5.0
const AMBIENT_LIT := 10.0
const CARDINAL := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]


static func _natural_light(sky: Dictionary) -> float:
	var angle := rad_to_deg(float(sky.sun_altitude))
	var solar := 0.0
	if angle > -1.0:
		solar = minf(125.0, 60.0 + (angle + 1.0) * 65.0 / 61.0)
	elif angle > -6.0:
		solar = 5.0 + 55.0 * (pow(2.0, (angle + 6.0) / 5.0) - 1.0)
	elif angle > -12.0:
		solar = 3.7 + 1.3 * (pow(2.0, (angle + 12.0) / 6.0) - 1.0)
	elif angle > -18.0:
		solar = 3.7 * (pow(2.0, (angle + 18.0) / 6.0) - 1.0)
	var moon := 7.0 * float(sky.moon_illumination) * float(sky.moon_above_horizon)
	return maxf(AMBIENT_MINIMAL, solar + moon)


static func enclosed(cell: Array) -> bool:
	return not cell.is_empty() and (int(cell[3]) & 1) != 0


static func sky_open(cell: Array) -> bool:
	return not cell.is_empty() and (int(cell[3]) & 0xaa) == 0


static func _transmission(cell: Array) -> float:
	if cell.is_empty() or cell[0] in ["#", "D", " "]:
		return 0.0
	match cell[0]:
		"w": return 0.72
		"Y": return 0.48
		"g", "f": return 0.80
		_: return 1.0


static func _wall_at(cells: Dictionary, p: Vector2i, layer: int) -> bool:
	var data: Array = cells.get(p, [])
	if data.is_empty():
		return false
	var tiles: PackedStringArray = data[2]
	var tile: String = data[0] if layer == 0 else tiles[layer - 1] if layer <= tiles.size() else " "
	return tile in ["#", "D", "o", "w", "O"]


static func aperture_normal(cells: Dictionary, p: Vector2i, layer: int) -> Vector2i:
	if layer == 0:
		for axis: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var a: Array = cells.get(p + axis, [])
			var b: Array = cells.get(p - axis, [])
			if not a.is_empty() and not b.is_empty() and enclosed(a) != enclosed(b) and not _wall_at(cells, p + axis, 0) and not _wall_at(cells, p - axis, 0):
				return axis
	var along_x := int(_wall_at(cells, p + Vector2i.LEFT, layer)) + int(_wall_at(cells, p + Vector2i.RIGHT, layer))
	var along_y := int(_wall_at(cells, p + Vector2i.UP, layer)) + int(_wall_at(cells, p + Vector2i.DOWN, layer))
	return Vector2i.RIGHT if along_y > along_x else Vector2i.DOWN


static func _ray_transmission(cells: Dictionary, start: Vector2i, end: Vector2i) -> float:
	var p := start
	var delta := (end - start).abs()
	var step := Vector2i(signi(end.x - start.x), signi(end.y - start.y))
	var error := delta.x - delta.y
	var transmission := 1.0
	while p != end:
		var previous := p
		var twice := 2 * error
		if twice > -delta.y:
			error -= delta.y
			p.x += step.x
		if twice < delta.x:
			error += delta.x
			p.y += step.y
		if p.x != previous.x and p.y != previous.y:
			if _transmission(cells.get(Vector2i(p.x, previous.y), [])) == 0.0 and _transmission(cells.get(Vector2i(previous.x, p.y), [])) == 0.0:
				return 0.0
		if p != end: # The face of an opaque destination can still be lit.
			transmission *= _transmission(cells.get(p, []))
			if transmission <= 0.02:
				return 0.0
	return transmission


static func calculate_ambient(cells: Dictionary, region: Rect2i, sky: Dictionary, z: int) -> Dictionary:
	var outdoor := _natural_light(sky)
	var inside := AMBIENT_DIM * 0.8 if z >= 0 and outdoor > AMBIENT_LIT else AMBIENT_LOW
	var daylight_tint := Color.WHITE.lerp(Color(1.0, 0.78, 0.57), float(sky.sun_warmth) * 0.75)
	var tints := {}
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var p := Vector2i(x, y)
			var data: Array = cells[p]
			if data[0] == " ":
				continue
			var natural := inside
			if z >= 0 and not enclosed(data):
				natural = outdoor if sky_open(data) else lerpf(inside, outdoor, 0.35)
			elif z >= 0 and data[0] in ["#", "D", "w", "O", "o"]:
				# Only the exterior face receives the outdoor field; the interior face picks up room light.
				var exterior: Array = cells.get(p + Vector2i.DOWN, [])
				if sky_open(exterior) and not enclosed(exterior) and not _wall_at(cells, p + Vector2i.DOWN, 0):
					var exterior_fill := 0.30 if data[0] in ["w", "O"] else 0.64
					natural = lerpf(inside, outdoor, exterior_fill)
			var level := maxf(natural - AMBIENT_LOW, 0.0)
			var daylight := 1.0 - exp(-level / 56.0)
			var twilight := 1.0 - exp(-level / 9.0)
			var hue := Color(0.74, 0.81, 1.0).lerp(daylight_tint, twilight)
			var brightness := 0.23 + twilight * 0.17 + daylight * 0.42
			tints[p] = Color(hue.r * brightness, hue.g * brightness, hue.b * brightness)
	return tints
