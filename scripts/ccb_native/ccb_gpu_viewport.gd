extends Control

# Godot 4.5 Dual-Channel World Renderer for the real CCB core engine.
# - Renders unmodified vanilla CCB gfx/ tilesets in true 2.5D Y-sorted painter's order
#   using real CCB subtile/rotation values, multi-hop looks_like fallbacks, and animated tiles.
# - Pipes the live world + semantic 3D geometry + surface mask directly through cangling-city's
#   full SceneLighting engine (Volumetric indoor sunbeams, Contact AO, Cascaded 3D raymarched
#   soft penumbra shadows, Multi-pass Colored GI Bounce, River Caustics, Rain Puddles, Dust Motes).
# - Delegates routes, explosions, bullets, hit flashes, SCT & 60fps smooth glide to CcbWorldEffects!

const Tiles = preload("res://scripts/undead_tiles.gd")
const RtLightingPipeline = preload("res://scripts/ccb_native/ccb_rt_lighting_pipeline.gd")
const WorldEffects = preload("res://scripts/ccb_native/ccb_world_effects.gd")
const WeatherFx = preload("res://scripts/weather_fx.gd")

const ZOOMS := [20, 24, 32, 40, 48]
const CRITTER_PLAYER := 0x01
const CRITTER_HOSTILE := 0x02
const CRITTER_NPC := 0x08
const CRITTER_MALE := 0x10

var zoom_idx := 2 # 32px default
var tile_px := 32

var _snapshot: Dictionary = {}
var _has_world := false
var _world_view: SubViewport
var _tile_canvas: Control
var _lighting: RtLightingPipeline
var _effects: WorldEffects
var _weather_fx: WeatherFx
var _overlay_layer: Control
var _ui_font: Font
var _view_origin_world := Vector2.ZERO
var _view_span_tiles := Vector2(28.0, 20.0)
var _has_animated_tiles := false
var _anim_redraw_accum := 0.0
var _resolved_entries: Array = [] # O(1) pre-resolved tile dictionaries per snapshot string ID!
var _resolved_tall: PackedByteArray = PackedByteArray()
var _resolved_season := ""


func build(font: Font) -> void:
	_ui_font = font
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Tiles.ensure_pack_tileset(true)

	# 1. Raw vanilla tileset SubViewport (unlit albedo in true 2.5D painter's order)
	_world_view = SubViewport.new()
	_world_view.disable_3d = true
	_world_view.transparent_bg = false
	_world_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_world_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_world_view)

	_tile_canvas = Control.new()
	_tile_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tile_canvas.draw.connect(_draw_tiles_subviewport)
	_world_view.add_child(_tile_canvas)

	# 2. Real-Time Per-Pixel 2.5D Raymarched Lighting & Continuous Shadowcasting FOV Pipeline
	_lighting = RtLightingPipeline.new()
	_lighting.build(self, _world_view.get_texture(), _draw_surface_mask)

	# 3. Dedicated smooth glide, auto-move routes, combat animations & SCT module
	_effects = WorldEffects.new()

	# 4. GPU Rain / Snow precipitation overlay masked to outdoor visible tiles
	_weather_fx = WeatherFx.new()
	_weather_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_weather_fx)

	# 5. Animated route, explosion, bullet, hit flash, SCT & targeting overlay layer
	_overlay_layer = Control.new()
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.draw.connect(_draw_world_overlays)
	add_child(_overlay_layer)

	resized.connect(_on_resized)
	_on_resized()
	set_process(true)


func apply_tileset_dir(dir_path: String, json_file: String, display_name: String) -> void:
	if Tiles.set_active_tileset_dir(dir_path, json_file, display_name):
		_trigger_redraw()


func adjust_zoom(delta_step: int) -> void:
	zoom_idx = clampi(zoom_idx + delta_step, 0, ZOOMS.size() - 1)
	tile_px = ZOOMS[zoom_idx]
	_sync_camera_and_lighting(true)
	_trigger_redraw()


func screen_to_world_tile(global_pos: Vector2) -> Vector2i:
	var local_p := global_pos - get_global_rect().position
	var wx := int(floor(_view_origin_world.x + local_p.x / float(tile_px)))
	var wy := int(floor(_view_origin_world.y + local_p.y / float(tile_px)))
	return Vector2i(wx, wy)


func get_view_center_tile() -> Vector2i:
	return _snapshot.get("center", Vector2i.ZERO)


