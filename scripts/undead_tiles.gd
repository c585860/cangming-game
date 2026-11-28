extends RefCounted

const ROOT := "res://art/undead_people/"
const PAGE_HEIGHT := 1024
const JOINS := [
	["unconnected", 0], ["end_piece", 0], ["end_piece", 3], ["corner", 0],
	["end_piece", 1], ["corner", 1], ["edge", 1], ["t_connection", 0],
	["end_piece", 2], ["edge", 0], ["corner", 3], ["t_connection", 3],
	["corner", 2], ["t_connection", 1], ["t_connection", 2], ["center", 0],
]
# Exact CCB tile_lookup_frame::subtile_keys order (src/tile_lookup.cpp)
const SUBTILE_KEYS := [
	"center", "corner", "edge", "t_connection", "end_piece", "unconnected", "open", "broken",
]
const LAYER_BOTH := 0
const LAYER_BG_ONLY := 1
const LAYER_FG_ONLY := 2

static var _base_size := Vector2i(32, 32)
static var _active_root := ROOT
static var _active_json_file := "tile_config.json"
static var _active_tileset_name := "builtin_undead_people"
static var _preferred_ccb_tileset := "MSX++UndeadPeopleEdition"
static var _tiles: Dictionary = {}
static var _sheets: Array[Dictionary] = []
static var _sprites: Dictionary = {}
static var _decoded: Dictionary = {}
static var _decoded_stamps: Dictionary = {}
static var _page_stamps: Dictionary = {}
static var _pinned_pages: Dictionary = {}
static var _looks_like: Dictionary = {}
static var _resolved_cache: Dictionary = {}
static var _tall_cache: Dictionary = {}
static var _sprite_3d_cache: Dictionary = {}
static var _fallback_white_tex: ImageTexture = null
static var _frame_id := 0
static var _attempted := false
static var _prewarmed := false
static var _used_animated_this_frame := false

const MAX_DECODED_ATLASES := 2
const DECODED_TTL_MS := 2500
const DEFAULT_MAX_RESIDENT_PAGES := 72
const DEFAULT_PAGE_MAX_AGE_MS := 120000


static func consume_animated_flag() -> bool:
	var v := _used_animated_this_frame
	_used_animated_this_frame = false
	return v


static func ccb_gfx_dir() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir().simplify_path()
	var rel_gfx1 := exe_dir.path_join("ccb_data/gfx").simplify_path()
	if DirAccess.dir_exists_absolute(rel_gfx1):
		return rel_gfx1
	var rel_gfx2 := exe_dir.path_join("../ccb_data/gfx").simplify_path()
	if DirAccess.dir_exists_absolute(rel_gfx2):
		return rel_gfx2
	var proj := ProjectSettings.globalize_path("res://").simplify_path()
	var local_gfx := proj.path_join("Cataclysm-Cleanwater-Bomb/gfx").simplify_path()
	if DirAccess.dir_exists_absolute(local_gfx):
		return local_gfx
	var sibling := proj.path_join("../Cataclysm-Cleanwater-Bomb/gfx").simplify_path()
	if DirAccess.dir_exists_absolute(sibling):
		return sibling
	return ""


static func list_available_tilesets() -> Array[String]:
	var out: Array[String] = []
	var gfx := ccb_gfx_dir()
	if not gfx.is_empty():
		var d := DirAccess.open(gfx)
		if d != null:
			d.list_dir_begin()
			var nm := d.get_next()
			while not nm.is_empty():
				if d.current_is_dir() and not nm.begins_with("."):
					var cfg := gfx.path_join(nm).path_join("tile_config.json")
					if FileAccess.file_exists(cfg):
						out.append(nm)
				nm = d.get_next()
			d.list_dir_end()
	out.sort()
	var idx := out.find("MSX++UndeadPeopleEdition")
	if idx > 0:
		out.remove_at(idx)
		out.insert(0, "MSX++UndeadPeopleEdition")
	if out.is_empty():
		out.append("builtin_undead_people")
	return out


static func get_active_tileset_name() -> String:
	return _active_tileset_name


static func get_preferred_ccb_tileset() -> String:
	return _preferred_ccb_tileset


static func list_vanilla_tilesets() -> Array[String]:
	return list_available_tilesets()


static func current_tileset_name() -> String:
	return _preferred_ccb_tileset if _active_tileset_name == "builtin_undead_people" else _active_tileset_name


static func set_tileset_name(name: String) -> bool:
	return set_preferred_ccb_tileset(name)


static func set_preferred_ccb_tileset(name: String) -> bool:
	_preferred_ccb_tileset = name
	if _active_tileset_name != "builtin_undead_people":
		return set_active_tileset(name)
	return true


static func set_looks_like_map(looks_like: Dictionary) -> void:
	_looks_like = looks_like
	_resolved_cache.clear()
	_tall_cache.clear()


static func _reset_catalog_caches() -> void:
	_tiles.clear()
	_sheets.clear()
	_sprites.clear()
	_decoded.clear()
	_decoded_stamps.clear()
	_page_stamps.clear()
	_pinned_pages.clear()
	_resolved_cache.clear()
	_tall_cache.clear()
	_sprite_3d_cache.clear()
	_attempted = false
	_prewarmed = false


