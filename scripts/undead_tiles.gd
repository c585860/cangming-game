extends RefCounted

const ROOT := "res://art/undead_people/"
const PAGE_HEIGHT := 1024
const JOINS := [
	["unconnected", 0], ["end_piece", 0], ["end_piece", 3], ["corner", 0],
	["end_piece", 1], ["corner", 1], ["edge", 1], ["t_connection", 0],
	["end_piece", 2], ["edge", 0], ["corner", 3], ["t_connection", 3],
	["corner", 2], ["t_connection", 1], ["t_connection", 2], ["center", 0],
]

static var _base_size := Vector2i(32, 32)
static var _tiles: Dictionary = {}
static var _sheets: Array[Dictionary] = []
static var _sprites: Dictionary = {}
static var _decoded: Dictionary = {}
static var _page_stamps: Dictionary = {}
static var _pinned_pages: Dictionary = {}
static var _frame_id := 0
static var _attempted := false
static var _prewarmed := false

const GAME_TILE_IDS := [
	# Ground & terrain
	"t_grass", "t_grass_long", "t_stone_road", "t_dirt", "t_sand", "t_floor", "t_carpet_red",
	"t_rock_floor", "t_stone_masonry_floor", "t_dock", "t_water_moving_dp", "t_water_moving_sh", "t_pillar",
	# Trees, shrubs & water flora
	"t_tree_willow", "t_tree_maple", "t_tree_pine", "t_shrub", "t_shrub_lilac", "t_shrub_blackberry",
	"f_cattails", "f_lilypad", "f_lotus",
	# Characters & worn overlays
	"player_male", "overlay_worn_straw_hat", "overlay_worn_bandana", "overlay_worn_tunic",
	"overlay_worn_pants", "overlay_worn_robe", "overlay_worn_cloak", "overlay_worn_coat_winter",
	"overlay_worn_boots", "overlay_worn_bastsandals", "overlay_worn_backpack", "overlay_worn_mbag",
	# All 50 SUS items
	"sheet_cotton", "pillow", "blanket", "quilt", "straw_hat", "bandana", "tunic", "longshirt",
	"pants", "robe", "cloak", "coat_winter", "boots", "bastsandals", "backpack", "mbag",
	"flatbread", "bread", "deluxe_rice", "jerky", "apple", "pear", "cake2", "tea", "water_clean",
	"brew_fruit_wine", "tea_raw", "mayapple", "bottle_glass", "book_archery", "paper", "rope_6",
	"knife_butcher", "chopsticks", "bowl_clay", "pot", "teapot", "salt", "noodles_fast", "hatchet",
	"crowbar", "oil_lamp", "lighter", "2x4", "rag", "ceramic_shard", "bandages", "candle", "towel", "soap",
]


static func _load_catalog() -> void:
	_attempted = true
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "tile_config.json"))
	if not catalog is Dictionary or not catalog.has("tiles-new"):
		push_error("Could not read the UNDEAD_PEOPLE(CCB) tileset catalog")
		return
	var info: Dictionary = catalog["tile_info"][0]
	_base_size = Vector2i(info["width"], info["height"])
	var first := 0
	for group: Dictionary in catalog["tiles-new"]:
		var file: String = ROOT + group["file"]
		var size := _png_size(file)
		var frame := Vector2i(group.get("sprite_width", _base_size.x), group.get("sprite_height", _base_size.y))
		@warning_ignore("integer_division")
		var cols := size.x / frame.x
		@warning_ignore("integer_division")
		var rows := size.y / frame.y
		if cols < 1 or rows < 1:
			push_error("Missing or invalid tileset atlas: " + file)
			_tiles.clear()
			return
		_sheets.append({"file": file, "first": first, "end": first + cols * rows,
			"frame": frame, "cols": cols, "rows": rows, "pages": {}})
		first += cols * rows
		var offset := Vector2i(group.get("sprite_offset_x", 0), group.get("sprite_offset_y", 0))
		var scale: float = group.get("pixelscale", 1.0)
		for entry: Dictionary in group["tiles"]:
			var ids: Array = entry["id"] if entry["id"] is Array else [entry["id"]]
			var multitile: bool = entry.get("multitile", false)
			var tile := _definition(entry, offset, scale, entry.get("rotates", multitile))
			var subtiles := {}
			if multitile:
				for part: Dictionary in entry.get("additional_tiles", []):
					subtiles[part["id"]] = _definition(part, offset, scale, true)
			tile["joins"] = subtiles
			for id: String in ids:
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


static func _definition(entry: Dictionary, offset: Vector2i, scale: float, rotates: bool) -> Dictionary:
	return {"fg": entry.get("fg", []), "bg": entry.get("bg", []), "offset": offset,
		"scale": scale, "rotates": rotates}


static func _page(sheet_idx: int, sheet: Dictionary, page: int, rows_per_page: int) -> Texture2D:
	var pages: Dictionary = sheet["pages"]
	var stamp_key := (sheet_idx << 16) | (page & 0xffff)
	_page_stamps[stamp_key] = _frame_id
	if pages.has(page):
		return pages[page]
	var file: String = sheet["file"]
	if not _decoded.has(file):
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(file)) != OK:
			push_error("Could not decode tileset atlas: " + file)
			_decoded[file] = null
		else:
			_decoded[file] = image
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


static func finish_frame() -> void:
	# Hold decoded PNGs only during a draw, for sharing between newly requested pages.
	_decoded.clear()
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
	# Pin all prewarmed pages so trim_unused_pages never evicts them and never re-decodes 4MB PNGs mid-walk!
	for key in _page_stamps:
		_pinned_pages[key] = true
	_decoded.clear()


static func trim_unused_pages(max_age_frames := 1800) -> int:
	var freed := 0
	for s_idx in range(_sheets.size()):
		var pages: Dictionary = _sheets[s_idx]["pages"]
		var stale: Array[int] = []
		for page_num: int in pages:
			var stamp_key := (s_idx << 16) | (page_num & 0xffff)
			if _pinned_pages.has(stamp_key):
				continue
			var last_used: int = int(_page_stamps.get(stamp_key, 0))
			if _frame_id - last_used >= max_age_frames:
				stale.append(page_num)
		for page_num in stale:
			pages.erase(page_num)
			_page_stamps.erase((s_idx << 16) | (page_num & 0xffff))
			freed += 1
	if freed > 0:
		_sprites.clear()
	return freed


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
		total += int(option["weight"])
	if total <= 0:
		return []
	var slot := posmod(roll, total)
	for option: Dictionary in value:
		slot -= int(option["weight"])
		if slot < 0:
			return option["sprite"]
	return []


static func _draw_layer(board: Control, value: Variant, roll: int, angle: int, foreground: bool,
		at: Vector2, zoom: Vector2, tint: Color, flip: bool) -> void:
	var picked: Variant = _pick(value, roll)
	var turn := 0
	var index: int
	if picked is Array:
		if picked.is_empty():
			return
		index = int(picked[posmod(angle, picked.size())])
		if foreground and picked.size() == 1:
			turn = angle
	else:
		index = int(picked)
		if foreground:
			turn = angle
	if index < 0:
		return
	var sprite := _sprite(index)
	if sprite.is_empty():
		return
	var source: Rect2 = sprite[1]
	var extent := source.size * zoom
	if turn != 0 or flip:
		board.draw_set_transform(at + extent * 0.5, turn * PI * 0.5, Vector2(-1, 1) if flip else Vector2.ONE)
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