func _on_resized() -> void:
	var w := maxi(64, int(size.x))
	var h := maxi(64, int(size.y))
	if _world_view != null and _world_view.size != Vector2i(w, h):
		_world_view.size = Vector2i(w, h)
		_tile_canvas.size = Vector2(w, h)
	if _lighting != null:
		_lighting.resize(Vector2i(w, h))
	_sync_camera_and_lighting(true)
	_trigger_redraw()


func update_world_snapshot(snap: Dictionary) -> void:
	_snapshot = snap
	_has_world = bool(snap.get("valid", false))
	visible = _has_world
	if not _has_world:
		return
	if _effects != null:
		_effects.sync_snapshot(snap)
	_sync_camera_and_lighting(true)
	_trigger_redraw()


func _trigger_redraw() -> void:
	if not _has_world or _world_view == null:
		return
	_tile_canvas.queue_redraw()
	_world_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _lighting != null:
		_lighting.trigger_mask_redraw()
	_overlay_layer.queue_redraw()


func _process(delta: float) -> void:
	if not _has_world or not visible:
		return
	var gliding := _effects != null and _effects.tick(delta)
	if gliding:
		if _lighting != null:
			_lighting.set_player_visual(
				_effects.get_player_visual(), _view_origin_world, size, tile_px,
				float(_snapshot.get("player_light", 0.0))
			)
		_trigger_redraw()
	elif _has_animated_tiles:
		_anim_redraw_accum += delta
		if _anim_redraw_accum >= 0.05: # 20fps tile animation (fire, water, glowing terminals)
			_anim_redraw_accum = 0.0
			_tile_canvas.queue_redraw()
			_world_view.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Zero-waste idle: only redraw overlay layer when routes, cursor, glide, SCT, or pulsing sound ripples are active!
	if _overlay_layer != null and _effects != null and _effects.needs_continuous_redraw():
		_overlay_layer.queue_redraw()

	if _lighting != null:
		_lighting.tick(delta)
	Tiles.finish_frame()


func _preresolve_snapshot_strings() -> void:
	var strings: PackedStringArray = _snapshot.get("strings", PackedStringArray())
	var s_len := strings.size()
	var season_names := ["spring", "summer", "autumn", "winter"]
	_resolved_season = season_names[clampi(int(_snapshot.get("season", 0)), 0, 3)]
	_resolved_entries.resize(s_len)
	_resolved_tall.resize(s_len)
	for i in range(s_len):
		var sid := strings[i]
		if sid.is_empty():
			_resolved_entries[i] = {}
			_resolved_tall[i] = 0
			continue
		var rid := Tiles.resolve_tile_id(sid, _resolved_season, true)
		var entry := Tiles.get_tile_entry(rid)
		_resolved_entries[i] = entry
		_resolved_tall[i] = 1 if bool(entry.get("tall", false)) else 0


func _sync_camera_and_lighting(rebuild_lighting: bool) -> void:
	if not _has_world:
		return
	var center: Vector2i = _snapshot.get("center", Vector2i.ZERO)
	_view_span_tiles = Vector2(maxf(1.0, size.x / float(tile_px)), maxf(1.0, size.y / float(tile_px)))
	_view_origin_world = Vector2(center) + Vector2(0.5, 0.5) - _view_span_tiles * 0.5

	if rebuild_lighting and _lighting != null:
		_preresolve_snapshot_strings()
		_lighting.update_from_snapshot(
			_snapshot, _view_origin_world, _view_span_tiles, size, tile_px
		)
		if _effects != null:
			_lighting.set_player_visual(
				_effects.get_player_visual(), _view_origin_world, size, tile_px,
				float(_snapshot.get("player_light", 0.0))
			)
		var wp := _lighting.get_weather_state()
		if _weather_fx != null:
			var rmask: PackedByteArray = _snapshot.get("rain_mask", PackedByteArray())
			var gorig: Vector2i = _snapshot.get("origin", Vector2i.ZERO)
			var gsz: Vector2i = _snapshot.get("size", Vector2i.ZERO)
			var msig := int(_snapshot.get("world_light_hash", 0)) ^ (gorig.x * 31) ^ (gorig.y * 131) ^ int(_snapshot.get("turn", 0))
			_weather_fx.configure_mask_bytes(
				wp.rain, wp.snow, _lighting.get_daylight(),
				_view_origin_world, _view_span_tiles, size, gorig, gsz, rmask, msig
			)
	elif _lighting != null:
		_lighting.sync_view(_view_origin_world, _view_span_tiles, size, tile_px)
		if _weather_fx != null and _weather_fx.visible:
			_weather_fx.set_view(_view_origin_world, _view_span_tiles, size)