# Directly loads ANY tileset folder discovered by CCB at runtime (gfx/ or user_gfx/),
# supporting custom JSON: filenames from tileset.txt with ZERO recompilation!
static func set_active_tileset_dir(dir_path: String, json_file := "tile_config.json", display_name := "") -> bool:
	var norm_dir := dir_path.replace("\\", "/").simplify_path()
	if not norm_dir.ends_with("/"):
		norm_dir += "/"
	var jfile := json_file if not json_file.is_empty() else "tile_config.json"
	if not FileAccess.file_exists(norm_dir + jfile):
		if FileAccess.file_exists(norm_dir + "tile_config.json"):
			jfile = "tile_config.json"
		else:
			return false
	var target_name := display_name if not display_name.is_empty() else norm_dir.trim_suffix("/").get_file()
	if norm_dir == _active_root and jfile == _active_json_file and _attempted:
		_active_tileset_name = target_name
		return true
	_active_root = norm_dir
	_active_json_file = jfile
	_active_tileset_name = target_name
	_preferred_ccb_tileset = target_name
	_reset_catalog_caches()
	_load_catalog()
	return not _tiles.is_empty()


static func set_active_tileset(name: String) -> bool:
	var target_root := ROOT
	var target_json := "tile_config.json"
	var target_name := "builtin_undead_people"
	if name != "builtin_undead_people":
		var gfx := ccb_gfx_dir()
		if not gfx.is_empty():
			var cand := gfx.path_join(name)
			if FileAccess.file_exists(cand.path_join("tile_config.json")):
				target_root = cand + "/"
				target_name = name
	if target_root == _active_root and target_json == _active_json_file and _attempted:
		return true
	_active_root = target_root
	_active_json_file = target_json
	_active_tileset_name = target_name
	_reset_catalog_caches()
	_load_catalog()
	return not _tiles.is_empty()


static func ensure_pack_tileset(is_cataclysm: bool) -> bool:
	if not is_cataclysm:
		if _active_tileset_name == "builtin_undead_people" and _attempted:
			return false
		set_active_tileset("builtin_undead_people")
		return true
	if _active_tileset_name != "builtin_undead_people" and _attempted:
		return false
	set_active_tileset(_preferred_ccb_tileset)
	return true


const GAME_TILE_IDS := [
	"t_grass", "t_grass_long", "t_stone_road", "t_dirt", "t_sand", "t_floor", "t_carpet_red",
	"t_rock_floor", "t_stone_masonry_floor", "t_dock", "t_water_moving_dp", "t_water_moving_sh", "t_pillar",
	"t_tree_willow", "t_tree_maple", "t_tree_pine", "t_shrub", "t_shrub_lilac", "t_shrub_blackberry",
	"f_cattails", "f_lilypad", "f_lotus",
	"player_male", "overlay_worn_straw_hat", "overlay_worn_bandana", "overlay_worn_tunic",
	"overlay_worn_pants", "overlay_worn_robe", "overlay_worn_cloak", "overlay_worn_coat_winter",
	"overlay_worn_boots", "overlay_worn_bastsandals", "overlay_worn_backpack", "overlay_worn_mbag",
	"sheet_cotton", "pillow", "blanket", "quilt", "straw_hat", "bandana", "tunic", "longshirt",
	"pants", "robe", "cloak", "coat_winter", "boots", "bastsandals", "backpack", "mbag",
	"flatbread", "bread", "deluxe_rice", "jerky", "apple", "pear", "cake2", "tea", "water_clean",
	"brew_fruit_wine", "tea_raw", "mayapple", "bottle_glass", "book_archery", "paper", "rope_6",
	"knife_butcher", "chopsticks", "bowl_clay", "pot", "teapot", "salt", "noodles_fast", "hatchet",
	"crowbar", "oil_lamp", "lighter", "2x4", "rag", "ceramic_shard", "bandages", "candle", "towel", "soap",
]


