extends Control

# Crisp pixel-art harmonized rain & snow precipitation layer,
# automatically masked out over buildings whose roofs have faded open.
var rain := 0.0
var snow := 0.0
var daylight := 1.0
var elapsed := 0.0
var view_origin := Vector2i.ZERO
var cell := 32
var revealed_interior: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func configure(rain_strength: float, snow_strength: float, day_level: float,
		origin := Vector2i.ZERO, cell_size := 32, interior := {}) -> void:
	var active := rain_strength > 0.01 or snow_strength > 0.01
	rain = rain_strength
	snow = snow_strength
	daylight = day_level
	view_origin = origin
	cell = maxi(1, cell_size)
	revealed_interior = interior
	visible = active
	set_process(active)
	if active:
		queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _inside_revealed(pos: Vector2) -> bool:
	if revealed_interior.is_empty():
		return false
	var tile := view_origin + Vector2i((pos / float(cell)).floor())
	return revealed_interior.has(tile)


static func _hash(i: int, salt: int) -> float:
	var n := ((i * 0x9e3779b9) ^ (salt * 0x85ebca6b)) & 0xffffffff
	n = ((n ^ (n >> 16)) * 0x7feb352d) & 0xffffffff
	return float((n ^ (n >> 15)) & 0xffff) / 65535.0


func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	if rain > 0.01:
		_draw_rain()
	if snow > 0.01:
		_draw_snow()


func _draw_rain() -> void:
	# Razor-thin 1px tapered Jiangnan drizzle/rain streaks (no thick blurry bars).
	var count := int(lerpf(90.0, 260.0, rain))
	var bright := lerpf(0.58, 0.94, daylight)
	var slant := Vector2(-4.0 - 3.0 * rain, 24.0 + 18.0 * rain)
	var speed := 620.0 + 300.0 * rain
	for i in range(count):
		var rx := _hash(i, 17)
		var ry := _hash(i, 53)
		var depth := 0.55 + 0.65 * _hash(i, 91)
		var y := fposmod(ry * size.y + elapsed * speed * depth, size.y + 48.0) - 24.0
		var x := fposmod(rx * size.x - elapsed * speed * 0.17 * depth, size.x + 48.0) - 24.0
		var p := Vector2(floorf(x), floorf(y))
		var seg := slant * depth
		if _inside_revealed(p + seg * 0.5):
			continue
		var a := (0.09 + 0.13 * rain) * (0.45 + 0.55 * depth)
		var mid := p + seg * 0.55
		# Faint tail -> crisp fine lead tip
		draw_line(p, mid, Color(0.76 * bright, 0.85 * bright, 0.93 * bright, a * 0.45), 1.0, false)
		draw_line(mid, p + seg, Color(0.86 * bright, 0.92 * bright, 0.98 * bright, a), 1.0, false)
	# Tiny pixel-scale ground impact splash ticks
	var splashes := int(lerpf(18.0, 56.0, rain))
	for i in range(splashes):
		var phase := fposmod(elapsed * 3.4 + _hash(i, 211), 1.0)
		var cycle := int(floor(elapsed * 3.4 + _hash(i, 211)))
		var sx := floorf(_hash(i + cycle * 97, 307) * size.x)
		var sy := floorf(_hash(i + cycle * 59, 419) * size.y)
		if _inside_revealed(Vector2(sx, sy)):
			continue
		var a := (1.0 - phase) * (0.16 + 0.16 * rain)
		var col := Color(0.86 * bright, 0.93 * bright, 0.99 * bright, a)
		var spread := floorf(1.0 + phase * 2.6)
		draw_rect(Rect2(sx - spread, sy, 1.0, 1.0), col)
		draw_rect(Rect2(sx + spread, sy, 1.0, 1.0), col)
		if phase < 0.45:
			draw_rect(Rect2(sx, sy - 1.0, 1.0, 1.0), col)


func _draw_snow() -> void:
	# Pixel-snapped 1x1 / 2x2 crisp drifting snow flecks harmonized with 32x32 tiles.
	var count := int(lerpf(80.0, 230.0, snow))
	var bright := lerpf(0.68, 1.0, daylight)
	for i in range(count):
		var rx := _hash(i, 701)
		var ry := _hash(i, 811)
		var depth := 0.40 + 0.80 * _hash(i, 919)
		var fall := (34.0 + 32.0 * snow) * depth
		var sway := sin(elapsed * (0.9 + depth * 0.8) + rx * TAU * 4.0) * (8.0 + 7.0 * depth)
		var y := fposmod(ry * size.y + elapsed * fall, size.y + 20.0) - 10.0
		var x := fposmod(rx * size.x - elapsed * (14.0 + 14.0 * snow) * depth + sway, size.x + 20.0) - 10.0
		var px := floorf(x)
		var py := floorf(y)
		if _inside_revealed(Vector2(px, py)):
			continue
		var sz := 2.0 if depth > 0.90 else 1.0
		var a := (0.28 + 0.46 * depth) * (0.62 + 0.38 * snow)
		var col := Color(0.93 * bright, 0.96 * bright, 1.0 * bright, a)
		draw_rect(Rect2(px, py, sz, sz), col)
		if depth > 1.08:
			draw_rect(Rect2(px - 1.0, py, 1.0, 1.0), Color(col.r, col.g, col.b, a * 0.35))
			draw_rect(Rect2(px + sz, py, 1.0, 1.0), Color(col.r, col.g, col.b, a * 0.35))