static func _encode_surface_id(local_tx: int, local_ty: int, is_char: bool) -> Color:
	var ix := local_tx + 2
	var iy := local_ty + 2
	var high := ((ix >> 8) & 7) + (((iy >> 8) & 7) << 4) + (128 if is_char else 0)
	return Color(float(ix & 255) / 255.0, float(iy & 255) / 255.0, float(high) / 255.0, 1.0)


func _draw_sprite_ccb(canvas: Control, id: String, origin_px: Vector2, tpx: float, roll: int,
		subtile := -1, rota := 0, season := "", tint := Color.WHITE,
		layer_mode := Tiles.LAYER_BOTH, male := true) -> bool:
	if id.is_empty():
		return false
	return Tiles.draw_at_subtile(canvas, id, origin_px, tpx, roll, subtile, rota, tint, Vector2.ZERO, false, season, layer_mode, male)


# True 2.5D Y-sorted painter's order so tall 64x80 trees/shrubs/walls are NEVER clipped by neighboring grass!
func _draw_tiles_subviewport() -> void:
	_tile_canvas.draw_rect(Rect2(Vector2.ZERO, _tile_canvas.size), Color.BLACK)
	if not _has_world:
		return

	var origin: Vector2i = _snapshot.get("origin", Vector2i.ZERO)
	var grid_sz: Vector2i = _snapshot.get("size", Vector2i.ZERO)
	var tiles_bytes: PackedByteArray = _snapshot.get("tiles", PackedByteArray())
	var stride: int = int(_snapshot.get("tile_stride", 48))
	var strings: PackedStringArray = _snapshot.get("strings", PackedStringArray())
	if grid_sz.x <= 0 or grid_sz.y <= 0 or tiles_bytes.size() < grid_sz.x * grid_sz.y * stride:
		return

	var s_len := _resolved_entries.size()
	if s_len == 0:
		_preresolve_snapshot_strings()
		s_len = _resolved_entries.size()
	var season_key := _resolved_season
	var tpx := float(tile_px)

	var min_tx := clampi(int(floor(_view_origin_world.x)) - origin.x - 2, 0, grid_sz.x - 1)
	var min_ty := clampi(int(floor(_view_origin_world.y)) - origin.y - 2, 0, grid_sz.y - 1)
	var max_tx := clampi(int(ceil(_view_origin_world.x + _view_span_tiles.x)) - origin.x + 2, 0, grid_sz.x - 1)
	var max_ty := clampi(int(ceil(_view_origin_world.y + _view_span_tiles.y)) - origin.y + 3, 0, grid_sz.y - 1)

	# Bucket creatures by rounded visual tile row for exact Y-sorted interleaving while gliding
	var creatures_by_row := {}
	var creatures: Array = _snapshot.get("creatures", [])
	for c_var in creatures:
		var cd: Dictionary = c_var
		var uid := int(cd.get("uid", 0))
		var raw_pos := Vector2(float(cd.get("x", 0)), float(cd.get("y", 0)))
		var vpos := _effects.get_creature_visual(uid, raw_pos) if _effects != null else raw_pos
		var cy := int(round(vpos.y)) - origin.y
		if not creatures_by_row.has(cy):
			creatures_by_row[cy] = []
		creatures_by_row[cy].append([cd, vpos])

	var worn: PackedStringArray = _snapshot.get("worn", PackedStringArray())
	var wielded: String = str(_snapshot.get("wielded", ""))
	Tiles.consume_animated_flag()

	# PASS 1: Flat ground terrain & tall-terrain ground `bg` patches (O(1) pre-resolved array lookup!)
	for ty in range(min_ty, max_ty + 1):
		var wy := origin.y + ty
		var sy := (float(wy) - _view_origin_world.y) * tpx
		var row_idx := ty * grid_sz.x
		for tx in range(min_tx, max_tx + 1):
			var off := (row_idx + tx) * stride
			if tiles_bytes.decode_u8(off + 16) == 0:
				continue
			var ter_i := tiles_bytes.decode_u16(off + 0)
			if ter_i <= 0 or ter_i >= s_len:
				continue
			var wx := origin.x + tx
			var pos_px := Vector2((float(wx) - _view_origin_world.x) * tpx, sy)
			var hash_v := wx * 73856093 ^ wy * 19349663
			var ter_sub := tiles_bytes.decode_u8(off + 18)
			var ter_rot := tiles_bytes.decode_u8(off + 19)
			var sub_arg := -1 if ter_sub >= 8 else int(ter_sub)
			var lmode := Tiles.LAYER_BG_ONLY if _resolved_tall[ter_i] != 0 else Tiles.LAYER_BOTH
			if not Tiles.draw_resolved_tile(_tile_canvas, _resolved_entries[ter_i], pos_px, tpx, hash_v, sub_arg, ter_rot, Color.WHITE, Vector2.ZERO, false, lmode):
				_tile_canvas.draw_rect(Rect2(pos_px, Vector2(tpx, tpx)), Color(0.11, 0.13, 0.11))

	# PASS 2: Y-sorted foreground row-by-row (O(1) pre-resolved array lookup + vehicle open/broken subtile support!)
	for ty in range(min_ty, max_ty + 1):
		var wy := origin.y + ty
		var sy := (float(wy) - _view_origin_world.y) * tpx
		var row_idx := ty * grid_sz.x
		for tx in range(min_tx, max_tx + 1):
			var off := (row_idx + tx) * stride
			if tiles_bytes.decode_u8(off + 16) == 0:
				continue
			var wx := origin.x + tx
			var sx := (float(wx) - _view_origin_world.x) * tpx
			var pos_px := Vector2(sx, sy)
			var rect := Rect2(sx, sy, tpx, tpx)
			var hash_v := wx * 73856093 ^ wy * 19349663

			var ter_i := tiles_bytes.decode_u16(off + 0)
			var furn_i := tiles_bytes.decode_u16(off + 2)
			var trap_i := tiles_bytes.decode_u16(off + 4)
			var vpart_i := tiles_bytes.decode_u16(off + 6)
			var field_i := tiles_bytes.decode_u16(off + 8)
			var item_i := tiles_bytes.decode_u16(off + 10)
			var corpse_i := tiles_bytes.decode_u16(off + 12)
			var item_cnt := tiles_bytes.decode_u16(off + 14)

			if ter_i > 0 and ter_i < s_len and _resolved_tall[ter_i] != 0:
				var ter_sub := tiles_bytes.decode_u8(off + 18)
				var ter_rot := tiles_bytes.decode_u8(off + 19)
				var sub_arg := -1 if ter_sub >= 8 else int(ter_sub)
				Tiles.draw_resolved_tile(_tile_canvas, _resolved_entries[ter_i], pos_px, tpx, hash_v, sub_arg, ter_rot, Color.WHITE, Vector2.ZERO, false, Tiles.LAYER_FG_ONLY)

			if furn_i > 0 and furn_i < s_len:
				var furn_sub := tiles_bytes.decode_u8(off + 20)
				var furn_rot := tiles_bytes.decode_u8(off + 21)
				var fsub_arg := -1 if furn_sub >= 8 else int(furn_sub)
				Tiles.draw_resolved_tile(_tile_canvas, _resolved_entries[furn_i], pos_px, tpx, hash_v, fsub_arg, furn_rot)

			if trap_i > 0 and trap_i < s_len:
				Tiles.draw_resolved_tile(_tile_canvas, _resolved_entries[trap_i], pos_px, tpx, hash_v)

			if vpart_i > 0 and vpart_i < s_len:
				var vp_packed := tiles_bytes.decode_u8(off + 22)
				var vrot := vp_packed & 3
				var vsub_raw := (vp_packed >> 4) & 0xF
				var vsub := -1 if vsub_raw == 0 else vsub_raw
				Tiles.draw_resolved_tile(_tile_canvas, _resolved_entries[vpart_i], pos_px, tpx, hash_v, vsub, vrot)

			if corpse_i > 0 and corpse_i < s_len:
				if not Tiles.draw_resolved_tile(_tile_canvas, _resolved_entries[corpse_i], pos_px, tpx, hash_v):
					_draw_sprite_ccb(_tile_canvas, "corpse", pos_px, tpx, hash_v, -1, 0, season_key)
			elif item_i > 0 and item_i < s_len:
				Tiles.draw_resolved_tile(_tile_canvas, _resolved_entries[item_i], pos_px, tpx, hash_v)
			if item_cnt > 1:
				_tile_canvas.draw_rect(Rect2(sx + tpx - 5.0, sy + tpx - 5.0, 4.0, 4.0), Color(0.95, 0.85, 0.25, 0.85))

			if field_i > 0 and field_i < s_len:
				if not Tiles.draw_resolved_tile(_tile_canvas, _resolved_entries[field_i], pos_px, tpx, hash_v):
					var fld_id := strings[field_i]
					if "fire" in fld_id:
						_tile_canvas.draw_rect(rect.grow(-4.0), Color(1.0, 0.45, 0.08, 0.65))
					elif "blood" in fld_id:
						_tile_canvas.draw_rect(rect.grow(-6.0), Color(0.55, 0.05, 0.05, 0.55))
					elif "smoke" in fld_id:
						_tile_canvas.draw_rect(rect, Color(0.45, 0.48, 0.52, 0.45))

		# Creatures standing on row `ty` (rendered at smooth 60fps interpolated visual coordinates!)
		if creatures_by_row.has(ty):
			for pair: Array in creatures_by_row[ty]:
				var cd: Dictionary = pair[0]
				var vpos: Vector2 = pair[1]
				var sx := (vpos.x - _view_origin_world.x) * tpx
				var sy_c := (vpos.y - _view_origin_world.y) * tpx
				if sx < -tpx or sx > _tile_canvas.size.x + tpx:
					continue
				var pos_px := Vector2(sx, sy_c)
				var sprite_id := str(cd.get("sprite", ""))
				var cflags := int(cd.get("flags", 0))
				var is_male := (cflags & CRITTER_MALE) != 0
				var hval := int(cd.get("x", 0)) * 31 + int(cd.get("y", 0)) * 17
				if not _draw_sprite_ccb(_tile_canvas, sprite_id, pos_px, tpx, hval, -1, 0, season_key, Color.WHITE, Tiles.LAYER_BOTH, is_male):
					var col := Color(0.95, 0.25, 0.25) if (cflags & CRITTER_HOSTILE) != 0 else Color(0.3, 0.9, 0.5)
					_tile_canvas.draw_rect(Rect2(pos_px, Vector2(tpx, tpx)).grow(-4.0), col)
				if (cflags & CRITTER_PLAYER) != 0:
					for wid_item in worn:
						_draw_sprite_ccb(_tile_canvas, "overlay_worn_" + wid_item, pos_px, tpx, 0, -1, 0, season_key, Color.WHITE, Tiles.LAYER_BOTH, is_male)
					if not wielded.is_empty():
						_draw_sprite_ccb(_tile_canvas, "overlay_wielded_" + wielded, pos_px, tpx, 0, -1, 0, season_key, Color.WHITE, Tiles.LAYER_BOTH, is_male)
				elif (cflags & CRITTER_NPC) != 0:
					var npc_worn: PackedStringArray = cd.get("worn", PackedStringArray())
					for nwid in npc_worn:
						_draw_sprite_ccb(_tile_canvas, "overlay_worn_" + nwid, pos_px, tpx, 0, -1, 0, season_key, Color.WHITE, Tiles.LAYER_BOTH, is_male)
					var nwield := str(cd.get("wielded", ""))
					if not nwield.is_empty():
						_draw_sprite_ccb(_tile_canvas, "overlay_wielded_" + nwield, pos_px, tpx, 0, -1, 0, season_key, Color.WHITE, Tiles.LAYER_BOTH, is_male)

	_has_animated_tiles = Tiles.consume_animated_flag()