static func _load_catalog() -> void:
	_attempted = true
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(_active_root + _active_json_file))
	if not catalog is Dictionary or not catalog.has("tiles-new"):
		if _active_root != ROOT:
			_active_root = ROOT
			_active_json_file = "tile_config.json"
			_active_tileset_name = "builtin_undead_people"
			catalog = JSON.parse_string(FileAccess.get_file_as_string(_active_root + _active_json_file))
		if not catalog is Dictionary or not catalog.has("tiles-new"):
			push_error("Could not read tileset catalog from " + _active_root + _active_json_file)
			return
	var info: Dictionary = catalog["tile_info"][0]
	_base_size = Vector2i(int(info.get("width", 32)), int(info.get("height", 32)))
	var default_scale: float = float(info.get("pixelscale", 1.0))
	var first := 0
	for group: Dictionary in catalog["tiles-new"]:
		var file: String = _active_root + str(group.get("file", ""))
		var size := _png_size(file)
		var frame := Vector2i(
			int(group.get("sprite_width", _base_size.x)),
			int(group.get("sprite_height", _base_size.y))
		)
		if frame.x <= 0 or frame.y <= 0:
			continue
		@warning_ignore("integer_division")
		var cols := size.x / frame.x
		@warning_ignore("integer_division")
		var rows := size.y / frame.y
		if cols < 1 or rows < 1:
			continue
		_sheets.append({
			"file": file, "first": first, "end": first + cols * rows,
			"frame": frame, "cols": cols, "rows": rows, "pages": {},
		})
		first += cols * rows
		var offset := Vector2i(
			int(group.get("sprite_offset_x", 0)),
			int(group.get("sprite_offset_y", 0))
		)
		var scale: float = float(group.get("pixelscale", default_scale))
		var is_tall := (frame.x > _base_size.x or frame.y > _base_size.y or offset.x != 0 or offset.y != 0)
		for entry: Dictionary in group.get("tiles", []):
			if not entry.has("id"):
				continue
			var ids: Array = entry["id"] if entry["id"] is Array else [entry["id"]]
			var multitile: bool = bool(entry.get("multitile", false))
			var fg_v: Variant = entry.get("fg", [])
			var bg_v: Variant = entry.get("bg", [])
			var fg_rot: bool = (fg_v is Array and (fg_v as Array).size() > 1 and not ((fg_v as Array)[0] is Dictionary))
			var bg_rot: bool = (bg_v is Array and (bg_v as Array).size() > 1 and not ((bg_v as Array)[0] is Dictionary))
			var def_rot: bool = bool(entry.get("rotates", multitile or fg_rot or bg_rot))
			var tile := _definition(entry, offset, scale, def_rot, is_tall)
			var subtiles := {}
			if multitile:
				for part: Dictionary in entry.get("additional_tiles", []):
					subtiles[part["id"]] = _definition(part, offset, scale, true, is_tall)
			tile["joins"] = subtiles
			# Match CCB tileset_loader.cpp: later definitions override earlier ones cleanly.
			for id_v in ids:
				var id := str(id_v)
				_tiles[id] = tile
				for part: String in subtiles:
					_tiles[id + "_" + part] = subtiles[part]


static func _png_size(path: String) -> Vector2i:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 24:
		return Vector2i.ZERO
	file.big_endian = true
	if file.get_32() != 0x89504e47 or file.get_32() != 0x0d0a1a0a:
		return Vector2i.ZERO
	file.seek(16)
	return Vector2i(file.get_32(), file.get_32())


static func _definition(entry: Dictionary, offset: Vector2i, scale: float, rotates: bool, is_tall: bool) -> Dictionary:
	return {
		"fg": entry.get("fg", []),
		"bg": entry.get("bg", []),
		"offset": offset,
		"scale": scale,
		"rotates": rotates,
		"tall": is_tall,
		"animated": bool(entry.get("animated", false)),
	}


static func _page(sheet_idx: int, sheet: Dictionary, page: int, rows_per_page: int) -> Texture2D:
	var pages: Dictionary = sheet["pages"]
	var stamp_key := (sheet_idx << 16) | (page & 0xffff)
	var now_ms := Time.get_ticks_msec()
	_page_stamps[stamp_key] = now_ms
	if pages.has(page):
		return pages[page]
	var file: String = sheet["file"]
	if not _decoded.has(file):
		# Keep at most MAX_DECODED_ATLASES raw PNGs resident simultaneously to prevent RAM spikes
		while _decoded.size() >= MAX_DECODED_ATLASES:
			var oldest_f := ""
			var oldest_t := 1 << 62
			for df: String in _decoded:
				var dt: int = int(_decoded_stamps.get(df, 0))
				if dt < oldest_t:
					oldest_t = dt
					oldest_f = df
			if oldest_f.is_empty():
				break
			_decoded.erase(oldest_f)
			_decoded_stamps.erase(oldest_f)
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(file)) != OK:
			push_error("Could not decode tileset atlas: " + file)
			_decoded[file] = null
		else:
			_decoded[file] = image
	_decoded_stamps[file] = now_ms
	var source: Image = _decoded[file]
	if source == null:
		return null
	var frame: Vector2i = sheet["frame"]
	var row := page * rows_per_page
	var rows := mini(rows_per_page, int(sheet["rows"]) - row)
	var region := Rect2i(0, row * frame.y, int(sheet["cols"]) * frame.x, rows * frame.y)
	var texture := ImageTexture.create_from_image(source.get_region(region))
	pages[page] = texture
	return texture


static func clear_decoded_cache() -> void:
	_decoded.clear()
	_decoded_stamps.clear()


static func finish_frame() -> void:
	if not _decoded.is_empty():
		var now_ms := Time.get_ticks_msec()
		var expired: Array[String] = []
		for df: String in _decoded:
			if now_ms - int(_decoded_stamps.get(df, 0)) >= DECODED_TTL_MS:
				expired.append(df)
		for df in expired:
			_decoded.erase(df)
			_decoded_stamps.erase(df)
	_frame_id += 1


static func _collect_layer_indices(value: Variant, out: Array[int]) -> void:
	if value is int:
		if value >= 0:
			out.append(value)
	elif value is Array:
		for item in value:
			if item is Dictionary and item.has("sprite"):
				_collect_layer_indices(item["sprite"], out)
			else:
				_collect_layer_indices(item, out)


