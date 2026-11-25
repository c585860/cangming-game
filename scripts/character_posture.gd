extends RefCounted

# Interactive character posture subsystem (sitting on Chinese chairs/benches, lying on canopy beds).
# Smoothly animates gliding onto the furniture, sitting/reclining with gentle idle breathing,
# brocade quilt draping on beds, and seamless stand-up when moving.

const Pack = preload("res://scripts/undead_tiles.gd")

var state: StringName = &"standing" # &"standing", &"sitting", &"lying"
var furniture_tile := Vector2i(-1, -1)
var blend := 0.0
var elapsed := 0.0
var bed_horizontal := false
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
		var has_w: bool = cells.get(target_tile + Vector2i.LEFT, [" "])[0] == "b"
		var has_e: bool = cells.get(target_tile + Vector2i.RIGHT, [" "])[0] == "b"
		var has_n: bool = cells.get(target_tile + Vector2i.UP, [" "])[0] == "b"
		var has_s: bool = cells.get(target_tile + Vector2i.DOWN, [" "])[0] == "b"
		bed_horizontal = (has_w or has_e) and not (has_n or has_s)
		var roll := ((target_tile.x * 0x9e3779b9) ^ (target_tile.y * 0x85ebca6b) ^ seed) & 0xffffffff
		quilt_color = Color("8f342d") if (roll % 2 == 0) else Color("34665c")
		if has_s and not has_n:
			return Vector2(target_tile) + Vector2(0.0, 0.22)
		if has_n and not has_s:
			return Vector2(target_tile) + Vector2(0.0, -0.22)
		if has_e and not has_w:
			return Vector2(target_tile) + Vector2(0.22, 0.0)
		if has_w and not has_e:
			return Vector2(target_tile) + Vector2(-0.22, 0.0)
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
		lit_tint: Color, outfit: String, outfit_tint: Color) -> void:
	var breath := sin(elapsed * 2.2) * (cell_f * 0.022) * blend
	var scale_x := -1.0 if flip else 1.0

	if state == &"sitting":
		# Seated pose: lowered smoothly onto cushion with slight seated torso compression & subtle leg tuck
		var sink := cell_f * 0.14 * blend + breath * 0.5
		var seat_pivot := origin + Vector2(cell_f * 0.5, cell_f * 0.78 + sink)
		var squash_y := lerpf(1.0, 0.84, blend)
		var stretch_x := lerpf(1.0, 1.06, blend) * scale_x
		# Soft seated shadow on cushion
		dest.draw_set_transform(origin + Vector2(cell_f * 0.5, cell_f * 0.72), 0.0, Vector2(0.95, 0.42))
		dest.draw_circle(Vector2.ZERO, cell_f * 0.26, Color(0.03, 0.02, 0.02, 0.34 * blend))
		dest.draw_set_transform(Vector2.ZERO)

		dest.draw_set_transform(seat_pivot, 0.0, Vector2(stretch_x, squash_y))
		var local_origin := -Vector2(cell_f * 0.5, cell_f * 0.80)
		for id: String in ["player_male", "overlay_worn_pants", "overlay_worn_boots", "overlay_worn_tunic"]:
			Pack.draw_at(dest, id, local_origin, cell_f, 0, -1, 0, lit_tint, Vector2.ZERO, false)
		Pack.draw_at(dest, outfit, local_origin, cell_f, 0, -1, 0, outfit_tint, Vector2.ZERO, false)
		dest.draw_set_transform(Vector2.ZERO)
		return

	if state == &"lying":
		# Reclining pose on the Chinese canopy bed: head resting on pillow, draped brocade quilt rising with breath!
		var center := origin + Vector2(cell_f * 0.50, cell_f * 0.46)
		var target_rot := (-PI * 0.5) if bed_horizontal else 0.0
		var rot := lerpf(0.0, target_rot, blend)
		var scale_y := lerpf(1.0, 0.92, blend)
		dest.draw_set_transform(center, rot, Vector2(scale_x, scale_y))
		var local_origin := -Vector2(cell_f * 0.5, cell_f * 0.5)
		for id: String in ["player_male", "overlay_worn_pants", "overlay_worn_tunic"]:
			Pack.draw_at(dest, id, local_origin, cell_f, 0, -1, 0, lit_tint, Vector2.ZERO, false)
		dest.draw_set_transform(Vector2.ZERO)

		# Draped brocade silk quilt covering chest & legs with gentle breathing rise!
		if blend > 0.25:
			var q_alpha := smoothstep(0.25, 0.92, blend)
			var q_col := Color(quilt_color.r * lit_tint.r, quilt_color.g * lit_tint.g, quilt_color.b * lit_tint.b, q_alpha)
			var q_hi := Color(minf(q_col.r * 1.18, 1.0), minf(q_col.g * 1.18, 1.0), minf(q_col.b * 1.18, 1.0), q_alpha)
			var trim := Color(0.84 * lit_tint.r, 0.70 * lit_tint.g, 0.38 * lit_tint.b, q_alpha * 0.9)
			var qr: Rect2
			if bed_horizontal:
				qr = Rect2(origin.x + cell_f * 0.36, origin.y + cell_f * 0.14 + breath, cell_f * 0.58, cell_f * 0.70)
			else:
				qr = Rect2(origin.x + cell_f * 0.16, origin.y + cell_f * 0.42 + breath, cell_f * 0.68, cell_f * 0.54)
			dest.draw_rect(qr, q_col)
			dest.draw_rect(Rect2(qr.position.x, qr.position.y, qr.size.x, maxf(2.0, cell_f * 0.08)), q_hi)
			dest.draw_rect(qr, trim, false, 1.0)

		# Gentle floating sleep/rest indicators ("·" soft breath bubbles rising slowly)
		if blend > 0.8:
			for i in range(2):
				var phase := fposmod(elapsed * 0.55 + float(i) * 0.5, 1.0)
				var z_pos := origin + Vector2(cell_f * (0.68 + 0.12 * sin(phase * PI * 2.0)), cell_f * (0.18 - phase * 0.48))
				var za := sin(phase * PI) * 0.65
				var z_col := Color(0.92, 0.88, 0.72, za)
				var zr := maxf(1.5, cell_f * (0.055 + 0.03 * phase))
				dest.draw_line(z_pos + Vector2(-zr, -zr), z_pos + Vector2(zr, -zr), z_col, 1.2)
				dest.draw_line(z_pos + Vector2(zr, -zr), z_pos + Vector2(-zr, zr), z_col, 1.2)
				dest.draw_line(z_pos + Vector2(-zr, zr), z_pos + Vector2(zr, zr), z_col, 1.2)
