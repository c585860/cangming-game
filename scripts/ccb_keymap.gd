extends RefCounted

# Authentic Cataclysm-Cleanwater-Bomb (CCB) Keybinding Dispatcher.
# Detects uppercase vs lowercase characters DIRECTLY from event.unicode (char(event.unicode)),
# NOT by checking shift+keycode — so CapsLock+G and Shift+G both naturally emit "G"!
# Also maps fullwidth Chinese IME punctuation fallbacks gracefully.

const FULLWIDTH_MAP := {
	"，": ",",
	"。": ".",
	"；": ";",
	"！": "!",
	"？": "?",
	"《": "<",
	"》": ">",
	"“": "\"",
	"”": "\"",
	"￥": "$",
	"、": "\\",
	"｜": "|",
	"＠": "@",
	"＋": "+",
}

# Exact CCB DEFAULTMODE bindings from Cataclysm-Cleanwater-Bomb/data/raw/keybindings.json
const CHAR_ACTIONS := {
	# Lowercase world interactions & item/screen commands
	"o": "open",
	"c": "close",
	"s": "smash",
	"e": "examine",
	"g": "pickup",
	",": "pickup",
	"d": "drop",
	"i": "inventory",
	"w": "wield",
	"a": "apply",
	"m": "map",
	"x": "look",
	";": "look",
	"z": "zoom_in",
	"\\": "haul",
	"\"": "move_mode",
	"@": "character",
	"+": "take_off",
	"|": "wait",
	"$": "sleep",
	"<": "stairs_up",
	">": "stairs_down",
	"!": "safe_mode",
	"?": "help",
	"0": "help",

	# Uppercase CCB commands — matched directly by Unicode uppercase character!
	"G": "grab",
	"E": "eat",
	"W": "wear",
	"T": "take_off",
	"D": "drop_dir",
	"R": "read",
	"V": "list_nearby",
	"X": "peek",
	"C": "chat",
	"A": "apply_wielded",
	"M": "missions",
	"P": "messages",
	"S": "save",
	"Z": "zoom_out",
	"J": "skills",
	"O": "multiplayer",
	"K": "debug",
}


static func event_char(event: InputEventKey) -> String:
	if event.unicode > 0:
		var ch := char(event.unicode)
		if FULLWIDTH_MAP.has(ch):
			return FULLWIDTH_MAP[ch]
		return ch
	return ""


static func match_action(event: InputEventKey) -> String:
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return ""
	# Enter / Numpad Enter -> CCB Action Menu
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER \
			or event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
		return "action_menu"
	var ch := event_char(event)
	if not ch.is_empty() and CHAR_ACTIONS.has(ch):
		return CHAR_ACTIONS[ch]
	return ""


static func is_wait_turn_key(event: InputEventKey) -> bool:
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	if event.keycode == KEY_KP_5 or event.physical_keycode == KEY_KP_5:
		return true
	var ch := event_char(event)
	return ch == "." or ch == "5"