static func prewarm_game_sprites() -> void:
	if _prewarmed:
		return
	_prewarmed = true
	if not _attempted:
		_load_catalog()
	var indices: Array[int] = []
	const SEASONS := ["", "spring", "summer", "autumn", "winter"]
	for base_id: String in GAME_TILE_IDS:
		for s: String in SEASONS:
			var resolved := base_id if s.is_empty() else (base_id + "_season_" + s)
			if not _tiles.has(resolved):
				continue
			var tile: Dictionary = _tiles[resolved]
			_collect_layer_indices(tile["bg"], indices)
			_collect_layer_indices(tile["fg"], indices)
			if tile.has("joins"):
				for sub: Dictionary in tile["joins"].values():
					_collect_layer_indices(sub["bg"], indices)
					_collect_layer_indices(sub["fg"], indices)
	for idx in indices:
		_sprite(idx)
	for key in _page_stamps:
		_pinned_pages[key] = true
	_decoded.clear()
	_decoded_stamps.clear()


static func trim_unused_pages(max_age_ms := DEFAULT_PAGE_MAX_AGE_MS, max_pages := DEFAULT_MAX_RESIDENT_PAGES) -> int:
	var now_ms := Time.get_ticks_msec()
	var freed := 0
	var total_pages := 0
	var unpinned_live: Array = [] # [last_used_ms, sheet_idx, page_num]

	for s_idx in range(_sheets.size()):
		var pages: Dictionary = _sheets[s_idx]["pages"]
		var stale: Array[int] = []
		for page_num: int in pages:
			var stamp_key := (s_idx << 16) | (page_num & 0xffff)
			if _pinned_pages.has(stamp_key):
				total_pages += 1
				continue
			var last_used: int = int(_page_stamps.get(stamp_key, 0))
			if max_age_ms > 0 and (now_ms - last_used >= max_age_ms):
				stale.append(page_num)
			else:
				total_pages += 1
				unpinned_live.append([last_used, s_idx, page_num])
		for page_num in stale:
			pages.erase(page_num)
			_page_stamps.erase((s_idx << 16) | (page_num & 0xffff))
			freed += 1

	# Enforce hard resident LRU page budget so long exploration sessions never bloat VRAM/RAM!
	if max_pages > 0 and total_pages > max_pages and not unpinned_live.is_empty():
		unpinned_live.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
		var to_drop := mini(unpinned_live.size(), total_pages - max_pages)
		for i in range(to_drop):
			var rec: Array = unpinned_live[i]
			var s_idx := int(rec[1])
			var p_num := int(rec[2])
			(_sheets[s_idx]["pages"] as Dictionary).erase(p_num)
			_page_stamps.erase((s_idx << 16) | (p_num & 0xffff))
			freed += 1

	if freed > 0:
		_sprites.clear()
		_sprite_3d_cache.clear()
	if _resolved_cache.size() > 8192:
		_resolved_cache.clear()
	if _tall_cache.size() > 8192:
		_tall_cache.clear()
	return freed


static func get_cache_stats() -> Dictionary:
	var pages_cnt := 0
	for s in _sheets:
		pages_cnt += (s["pages"] as Dictionary).size()
	return {
		"pages": pages_cnt,
		"decoded": _decoded.size(),
		"sprites": _sprites.size(),
		"sprites_3d": _sprite_3d_cache.size(),
		"resolved": _resolved_cache.size(),
		"tiles": _tiles.size(),
	}


static func has_tile(id: String) -> bool:
	if not _attempted:
		_load_catalog()
	return _tiles.has(id)


static func resolve_seasonal(id: String, season: String) -> String:
	if not _attempted:
		_load_catalog()
	if not season.is_empty():
		var variant := id + "_season_" + season
		if _tiles.has(variant):
			return variant
	return id


static func _try_with_season(key: String, season: String) -> String:
	if not season.is_empty():
		var sv := key + "_season_" + season
		if _tiles.has(sv):
			return sv
	if _tiles.has(key):
		return key
	return ""


