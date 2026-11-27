extends RefCounted

# Modular 60 FPS World Effects & Animation Renderer for the embedded real CCB engine:
# - Smooth exponential creature/player movement glide (player, NPCs, monsters)
# - Auto-Move active route & mouse hover Destination Preview (glowing polyline + pulsing destination reticle)
# - Live CCB transient combat & world animations:
#   Explosions, Flying Bullets/Tracers, Hit Flashes, Aim/Throw Lines, Zone Rectangles,
#   Unobscuring Cursors, Pulsing Sound Ripples (?), Floating Scrolling Combat Text (SCT), and Monster HP bars.

const TILE_FLAG_OVERLAY := 0x20
const CRITTER_PLAYER := 0x01

const PATH_AUTOMOVE := 1
const PATH_PREVIEW := 2
const PATH_DESTINATION := 3

const OV_HIGHLIGHT := 1
const OV_HIT_FLASH := 2
const OV_EXPLOSION := 3
const OV_BULLET := 4
const OV_ZONE := 5
const OV_SOUND := 6
const OV_CURSOR := 7

const GLIDE_SPEED := 20.0 # ~90ms silky exponential settle

var _critter_visual: Dictionary = {} # uid (int) -> Vector2 (world tile coords)
var _critter_target: Dictionary = {} # uid (int) -> Vector2
var _player_visual := Vector2.ZERO
var _player_target := Vector2.ZERO
var _has_player := false
var _last_z := 0
var _anim_time := 0.0
var _is_gliding := false
var _cached_overlays: Array = [] # sparse [wx, wy, kind, cp, fg_col, bg_col] built ONCE per snapshot!
var _has_animated_fx := false


func reset() -> void:
	_critter_visual.clear()
	_critter_target.clear()
	_cached_overlays.clear()
	_has_player = false
	_is_gliding = false
	_has_animated_fx = false


func sync_snapshot(snap: Dictionary) -> void:
	var z := int(snap.get("z", 0))
	var p_tile: Vector2i = snap.get("player", Vector2i.ZERO)
	var p_vec := Vector2(p_tile)
	if not _has_player or z != _last_z or _player_visual.distance_to(p_vec) > 4.5:
		_player_visual = p_vec
		_critter_visual.clear()
		_critter_target.clear()
		_has_player = true
	_last_z = z
	_player_target = p_vec

	var alive_uids := {}
	var creatures: Array = snap.get("creatures", [])
	for c_var in creatures:
		var cd: Dictionary = c_var
		var uid := int(cd.get("uid", 0))
		if uid == 0:
			continue
		var tgt := Vector2(float(cd.get("x", 0)), float(cd.get("y", 0)))
		alive_uids[uid] = true
		_critter_target[uid] = tgt
		if not _critter_visual.has(uid) or (_critter_visual[uid] as Vector2).distance_to(tgt) > 4.5:
			_critter_visual[uid] = tgt
		elif (_critter_visual[uid] as Vector2).distance_squared_to(tgt) > 0.0004:
			_is_gliding = true

	# Prune creatures that left view
	var stale: Array = []
	for uid in _critter_visual:
		if not alive_uids.has(uid):
			stale.append(uid)
	for uid in stale:
		_critter_visual.erase(uid)
		_critter_target.erase(uid)

	# Pre-extract sparse active tile overlays ONCE per snapshot (eliminates 2,501-tile x 60 FPS scan!)
	_cached_overlays.clear()
	var has_pulsing_ov := false
	if bool(snap.get("has_overlays", true)):
		var origin: Vector2i = snap.get("origin", Vector2i.ZERO)
		var grid_sz: Vector2i = snap.get("size", Vector2i.ZERO)
		var tiles_bytes: PackedByteArray = snap.get("tiles", PackedByteArray())
		var stride: int = int(snap.get("tile_stride", 48))
		if grid_sz.x > 0 and grid_sz.y > 0 and tiles_bytes.size() >= grid_sz.x * grid_sz.y * stride:
			for ty in range(grid_sz.y):
				var wy := origin.y + ty
				var row_idx := ty * grid_sz.x
				for tx in range(grid_sz.x):
					var off := (row_idx + tx) * stride
					if (tiles_bytes.decode_u8(off + 24) & TILE_FLAG_OVERLAY) == 0:
						continue
					var ov_kind := tiles_bytes.decode_u8(off + 44)
					if ov_kind == 0:
						continue
					var wx := origin.x + tx
					var cp := tiles_bytes.decode_u32(off + 32)
					var fg_col := _unpack_rgba(tiles_bytes.decode_u32(off + 36), 0.96)
					var bg_col := _unpack_rgba(tiles_bytes.decode_u32(off + 40), 0.96)
					_cached_overlays.append([wx, wy, ov_kind, cp, fg_col, bg_col])
					if ov_kind == OV_SOUND or ov_kind == OV_CURSOR or ov_kind == OV_EXPLOSION:
						has_pulsing_ov = true

	var path_pts: Array = snap.get("path_points", [])
	var sct_list: Array = snap.get("sct", [])
	_has_animated_fx = (not path_pts.is_empty()) or bool(snap.get("is_looking", false)) \
		or has_pulsing_ov or (not sct_list.is_empty())


