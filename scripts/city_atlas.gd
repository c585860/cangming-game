extends Control

signal destination_requested(position: Vector2i)
signal selection_changed(title: String, details: String)

const Tiles = preload("res://scripts/undead_tiles.gd")
const STEP := 10
const NONE := Vector2i(-1, -1)
const ART := ["field", "road", "dirt_road", "river_center", "bridge", "forest", "river",
	"house_09", "s_grocery", "s_pharm", "warehouse", "motel_1", "urban_9_2", "park", "farm_3"]
const LAND := ["空地", "主街", "街巷", "沧菱河", "桥梁", "林地", "河岸", "住宅", "商铺",
	"药铺或医馆", "仓房或工坊", "客栈", "公共建筑", "广场或园林", "果圃"]
const DIR := [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]

var world: CanglingWorld
var cells: PackedByteArray
var dimensions: Vector2i
var labels := {}
var selected := NONE
var hovered := NONE
var center := Vector2.ZERO
var offset := Vector2.ZERO
var pixels := 1.0
var zoom := 0
var dragging := false
var artwork := Control.new()
var marks := Control.new()


func build(model: CanglingWorld, raster: PackedByteArray) -> void:
	world = model
	cells = raster
	dimensions = Vector2i(Vector2(world.city_size) / STEP)
	for p: Vector2i in world.landmarks:
		labels[_index(p)] = world.landmarks[p]
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for layer: Control in [artwork, marks]:
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.draw.connect(_draw_artwork)
	marks.draw.connect(_draw_marks)
	resized.connect(_frame)
	mouse_exited.connect(func():
		dragging = false
		hovered = NONE
		_notify())
	fit()


func _index(p: Vector2i) -> Vector2i:
	return Vector2i((Vector2(p) / STEP).floor())


func _cell(p: Vector2i) -> int:
	return (p.y * dimensions.x + p.x) * 2


func _inside(p: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, dimensions).has_point(p)


func _at(p: Vector2) -> Vector2i:
	return Vector2i(((p - offset) / pixels).floor())


func fit() -> void:
	zoom = 0
	center = Vector2(dimensions) * 0.5
	selected = _index(world.pos)
	hovered = NONE
	_frame()
	_notify()


func _frame() -> void:
	if size.x < 1 or size.y < 1:
		return
	center = center.clamp(Vector2.ZERO, Vector2(dimensions))
	pixels = minf(size.x / dimensions.x, size.y / dimensions.y) * pow(1.6, zoom)
	offset = size * 0.5 - center * pixels
	artwork.queue_redraw()
	marks.queue_redraw()


func _zoom(amount: int, anchor: Vector2) -> void:
	var next := clampi(zoom + amount, 0, 6)
	if next == zoom:
		return
	var target := (anchor - offset) / pixels
	var next_pixels := pixels * pow(1.6, amount)
	zoom = next
	center = Vector2(dimensions) * 0.5 if zoom == 0 else target - (anchor - size * 0.5) / next_pixels
	_frame()


func keyboard(key: Key) -> bool:
	var direction := Vector2i.ZERO
	match key:
		KEY_LEFT, KEY_A: direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D: direction = Vector2i.RIGHT
		KEY_UP, KEY_W: direction = Vector2i.UP
		KEY_DOWN, KEY_S: direction = Vector2i.DOWN
		KEY_HOME: fit()
		KEY_ENTER, KEY_KP_ENTER: travel()
		_: return false
	if direction != Vector2i.ZERO:
		hovered = NONE
		selected = (selected + direction).clamp(Vector2i.ZERO, dimensions - Vector2i.ONE)
		if not Rect2(Vector2.ZERO, size).grow(-pixels).has_point(offset + Vector2(selected) * pixels):
			center = Vector2(selected) + Vector2.ONE * 0.5
			_frame()
		_notify()
	return true


