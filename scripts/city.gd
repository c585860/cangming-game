extends RefCounted

const DOOR := "D"
const OPEN_DOOR := "o"
const SECTOR := 60
const CACHE_SIZE := 72
const BRIDGES := [5, 11, 17, 22]
const ROLES := {
	"住宅": [["kitchen", "dining", "living", "storage"], ["bedroom", "bedroom", "study", "wash"]],
	"客栈": [["reception", "kitchen", "dining", "storage"], ["guest", "guest", "guest", "wash"]],
	"药铺": [["shop", "clinic", "storage", "workshop"], ["bedroom", "study", "guest", "wash"]],
	"工坊": [["workshop", "forge", "storage", "shop"], ["storage", "study", "bedroom", "wash"]],
	"仓房": [["storage", "storage", "storage", "reception"], ["storage", "storage", "study", "wash"]],
	"书院": [["classroom", "library", "reception", "study"], ["library", "bedroom", "study", "wash"]],
	"医馆": [["clinic", "clinic", "shop", "storage"], ["guest", "guest", "study", "wash"]],
	"巡检所": [["reception", "storage", "study", "dining"], ["guest", "guest", "study", "wash"]],
	"商铺": [["shop", "shop", "storage", "workshop"], ["bedroom", "study", "guest", "wash"]]
}

var size: Vector2i
var start: Vector2i
var seed_value: int
var sites: Dictionary = {}
var landmarks: Dictionary = {}
var room_kits: Dictionary = {}
var blocks: Dictionary = {}
var lru: Array[Vector2i] = []


func setup(chosen_seed: int) -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/city.json"))
	room_kits = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
	size = coord(spec.size)
	start = coord(spec.start)
	seed_value = chosen_seed
	landmarks = {
		Vector2i(1201, 1376): "南门", Vector2i(1232, 1350): "南坊街市", Vector2i(1170, 1350): "吐纳院",
		Vector2i(1332, 1322): "沧菱码头", Vector2i(1326, 1358): "采药河滩", Vector2i(542, 604): "沧菱书院",
		Vector2i(662, 796): "内城巡检所", Vector2i(842, 606): "城东医馆", Vector2i(1086, 1033): "商街",
		Vector2i(184, 1002): "西坊民居", Vector2i(1266, 965): "临河仓场", Vector2i(518, 306): "北坊",
		Vector2i(150, 128): "西北果圃", Vector2i(1410, 1030): "东堤渡口"
	}
	sites = {Vector2i(1232, 1350): &"merchant", Vector2i(1170, 1350): &"altar", Vector2i(1332, 1322): &"ferryman"}
	for p in [Vector2i(1325, 1345), Vector2i(1328, 1353), Vector2i(1326, 1362), Vector2i(1328, 1368)]:
		sites[p] = &"herb"


static func coord(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))


func sector_at(p: Vector2i) -> Vector2i:
	return Vector2i((Vector2(p) / float(SECTOR)).floor())


func district(s: Vector2i) -> String:
	if s.x >= 23:
		return "东岸"
	if s.x == 22:
		return "河埠"
	if s.x >= 19 and (s.y in [5, 11, 15, 16, 17, 21] or s.x == 21):
		return "漕运仓场"
	if s.x <= 1 or s.y <= 1 or s.y >= 23 or (s.x <= 3 and s.y <= 4):
		return "城外田圃"
	if s.x in [9, 10, 11, 12, 13, 14] and s.y in [9, 10, 11, 12, 13]:
		return "内城"
	if s.y in [5, 11, 17, 22] or s.x in [6, 14, 18, 20]:
		return "沿街商坊"
	if s.x >= 15:
		return "东坊民居"
	return "西坊民居" if s.y >= 9 else "北坊民居"


func hub(s: Vector2i) -> Vector2i:
	return s * SECTOR + Vector2i.ONE


func tile(p: Vector2i, level := 0) -> String:
	if not Rect2i(Vector2i.ZERO, size).has_point(p):
		return " "
	var sector := sector_at(p)
	var block := _get_block(sector)
	var local := p - sector * SECTOR
	var tiles: PackedByteArray = block.upper if level == 1 else block.ground
	return String.chr(tiles[local.y * SECTOR + local.x])


func _get_block(s: Vector2i) -> Dictionary:
	if blocks.has(s):
		if lru.back() != s:
			lru.erase(s)
			lru.append(s)
		return blocks[s]
	var generated := _generate(s)
	if lru.size() == CACHE_SIZE:
		blocks.erase(lru.pop_front())
	lru.append(s)
	blocks[s] = generated
	return generated


