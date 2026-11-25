extends RefCounted

# Dedicated footprint & footfall VFX subsystem:
# - Snow footprints on outdoor snow-covered ground
# - Wet footprints tracked from rain puddles / wet shore onto drier stone or indoor wooden floors
# - Expanding puddle splash rings & subtle footfall puffs decoupled at 60 FPS

const Lighting = preload("res://scripts/lighting.gd")
const MAX_MARKS := 200
const MAX_SPLASHES := 24

var marks: Array[Dictionary] = []
var splashes: Array[Dictionary] = []
var wet_shoe_charge := 0.0
var _step_parity := 0


func clear() -> void:
	marks.clear()
	splashes.clear()
	wet_shoe_charge = 0.0


static func _stone_hold_for(data: Array) -> float:
	if data.is_empty():
		return 0.0
	var tile: String = data[0]
	var surf: String = data[1]
	if surf in ["m", "p", "G", "j", "J"] or tile == "+":
		return 1.0
	if tile == ":" or surf == "d":
		return 0.5
	return 0.0


func record_step(from_pos: Vector2i, to_pos: Vector2i, world: RefCounted, weather: RefCounted, cells: Dictionary) -> void:
	if world == null or weather == null:
		return
	var delta := to_pos - from_pos
	if delta == Vector2i.ZERO or delta.length_squared() > 4:
		return
	var dir := Vector2(delta).normalized()
	_step_parity += 1
	var side := -1.0 if (_step_parity & 1) == 0 else 1.0

	var from_data: Array = cells.get(from_pos, [])
	var to_data: Array = cells.get(to_pos, [])
	if from_data.is_empty():
		return
	var from_indoors := Lighting.enclosed(from_data)
	var from_tile: String = from_data[0]
	var to_indoors := not to_data.is_empty() and Lighting.enclosed(to_data)
	var to_tile: String = to_data[0] if not to_data.is_empty() else " "

	# 1. Check snow footprints on outdoor snow
	if world.floor == 0 and weather.snow_cover > 0.15 and not from_indoors and from_tile not in ["~", "W", " "]:
		marks.append({
			"kind": &"snow",
			"pos": Vector2(from_pos),
			"dir": dir,
			"side": side,
			"strength": clampf(weather.snow_cover, 0.25, 1.0),
			"age": 0.0,
			"minute": world.minutes,
			"floor": world.floor,
		})
		_add_puff(Vector2(to_pos) + Vector2(0.5, 0.78), &"snow")

	# 2. Check rain puddle immersion -> charge wet shoes + spawn puddle splash ring!
	var from_hold := _stone_hold_for(from_data) if not from_indoors else 0.0
	var to_hold := _stone_hold_for(to_data) if not to_indoors else 0.0
	var from_puddle := 0.0
	var to_puddle := 0.0
	if world.floor == 0 and weather.wetness > 0.12 and weather.snow_cover <= 0.12:
		if not from_indoors:
			from_puddle = weather.puddle_depth_at(Vector2(from_pos) + Vector2(0.5, 0.5), from_hold, world.seed)
		if not to_indoors:
			to_puddle = weather.puddle_depth_at(Vector2(to_pos) + Vector2(0.5, 0.5), to_hold, world.seed)
	if from_tile == "~" or to_tile == "~":
		from_puddle = maxf(from_puddle, 0.85)
		to_puddle = maxf(to_puddle, 0.85)

	if to_puddle > 0.18 or from_puddle > 0.18:
		wet_shoe_charge = minf(1.0, maxf(wet_shoe_charge, 0.65 + 0.35 * maxf(from_puddle, to_puddle)))
		_add_puff(Vector2(to_pos) + Vector2(0.5, 0.78), &"splash")
	elif wet_shoe_charge > 0.08:
		# Stepping onto drier stone, non-puddle road, or wooden indoor floor leaves realistic drying wet footprints!
		if from_tile not in ["~", "W", " "] and (from_indoors or from_puddle < 0.14):
			marks.append({
				"kind": &"wet",
				"pos": Vector2(from_pos),
				"dir": dir,
				"side": side,
				"strength": wet_shoe_charge,
				"age": 0.0,
				"minute": world.minutes,
				"floor": world.floor,
			})
			wet_shoe_charge = maxf(0.0, wet_shoe_charge - (0.14 if from_indoors else 0.12))

	if marks.size() > MAX_MARKS:
		marks = marks.slice(marks.size() - MAX_MARKS)


func _add_puff(world_center: Vector2, kind: StringName) -> void:
	splashes.append({"pos": world_center, "kind": kind, "age": 0.0, "life": 0.55 if kind == &"splash" else 0.38})
	if splashes.size() > MAX_SPLASHES:
		splashes.pop_front()


func tick(delta: float, weather: RefCounted) -> bool:
	var dirty := false
	if not splashes.is_empty():
		var alive_splashes: Array[Dictionary] = []
		for sp: Dictionary in splashes:
			sp["age"] = float(sp["age"]) + delta
			if float(sp["age"]) < float(sp["life"]):
				alive_splashes.append(sp)
		splashes = alive_splashes
		dirty = true
	if not marks.is_empty():
		var dry_rate := 0.045 if (weather == null or float(weather.rain) < 0.1) else 0.015
		var alive_marks: Array[Dictionary] = []
		for m: Dictionary in marks:
			m["age"] = float(m["age"]) + delta
			if m["kind"] == &"wet":
				m["strength"] = float(m["strength"]) - delta * dry_rate
				if float(m["strength"]) > 0.04:
					alive_marks.append(m)
					dirty = true
			elif m["kind"] == &"snow":
				if weather != null and float(weather.snow_cover) >= 0.12:
					alive_marks.append(m)
				else:
					dirty = true
		if alive_marks.size() != marks.size():
			dirty = true
		marks = alive_marks
	return dirty


