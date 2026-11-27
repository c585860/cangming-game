extends Control

signal destination_requested(position: Vector2i)

const World = preload("res://scripts/world.gd")
const NONE := Vector2i(-1, -1)
const COLORS := {
	"w": "b2c0bc", "#": "6f7673", "D": "b8824f", "o": "a69882",
	"~": "468e98", "W": "335b76", "+": "9ea392", "=": "a8885c",
	":": "8a7652", "i": "947856", "g": "678a4a", "Y": "3e613b",
	"s": "b2a179", "f": "7a684e", "L": "e6ba5c", "h": "d97942",
	"b": "947856", "t": "947856", "c": "947856", " ": "0d120f",
	"^": "dfc57b", "v": "dfc57b", "X": "dfc57b",
}
const DISTRICTS := {".": Color("49623b"), "i": Color("686e62"), "+": Color("886f4c"),
	"H": Color("917753"), "c": Color("6c5f54"), "g": Color("395846"),
	"=": Color("2b5367"), "~": Color("2b5367")}
const DIRS := [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]

var world: World
var overview := false
var overview_tiles: Array[String] = []
var roads: Array[PackedVector2Array] = []
var bridges: Array[PackedVector2Array] = []
var landmarks: Dictionary
var extent: int
var cols := 0
var rows := 0
var cell := 1.0
var offset := Vector2.ZERO
var cursor := NONE


func build(model: World, full := false) -> void:
	world = model
	overview = full
	extent = world.sector_size
	resized.connect(queue_redraw)
	if overview:
		cols = ceili(float(world.city_size.x) / extent)
		rows = ceili(float(world.city_size.y) / extent)
		landmarks = world.landmarks
		for y in rows:
			for x in cols:
				var sector := Vector2i(x, y)
				overview_tiles.append(world.overview(sector))
				for direction in [2, 3]:
					var points: Array = world.street_curve(sector, direction)
					if points.is_empty():
						continue
					var curve := PackedVector2Array()
					for p: Vector2i in points:
						curve.append(Vector2(sector) + Vector2.ONE * 0.5 + Vector2(p - points[0]) / extent)
					if x == 22 and direction == 2:
						bridges.append(curve)
					else:
						roads.append(curve)
		mouse_exited.connect(func(): cursor = NONE; queue_redraw())
	else:
		mouse_filter = MOUSE_FILTER_IGNORE


func _sector(p: Vector2i) -> Vector2i:
	return Vector2i(Vector2(p) / extent)


func _map_cell(pointer: Vector2) -> Vector2i:
	return Vector2i(((pointer - offset) / cell).floor())


func _get_tooltip(at_position: Vector2) -> String:
	if not overview:
		return ""
	var sector := _map_cell(at_position)
	if not Rect2i(0, 0, cols, rows).has_point(sector):
		return ""
	var names := PackedStringArray()
	for p: Vector2i in landmarks:
		if _sector(p) == sector:
			names.append(landmarks[p])
	return " / ".join(names) if not names.is_empty() else world.location(sector * extent + Vector2i.ONE)


func _gui_input(event: InputEvent) -> void:
	if not overview or not (event is InputEventMouseMotion or event is InputEventMouseButton):
		return
	var sector := _map_cell(event.position)
	cursor = sector if Rect2i(0, 0, cols, rows).has_point(sector) else NONE
	if cursor != NONE and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		destination_requested.emit(cursor * extent + Vector2i.ONE)
		accept_event()
	queue_redraw()


func _draw() -> void:
	if world == null or size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d120f"))
	if not overview:
		_draw_local()
		return
	cell = maxf(1.0, floorf(minf((size.x - 24.0) / cols, (size.y - 8.0) / rows)))
	offset = (size - Vector2(cols, rows) * cell) * 0.5
	for y in rows:
		for x in cols:
			var ink: Color = DISTRICTS[overview_tiles[y * cols + x]]
			var at := offset + Vector2(x, y) * cell
			draw_rect(Rect2(at, Vector2.ONE * cell), ink.darkened(0.22))
	_draw_roads(roads, Color("aaa497"))
	_draw_roads(bridges, Color("d2ad78"))
	if cursor != NONE:
		draw_rect(Rect2(offset + Vector2(cursor) * cell, Vector2.ONE * cell), Color("e3dfb5"), false, 1.5)
	for p: Vector2i in landmarks:
		var at := offset + (Vector2(_sector(p)) + Vector2.ONE * 0.5) * cell
		draw_circle(at, maxf(2.0, cell * 0.20), Color("ecc775"))
	var player := offset + Vector2(_sector(world.pos)) * cell
	draw_rect(Rect2(player + Vector2.ONE, Vector2.ONE * maxf(cell - 2.0, 1.0)), Color("eaeade"), false, 1.5)
	draw_string(get_theme_default_font(), player + Vector2(0, cell * 0.76), "@", HORIZONTAL_ALIGNMENT_CENTER, cell, maxi(9, int(cell * 0.76)), Color("fcf8e2"))