func needs_continuous_redraw() -> bool:
	return _is_gliding or _has_animated_fx


func tick(delta: float) -> bool:
	_anim_time += delta
	var moved := false
	var t := 1.0 - exp(-GLIDE_SPEED * clampf(delta, 0.0, 0.05))

	if _has_player:
		var pd := _player_visual.distance_squared_to(_player_target)
		if pd > 0.0002:
			_player_visual = _player_visual.lerp(_player_target, t)
			moved = true
		elif pd > 0.0:
			_player_visual = _player_target
			moved = true

	for uid in _critter_target:
		var tgt: Vector2 = _critter_target[uid]
		var cur: Vector2 = _critter_visual.get(uid, tgt)
		var d2 := cur.distance_squared_to(tgt)
		if d2 > 0.0002:
			_critter_visual[uid] = cur.lerp(tgt, t)
			moved = true
		elif d2 > 0.0:
			_critter_visual[uid] = tgt
			moved = true

	_is_gliding = moved
	return moved


func is_gliding() -> bool:
	return _is_gliding


func get_player_visual() -> Vector2:
	return _player_visual


func get_creature_visual(uid: int, fallback: Vector2) -> Vector2:
	if uid != 0 and _critter_visual.has(uid):
		return _critter_visual[uid]
	return fallback


static func _unpack_rgba(rgba: int, alpha_override := -1.0) -> Color:
	var a := alpha_override if alpha_override >= 0.0 else float((rgba >> 24) & 0xFF) / 255.0
	return Color(
		float(rgba & 0xFF) / 255.0,
		float((rgba >> 8) & 0xFF) / 255.0,
		float((rgba >> 16) & 0xFF) / 255.0,
		a
	)


