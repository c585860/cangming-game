extends RefCounted

const Lighting = preload("res://scripts/lighting.gd")
const SLOTS := 4
const REACH := 9

# Format: [z_height, energy, color, flicker_kind (0=steady, 1=flame, 2=qi), always_fraction (0..0.9)]
const LAMP_STREET := [2.05, 26.0, Color(1.0, 0.74, 0.40), 1.0, 0.0]
const LAMP_HEARTH := [0.82, 16.5, Color(1.0, 0.48, 0.18), 1.0, 0.55]
const LAMP_INDOOR := [1.28, 12.5, Color(1.0, 0.77, 0.46), 1.0, 0.22]
const LAMP_MARKET := [2.05, 24.0, Color(1.0, 0.76, 0.42), 1.0, 0.0]
const LAMP_BRIDGE := [1.95, 19.0, Color(1.0, 0.73, 0.39), 1.0, 0.0]
const LAMP_ALTAR := [1.15, 19.5, Color(0.36, 0.96, 0.78), 2.0, 0.65]
const LAMP_HERB := [0.35, 6.0, Color(0.45, 0.94, 0.74), 2.0, 0.28]


static func _hash(p: Vector2i, seed: int) -> int:
	var n := ((p.x * 0x9e3779b9) ^ (p.y * 0x85ebca6b) ^ seed) & 0xffffffff
	n = ((n ^ (n >> 16)) * 0x7feb352d) & 0xffffffff
	return n ^ (n >> 15)


static func _is_bridge_post(cells: Dictionary, p: Vector2i) -> bool:
	if cells[p][0] != "=":
		return false
	var north: Array = cells.get(p + Vector2i.UP, [])
	var south: Array = cells.get(p + Vector2i.DOWN, [])
	var edge: bool = (not north.is_empty() and north[0] in ["~", "W"]) or (not south.is_empty() and south[0] in ["~", "W"])
	if not edge:
		return false
	var west: Array = cells.get(p + Vector2i.LEFT, [])
	var east: Array = cells.get(p + Vector2i.RIGHT, [])
	var near_bank: bool = (not west.is_empty() and west[0] != "=") or (not east.is_empty() and east[0] != "=")
	return near_bank or posmod(p.x, 12) == 0


static func _spec_for(cells: Dictionary, p: Vector2i, sites: Dictionary, seed: int, placed_indoor: Array[Vector2i]) -> Array:
	var site: StringName = sites.get(p, &"")
	match site:
		&"altar": return [&"altar", LAMP_ALTAR]
		&"merchant": return [&"lantern", LAMP_MARKET]
		&"ferryman": return [&"lantern", LAMP_MARKET]
		&"herb": return [&"herb", LAMP_HERB]
	var data: Array = cells[p]
	var tile: String = data[0]
	if tile == "L":
		return [&"street_lamp", LAMP_STREET]
	if tile == "h":
		return [&"hearth", LAMP_HEARTH]
	if tile == "=" and _is_bridge_post(cells, p):
		return [&"bridge_lamp", LAMP_BRIDGE]
	if Lighting.enclosed(data) and tile in ["l", "k", "t", "K"]:
		# Deterministic cozy candle/oil-lamp spacing inside rooms so interiors glow warmly at night.
		var roll := _hash(p, seed ^ 0x51a7c3)
		if roll % 3 == 0:
			for other: Vector2i in placed_indoor:
				if (other - p).length_squared() < 25:
					return []
			placed_indoor.append(p)
			return [&"candle", LAMP_INDOOR]
	return []


static func bake(cells: Dictionary, area: Rect2i, region: Rect2i, sites: Dictionary = {}, seed: int = 0) -> Array:
	var sources: Array[Array] = []
	var active_emitters := {}
	var picks := {}
	var placed_indoor: Array[Vector2i] = []
	var source_region := region.grow(REACH).intersection(area)
	for y in range(source_region.position.y, source_region.end.y):
		for x in range(source_region.position.x, source_region.end.x):
			var p := Vector2i(x, y)
			if not cells.has(p):
				continue
			var chosen := _spec_for(cells, p, sites, seed, placed_indoor)
			if chosen.is_empty():
				continue
			var kind: StringName = chosen[0]
			var spec: Array = chosen[1]
			active_emitters[p] = kind
			var local := Vector2(p - area.position) + Vector2(0.5, 0.5)
			sources.append([Vector4(local.x, local.y, float(spec[0]), float(spec[1])), spec[2], float(spec[3]), float(spec[4])])
			var index := sources.size()
			var influence := Rect2i(p - Vector2i.ONE * REACH, Vector2i.ONE * (REACH * 2 + 1)).intersection(region)
			for iy in range(influence.position.y, influence.end.y):
				for ix in range(influence.position.x, influence.end.x):
					var at := Vector2i(ix, iy)
					if not cells.has(at) or cells[at][0] == " ":
						continue
					var distance := Vector2(at - p).length()
					if distance >= float(REACH):
						continue
					var transmission := Lighting._ray_transmission(cells, p, at)
					if transmission <= 0.02:
						continue
					var rate := transmission * float(spec[1]) / (1.0 + distance)
					var entries: Array = picks.get(at, [])
					var slot := entries.size()
					while slot > 0 and float(entries[slot - 1].z) < rate:
						slot -= 1
					if slot >= SLOTS:
						continue
					entries.insert(slot, Vector3(float(index), transmission, rate))
					if entries.size() > SLOTS:
						entries.pop_back()
					picks[at] = entries
	var slots := Image.create_empty(area.size.x * 2, area.size.y, false, Image.FORMAT_RGBAF)
	slots.fill(Color(0.0, 0.0, 0.0, 0.0))
	for p: Vector2i in picks:
		var entries: Array = picks[p]
		var indices := Color(0.0, 0.0, 0.0, 0.0)
		var transmission := Color(0.0, 0.0, 0.0, 0.0)
		for i in range(entries.size()):
			indices[i] = entries[i].x
			transmission[i] = entries[i].y
		var local := p - area.position
		slots.set_pixelv(local, indices)
		slots.set_pixelv(local + Vector2i(area.size.x, 0), transmission)
	# Row 0: (local.x, local.y, z_height, energy)
	# Row 1: (color.r, color.g, color.b, flicker_kind + always_fraction)
	var lamps := Image.create_empty(maxi(1, sources.size()), 2, false, Image.FORMAT_RGBAF)
	lamps.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i in range(sources.size()):
		var entry: Array = sources[i]
		var geom: Vector4 = entry[0]
		var col: Color = entry[1]
		var mode := float(entry[2]) + clampf(float(entry[3]), 0.0, 0.92)
		lamps.set_pixel(i, 0, Color(geom.x, geom.y, geom.z, geom.w))
		lamps.set_pixel(i, 1, Color(col.r, col.g, col.b, mode))
	return [ImageTexture.create_from_image(slots), ImageTexture.create_from_image(lamps), active_emitters]