func travel() -> void:
	var base := selected * STEP
	var target := base + Vector2i(5, 5)
	var best := 999
	for y in STEP:
		for x in STEP:
			var p := base + Vector2i(x, y)
			var distance := absi(x - 5) + absi(y - 5)
			if distance < best and world.walkable(p):
				best = distance
				target = p
	destination_requested.emit(target)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE: dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1, event.position)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				var p := _at(event.position)
				if event.pressed and _inside(p):
					selected = p
					hovered = NONE
					_notify()
					if event.button_index == MOUSE_BUTTON_RIGHT:
						travel()
			_: return
		accept_event()
	elif event is InputEventMouseMotion:
		if dragging and zoom > 0:
			center -= event.relative / pixels
			_frame()
		var p := _at(event.position)
		p = p if _inside(p) else NONE
		if p != hovered:
			hovered = p
			_notify()


func _notify() -> void:
	var p := hovered if _inside(hovered) else selected
	if not _inside(p) or cells.is_empty():
		return
	var base := p * STEP
	var district := world.location(base + Vector2i(5, 5))
	var kind: int = cells[_cell(p)]
	var title: String = labels.get(p, district if kind >= 7 else LAND[kind])
	var details := "%s  ·  %s\n区块  %d，%d\n地格  %d–%d，%d–%d" % [district, LAND[kind],
		p.x + 1, p.y + 1, base.x, base.x + STEP - 1, base.y, base.y + STEP - 1]
	selection_changed.emit(title, details)
	marks.queue_redraw()


func _draw_artwork() -> void:
	artwork.draw_rect(Rect2(Vector2.ZERO, size), Color("0e1411"))
	if cells.is_empty():
		return
	var lo := _at(Vector2.ZERO).clamp(Vector2i.ZERO, dimensions)
	var hi := (_at(size) + Vector2i.ONE).clamp(Vector2i.ZERO, dimensions)
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var p := Vector2i(x, y)
			var i := _cell(p)
			var kind: int = cells[i]
			var roll := hash(p) ^ world.seed
			var mask := -1
			if kind in [1, 2, 4]:
				mask = 0
				for d in 4:
					var n: Vector2i = p + DIR[d]
					if cells[i + 1] & (1 << d) and _inside(n) and cells[_cell(n)] in [1, 2, 4]:
						mask |= 1 << d
			var rotation := 1 if mask >= 0 and (mask & 6) else 0
			var id: String = "house_16" if kind == 7 and (roll & 1) == 0 else ART[kind]
			Tiles.draw_at(artwork, id, offset + Vector2(p) * pixels, pixels + 0.015, roll, mask, rotation, Color("e6e0cf"))
	# Subtle gilded map boundary frame
	var map_rect := Rect2(offset, Vector2(dimensions) * pixels)
	artwork.draw_rect(map_rect, Color(0.62, 0.53, 0.31, 0.65), false, 1.5)
	Tiles.finish_frame()


func _draw_marks() -> void:
	if world == null:
		return
	var font := get_theme_default_font()
	for p: Vector2i in labels:
		var at := offset + (Vector2(p) + Vector2.ONE * 0.5) * pixels
		if not Rect2(Vector2.ZERO, size).has_point(at):
			continue
		var r := clampf(pixels * 0.25, 2.5, 4.5)
		marks.draw_circle(at, r + 1.4, Color(0.08, 0.11, 0.09, 0.85))
		marks.draw_circle(at, r, Color("ecc76c"))
		if zoom >= 1:
			var text: String = labels[p]
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var tag := Rect2(at + Vector2(7, -17), Vector2(width + 10, 20))
			marks.draw_rect(tag, Color(0.08, 0.12, 0.10, 0.90))
			marks.draw_rect(tag, Color(0.62, 0.53, 0.31, 0.72), false, 1.0)
			marks.draw_string(font, at + Vector2(12, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f3dca0"))
	var pc := offset + (Vector2(_index(world.pos)) + Vector2.ONE * 0.5) * pixels
	marks.draw_circle(pc, 5.5, Color("0d1410"))
	marks.draw_circle(pc, 3.6, Color("7ee8c0"))
	for p: Vector2i in [selected, hovered]:
		if _inside(p):
			var rect := Rect2(offset + Vector2(p) * pixels, Vector2.ONE * pixels)
			marks.draw_rect(rect, Color("7ae4b6") if p == selected else Color("edd99a"), false, 1.8)
