extends RefCounted

const Lighting = preload("res://scripts/lighting.gd")
const DISTANCE := 12
const PORTALS := {"w": 0.48, "O": 0.61, "o": 0.73}


static func _connects(data: Array) -> bool:
	return Lighting.enclosed(data) and data[0] not in [" ", "#", "D", "w"]


static func _can_step(cells: Dictionary, normals: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	if not _connects(cells.get(to, [])):
		return false
	var axis := (to - from).abs()
	var here: Vector2i = normals.get(from, Vector2i.ZERO)
	var there: Vector2i = normals.get(to, Vector2i.ZERO)
	return (here == Vector2i.ZERO or here == axis) and (there == Vector2i.ZERO or there == axis)


static func _sky_at_opening(cells: Dictionary, p: Vector2i, outward: Vector2i) -> float:
	var tangent := Vector2i(-outward.y, outward.x)
	var sky := 0.0
	for lateral in [-1, 0, 1]:
		var value := 0.0
		for distance in range(1, 5):
			var at := p + outward * distance + tangent * int(lateral) * (distance - 1)
			var data: Array = cells.get(at, [])
			if data.is_empty() or Lighting.enclosed(data) or data[0] in ["#", "D", "w"]:
				break
			if Lighting.sky_open(data):
				value += 0.25 / (1.0 + float(distance - 1) * 0.16)
		var weight := 0.50 if lateral == 0 else 0.25
		sky += value * weight
	return sky


static func _write(levels: Dictionary, p: Vector2i, intensity: float) -> void:
	var old := float(levels.get(p, 0.0))
	levels[p] = old + (1.0 - old) * intensity


static func _spread(cells: Dictionary, normals: Dictionary, levels: Dictionary,
		start: Vector2i, portal: Vector2i, strength: float) -> void:
	var queue: Array[Vector2i] = [start]
	var distances := {}
	distances[start] = 0
	distances[portal] = 0
	var inward := Vector2(start - portal)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		var steps := int(distances[p])
		# Measure from the inner face of the aperture. Light that reaches a
		# tile via a detour should be weaker than light facing the opening.
		var offset := p - start
		var displacement := Vector2(offset) + inward * 0.5
		var radius := displacement.length()
		var facing := clampf(displacement.dot(inward) / radius, 0.0, 1.0)
		var detour := float(steps - absi(offset.x) - absi(offset.y))
		var distance := radius + maxf(detour, 0.0) * 0.60
		var spread := lerpf(0.30, 1.0, facing) / (1.0 + 0.11 * distance * distance)
		var edge := 1.0 - smoothstep(float(DISTANCE - 4), float(DISTANCE), float(steps))
		_write(levels, p, strength * spread * edge)
		for step: Vector2i in Lighting.CARDINAL:
			var at := p + step
			if steps + 1 >= DISTANCE or distances.has(at) or not _can_step(cells, normals, p, at):
				continue
			distances[at] = steps + 1
			queue.append(at)


static func _incident_surfaces(cells: Dictionary, levels: Dictionary) -> Dictionary:
	var incident := {}
	for p: Vector2i in levels:
		if not _connects(cells[p]):
			continue
		var light := float(levels[p])
		var walls := 0
		for step: Vector2i in Lighting.CARDINAL:
			var neighbor: Array = cells.get(p + step, [])
			if not neighbor.is_empty() and neighbor[0] in ["#", "D"]:
				walls += 1
		# A wall face picks up light only from the room on that face's side.
		incident[p] = light * (1.0 + 0.16 * mini(walls, 2))
	return incident


static func _reflect(cells: Dictionary, normals: Dictionary, incident: Dictionary, receiver: Vector2i) -> float:
	if not _connects(cells[receiver]):
		return 0.0
	var total := float(incident.get(receiver, 0.0)) * 0.26
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var direction := Vector2i(dx, dy)
			var from := receiver
			for distance in range(1, 4):
				var to := from + direction
				if dx != 0 and dy != 0:
					var a := from + Vector2i(dx, 0)
					var b := from + Vector2i(0, dy)
					if not (_can_step(cells, normals, from, a) and _can_step(cells, normals, from, b)
							and _can_step(cells, normals, a, to) and _can_step(cells, normals, b, to)):
						break
				elif not _can_step(cells, normals, from, to):
					break
				var falloff := 1.0 + float(direction.length_squared() * distance * distance)
				total += float(incident.get(to, 0.0)) / falloff
				from = to
	return 1.0 - exp(-total * 0.50)


static func bake(cells: Dictionary, area: Rect2i, z: int) -> ImageTexture:
	var image := Image.create_empty(area.size.x, area.size.y, false, Image.FORMAT_RG8)
	image.fill(Color.BLACK)
	if z < 0:
		return ImageTexture.create_from_image(image)
	var portals := {}
	for p: Vector2i in cells:
		var data: Array = cells[p]
		if Lighting.enclosed(data) and PORTALS.has(data[0]):
			portals[p] = Lighting.aperture_normal(cells, p, 0)
	var levels := {}
	for p: Vector2i in portals:
		var normal: Vector2i = portals[p]
		for outward: Vector2i in [normal, -normal]:
			var entry := p - outward
			if not _connects(cells.get(entry, [])):
				continue
			var visible_sky := _sky_at_opening(cells, p, outward)
			if visible_sky <= 0.01:
				continue
			var strength := float(PORTALS[cells[p][0]]) * visible_sky
			_write(levels, p, strength)
			_spread(cells, portals, levels, entry, p, strength)
	var incident := _incident_surfaces(cells, levels)
	for p: Vector2i in levels:
		image.set_pixelv(p - area.position, Color(float(levels[p]), _reflect(cells, portals, incident, p), 0.0))
	return ImageTexture.create_from_image(image)
