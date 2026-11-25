extends RefCounted

# Decoupled 60 FPS character locomotion, procedural walking animation, and real-time character lighting.
# Rendered on its own layer above the atmosphere post-process so the player is NEVER occluded or
# self-shadowed during smooth movement, while still receiving dynamic day/night/indoor/lantern tinting.

const Pack = preload("res://scripts/undead_tiles.gd")
const Lighting = preload("res://scripts/lighting.gd")
const Posture = preload("res://scripts/character_posture.gd")

var visual_pos := Vector2.ZERO
var target_pos := Vector2.ZERO
var facing_x := 1
var facing_dir := Vector2.DOWN
var walk_cycle := 0.0
var walk_blend := 0.0
var move_speed := 7.6 # tiles/sec, matched smoothly to MoveInput.REPEAT_STEP_INTERVAL (0.135s -> 7.4/s)
var posture := Posture.new()


func snap_to(grid_pos: Vector2i) -> void:
	visual_pos = Vector2(grid_pos)
	target_pos = Vector2(grid_pos)
	walk_blend = 0.0
	posture.reset()


func enter_posture(kind: StringName, furniture_tile: Vector2i, cells: Dictionary, seed: int) -> void:
	var dest := posture.enter(kind, furniture_tile, cells, seed)
	var delta := dest - visual_pos
	if absf(delta.x) > 0.05:
		facing_x = -1 if delta.x < 0.0 else 1
	target_pos = dest


func exit_posture(stand_pos: Vector2i) -> void:
	if not posture.is_active():
		return
	posture.exit()
	target_pos = Vector2(stand_pos)


func is_resting() -> bool:
	return posture.is_active()


func set_target(grid_pos: Vector2i) -> void:
	if posture.is_active():
		posture.exit()
	var next := Vector2(grid_pos)
	var delta := next - target_pos
	if delta.length_squared() > 16.0:
		snap_to(grid_pos)
		return
	if delta.length_squared() > 0.001:
		facing_dir = delta.normalized()
		if absf(delta.x) > 0.05:
			facing_x = -1 if delta.x < 0.0 else 1
	target_pos = next


func tick(delta: float) -> bool:
	var diff := target_pos - visual_pos
	var dist := diff.length()
	var moved := false
	if dist > 0.002:
		var speed := maxf(move_speed, dist * 6.8)
		var step := minf(dist, speed * delta)
		visual_pos += diff * (step / dist)
		if not posture.is_active():
			walk_cycle = fposmod(walk_cycle + step * 1.10, 2.0)
			walk_blend = move_toward(walk_blend, 1.0, delta * 14.0)
		else:
			walk_blend = move_toward(walk_blend, 0.0, delta * 14.0)
		moved = true
	else:
		visual_pos = target_pos
		if walk_blend > 0.005:
			walk_blend = move_toward(walk_blend, 0.0, delta * 10.0)
			moved = true
		else:
			walk_blend = 0.0
	if posture.tick(delta):
		moved = true
	return moved


func bob_px(cell_size: float) -> float:
	if walk_blend <= 0.001:
		return 0.0
	return -absf(sin(walk_cycle * PI)) * (cell_size * 0.115) * walk_blend


func lean_rad() -> float:
	if walk_blend <= 0.001:
		return 0.0
	return sin(walk_cycle * PI) * 0.06 * walk_blend


func stride_offset_x(cell_size: float) -> float:
	if walk_blend <= 0.001:
		return 0.0
	return sin(walk_cycle * PI) * (cell_size * 0.028) * walk_blend


