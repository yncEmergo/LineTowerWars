class_name KeyPosition
extends RefCounted

## A key named by WHERE IT SITS, which is how every hotkey in this game is read.
##
## Godot reports two codes for a press. `keycode` follows the player's keyboard
## layout: the key printed Y on a German board reports KEY_Y. `physical_keycode`
## names the key by its PLACE, spelled as the US QWERTY key that sits there, so
## that same key reports KEY_Z on every board. The command card and the Research
## Center are shapes the left hand learns, so a square is a place, and every key
## the game stores, compares or answers is the physical one. Docs/hotkeys.md 1.
##
## What a square DRAWS is the other half: the letter printed on the player's own
## keyboard in that place, asked of the OS. A German board draws Y in the bottom
## left, an American one Z and a French one W, and nothing anywhere has to be
## told which board a player has.
##
## A handful of statics rather than an object, the same shape as StringUtil.

## The display servers known to answer what a key prints. Anything else - a
## headless process above all, which is what a dedicated server is - prints
## "Not supported by this display server" on EVERY call, and a label is asked
## for on every refresh of a card. So the question is not asked there at all,
## and the key's position name is drawn instead: the US QWERTY letter.
const LABEL_SERVERS: Array[String] = ["Windows", "X11", "macOS"]

## Whether this process may ask the OS about its keyboard: -1 until the first
## question, then 0 or 1. The display server cannot change under a running
## process, so it is asked once.
static var _can_ask: int = -1


## The key a press names, by position.
##
## Falls back to the layout keycode for an event that carries no physical code,
## which is only ever a synthetic one - a test or a tool injecting a press. A
## real key always has both.
static func of_press(event: InputEventKey) -> Key:
	if event.physical_keycode != KEY_NONE:
		return event.physical_keycode
	return event.keycode


## What the player's own keyboard prints on the key in this place, ready to
## draw in a square's corner.
##
## Falls back to the position's own name where the OS has no answer - see
## LABEL_SERVERS - so it is never empty for a key.
static func printed_label(physical: Key) -> String:
	if physical == KEY_NONE:
		return ""
	var label: Key = physical
	if _may_ask_os():
		label = DisplayServer.keyboard_get_label_from_physical(physical)
		if label == KEY_NONE:
			label = physical
	return OS.get_keycode_string(label).to_upper()


## A position as the settings file and a .tres store it: the name Godot gives
## the key in that place, which is the US QWERTY key there - "Z" for the bottom
## left of the card, whatever that key prints.
static func to_stored(physical: Key) -> String:
	if physical == KEY_NONE:
		return ""
	return OS.get_keycode_string(physical)


## The position a stored name stands for, or KEY_NONE for an empty one.
static func from_stored(text: String) -> Key:
	if text.is_empty():
		return KEY_NONE
	return OS.find_keycode_from_string(text.to_upper()) as Key


## Whether the key in this place is held down right now. For hold-to-repeat,
## which has to notice a release that happened while another window had focus.
static func is_down(physical: Key) -> bool:
	return physical != KEY_NONE && Input.is_physical_key_pressed(physical)


## The position of the letter key that TYPES this character on this machine's
## keyboard, or the character's own code where no letter key does.
##
## Only for reading a binding saved before keys were positions, when the file
## stored what a key typed: the German Y becomes the bottom left key. Letters
## are the only keys whose place differs between layouts in a way that matters
## here, and a process that cannot ask keeps the code as it was.
static func from_layout_key(logical: Key) -> Key:
	if !_may_ask_os():
		return logical
	for code: int in range(KEY_A, KEY_Z + 1):
		var physical: Key = code as Key
		if DisplayServer.keyboard_get_keycode_from_physical(physical) == logical:
			return physical
	return logical


static func _may_ask_os() -> bool:
	if _can_ask < 0:
		_can_ask = 1 if LABEL_SERVERS.has(DisplayServer.get_name()) else 0
	return _can_ask == 1