static func _resolve_vpart_with_variant(base_id: String, variant: String, season: String) -> String:
	# Exact CCB tile_lookup_frame::resolve parity for TILE_CATEGORY::VEHICLE_PART:
	# 1. Try cur + "_" + variant_chunk (progressively stripping '_' from variant tail, e.g. horizontal_front -> horizontal)
	#    plus cur + "#" + variant_chunk (for tilesets using '#' variant ids)
	# 2. Try cur (without variant)
	# 3. Follow looks_like chain PRESERVING variant (trying both vp_<ll> and raw <ll> for furniture fallbacks!)
	var cur := base_id
	for _hop in range(10):
		if cur.is_empty():
			break
		if not variant.is_empty():
			var vchunk := variant
			while not vchunk.is_empty():
				var hit := _try_with_season(cur + "_" + vchunk, season)
				if not hit.is_empty():
					return hit
				hit = _try_with_season(cur + "#" + vchunk, season)
				if not hit.is_empty():
					return hit
				var us := vchunk.rfind("_")
				vchunk = vchunk.substr(0, us) if us > 0 else ""
		var direct := _try_with_season(cur, season)
		if not direct.is_empty():
			return direct
		# Also try raw id without "vp_" prefix if it's a furniture fallback (e.g. f_oven, f_fridge)
		if cur.begins_with("vp_"):
			var raw_no_vp := cur.substr(3)
			var fhit := _try_with_season(raw_no_vp, season)
			if not fhit.is_empty():
				return fhit
		var nxt := str(_looks_like.get(cur, ""))
		if nxt.is_empty() and cur.begins_with("vp_"):
			nxt = str(_looks_like.get(cur.substr(3), ""))
		if nxt.is_empty() or nxt == cur:
			break
		cur = nxt

	# Progressive tail-stripping fallback on base_id (e.g. vp_wheel_wide_or_steerable -> vp_wheel_wide)
	if base_id.begins_with("vp_"):
		var chunk := base_id
		while true:
			var u := chunk.rfind("_")
			if u <= 2:
				break
			chunk = chunk.substr(0, u)
			if not variant.is_empty():
				var vhit := _try_with_season(chunk + "_" + variant, season)
				if not vhit.is_empty():
					return vhit
			var bhit := _try_with_season(chunk, season)
			if not bhit.is_empty():
				return bhit
		var unk := _try_with_season("vp_unknown_vehicle_part", season)
		if not unk.is_empty():
			return unk
	return ""


# Authentic CCB multi-hop lookup: seasonal suffix -> direct id -> overlay gender & looks_like
# -> vehicle part #variant + looks_like chain -> 10-hop looks_like chain -> monster tail-strip!
static func resolve_tile_id(id: String, season := "", male := true) -> String:
	if id.is_empty():
		return ""
	if not _attempted:
		_load_catalog()
	var cache_key := id + "|" + season + ("|m" if male else "|f")
	if _resolved_cache.has(cache_key):
		return str(_resolved_cache[cache_key])

	var found := ""
	# 1. Vehicle parts: split CCB's '#' variant separator (e.g. "vp_frame#cover", "vp_quarterpanel#ne")
	if id.begins_with("vp_"):
		var sep := id.find("#")
		var vp_base := id.substr(0, sep) if sep > 0 else id
		var vp_var := id.substr(sep + 1) if sep > 0 else ""
		found = _resolve_vpart_with_variant(vp_base, vp_var, season)
	# 2. Overlay paperdoll lookup (matches cata_tiles::find_overlay_looks_like)
	elif id.begins_with("overlay_worn_") or id.begins_with("overlay_wielded_"):
		var over_type := "worn_" if id.begins_with("overlay_worn_") else "wielded_"
		var item_id := id.substr(8 + over_type.length())
		var gprefix := "overlay_male_" if male else "overlay_female_"
		var cur := item_id
		for _hop in range(10):
			if cur.is_empty():
				break
			found = _try_with_season(gprefix + over_type + cur, season)
			if not found.is_empty():
				break
			found = _try_with_season("overlay_" + over_type + cur, season)
			if not found.is_empty():
				break
			cur = str(_looks_like.get(cur, ""))
	else:
		var cur := id
		for _hop in range(10):
			if cur.is_empty():
				break
			found = _try_with_season(cur, season)
			if not found.is_empty():
				break
			var nxt := str(_looks_like.get(cur, ""))
			if nxt == cur:
				break
			cur = nxt
		# Mod/variant monster tail-stripping fallback (e.g. mon_zombie_custom_var -> mon_zombie)
		if found.is_empty() and id.begins_with("mon_"):
			var mchunk := id
			while true:
				var u := mchunk.rfind("_")
				if u <= 3:
					break
				mchunk = mchunk.substr(0, u)
				found = _try_with_season(mchunk, season)
				if not found.is_empty():
					break

	_resolved_cache[cache_key] = found
	return found


static func resolve_field_tile_id(id: String, intensity: int, season := "") -> String:
	if id.is_empty():
		return ""
	var clamped_i := clampi(intensity, 1, 3)
	var int_id := "%s_int%d" % [id, clamped_i]
	if _tiles.has(int_id):
		return int_id
	if not season.is_empty():
		var int_s := "%s_season_%s" % [int_id, season]
		if _tiles.has(int_s):
			return int_s
	return resolve_tile_id(id, season, true)


static func get_tile_entry(resolved_id: String) -> Dictionary:
	if resolved_id.is_empty():
		return {}
	return _tiles.get(resolved_id, {})