func _generate(s: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(s.x, s.y, seed_value))
	var ground := PackedByteArray()
	var upper := PackedByteArray()
	ground.resize(SECTOR * SECTOR)
	upper.resize(SECTOR * SECTOR)
	ground.fill(46)
	upper.fill(32)
	var base := s * SECTOR
	var area := district(s)
	for y in SECTOR:
		var global_y := base.y + y
		var shore := 1333 + roundi(sin(global_y * 0.015) * 3.0)
		for x in SECTOR:
			var global_x := base.x + x
			if global_x >= shore and global_x < shore + 40:
				var is_bridge := s.y in BRIDGES and y <= 3
				_set(ground, x, y, "=" if is_bridge else ("~" if global_x - shore < 3 or shore + 40 - global_x <= 3 else "W"))
			elif x <= 3 or y <= 3:
				_set(ground, x, y, "+" if s.x in [6, 14, 20] or s.y in BRIDGES else ":")
			elif global_y == 1376 and global_x >= 60 and global_x <= 1318:
				_set(ground, x, y, "#")
			elif s.x < 22 and s.x > 0 and s.y > 1 and s.y < 23 and (x in [29, 30, 31] or y in [29, 30, 31]):
				_set(ground, x, y, ":")
			elif global_x >= 1320 and global_x < shore:
				if (global_y * 23 + x * 7) % 17 < 5:
					_set(ground, x, y, "s")
	var plots: Array[Dictionary] = []
	if area not in ["河埠", "东岸"]:
		for lot in 4:
			var origin := Vector2i(5 + (lot % 2) * 27, 5 + floori(lot / 2.0) * 27)
			var kind := _lot_kind(s, lot, area, rng)
			if kind in ["广场", "果圃", "公园", "空地"]:
				if kind != "空地":
					_open_plot(ground, origin, kind, rng)
				plots.append({"rect": Rect2i(origin, Vector2i(24, 24)), "name": kind})
				continue
			var footprint := _build(ground, upper, origin, kind, rng)
			plots.append({"rect": footprint, "name": kind})
	for pos_marker: Vector2i in sites:
		if sector_at(pos_marker) == s:
			var p := pos_marker - base
			_set(ground, p.x, p.y, "=" if sites[pos_marker] == &"ferryman" else ("s" if sites[pos_marker] == &"herb" else "+"))
	return {"ground": ground, "upper": upper, "plots": plots}


func _lot_kind(s: Vector2i, lot: int, area: String, rng: RandomNumberGenerator) -> String:
	if s == Vector2i(20, 22):
		return ["广场", "商铺", "药铺", "客栈"][lot]
	if s == Vector2i(19, 22):
		return ["公园", "住宅", "住宅", "住宅"][lot]
	if s == Vector2i(9, 10) and lot == 0:
		return "书院"
	if s == Vector2i(11, 13) and lot in [0, 2]:
		return "巡检所"
	if s == Vector2i(14, 10) and lot == 0:
		return "医馆"
	var table: Array = {
		"城外田圃": ["果圃", "空地", "果圃", "空地", "住宅"],
		"漕运仓场": ["仓房", "仓房", "仓房", "工坊", "工坊", "住宅", "客栈", "公园"],
		"内城": ["住宅", "住宅", "住宅", "书院", "巡检所", "医馆", "公园", "商铺"],
		"沿街商坊": ["商铺", "商铺", "住宅", "住宅", "客栈", "药铺", "工坊", "广场"]
	}.get(area, ["住宅", "住宅", "住宅", "住宅", "住宅", "果圃", "公园", "商铺"])
	return table[rng.randi_range(0, table.size() - 1)]


func _open_plot(tiles: PackedByteArray, origin: Vector2i, kind: String, rng: RandomNumberGenerator) -> void:
	for y in range(2, 22):
		for x in range(2, 22):
			var p := origin + Vector2i(x, y)
			if kind == "广场" and x in range(3, 21) and y in range(3, 21):
				_set(tiles, p.x, p.y, "+")
			elif kind in ["公园", "果圃"] and x % 4 == 0 and y % 4 == 0 and rng.randf() < 0.78:
				_set(tiles, p.x, p.y, "g")
			elif x in [11, 12] or y in [11, 12]:
				_set(tiles, p.x, p.y, ":")