func _draw_roads(curves: Array[PackedVector2Array], color: Color) -> void:
	var transform := Transform2D(Vector2(cell, 0), Vector2(0, cell), offset)
	for curve in curves:
		draw_polyline(transform * curve, color, maxf(1.0, cell * 0.09), true)


func _draw_local() -> void:
	if world.has_method("is_cataclysm_pack") and world.is_cataclysm_pack():
		_draw_ccb_overmap_mini()
		return
	var block := floorf(minf((size.x - 8.0) / 25.0, (size.y - 8.0) / 15.0))
	if block < 1.0:
		return
	var map_size := Vector2(25, 15) * block
	var corner := (size - map_size) * 0.5
	for y in 15:
		for x in 25:
			var p := world.pos + Vector2i(x - 12, y - 7)
			if not Rect2i(Vector2i.ZERO, world.city_size).has_point(p):
				continue
			var tint := Color(COLORS.get(world.terrain_at(p), "446141"))
			var site := world.site_at(p)
			if site in [&"innkeeper", &"blacksmith", &"herbalist", &"martial_master", &"pawnbroker", &"boatman", &"storyteller"]:
				tint = Color("f0c665")
			draw_rect(Rect2(corner + Vector2(x, y) * block, Vector2.ONE * block), tint)
	# Crisp jade-gold player marker at center
	var pcenter := corner + Vector2(12.5, 7.5) * block
	draw_circle(pcenter, maxf(3.0, block * 0.55), Color("101914"))
	draw_circle(pcenter, maxf(2.0, block * 0.38), Color("8ef0c8"))
	# Subtle scroll inner border & north compass badge
	draw_rect(Rect2(corner, map_size), Color(0.62, 0.53, 0.31, 0.55), false, 1.0)
	var font := get_theme_default_font()
	var badge_rect := Rect2(Vector2(size.x * 0.5 - 10.0, 2.0), Vector2(20.0, 15.0))
	draw_rect(badge_rect, Color(0.07, 0.10, 0.09, 0.85))
	draw_rect(badge_rect, Color(0.62, 0.53, 0.31, 0.65), false, 1.0)
	draw_string(font, Vector2(size.x * 0.5 - 6.0, 14.0), "北", HORIZONTAL_ALIGNMENT_CENTER, 12.0, 11, Color("e7c878"))


func _draw_ccb_overmap_mini() -> void:
	var omt: Vector2i = world.ccb_world_to_omt(world.pos)
	var radius := 5
	var data: Dictionary = world.ccb_overmap_slice(omt, radius)
	var om_rows: Array = data.get("rows", [])
	var om_cols: Array = data.get("colors", [])
	var side := radius * 2 + 1
	if om_rows.is_empty():
		return
	var cell_w := floorf((size.x - 16.0) / float(side))
	var cell_h := floorf((size.y - 12.0) / float(side))
	var step := maxf(6.0, minf(cell_w, cell_h))
	var ox := (size.x - step * float(side)) * 0.5
	var oy := (size.y - step * float(side)) * 0.5
	var font := get_theme_default_font()
	var fsz := maxi(8, int(step * 0.88))
	for y in range(mini(side, om_rows.size())):
		var rstr: String = str(om_rows[y])
		var crow: Array = om_cols[y]
		for x in range(mini(side, rstr.length())):
			var px := ox + float(x) * step
			var py := oy + float(y) * step
			var col := Color(str(crow[x]))
			draw_rect(Rect2(px, py, step - 1.0, step - 1.0), col.darkened(0.65))
			if x == radius and y == radius:
				draw_rect(Rect2(px, py, step - 1.0, step - 1.0), Color("f0e068"), false, 1.4)
				if font != null:
					draw_string(font, Vector2(px + 1.0, py + step - 2.0), "@", HORIZONTAL_ALIGNMENT_CENTER, step - 1.0, fsz, Color("fff078"))
			elif font != null:
				draw_string(font, Vector2(px + 1.0, py + step - 2.0), rstr.substr(x, 1), HORIZONTAL_ALIGNMENT_CENTER, step - 1.0, fsz, col.lightened(0.25))
	draw_rect(Rect2(ox - 2.0, oy - 2.0, step * float(side) + 3.0, step * float(side) + 3.0), Color(0.45, 0.55, 0.50, 0.55), false, 1.0)
