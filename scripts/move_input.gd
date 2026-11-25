extends RefCounted

# Dedicated rate-capped directional input controller (Arrows + WASD + Numpad).
# Ignores OS key-repeat echo spam so holding a key moves at a steady cadence synced with walk animation.

const INITIAL_HOLD_DELAY := 0.165
const REPEAT_STEP_INTERVAL := 0.135

const KEY_DIRS := {
	KEY_UP: Vector2i.UP,
	KEY_W: Vector2i.UP,
	KEY_KP_8: Vector2i.UP,
	KEY_DOWN: Vector2i.DOWN,
	KEY_S: Vector2i.DOWN,
	KEY_KP_2: Vector2i.DOWN,
	KEY_LEFT: Vector2i.LEFT,
	KEY_A: Vector2i.LEFT,
	KEY_KP_4: Vector2i.LEFT,
	KEY_RIGHT: Vector2i.RIGHT,
	KEY_D: Vector2i.RIGHT,
	KEY_KP_6: Vector2i.RIGHT,
	KEY_KP_7: Vector2i(-1, -1),
	KEY_KP_9: Vector2i(1, -1),
	KEY_KP_1: Vector2i(-1, 1),
	KEY_KP_3: Vector2i(1, 1),
}

var _held_order: Array[int] = []
var _cooldown := 0.0
var _diag_toggle := false


func reset() -> void:
	_held_order.clear()
	_cooldown = 0.0


static func key_to_dir(event: InputEventKey) -> Vector2i:
	if KEY_DIRS.has(event.keycode):
		return KEY_DIRS[event.keycode]
	if KEY_DIRS.has(event.physical_keycode):
		return KEY_DIRS[event.physical_keycode]
	return Vector2i.ZERO


static func _canonical_key(event: InputEventKey) -> int:
	if KEY_DIRS.has(event.keycode):
		return int(event.keycode)
	if KEY_DIRS.has(event.physical_keycode):
		return int(event.physical_keycode)
	return 0


func is_movement_key(event: InputEventKey) -> bool:
	return _canonical_key(event) != 0


func handle_key_release(event: InputEventKey) -> void:
	var k := _canonical_key(event)
	if k != 0:
		_held_order.erase(k)


func handle_key_press(event: InputEventKey) -> Vector2i:
	var k := _canonical_key(event)
	if k == 0:
		return Vector2i.ZERO
	# Always ignore OS echo spam; held motion is stepped cleanly in tick().
	if event.echo:
		return Vector2i.ZERO
	_held_order.erase(k)
	_held_order.append(k)
	if _cooldown > 0.02:
		# Respect step cap even on rapid key mashing
		return Vector2i.ZERO
	_cooldown = INITIAL_HOLD_DELAY
	return _resolve_step(KEY_DIRS[k])


func tick(delta: float) -> Vector2i:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	# Prune keys that may have been released while unfocused
	for i in range(_held_order.size() - 1, -1, -1):
		var k := _held_order[i]
		if not Input.is_key_pressed(k) and not Input.is_physical_key_pressed(k):
			_held_order.remove_at(i)
	if _held_order.is_empty() or _cooldown > 0.0:
		return Vector2i.ZERO
	_cooldown = REPEAT_STEP_INTERVAL
	var active_key := _held_order[_held_order.size() - 1]
	return _resolve_step(KEY_DIRS[active_key])


func _resolve_step(raw: Vector2i) -> Vector2i:
	# Grid movement is 4-way; numpad diagonals (1/3/7/9) smoothly alternate X/Y steps!
	if raw.x != 0 and raw.y != 0:
		_diag_toggle = not _diag_toggle
		return Vector2i(raw.x, 0) if _diag_toggle else Vector2i(0, raw.y)
	return raw