func _build(ground: PackedByteArray, upper: PackedByteArray, origin: Vector2i, kind: String, rng: RandomNumberGenerator) -> Rect2i:
	var width := rng.randi_range(16, 20)
	var depth := rng.randi_range(13, 17)
	var facing_north := rng.randi_range(0, 1) == 0
	var left := origin.x + (24 - width) / 2.0
	var top := origin.y + (24 - depth) / 2.0 - (2 if not facing_north else -2)
	var rect := Rect2i(int(left), int(top), width, depth)
	var mid := rng.randi_range(width / 2 - 1, width / 2 + 1)
	var divider := rng.randi_range(5, depth - 6)
	var stair := Vector2i(mid, rng.randi_range(3, depth - 4))
	var roles: Array = ROLES[kind]
	for floor_index in 2:
		var tiles := ground if floor_index == 0 else upper
		for y in depth:
			for x in width:
				var value := "i"
				if x == 0 or x == width - 1 or y == 0 or y == depth - 1:
					value = "w" if (x * 7 + y * 3) % 9 == 2 else "#"
				elif x == mid - 1 or x == mid + 1 or (y == divider and absi(x - mid) > 1):
					value = "#"
				_set(tiles, rect.position.x + x, rect.position.y + y, value)
		var room_top := rng.randi_range(2, divider - 2)
		var room_bottom := rng.randi_range(divider + 2, depth - 3)
		for wall in [mid - 1, mid + 1]:
			_set(tiles, rect.position.x + wall, rect.position.y + room_top, "D")
			_set(tiles, rect.position.x + wall, rect.position.y + room_bottom, "D")
		_set(tiles, rect.position.x + stair.x, rect.position.y + stair.y, "^" if floor_index == 0 else "v")
		var rooms := [Rect2i(1, 1, mid - 2, divider - 1), Rect2i(mid + 2, 1, width - mid - 3, divider - 1),
			Rect2i(1, divider + 1, mid - 2, depth - divider - 2), Rect2i(mid + 2, divider + 1, width - mid - 3, depth - divider - 2)]
		for i in 4:
			var room: Rect2i = rooms[i]
			var kit_id: String = roles[floor_index][(i + (2 if facing_north else 0)) % 4]
			_furnish(tiles, rect.position, room, kit_id, rng)
	var entry := rect.position + Vector2i(mid, 0 if facing_north else depth - 1)
	_set(ground, entry.x, entry.y, "D")
	var edge := origin.y if facing_north else origin.y + 24
	for y in range(mini(entry.y, edge), maxi(entry.y, edge) + 1):
		if y != entry.y:
			_set(ground, entry.x, y, ":")
	for y in range(mini(entry.y, edge), maxi(entry.y, edge) + 1):
		if y != entry.y and y != edge:
			if rng.randf() < 0.42:
				_set(ground, origin.x + 2, y, "g")
			if rng.randf() < 0.42:
				_set(ground, origin.x + 21, y, "g")
	if kind == "住宅" and rng.randf() < 0.72:
		# Enclose the yard, keeping its gate on the same approach as the house door.
		for x in range(origin.x + 1, origin.x + 23):
			_set(ground, x, edge, "D" if x == entry.x else "f")
	return rect


func _furnish(tiles: PackedByteArray, base: Vector2i, room: Rect2i, role: String, rng: RandomNumberGenerator) -> void:
	var kit: Array = room_kits[role]
	var candidates: Array[Vector2i] = []
	for x in range(room.position.x + 1, room.end.x - 1):
		candidates.append(Vector2i(x, room.position.y))
		candidates.append(Vector2i(x, room.end.y - 1))
	for y in range(room.position.y + 1, room.end.y - 1):
		var edge_x := room.position.x if room.position.x == 1 else room.end.x - 1
		candidates.append(Vector2i(edge_x, y))
	for piece: String in kit:
		if candidates.is_empty():
			break
		var index := rng.randi_range(0, candidates.size() - 1)
		var spot := base + candidates[index]
		candidates.remove_at(index)
		_set(tiles, spot.x, spot.y, piece)


func _set(tiles: PackedByteArray, x: int, y: int, value: String) -> void:
	tiles[y * SECTOR + x] = value.unicode_at(0)


func location(p: Vector2i) -> String:
	var s := sector_at(p)
	var local := p - s * SECTOR
	for plot: Dictionary in _get_block(s).plots:
		if plot.rect.has_point(local):
			return plot.name
	return district(s)