func draw(canvas: Control, board: Control, world: RefCounted, weather: RefCounted, daylight: float, visible: Rect2i) -> void:
	var cell_f := float(board.cell)
	var offset: Vector2 = board.cam_px_offset
	var snow_alpha := smoothstep(0.15, 0.45, float(weather.snow_cover)) if weather != null else 0.0
	for m: Dictionary in marks:
		if int(m["floor"]) != world.floor:
			continue
		var p_vec: Vector2 = m["pos"]
		var cell_i := Vector2i(floori(p_vec.x), floori(p_vec.y))
		if not visible.has_point(cell_i):
			continue
		var origin := (p_vec - Vector2(board.view_origin)) * cell_f + offset
		if m["kind"] == &"snow":
			if snow_alpha <= 0.02:
				continue
			var age_min := maxi(0, world.minutes - int(m["minute"]))
			var fade := clampf(1.0 - float(age_min) / 180.0, 0.0, 1.0) * snow_alpha
			_draw_snow_print(canvas, origin, cell_f, m["dir"], float(m["side"]), fade, daylight)
		elif m["kind"] == &"wet":
			var fade := clampf(float(m["strength"]), 0.0, 1.0)
			_draw_wet_print(canvas, origin, cell_f, m["dir"], float(m["side"]), fade, daylight)

	for sp: Dictionary in splashes:
		var t := clampf(float(sp["age"]) / float(sp["life"]), 0.0, 1.0)
		var screen := (Vector2(sp["pos"]) - Vector2(board.view_origin)) * cell_f + offset
		if sp["kind"] == &"splash":
			var rad := (0.14 + 0.34 * t) * cell_f
			var a := (1.0 - t) * (0.48 * lerpf(0.55, 1.0, daylight))
			canvas.draw_set_transform(screen, 0.0, Vector2(1.0, 0.48))
			canvas.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 18, Color(0.78, 0.88, 0.96, a), 1.2, true)
			canvas.draw_set_transform(Vector2.ZERO)
		elif sp["kind"] == &"snow":
			var rad := (0.08 + 0.18 * t) * cell_f
			var a := (1.0 - t) * 0.32 * lerpf(0.45, 1.0, daylight)
			canvas.draw_circle(screen + Vector2(0.0, -t * 4.0), rad, Color(0.92, 0.96, 1.0, a))


static func _draw_snow_print(canvas: Control, origin: Vector2, cell_size: float, dir: Vector2,
		side: float, alpha: float, daylight: float) -> void:
	if alpha <= 0.02:
		return
	var angle := dir.angle() if dir.length_squared() > 0.01 else 0.0
	var perp := Vector2(-sin(angle), cos(angle))
	var center := origin + Vector2.ONE * (cell_size * 0.5) + perp * (side * cell_size * 0.13)
	var bright := lerpf(0.28, 1.0, daylight)
	var indent := Color(0.36 * bright, 0.47 * bright, 0.60 * bright, 0.46 * alpha)
	var core := Color(0.28 * bright, 0.39 * bright, 0.52 * bright, 0.38 * alpha)
	var rim := Color(0.95 * bright, 0.98 * bright, 1.0 * bright, 0.34 * alpha)
	var sole_r := maxf(1.5, cell_size * 0.068)
	var heel_r := maxf(1.2, cell_size * 0.054)
	canvas.draw_set_transform(center, angle, Vector2(1.28, 0.84))
	canvas.draw_circle(Vector2(sole_r * 0.72, 0.0) + Vector2(0.6, 0.6), sole_r + 0.6, rim)
	canvas.draw_circle(Vector2(-heel_r * 0.95, 0.0) + Vector2(0.6, 0.6), heel_r + 0.5, rim)
	canvas.draw_circle(Vector2(sole_r * 0.72, 0.0), sole_r, indent)
	canvas.draw_circle(Vector2(-heel_r * 0.95, 0.0), heel_r, indent)
	canvas.draw_circle(Vector2(sole_r * 0.72, 0.0), sole_r * 0.55, core)
	canvas.draw_set_transform(Vector2.ZERO)


static func _draw_wet_print(canvas: Control, origin: Vector2, cell_size: float, dir: Vector2,
		side: float, alpha: float, daylight: float) -> void:
	if alpha <= 0.03:
		return
	var angle := dir.angle() if dir.length_squared() > 0.01 else 0.0
	var perp := Vector2(-sin(angle), cos(angle))
	var center := origin + Vector2.ONE * (cell_size * 0.5) + perp * (side * cell_size * 0.13)
	var sole_r := maxf(1.6, cell_size * 0.072)
	var heel_r := maxf(1.3, cell_size * 0.056)
	# Dark damp stain on stone/wood + subtle glossy sky-sheen glint on the wet film!
	var damp := Color(0.05, 0.07, 0.09, 0.46 * alpha)
	var glint := Color(0.70 * lerpf(0.35, 1.0, daylight), 0.78 * lerpf(0.35, 1.0, daylight), 0.86 * lerpf(0.35, 1.0, daylight), 0.24 * alpha)
	canvas.draw_set_transform(center, angle, Vector2(1.30, 0.82))
	canvas.draw_circle(Vector2(sole_r * 0.72, 0.0), sole_r, damp)
	canvas.draw_circle(Vector2(-heel_r * 0.95, 0.0), heel_r, damp)
	canvas.draw_circle(Vector2(sole_r * 0.85, -0.35), sole_r * 0.48, glint)
	canvas.draw_circle(Vector2(-heel_r * 0.85, -0.30), heel_r * 0.42, glint)
	canvas.draw_set_transform(Vector2.ZERO)
