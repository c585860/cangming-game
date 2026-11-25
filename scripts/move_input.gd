extends RefCounted

# Authentic CCB 8-direction movement controller:
# - Numpad 1/2/3/4/6/7/8/9 (standard roguelike / CCB numpad)
# - Arrow keys (Up/Down/Left/Right + simultaneous diagonal chords)
# - Classic CCB lowercase vi-keys (h, j, k, l, y, u, b, n) matched strictly via lowercase event.unicode
#   so uppercase H/J/K/L/Y/U/B/N NEVER trigger movement (e.g. uppercase K opens Debug)!
# - NO WASD hijacking: w (wield), a (apply), s (smash), d (drop) remain 100% pure CCB actions!

const INITIAL_HOLD_DELAY := 0.165
const REPEAT_STEP_INTERVAL := 0.135

const NON_CHAR_DIRS := {
	KEY_UP: Vector2i.UP,
	KEY_KP_8: Vector2i.UP,
	KEY_DOWN: Vector2i.DOWN,
	KEY_KP_2: Vector2i.DOWN,
	KEY_LEFT: Vector2i.LEFT,
	KEY_KP_4: Vector2i.LEFT,
	KEY_RIGHT: Vector2i.RIGHT,
	KEY_KP_6: Vector2i.RIGHT,
	KEY_KP_7: Vector2i(-1, -1),
	KEY_KP_9: Vector2i(1, -1),
	KEY_KP_1: Vector2i(-1, 1),
	KEY_KP_3: Vector2i(1, 1),
}

# Lowercase CCB vi-keys (strictly matched against lowercase Unicode char!)
const VI_CHAR_TO_KEY := {
	"h": KEY_H,
	"j": KEY_J,
	"k": KEY_K,
	"l": KEY_L,
	"y": KEY_Y,
	"u": KEY_U,
	"b": KEY_B,
	"n": KEY_N,
}

const VI_KEY_DIRS := {
	KEY_H: Vector2i.LEFT,
	KEY_J: Vector2i.DOWN,
	KEY_K: Vector2i.UP,
	KEY_L: Vector2i.RIGHT,
	KEY_Y: Vector2i(-1, -1),
	KEY_U: Vector2i(1, -1),
	KEY_B: Vector2i(-1, 1),
	KEY_N: Vector2i(1, 1),
}

var _held_order: Array[int] = []
var _cooldown := 0.0


func reset() -> void:
	_held_order.clear()
	_cooldown = 0.0


static func _dir_for_id(k: int) -> Vector2i:
	if NON_CHAR_DIRS.has(k):
		return NON_CHAR_DIRS[k]
	if VI_KEY_DIRS.has(k):
		return VI_KEY_DIRS[k]
	return Vector2i.ZERO


static func _canonical_key(event: InputEventKey, for_release := false) -> int:
	if NON_CHAR_DIRS.has(event.keycode):
		return int(event.keycode)
	if NON_CHAR_DIRS.has(event.physical_keycode):
		return int(event.physical_keycode)
	if for_release:
		if VI_KEY_DIRS.has(event.keycode):
			return int(event.keycode)
		if VI_KEY_DIRS.has(event.physical_keycode):
			return int(event.physical_keycode)
		return 0
	# For key press, strictly check lowercase event.unicode so CapsLock/Shift uppercase letters
	# (like 'K' for Debug) NEVER get misinterpreted as movement!
	if event.unicode > 0:
		var ch := char(event.unicode)
		if VI_CHAR_TO_KEY.has(ch):
			return int(VI_CHAR_TO_KEY[ch])
	return 0


static func key_to_dir(event: InputEventKey) -> Vector2i:
	var k := _canonical_key(event, false)
	return _dir_for_id(k) if k != 0 else Vector2i.ZERO


func is_movement_key(event: InputEventKey) -> bool:
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	return _canonical_key(event, false) != 0


func handle_key_release(event: InputEventKey) -> void:
	var k := _canonical_key(event, true)
	if k != 0:
		_held_order.erase(k)


func handle_key_press(event: InputEventKey) -> Vector2i:
	var k := _canonical_key(event, false)
	if k == 0:
		return Vector2i.ZERO
	if event.echo:
		return Vector2i.ZERO
	_held_order.erase(k)
	_held_order.append(k)
	if _cooldown > 0.02:
		return Vector2i.ZERO
	_cooldown = INITIAL_HOLD_DELAY
	return _resolve_held_direction()


func tick(delta: float) -> Vector2i:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	for i in range(_held_order.size() - 1, -1, -1):
		var k := _held_order[i]
		if not Input.is_key_pressed(k) and not Input.is_physical_key_pressed(k):
			_held_order.remove_at(i)
	if _held_order.is_empty() or _cooldown > 0.0:
		return Vector2i.ZERO
	_cooldown = REPEAT_STEP_INTERVAL
	return _resolve_held_direction()


func _resolve_held_direction() -> Vector2i:
	if _held_order.is_empty():
		return Vector2i.ZERO
	var latest_dir: Vector2i = _dir_for_id(_held_order[_held_order.size() - 1])
	if latest_dir.x != 0 and latest_dir.y != 0:
		return latest_dir
	var dx := 0
	var dy := 0
	for k in _held_order:
		var d: Vector2i = _dir_for_id(k)
		if d.x != 0:
			dx = d.x
		if d.y != 0:
			dy = d.y
	var combined := Vector2i(dx, dy)
	return combined if combined != Vector2i.ZERO else latest_dir
