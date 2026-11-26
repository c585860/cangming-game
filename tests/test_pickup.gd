extends SceneTree

# Run with Godot --headless --path . --script tests/test_pickup.gd
var failures := 0


static func fixture(world: Object, path: String, bag: Dictionary, piles: Array, tiles: Array = []) -> void:
	world.setup(73)
	assert(world.save_game(path))
	var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var counts: Array = save.items.bag
	counts.fill(0)
	for id: int in bag:
		counts[id] = bag[id]
	save.items.placed = []
	save.items.taken = []
	for pile: Array in piles:
		var p: Vector2i = world.pos + Vector2i(pile[0])
		var key: int = p.y * int(world.city_size.x) + p.x
		if not save.items.taken.has(key):
			save.items.taken.append(key)
		save.items.placed.append([key, pile[1], pile[2]])
	for tile: Array in tiles:
		var p: Vector2i = world.pos + Vector2i(tile[0])
		save.tile_overrides.append([p.y * int(world.city_size.x) + p.x, str(tile[1]).unicode_at(0)])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(save))
	file.close()
	assert(world.load_game(path))


static func count_id(rows: Array, id: int) -> int:
	for row: Dictionary in rows:
		if row.id == id:
			return int(row.count)
	return 0


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func _initialize() -> void:
	var world: Object = ClassDB.instantiate("CanglingWorld")
	var path := "user://pickup-test-%d.json" % OS.get_process_id()
	fixture(world, path, {}, [[Vector2i.ZERO, 5, 5], [Vector2i.RIGHT, 5, 3]])
	var p: Vector2i = world.pos
	var first := {"floor": 0, "position": p, "item": 5, "quantity": 3}
	var second := {"floor": 0, "position": p + Vector2i.RIGHT, "item": 5, "quantity": 1}
	var results: Array = world.pickup_items([first, second])
	check(results.size() == 2 and results[0].moved == 3 and results[1].moved == 1, "independent source amounts")
	check(count_id(world.items_at(p), 5) == 2 and count_id(world.items_at(second.position), 5) == 2, "ground remainders")
	check(world.save_game(path) and world.load_game(path), "save round trip")
	check(count_id(world.inventory(), 5) == 4 and count_id(world.items_at(p), 5) == 2, "persisted transfer")
	results = world.pickup_items([first])
	check(results[0].requested == 3 and results[0].moved == 2 and not str(results[0].reason).is_empty(), "stale quantity")
	results = world.pickup_items([{}, null, {"floor": 1, "position": p, "item": 5, "quantity": 1},
		{"floor": 0, "position": p + Vector2i(2, 0), "item": 5, "quantity": 1}])
	for row: Dictionary in results:
		check(row.moved == 0 and not str(row.reason).is_empty(), "invalid source")

	fixture(world, path, {5: 999}, [[Vector2i.ZERO, 5, 3]])
	check(" 0 " in str(world.take_all_at(p)), "full stack reported a successful pickup")
	check(count_id(world.items_at(p), 5) == 3, "full stack lost items")

	var cap: int = world.character_status().max_carry_volume_ml
	fixture(world, path, {5: floori(cap / 250.0) - 1}, [[Vector2i.ZERO, 0, 1], [Vector2i.ZERO, 5, 2]])
	check(" 1 " in str(world.take_all_at(p)), "large item stopped a later fitting item")
	check(count_id(world.items_at(p), 0) == 1 and count_id(world.items_at(p), 5) == 1, "volume conservation")

	fixture(world, path, {}, [[Vector2i.RIGHT, 5, 2]], [[Vector2i.RIGHT, "c"]])
	check(world.items_at(second.position).is_empty(), "closed cabinet exposed its contents")
	check(world.pickup_items([second])[0].moved == 0, "closed cabinet allowed pickup")
	world.open_at(second.position)
	check(world.pickup_items([second])[0].moved == 1, "open cabinet blocked pickup")
	world.close_at(second.position)
	check(world.pickup_items([second])[0].moved == 0, "cabinet closed after preview")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Pickup mechanics failures: ", failures)
	quit(1 if failures else 0)