func compute_player_tint(cells: Dictionary, scene_lighting: RefCounted, weather: RefCounted) -> Color:
	# Physically-inspired real-time character lighting synced with outdoor/indoor sky & nearby lanterns,
	# with a gentle legibility floor so the player is always clearly visible even in midnight interiors.
	var p := Vector2i(roundi(visual_pos.x), roundi(visual_pos.y))
	var data: Array = cells.get(p, [])
	var indoors := not data.is_empty() and Lighting.enclosed(data)
	var base_light: Color = scene_lighting.current_roof_light
	if indoors:
		base_light = Color(
			lerpf(0.38, 0.72, scene_lighting.current_daylight),
			lerpf(0.40, 0.72, scene_lighting.current_daylight),
			lerpf(0.46, 0.74, scene_lighting.current_daylight)
		)
	# Gather warm glow from nearby active emitters (lanterns, candles, hearths, altar)
	var lamp_boost := Color(0.0, 0.0, 0.0, 0.0)
	var lp := float(scene_lighting.current_lamp_power)
	for ep: Vector2i in scene_lighting.active_emitters:
		var dist := visual_pos.distance_to(Vector2(ep))
		if dist > 6.5:
			continue
		var kind: StringName = scene_lighting.active_emitters[ep]
		var col := Color(1.0, 0.78, 0.48)
		var power := lp
		if kind == &"altar" or kind == &"herb":
			col = Color(0.45, 0.96, 0.80)
			power = maxf(lp, 0.55)
		elif kind == &"hearth":
			col = Color(1.0, 0.56, 0.28)
			power = maxf(lp, 0.50)
		elif kind == &"candle":
			power = maxf(lp, 0.25)
		var atten := power * clampf(1.0 - dist / 6.5, 0.0, 1.0)
		atten = atten * atten * 0.55
		lamp_boost.r += col.r * atten
		lamp_boost.g += col.g * atten
		lamp_boost.b += col.b * atten
	var r := clampf(base_light.r + lamp_boost.r, 0.44, 1.08)
	var g := clampf(base_light.g + lamp_boost.g, 0.46, 1.06)
	var b := clampf(base_light.b + lamp_boost.b, 0.50, 1.08)
	if weather != null and float(weather.rain) > 0.2 and not indoors:
		r *= 0.94
		g *= 0.97
	return Color(r, g, b, 1.0)


func draw_character(board: Control, dest: Control, role: StringName, at_world: Vector2,
		animated := false, tile_cell := Vector2i.ZERO, lit_tint := Color.WHITE) -> void:
	var masking := dest.has_method("surface_id")
	var cell_f := float(board.cell)
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	var origin := (at_world - Vector2(board.view_origin)) * cell_f + cam_offset
	var tint: Color = dest.call("surface_id", tile_cell) if masking else lit_tint
	var outfit := "overlay_worn_cloak"
	var outfit_tint := tint if masking else (Color("c9e3d7") * lit_tint)
	match role:
		&"merchant":
			outfit = "overlay_worn_robe"
			outfit_tint = tint if masking else (Color("e9d29c") * lit_tint)
		&"ferryman":
			outfit = "overlay_worn_straw_hat"
			outfit_tint = tint if masking else (Color("e4d4b2") * lit_tint)

	var flip := animated and facing_x < 0
	if animated and not masking and posture.is_active():
		posture.draw_posture(dest, origin, cell_f, flip, lit_tint, outfit, outfit_tint)
		return

	var bob := bob_px(cell_f) if animated else 0.0
	var sway := stride_offset_x(cell_f) if animated else 0.0
	var lean := lean_rad() if animated else 0.0
	var draw_origin := origin + Vector2(sway, bob)

	if animated and not masking:
		# Subtle soft contact grounding oval right beneath the animated feet
		var foot := origin + Vector2(cell_f * 0.5, cell_f * 0.87)
		var shadow_scale := 1.0 - absf(bob) / maxf(1.0, cell_f * 0.35)
		dest.draw_set_transform(foot, 0.0, Vector2(shadow_scale, 0.36 * shadow_scale))
		dest.draw_circle(Vector2.ZERO, cell_f * 0.28, Color(0.03, 0.05, 0.06, 0.34))
		dest.draw_set_transform(Vector2.ZERO)

	if animated and (absf(lean) > 0.002 or flip) and not masking:
		# Apply lean & horizontal flip in ONE transform and pass flip=false to Pack.draw_at;
		# Pack._draw_layer resets draw_set_transform when flip=true, which previously overwrote
		# our pivot and threw the sprite off-screen whenever walking left!
		var pivot := draw_origin + Vector2(cell_f * 0.5, cell_f * 0.85)
		var scale_vec := Vector2(-1.0 if flip else 1.0, 1.0)
		dest.draw_set_transform(pivot, lean, scale_vec)
		var local_origin := -Vector2(cell_f * 0.5, cell_f * 0.85)
		for id: String in ["player_male", "overlay_worn_pants", "overlay_worn_boots", "overlay_worn_tunic"]:
			Pack.draw_at(dest, id, local_origin, cell_f, 0, -1, 0, tint, Vector2.ZERO, false)
		Pack.draw_at(dest, outfit, local_origin, cell_f, 0, -1, 0, outfit_tint, Vector2.ZERO, false)
		dest.draw_set_transform(Vector2.ZERO)
	else:
		for id: String in ["player_male", "overlay_worn_pants", "overlay_worn_boots", "overlay_worn_tunic"]:
			Pack.draw_at(dest, id, draw_origin, cell_f, 0, -1, 0, tint, Vector2.ZERO, flip)
		Pack.draw_at(dest, outfit, draw_origin, cell_f, 0, -1, 0, outfit_tint, Vector2.ZERO, flip)