static func draw_resolved_tile(board: Control, tile_in: Dictionary, origin: Vector2, cell_size: float,
		roll := 0, subtile_idx := -1, rota := 0, tint := Color.WHITE, offset := Vector2.ZERO,
		flip := false, layer_mode := LAYER_BOTH) -> bool:
	if tile_in.is_empty():
		return false
	var tile: Dictionary = tile_in
	if tile.has("joins"):
		var joins: Dictionary = tile["joins"]
		if subtile_idx >= 0 and subtile_idx < SUBTILE_KEYS.size():
			var sub: Dictionary = joins.get(SUBTILE_KEYS[subtile_idx], {})
			if not sub.is_empty():
				tile = sub
		elif subtile_idx < 0 and joins.has("unconnected"):
			# Never accidentally render a multitile base placeholder square (e.g. fd_blood solid red block)!
			var unc: Dictionary = joins.get("unconnected", {})
			if not unc.is_empty():
				tile = unc
	var rotates: bool = bool(tile.get("rotates", false))
	var angle := rota if rotates else 0
	var use_roll := roll
	if bool(tile.get("animated", false)):
		_used_animated_this_frame = true
		@warning_ignore("integer_division")
		use_roll = roll + int(Time.get_ticks_msec() / 17)
	var zoom := Vector2.ONE * cell_size / Vector2(_base_size)
	var at := origin + (Vector2(tile["offset"]) + offset) * zoom
	var scale: Vector2 = zoom * float(tile["scale"])
	var rot_bg := rotates and (tile["fg"] is Array and (tile["fg"] as Array).is_empty())
	if layer_mode == LAYER_BOTH or layer_mode == LAYER_BG_ONLY:
		_draw_layer(board, tile["bg"], use_roll, angle, rot_bg, at, scale, tint, false)
	if layer_mode == LAYER_BOTH or layer_mode == LAYER_FG_ONLY:
		_draw_layer(board, tile["fg"], use_roll, angle, true, at, scale, tint, flip)
	return true


static func is_tall_tile(id: String, season := "") -> bool:
	var key := id + "|" + season
	if _tall_cache.has(key):
		return bool(_tall_cache[key])
	var res := resolve_tile_id(id, season)
	var tall := false
	if not res.is_empty() and _tiles.has(res):
		tall = bool(_tiles[res].get("tall", false))
	_tall_cache[key] = tall
	return tall


static func _sprite(index: int) -> Array:
	if _sprites.has(index):
		return _sprites[index]
	for s_idx in range(_sheets.size()):
		var sheet: Dictionary = _sheets[s_idx]
		if index < int(sheet["first"]) or index >= int(sheet["end"]):
			continue
		var frame: Vector2i = sheet["frame"]
		var local := index - int(sheet["first"])
		var cols: int = sheet["cols"]
		@warning_ignore("integer_division")
		var row := local / cols
		@warning_ignore("integer_division")
		var rows_per_page := maxi(1, PAGE_HEIGHT / frame.y)
		@warning_ignore("integer_division")
		var texture := _page(s_idx, sheet, row / rows_per_page, rows_per_page)
		if texture == null:
			break
		var region := Rect2(Vector2((local % cols) * frame.x, (row % rows_per_page) * frame.y), Vector2(frame))
		var sprite := [texture, region]
		_sprites[index] = sprite
		return sprite
	_sprites[index] = []
	return []


static func _pick(value: Variant, roll: int) -> Variant:
	if not value is Array or value.is_empty() or not value[0] is Dictionary:
		return value
	var total := 0
	for option: Dictionary in value:
		total += int(option.get("weight", 1))
	if total <= 0:
		return []
	var slot := posmod(roll, total)
	for option: Dictionary in value:
		slot -= int(option.get("weight", 1))
		if slot < 0:
			return option.get("sprite", [])
	return []


static func _draw_layer(board: Control, value: Variant, roll: int, angle: int, foreground: bool,
		at: Vector2, zoom: Vector2, tint: Color, flip: bool) -> void:
	var picked: Variant = _pick(value, roll)
	var turn := 0
	var index: int = -1
	if picked is Array:
		if picked.is_empty():
			return
		if picked.size() == 1:
			index = int(picked[0])
			if foreground:
				turn = posmod(angle, 4)
		else:
			index = int(picked[posmod(angle, picked.size())])
	elif picked is int or picked is float:
		index = int(picked)
		if foreground:
			turn = posmod(angle, 4)
	else:
		return
	if index < 0:
		return
	var sprite := _sprite(index)
	if sprite.is_empty():
		return
	var source: Rect2 = sprite[1]
	var extent := source.size * zoom
	if turn != 0 or flip:
		# Exact match to CCB src/sprite_geometry.h: 1=+90deg, 2=flip H+V, 3=-90deg
		var rot_rad := 0.0
		var sc := Vector2.ONE
		if turn == 1:
			rot_rad = PI * 0.5
		elif turn == 2:
			sc = Vector2(-1.0, -1.0)
		elif turn == 3:
			rot_rad = -PI * 0.5
		if flip:
			sc.x = -sc.x
		board.draw_set_transform(at + extent * 0.5, rot_rad, sc)
		board.draw_texture_rect_region(sprite[0], Rect2(-extent * 0.5, extent), source, tint)
		board.draw_set_transform(Vector2.ZERO)
	else:
		board.draw_texture_rect_region(sprite[0], Rect2(at, extent), source, tint)


static func draw(board: Control, id: String, p: Vector2i, roll := 0, mask := -1, orientation := 0,
		tint := Color.WHITE, offset := Vector2.ZERO, flip := false, season := "") -> void:
	if board.has_method("surface_id"):
		tint = board.call("surface_id", p)
	var cam_offset: Vector2 = board.cam_px_offset if "cam_px_offset" in board else Vector2.ZERO
	draw_at(board, id, Vector2((p - board.view_origin) * board.cell) + cam_offset, float(board.cell), roll, mask,
		orientation, tint, offset, flip, season)


