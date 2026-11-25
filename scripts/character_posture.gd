extends RefCounted

# Interactive character posture subsystem (sitting on Chinese chairs/benches, lying on 2-tile canopy beds).
# Aligns lying angle, head-to-pillow placement, and draped brocade quilt seamlessly with the bed's
# exact 4-way orientation (North->South, South->North, West->East, East->West)!

const Pack = preload("res://scripts/undead_tiles.gd")
const ChineseFurn = preload("res://scripts/chinese_furniture.gd")

var state: StringName = &"standing" # &"standing", &"sitting", &"lying"
var furniture_tile := Vector2i(-1, -1)
var blend := 0.0
var elapsed := 0.0
var bed_dir := Vector2i.DOWN
var bed_two_tile := true
var quilt_color := Color("8f342d")


func is_active() -> bool:
	return state != &"standing"


func reset() -> void:
	state = &"standing"
	furniture_tile = Vector2i(-1, -1)
	blend = 0.0
	elapsed = 0.0


func enter(kind: StringName, target_tile: Vector2i, cells: Dictionary, seed: int) -> Vector2:
	state = kind
	furniture_tile = target_tile
	blend = 0.0
	elapsed = 0.0
	if kind == &"lying":
		var info := ChineseFurn.bed_layout(cells, target_tile, seed)
		var head: Vector2i = info["head"]
		bed_dir = info["dir"]
		bed_two_tile = bool(info["is_two_tile"])
		quilt_color = info["quilt_color"]
		# Place character center slightly past the head pillow toward the foot tile along the 2-tile bed!
		var offset := Vector2(bed_dir) * (0.28 if bed_two_tile else 0.04)
		return Vector2(head) + offset
	return Vector2(target_tile)


func exit() -> void:
	state = &"standing"
	furniture_tile = Vector2i(-1, -1)
	elapsed = 0.0


func tick(delta: float) -> bool:
	if state != &"standing":
		elapsed += delta
		blend = move_toward(blend, 1.0, delta * 6.5)
		return true
	if blend > 0.005:
		blend = move_toward(blend, 0.0, delta * 9.0)
		return true
	blend = 0.0
	return false