func draw_overlays(canvas: Control, snap: Dictionary, view_origin_world: Vector2,
		tile_px: float, ui_font: Font) -> void:
	if not bool(snap.get("valid", false)):
		return

	var pulse := 0.5 + 0.5 * sin(_anim_time * 5.2)

	# 1. Auto-Move Route & Mouse Destination Preview (glowing polyline + step beads + animated target reticle)
	var path_pts: Array = snap.get("path_points", [])
	if not path_pts.is_empty():
		_draw_route(canvas, snap, path_pts, view_origin_world, tile_px, pulse)

	# 2. Sparse cached transient CCB animations & tile overlays (0..8 items instead of 2,501-tile scan!)
	for ov_var in _cached_overlays:
		var ov: Array = ov_var
		var sx := (float(ov[0]) - view_origin_world.x) * tile_px
		var sy := (float(ov[1]) - view_origin_world.y) * tile_px
		if sx < -tile_px or sy < -tile_px or sx > canvas.size.x + tile_px or sy > canvas.size.y + tile_px:
			continue
		_draw_tile_effect(canvas, int(ov[2]), int(ov[3]), sx, sy, tile_px, ov[4], ov[5], ui_font, pulse)

	# 3. Look-around / aiming center cursor
	if bool(snap.get("is_looking", false)):
		var center: Vector2i = snap.get("center", Vector2i.ZERO)
		var cx := (float(center.x) - view_origin_world.x) * tile_px
		var cy := (float(center.y) - view_origin_world.y) * tile_px
		var ccol := Color(1.0, 0.92, 0.25, 0.78 + 0.22 * pulse)
		_draw_corner_reticle(canvas, Rect2(cx + 1.0, cy + 1.0, tile_px - 2.0, tile_px - 2.0), ccol, 2.0)

	# 4. Scrolling Combat Text (SCT floating damage / dodge / crit labels)
	var sct_list: Array = snap.get("sct", [])
	if ui_font != null and not sct_list.is_empty():
		var fsize := maxi(12, int(tile_px * 0.48))
		for s_var in sct_list:
			var sd: Dictionary = s_var
			var txt := str(sd.get("text", ""))
			if txt.is_empty():
				continue
			var wx := float(sd.get("x", 0))
			var wy := float(sd.get("y", 0))
			var step := float(sd.get("step", 0))
			var max_st := maxf(1.0, float(sd.get("max_steps", 8)))
			var alpha := clampf(1.25 - (step / max_st), 0.25, 1.0)
			var sx := (wx - view_origin_world.x) * tile_px
			var sy := (wy - view_origin_world.y + 0.72) * tile_px
			if sx < -tile_px * 3.0 or sy < -tile_px or sx > canvas.size.x + tile_px * 3.0 or sy > canvas.size.y + tile_px:
				continue
			var col := _unpack_rgba(int(sd.get("rgba", 0xFFFFFFFF)), alpha)
			var shadow := Color(0.0, 0.0, 0.0, alpha * 0.85)
			canvas.draw_string(ui_font, Vector2(sx + 1.0, sy + 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, shadow)
			canvas.draw_string(ui_font, Vector2(sx, sy), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, col)

	# 5. Subtle damage indicator bar under injured hostile/friendly creatures (tracks smooth glide position!)
	var creatures: Array = snap.get("creatures", [])
	for c_var in creatures:
		var cd: Dictionary = c_var
		var hp_pct := int(cd.get("hp_pct", 100))
		var cflags := int(cd.get("flags", 0))
		if hp_pct >= 100 or (cflags & CRITTER_PLAYER) != 0:
			continue
		var uid := int(cd.get("uid", 0))
		var vpos := get_creature_visual(uid, Vector2(float(cd.get("x", 0)), float(cd.get("y", 0))))
		var sx := (vpos.x - view_origin_world.x) * tile_px
		var sy := (vpos.y - view_origin_world.y) * tile_px
		if sx < -tile_px or sy < -tile_px or sx > canvas.size.x + tile_px or sy > canvas.size.y + tile_px:
			continue
		var bw := tile_px - 4.0
		var fill_w := bw * clampf(float(hp_pct) / 100.0, 0.0, 1.0)
		canvas.draw_rect(Rect2(sx + 2.0, sy + tile_px - 4.0, bw, 3.0), Color(0.0, 0.0, 0.0, 0.82))
		var bar_col := Color(0.28, 0.90, 0.30) if hp_pct > 60 else (Color(0.95, 0.80, 0.18) if hp_pct > 30 else Color(0.95, 0.24, 0.22))
		canvas.draw_rect(Rect2(sx + 2.0, sy + tile_px - 4.0, fill_w, 3.0), bar_col)


func _draw_route(canvas: Control, snap: Dictionary, path_pts: Array, view_origin_world: Vector2,
		tile_px: float, pulse: float) -> void:
	var is_active := int((path_pts[0] as Dictionary).get("kind", PATH_PREVIEW)) == PATH_AUTOMOVE
	var line_col := Color(0.32, 0.92, 0.72, 0.82) if is_active else Color(0.42, 0.80, 1.0, 0.74)
	var glow_col := Color(line_col.r, line_col.g, line_col.b, 0.22)

	var pts := PackedVector2Array()
	var p_vis := _player_visual if _has_player else Vector2(snap.get("player", Vector2i.ZERO))
	pts.append((p_vis + Vector2(0.5, 0.5) - view_origin_world) * tile_px)
	for p_var in path_pts:
		var pd: Dictionary = p_var
		var w := Vector2(float(pd.get("x", 0)) + 0.5, float(pd.get("y", 0)) + 0.5)
		pts.append((w - view_origin_world) * tile_px)

	if pts.size() >= 2:
		canvas.draw_polyline(pts, glow_col, maxf(4.0, tile_px * 0.22), true)
		canvas.draw_polyline(pts, line_col, maxf(2.0, tile_px * 0.08), true)

	# Animated marching beads along waypoints + target reticle at destination
	for i in range(path_pts.size()):
		var pd: Dictionary = path_pts[i]
		var wx := float(pd.get("x", 0))
		var wy := float(pd.get("y", 0))
		var center := Vector2((wx + 0.5 - view_origin_world.x) * tile_px, (wy + 0.5 - view_origin_world.y) * tile_px)
		var kind := int(pd.get("kind", PATH_PREVIEW))
		if kind == PATH_DESTINATION or i == path_pts.size() - 1:
			var r := tile_px * (0.34 + 0.06 * pulse)
			var dest_col := Color(1.0, 0.94, 0.42, 0.92) if is_active else Color(0.55, 0.92, 1.0, 0.90)
			canvas.draw_arc(center, r, 0.0, TAU, 24, Color(dest_col.r, dest_col.g, dest_col.b, 0.28), 3.5, true)
			canvas.draw_arc(center, r * 0.78, 0.0, TAU, 24, dest_col, 1.8, true)
			# Crisp diamond center
			var d := tile_px * 0.14
			var diamond := PackedVector2Array([
				center + Vector2(0, -d), center + Vector2(d, 0),
				center + Vector2(0, d), center + Vector2(-d, 0),
			])
			canvas.draw_colored_polygon(diamond, dest_col)
		else:
			var wave := 0.5 + 0.5 * sin(_anim_time * 7.0 - float(i) * 0.7)
			var br := maxf(2.0, tile_px * (0.08 + 0.04 * wave))
			canvas.draw_circle(center, br, Color(line_col.r, line_col.g, line_col.b, 0.55 + 0.40 * wave))


func _draw_tile_effect(canvas: Control, kind: int, cp: int, sx: float, sy: float, tpx: float,
		fg_col: Color, bg_col: Color, ui_font: Font, pulse: float) -> void:
	var center := Vector2(sx + tpx * 0.5, sy + tpx * 0.5)
	var rect := Rect2(sx + 1.0, sy + 1.0, tpx - 2.0, tpx - 2.0)

	match kind:
		OV_EXPLOSION:
			var glow := Color(1.0, 0.55, 0.14, 0.38)
			var core := Color(1.0, 0.90, 0.45, 0.85)
			canvas.draw_circle(center, tpx * 0.56, glow)
			canvas.draw_circle(center, tpx * 0.32, Color(fg_col.r, maxf(fg_col.g, 0.45), 0.12, 0.72))
			canvas.draw_circle(center, tpx * 0.16, core)
		OV_BULLET:
			canvas.draw_circle(center, tpx * 0.28, Color(1.0, 0.42, 0.15, 0.38))
			canvas.draw_circle(center, tpx * 0.15, Color(1.0, 0.88, 0.52, 0.95))
			canvas.draw_circle(center, tpx * 0.08, Color.WHITE)
		OV_HIT_FLASH:
			var fcol := Color(bg_col.r, bg_col.g, bg_col.b, 0.42)
			canvas.draw_rect(rect, fcol)
			canvas.draw_rect(rect, Color(bg_col.r, bg_col.g, bg_col.b, 0.88), false, 2.0)
		OV_ZONE:
			canvas.draw_rect(rect, Color(0.25, 0.88, 0.40, 0.22))
			canvas.draw_rect(rect, Color(0.40, 0.95, 0.52, 0.65), false, 1.0)
		OV_HIGHLIGHT:
			var hcol := Color(0.95, 0.86, 0.32, 0.22) if (bg_col.r + bg_col.g > 0.8) else Color(bg_col.r, bg_col.g, bg_col.b, 0.24)
			canvas.draw_rect(rect, hcol)
			canvas.draw_rect(rect, Color(hcol.r, hcol.g, hcol.b, 0.70), false, 1.2)
		OV_CURSOR:
			var ccol := Color(0.40, 1.0, 0.62, 0.88) if cp == 88 else Color(0.45, 0.92, 1.0, 0.88)
			_draw_corner_reticle(canvas, rect, ccol, 1.8)
		OV_SOUND:
			var rad := tpx * (0.28 + 0.18 * pulse)
			canvas.draw_arc(center, rad, 0.0, TAU, 20, Color(fg_col.r, fg_col.g, fg_col.b, 0.65 * (1.0 - pulse * 0.5)), 1.5, true)
			if ui_font != null:
				canvas.draw_string(ui_font, Vector2(sx + tpx * 0.28, sy + tpx * 0.76), "?", HORIZONTAL_ALIGNMENT_LEFT, -1.0, maxi(12, int(tpx * 0.60)), fg_col)


static func _draw_corner_reticle(canvas: Control, r: Rect2, col: Color, w: float) -> void:
	var arm := minf(r.size.x, r.size.y) * 0.30
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	# Top-left
	canvas.draw_line(Vector2(x0, y0), Vector2(x0 + arm, y0), col, w)
	canvas.draw_line(Vector2(x0, y0), Vector2(x0, y0 + arm), col, w)
	# Top-right
	canvas.draw_line(Vector2(x1, y0), Vector2(x1 - arm, y0), col, w)
	canvas.draw_line(Vector2(x1, y0), Vector2(x1, y0 + arm), col, w)
	# Bottom-left
	canvas.draw_line(Vector2(x0, y1), Vector2(x0 + arm, y1), col, w)
	canvas.draw_line(Vector2(x0, y1), Vector2(x0, y1 - arm), col, w)
	# Bottom-right
	canvas.draw_line(Vector2(x1, y1), Vector2(x1 - arm, y1), col, w)
	canvas.draw_line(Vector2(x1, y1), Vector2(x1, y1 - arm), col, w)