static func draw_at(board: Control, id: String, origin: Vector2, cell_size: float, roll := 0,
		mask := -1, orientation := 0, tint := Color.WHITE, offset := Vector2.ZERO, flip := false, season := "") -> void:
	if not _attempted:
		_load_catalog()
	var resolved := resolve_seasonal(id, season)
	var tile: Dictionary = _tiles.get(resolved, _tiles.get(id, _tiles.get("unknown", {})))
	if tile.is_empty():
		return
	if mask >= 0 and tile.has("joins"):
		var join: Array = JOINS[mask & 15]
		var sub: Dictionary = tile["joins"].get(join[0], {})
		if not sub.is_empty():
			tile = sub
			orientation = join[1]
	var angle := orientation if tile["rotates"] else 0
	var zoom := Vector2.ONE * cell_size / Vector2(_base_size)
	var at := origin + (Vector2(tile["offset"]) + offset) * zoom
	var scale: Vector2 = zoom * float(tile["scale"])
	_draw_layer(board, tile["bg"], roll, angle, false, at, scale, tint, false)
	_draw_layer(board, tile["fg"], roll, angle, true, at, scale, tint, flip)


# Authentic CCB renderer using real CCB subtile (0..7) + rotation (0..15) + looks_like + layer split!
static func draw_at_subtile(board: Control, id: String, origin: Vector2, cell_size: float, roll := 0,
		subtile_idx := -1, rota := 0, tint := Color.WHITE, offset := Vector2.ZERO, flip := false,
		season := "", layer_mode := LAYER_BOTH, male := true) -> bool:
	var resolved := resolve_tile_id(id, season, male)
	if resolved.is_empty():
		return false
	return draw_resolved_tile(board, _tiles[resolved], origin, cell_size, roll, subtile_idx, rota, tint, offset, flip, layer_mode)


static func get_fallback_white_tex() -> Texture2D:
	if _fallback_white_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_fallback_white_tex = ImageTexture.create_from_image(img)
	return _fallback_white_tex


# Computes & caches exact CCB render3d.cpp sprite_info metrics (atlas UV, opaque-cropped ground UV,
# base_drop fraction, transparency flag, pixel dimensions) ONCE per unique sprite index.
static func _sprite_3d_metrics(index: int) -> Dictionary:
	var cached = _sprite_3d_cache.get(index)
	if cached != null:
		return cached
	var sp := _sprite(index)
	if sp.is_empty():
		var empty_d := {}
		_sprite_3d_cache[index] = empty_d
		return empty_d
	var tex: Texture2D = sp[0]
	var reg: Rect2 = sp[1]
	var tsz := Vector2(tex.get_size())
	if tsz.x <= 0.0 or tsz.y <= 0.0:
		var empty_d2 := {}
		_sprite_3d_cache[index] = empty_d2
		return empty_d2

	var u0 := reg.position.x / tsz.x
	var v0 := reg.position.y / tsz.y
	var u1 := reg.end.x / tsz.x
	var v1 := reg.end.y / tsz.y
	var px_w := int(reg.size.x)
	var px_h := int(reg.size.y)
	var aspect := float(px_w) / float(maxi(1, px_h))

	var gu0 := u0
	var gv0 := v0
	var gu1 := u1
	var gv1 := v1
	var base_drop := 0.0
	var has_trans := false

	var img := tex.get_image()
	if img != null and px_w > 0 and px_h > 0:
		var rx0 := clampi(int(reg.position.x), 0, img.get_width() - 1)
		var ry0 := clampi(int(reg.position.y), 0, img.get_height() - 1)
		var rx1 := clampi(rx0 + px_w, rx0, img.get_width())
		var ry1 := clampi(ry0 + px_h, ry0, img.get_height())
		var min_x := px_w
		var min_y := px_h
		var max_x := -1
		var max_y := -1
		var opaque_cnt := 0
		for py in range(ry0, ry1):
			for px in range(rx0, rx1):
				if img.get_pixel(px, py).a >= 0.12:
					opaque_cnt += 1
					var lx := px - rx0
					var ly := py - ry0
					if lx < min_x: min_x = lx
					if ly < min_y: min_y = ly
					if lx > max_x: max_x = lx
					if ly > max_y: max_y = ly
		if max_x >= min_x and max_y >= min_y:
			var ow := float(max_x - min_x + 1)
			var oh := float(max_y - min_y + 1)
			var dw := float(px_w)
			var dh := float(px_h)
			gu0 = u0 + (u1 - u0) * (float(min_x) / dw)
			gu1 = u0 + (u1 - u0) * (float(max_x + 1) / dw)
			gv0 = v0 + (v1 - v0) * (float(min_y) / dh)
			gv1 = v0 + (v1 - v0) * (float(max_y + 1) / dh)
			base_drop = clampf(1.0 - float(max_y + 1) / dh, 0.0, 1.0)
			has_trans = (opaque_cnt * 20 < px_w * px_h * 19) or (ow * oh * 20.0 < dw * dh * 19.0)

	var info := {
		"tex": tex,
		"u0": u0, "v0": v0, "u1": u1, "v1": v1,
		"gu0": gu0, "gv0": gv0, "gu1": gu1, "gv1": gv1,
		"base_drop": base_drop,
		"has_trans": has_trans,
		"px_w": px_w,
		"px_h": px_h,
		"aspect": aspect,
	}
	_sprite_3d_cache[index] = info
	return info


