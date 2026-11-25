extends Control

# Lightweight animated rain & snowfall screen-space layer rendered above the lit board.
var rain := 0.0
var snow := 0.0
var daylight := 1.0
var elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(rain_strength: float, snow_strength: float, day_level: float) -> void:
	var active := rain_strength > 0.01 or snow_strength > 0.01
	rain = rain_strength
	snow = snow_strength
	daylight = day_level
	visible = active
	set_process(active)
	if active:
		queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


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
	var count := int(lerpf(65.0, 210.0, rain))
	var bright := lerpf(0.55, 0.92, daylight)
	var base_col := Color(0.76 * bright, 0.86 * bright, 0.94 * bright, 0.16 + 0.16 * rain)
	var slant := Vector2(-5.5 - 3.5 * rain, 22.0 + 14.0 * rain)
	var speed := 460.0 + 220.0 * rain
	for i in range(count):
		var rx := _hash(i, 17)
		var ry := _hash(i, 53)
		var layer := 0.65 + 0.60 * _hash(i, 91)
		var y := fposmod(ry * size.y + elapsed * speed * layer, size.y + 40.0) - 20.0
		var x := fposmod(rx * size.x - elapsed * speed * 0.24 * layer, size.x + 40.0) - 20.0
		var seg := slant * layer
		var col := base_col
		col.a *= 0.60 + 0.40 * layer
		draw_line(Vector2(x, y), Vector2(x, y) + seg, col, 1.0 if layer < 1.0 else 1.35, true)
	# Subtle rain splash glints
	var splashes := int(lerpf(12.0, 38.0, rain))
	var splash_col := Color(0.84 * bright, 0.92 * bright, 0.98 * bright, 0.24 * rain)
	for i in range(splashes):
		var phase := fposmod(elapsed * 2.6 + _hash(i, 211), 1.0)
		var cycle := int(floor(elapsed * 2.6 + _hash(i, 211)))
		var sx := _hash(i + cycle * 97, 307) * size.x
		var sy := _hash(i + cycle * 59, 419) * size.y
		var rad := 1.5 + phase * 5.0
		var c := splash_col
		c.a *= (1.0 - phase)
		draw_set_transform(Vector2(sx, sy), 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 12, c, 1.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_snow() -> void:
	var count := int(lerpf(55.0, 175.0, snow))
	var bright := lerpf(0.68, 1.0, daylight)
	for i in range(count):
		var rx := _hash(i, 701)
		var ry := _hash(i, 811)
		var depth := 0.45 + 0.85 * _hash(i, 919)
		var fall := (42.0 + 38.0 * snow) * depth
		var sway := sin(elapsed * (1.1 + depth * 0.9) + rx * TAU * 4.0) * (10.0 + 8.0 * depth)
		var y := fposmod(ry * size.y + elapsed * fall, size.y + 24.0) - 12.0
		var x := fposmod(rx * size.x - elapsed * (18.0 + 16.0 * snow) * depth + sway, size.x + 24.0) - 12.0
		var radius := (1.1 + 1.5 * depth) * (0.85 + 0.25 * snow)
		var col := Color(0.92 * bright, 0.96 * bright, 1.0 * bright, (0.35 + 0.42 * depth) * (0.65 + 0.35 * snow))
		draw_circle(Vector2(x, y), radius, col)