# Encodes standing 3D objects into cangling-city's surface_mask SubViewport
func _draw_surface_mask() -> void:
	if not _has_world or _lighting == null:
		return
	var mc := _lighting.mask_canvas
	var origin: Vector2i = _snapshot.get("origin", Vector2i.ZERO)
	var grid_sz: Vector2i = _snapshot.get("size", Vector2i.ZERO)
	var tiles_bytes: PackedByteArray = _snapshot.get("tiles", PackedByteArray())
	var stride: int = int(_snapshot.get("tile_stride", 48))
	var s_len := _resolved_entries.size()
	if grid_sz.x <= 0 or grid_sz.y <= 0 or tiles_bytes.size() < grid_sz.x * grid_sz.y * stride or s_len == 0:
		return

	var season_key := _resolved_season
	var tpx := float(tile_px)

	var min_tx := clampi(int(floor(_view_origin_world.x)) - origin.x - 2, 0, grid_sz.x - 1)
	var min_ty := clampi(int(floor(_view_origin_world.y)) - origin.y - 2, 0, grid_sz.y - 1)
	var max_tx := clampi(int(ceil(_view_origin_world.x + _view_span_tiles.x)) - origin.x + 2, 0, grid_sz.x - 1)
	var max_ty := clampi(int(ceil(_view_origin_world.y + _view_span_tiles.y)) - origin.y + 3, 0, grid_sz.y - 1)

	for ty in range(min_ty, max_ty + 1):
		var wy := origin.y + ty
		var sy := (float(wy) - _view_origin_world.y) * tpx
		var row_idx := ty * grid_sz.x
		for tx in range(min_tx, max_tx + 1):
			var off := (row_idx + tx) * stride
			if tiles_bytes.decode_u8(off + 16) == 0:
				continue
			var lkind := tiles_bytes.decode_u8(off + 26)
			if lkind == 0:
				continue
			var wx := origin.x + tx
			var pos_px := Vector2((float(wx) - _view_origin_world.x) * tpx, sy)
			var hash_v := wx * 73856093 ^ wy * 19349663
			var sid := _encode_surface_id(tx, ty, false)

			var ter_i := tiles_bytes.decode_u16(off + 0)
			var furn_i := tiles_bytes.decode_u16(off + 2)
			var vpart_i := tiles_bytes.decode_u16(off + 6)

			if lkind >= 1 and lkind <= 6 and ter_i > 0 and ter_i < s_len:
				var ter_sub := tiles_bytes.decode_u8(off + 18)
				var ter_rot := tiles_bytes.decode_u8(off + 19)
				var sub_arg := -1 if ter_sub >= 8 else int(ter_sub)
				var lmode := Tiles.LAYER_FG_ONLY if _resolved_tall[ter_i] != 0 else Tiles.LAYER_BOTH
				Tiles.draw_resolved_tile(mc, _resolved_entries[ter_i], pos_px, tpx, hash_v, sub_arg, ter_rot, sid, Vector2.ZERO, false, lmode)
			if furn_i > 0 and furn_i < s_len and lkind >= 6:
				var furn_sub := tiles_bytes.decode_u8(off + 20)
				var furn_rot := tiles_bytes.decode_u8(off + 21)
				var fsub_arg := -1 if furn_sub >= 8 else int(furn_sub)
				Tiles.draw_resolved_tile(mc, _resolved_entries[furn_i], pos_px, tpx, hash_v, fsub_arg, furn_rot, sid)
			if vpart_i > 0 and vpart_i < s_len:
				var vp_packed := tiles_bytes.decode_u8(off + 22)
				var vrot := vp_packed & 3
				var vsub_raw := (vp_packed >> 4) & 0xF
				var vsub := -1 if vsub_raw == 0 else vsub_raw
				Tiles.draw_resolved_tile(mc, _resolved_entries[vpart_i], pos_px, tpx, hash_v, vsub, vrot, sid)

	# Stamp all creatures at their smooth visual positions with character bit 128
	var creatures: Array = _snapshot.get("creatures", [])
	for c_var in creatures:
		var cd: Dictionary = c_var
		var uid := int(cd.get("uid", 0))
		var raw_pos := Vector2(float(cd.get("x", 0)), float(cd.get("y", 0)))
		var vpos := _effects.get_creature_visual(uid, raw_pos) if _effects != null else raw_pos
		var tx := clampi(int(round(vpos.x)) - origin.x, 0, grid_sz.x - 1)
		var ty := clampi(int(round(vpos.y)) - origin.y, 0, grid_sz.y - 1)
		var pos_px := Vector2((vpos.x - _view_origin_world.x) * tpx, (vpos.y - _view_origin_world.y) * tpx)
		var sid := _encode_surface_id(tx, ty, true)
		var cflags := int(cd.get("flags", 0))
		var is_male := (cflags & CRITTER_MALE) != 0
		_draw_sprite_ccb(mc, str(cd.get("sprite", "")), pos_px, tpx, int(raw_pos.x) * 31 + int(raw_pos.y) * 17, -1, 0, season_key, sid, Tiles.LAYER_BOTH, is_male)


func _draw_world_overlays() -> void:
	if not _has_world or _effects == null:
		return
	_effects.draw_overlays(_overlay_layer, _snapshot, _view_origin_world, float(tile_px), _ui_font)