static func _pick_3d_index_and_turn(value: Variant, roll: int, angle: int, allow_turn: bool) -> Array:
	var picked: Variant = _pick(value, roll)
	var turn := 0
	var index := -1
	if picked is Array:
		if picked.is_empty():
			return [-1, 0]
		if picked.size() == 1:
			index = int(picked[0])
			if allow_turn:
				turn = posmod(angle, 4)
		else:
			index = int(picked[posmod(angle, picked.size())])
	elif picked is int or picked is float:
		index = int(picked)
		if allow_turn:
			turn = posmod(angle, 4)
	return [index, turn]


# Resolves a CCB tile ID + subtile + rotation + pick mode into 3D GPU atlas coordinates & metrics.
# pick_mode: 0=FG, 1=BG, 2=GROUND (bg else fg, opaque-cropped), 3=FIELD (intensity), 4=OVERLAY
static func resolve_3d_sprite(id: String, season: String, roll: int, subtile_idx: int, rota: int,
		pick_mode: int, male := true, field_intensity := 1) -> Dictionary:
	if id.is_empty():
		return {}
	if not _attempted:
		_load_catalog()
	var resolved := resolve_field_tile_id(id, field_intensity, season) if pick_mode == 3 else resolve_tile_id(id, season, male)
	if resolved.is_empty():
		return {}
	var base_tile: Dictionary = _tiles.get(resolved, {})
	if base_tile.is_empty():
		return {}
	var tile: Dictionary = base_tile
	if tile.has("joins"):
		var joins: Dictionary = tile["joins"]
		if subtile_idx >= 0 and subtile_idx < SUBTILE_KEYS.size():
			var sub: Dictionary = joins.get(SUBTILE_KEYS[subtile_idx], {})
			if not sub.is_empty():
				tile = sub
		elif subtile_idx < 0 and joins.has("unconnected"):
			var unc: Dictionary = joins.get("unconnected", {})
			if not unc.is_empty():
				tile = unc

	var rotates: bool = bool(tile.get("rotates", false))
	var angle := rota if rotates else 0
	var use_roll := roll
	if bool(tile.get("animated", false)):
		_used_animated_this_frame = true
		@warning_ignore("integer_division")
		use_roll = roll + int(Time.get_ticks_msec() / 50)

	var idx_turn := [-1, 0]
	var used_bg := false
	if pick_mode == 1: # BG only (fallback to base tile bg if subtile lacks bg)
		idx_turn = _pick_3d_index_and_turn(tile["bg"], use_roll, angle, rotates)
		if int(idx_turn[0]) < 0 and tile != base_tile:
			idx_turn = _pick_3d_index_and_turn(base_tile["bg"], use_roll, angle, rotates)
		used_bg = int(idx_turn[0]) >= 0
	elif pick_mode == 2: # GROUND: prefer bg (or base bg), else fg
		idx_turn = _pick_3d_index_and_turn(tile["bg"], use_roll, angle, false)
		if int(idx_turn[0]) < 0 and tile != base_tile:
			idx_turn = _pick_3d_index_and_turn(base_tile["bg"], use_roll, angle, false)
		if int(idx_turn[0]) >= 0:
			used_bg = true
		else:
			idx_turn = _pick_3d_index_and_turn(tile["fg"], use_roll, angle, rotates)
	else: # FG / FIELD / OVERLAY (fallback to bg only if fg empty on pick_mode==0)
		idx_turn = _pick_3d_index_and_turn(tile["fg"], use_roll, angle, rotates)
		if int(idx_turn[0]) < 0 and pick_mode == 0:
			idx_turn = _pick_3d_index_and_turn(tile["bg"], use_roll, angle, rotates)
			used_bg = int(idx_turn[0]) >= 0

	var spr_idx := int(idx_turn[0])
	if spr_idx < 0:
		return {}
	var m := _sprite_3d_metrics(spr_idx)
	if m.is_empty():
		return {}
	var off_v: Vector2i = tile.get("offset", Vector2i.ZERO)
	return {
		"tex": m["tex"],
		"u0": float(m["u0"]), "v0": float(m["v0"]),
		"u1": float(m["u1"]), "v1": float(m["v1"]),
		"gu0": float(m["gu0"]), "gv0": float(m["gv0"]),
		"gu1": float(m["gu1"]), "gv1": float(m["gv1"]),
		"base_drop": float(m["base_drop"]),
		"has_trans": bool(m["has_trans"]),
		"px_w": int(m["px_w"]),
		"px_h": int(m["px_h"]),
		"aspect": float(m["aspect"]),
		"offset": off_v,
		"rot4": int(idx_turn[1]),
		"used_bg": used_bg,
		"has_bg": (tile["bg"] is int and int(tile["bg"]) >= 0) or (tile["bg"] is Array and not (tile["bg"] as Array).is_empty()),
		"has_fg": (tile["fg"] is int and int(tile["fg"]) >= 0) or (tile["fg"] is Array and not (tile["fg"] as Array).is_empty()),
	}