func draw_posture(dest: Control, origin: Vector2, cell_f: float, flip: bool,
		lit_tint: Color, outfit: String, outfit_tint: Color, worn_overlays := PackedStringArray()) -> void:
	var breath := sin(elapsed * 2.2) * (cell_f * 0.020) * blend
	var scale_x := -1.0 if flip else 1.0

	if state == &"sitting":
		var sink := cell_f * 0.14 * blend + breath * 0.5
		var seat_pivot := origin + Vector2(cell_f * 0.5, cell_f * 0.78 + sink)
		var squash_y := lerpf(1.0, 0.84, blend)
		var stretch_x := lerpf(1.0, 1.06, blend) * scale_x
		dest.draw_set_transform(origin + Vector2(cell_f * 0.5, cell_f * 0.72), 0.0, Vector2(0.95, 0.42))
		dest.draw_circle(Vector2.ZERO, cell_f * 0.26, Color(0.03, 0.02, 0.02, 0.34 * blend))
		dest.draw_set_transform(Vector2.ZERO)

		dest.draw_set_transform(seat_pivot, 0.0, Vector2(stretch_x, squash_y))
		var local_origin := -Vector2(cell_f * 0.5, cell_f * 0.80)
		Pack.draw_at(dest, "player_male", local_origin, cell_f, 0, -1, 0, lit_tint, Vector2.ZERO, false)
		if not worn_overlays.is_empty():
			for oid: String in worn_overlays:
				var ot := outfit_tint if oid in ["overlay_worn_cloak", "overlay_worn_robe"] else lit_tint
				Pack.draw_at(dest, oid, local_origin, cell_f, 0, -1, 0, ot, Vector2.ZERO, false)
		else:
			for id: String in ["overlay_worn_pants", "overlay_worn_boots", "overlay_worn_tunic"]:
				Pack.draw_at(dest, id, local_origin, cell_f, 0, -1, 0, lit_tint, Vector2.ZERO, false)
			Pack.draw_at(dest, outfit, local_origin, cell_f, 0, -1, 0, outfit_tint, Vector2.ZERO, false)
		dest.draw_set_transform(Vector2.ZERO)
		return

	if state == &"lying":
		# Exact 4-way lying angle matching head -> foot:
		# (0, +1) N->S => 0, (0, -1) S->N => PI, (+1, 0) W->E => -PI/2, (-1, 0) E->W => +PI/2
		var target_rot := 0.0
		if bed_dir == Vector2i.RIGHT:
			target_rot = -PI * 0.5
		elif bed_dir == Vector2i.LEFT:
			target_rot = PI * 0.5
		elif bed_dir == Vector2i.UP:
			target_rot = PI

		var center := origin + Vector2(cell_f * 0.50, cell_f * 0.50)
		var rot := lerpf(0.0, target_rot, blend)
		# Stretch slightly along bed length on a 2-tile bed so proportions look natural
		var body_scale_y := lerpf(1.0, 1.12 if bed_two_tile else 0.94, blend)
		dest.draw_set_transform(center, rot, Vector2(1.0, body_scale_y))
		var local_origin := -Vector2(cell_f * 0.5, cell_f * 0.5)
		Pack.draw_at(dest, "player_male", local_origin, cell_f, 0, -1, 0, lit_tint, Vector2.ZERO, false)
		if not worn_overlays.is_empty():
			for oid: String in worn_overlays:
				if oid in ["overlay_worn_backpack", "overlay_worn_straw_hat", "overlay_worn_mbag"]:
					continue
				Pack.draw_at(dest, oid, local_origin, cell_f, 0, -1, 0, lit_tint, Vector2.ZERO, false)
		else:
			for id: String in ["overlay_worn_pants", "overlay_worn_tunic"]:
				Pack.draw_at(dest, id, local_origin, cell_f, 0, -1, 0, lit_tint, Vector2.ZERO, false)

		# Draped brocade silk quilt drawn in the EXACT SAME rotated bed coordinate space!
		# Covers from chest (+0.02*cell) all the way past feet (+1.05*cell on 2-tile bed), matching bed color!
		if blend > 0.25:
			var q_alpha := smoothstep(0.25, 0.92, blend)
			var q_col := Color(quilt_color.r * lit_tint.r, quilt_color.g * lit_tint.g, quilt_color.b * lit_tint.b, q_alpha)
			var q_hi := Color(minf(q_col.r * 1.18, 1.0), minf(q_col.g * 1.18, 1.0), minf(q_col.b * 1.18, 1.0), q_alpha)
			var trim := Color(0.84 * lit_tint.r, 0.70 * lit_tint.g, 0.38 * lit_tint.b, q_alpha * 0.92)
			var qw := cell_f * 0.68
			var q_top := cell_f * 0.02 + breath
			var q_len := cell_f * (0.98 if bed_two_tile else 0.46)
			var qr := Rect2(-qw * 0.5, q_top, qw, q_len)
			dest.draw_rect(qr, q_col)
			dest.draw_rect(Rect2(qr.position.x, qr.position.y, qr.size.x, maxf(2.5, cell_f * 0.09)), q_hi)
			dest.draw_rect(qr, trim, false, 1.0)
		dest.draw_set_transform(Vector2.ZERO)

		# Gentle floating sleep "Z" cues rising above the head
		if blend > 0.8:
			var head_world_off := -Vector2(bed_dir) * (cell_f * 0.25)
			for i in range(2):
				var phase := fposmod(elapsed * 0.55 + float(i) * 0.5, 1.0)
				var z_pos := center + head_world_off + Vector2(cell_f * (0.18 + 0.12 * sin(phase * PI * 2.0)), -cell_f * (0.30 + phase * 0.48))
				var za := sin(phase * PI) * 0.65
				var z_col := Color(0.92, 0.88, 0.72, za)
				var zr := maxf(1.5, cell_f * (0.055 + 0.03 * phase))
				dest.draw_line(z_pos + Vector2(-zr, -zr), z_pos + Vector2(zr, -zr), z_col, 1.2)
				dest.draw_line(z_pos + Vector2(zr, -zr), z_pos + Vector2(-zr, zr), z_col, 1.2)
				dest.draw_line(z_pos + Vector2(-zr, zr), z_pos + Vector2(zr, zr), z_col, 1.2)
