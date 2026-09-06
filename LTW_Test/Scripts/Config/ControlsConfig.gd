class_name ControlsConfig
extends Resource

## Input timings, the command card layout and control group setup.
##
## Separate from GameConfig because none of this is a rule of the game - it is
## how the player drives it, and it will grow as hotkeys and rebinding arrive.

## Keys that are only ever held WITH another one, so binding a command to one
## alone would give it a key that never arrives on its own.
const MODIFIER_KEYS: Array[int] = [
	KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK,
]

## The mouse buttons that can carry a control group, in the order they are
## handed out past the numbered ones.
##
## A CONST rather than a setting, because this is a fact about the hardware and
## not a choice: a mouse has these two side buttons or it has none. What IS a
## choice - whether the game uses them - is control_group_mouse_buttons below.
const MOUSE_GROUP_BUTTONS: Array[int] = [
	MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2,
]
## What each of those buttons draws on its square. Kept short deliberately: it
## shares a 32 pixel square with a unit count, and "Mouse Button 4" does not.
const MOUSE_GROUP_LABELS: Array[String] = ["M4", "M5"]

@export_group("Selection")
## How quickly a second click must land to count as a double click, in seconds.
## Used both for selecting every unit of a type and for centring on a control
## group.
@export var double_click_seconds: float = 0.5

@export_group("Command card")
## Shape of the command card grid, in slots.
@export var command_columns: int = 4
@export var command_rows: int = 3
## Grid hotkeys, one row of letters per row of the card, left to right.
##
## The card is a grid and the key is read straight off the POSITION, WC3 grid
## style, so an ability never names a key of its own - it names the slot it
## sits in and the key follows from that. Learn the shape once and it holds for
## every unit in the game.
##
## Letters, not keycodes, because a keycode in Godot already follows the
## player's keyboard layout: on a German board the key printed Y reports KEY_Y,
## which is exactly what the bottom left of the card should be. These rows are
## authored EUROPEAN and an American board wants Y and Z swapped out of them,
## which is UserSettings.keyboard_layout and happens in _letter_at rather than
## in a second copy of the rows.
##
## Three straight rows of the keyboard and nothing else. A square that wants a
## key the grid cannot give it - Sell, which is the same command on every card
## a player ever opens - takes a key of its OWN instead, off the grid entirely:
## see HotkeyAction and UnitAbility.hotkey_action.
@export var command_hotkey_rows: PackedStringArray = PackedStringArray([
	"qwer", "asdf", "yxcv",
])

@export_group("Rebindable keys")
## Every command that answers to a key of its own rather than to a square, in
## the order the options screen lists them.
##
## THE LIST IS THE FEATURE. The card is a grid precisely so that hundreds of
## abilities need no keys of their own, and this is the short, authored set of
## exceptions - the commands that mean the same thing on every card, plus the
## one screen that is not a card. An ability joins it by naming one of these in
## its own hotkey_action, and several abilities may name the same one.
@export var hotkey_actions: Array[HotkeyAction] = []

@export_group("Research Center")
## What opens and closes the screen, and the letter its button draws.
##
## A rebindable action rather than a square, because the screen is not a unit
## and has no card to sit on. It also has the weakest claim on its letter: the
## selected unit's command card answers first and this takes only what the card
## leaves alone, so a tower whose square carries this letter keeps it. Null, or
## an action with no key, for a screen reachable by its button alone.
##
## Belongs in hotkey_actions as well, which is what puts it in the options
## screen beside the others; this export is how the screen itself finds it.
@export var research_toggle_action: HotkeyAction
## Shape of the Research Center grid, in squares. Ten elements, five to each
## half of the grid, and three technologies across for each of them.
@export var research_columns: int = 6
@export var research_rows: int = 5
## Grid hotkeys, one row of letters per row of the grid, left to right. Same
## rule as the command card: the key belongs to the SQUARE, so a technology
## names where it sits and never which key it answers to.
##
## The third row is the German "yxcvbn" for the same reason the command card's
## is - a keycode already follows the player's layout, so the key printed Y
## reports KEY_Y. An American layout wants "zxcvbn", and that swap belongs in a
## settings menu once one exists.
@export var research_hotkey_rows: PackedStringArray = PackedStringArray([
	"qwerty", "asdfgh", "yxcvbn", "qwerty", "asdfgh",
])
## First row whose letters are pressed with SHIFT held, drawn as "S+Q".
##
## The grid is deeper than a keyboard has comfortable rows, so the bottom rows
## repeat the top ones with a modifier rather than reaching for keys nobody can
## find. Set it past the last row to use no modifier at all.
@export var research_shift_from_row: int = 3

@export_group("Control groups")
## How many control groups exist. They bind to the number keys starting at 1,
## so nine fills the row.
@export_range(0, 9) var control_group_count: int = 9
## Whether the two side buttons of the mouse carry a control group each, past
## the numbered ones.
##
## Worth a group and not merely allowed one: they are under the thumb already,
## so a group reached by one costs no hand movement at all, and this game asks
## for nothing else from them. Off gives them back to whatever the player's own
## mouse software wants them for.
@export var control_group_mouse_buttons: bool = true

@export_group("Hold to repeat")
## Grace period before holding an ability key starts repeating it, so a normal
## press is never mistaken for a hold.
@export var hold_repeat_delay: float = 0.3
## Seconds between the first repeats. Deliberately slower than the cap, so the
## player can still let go after one or two.
@export var hold_repeat_start_interval: float = 0.35
## Seconds between repeats once fully ramped up. 0.1 is ten a second.
@export var hold_repeat_min_interval: float = 0.1
## How long the hold takes to accelerate from the start interval to the cap.
@export var hold_repeat_ramp_seconds: float = 1.5


## Slots one command card holds.
func command_slot_count() -> int:
	return maxi(0, command_columns) * maxi(0, command_rows)


## The Nth letter of the grid, counting from 0 at the top left and running left
## to right, then down. "Q" for the first.
##
## The letter one square of the GRID carries, which is not always the letter
## the card draws on that square: an ability keeps the key of the square it
## claimed even when it has to sit on another one. What a given square of a
## given card draws is that card's answer, because only the card knows what is
## on it - see UnitPanel._letter_for.
##
## Empty when the rows do not reach that far, which leaves a square usable by
## mouse and simply unbound.
func grid_letter(index: int) -> String:
	return _letter_at(command_hotkey_rows, command_columns, index)


## Whether a press is the key that opens and closes the Research Center.
##
## Shift is part of the answer, exactly as it is for a square: the shifted
## letters belong to the grid's bottom rows, so Shift and this letter is a
## technology rather than the screen shutting under the player's hands.
##
## Asked rather than answered with a keycode, so the empty letter - no key at
## all - is handled here rather than in every caller.
func is_research_toggle_key(key: Key, shift_held: bool) -> bool:
	if shift_held || research_toggle_action == null:
		return false
	return research_toggle_action.matches(key)


## The letter the Research Center's own button draws, which is whatever its
## action currently answers to. Empty for a screen with no key at all.
func research_toggle_label() -> String:
	if research_toggle_action == null:
		return ""
	return research_toggle_action.label()


## Whether a key is already spoken for by the game itself, and so can never be
## handed to a rebindable action.
##
## Everything it refuses is a key a player must not be ABLE to take, rather
## than one it would merely be odd to take. See reserved_key_reason.
func is_key_reserved(key: Key) -> bool:
	return !reserved_key_reason(key).is_empty()


## The same question answered in words, so the options screen can say why it
## refused rather than only that it did. Empty means the key is free.
##
## The command card's letters are refused in BOTH layouts rather than only in
## the one in use, so switching board later can never turn a binding a player
## already made into a key that means two things at once. The rest are the keys
## the game answers wherever you are: the control groups, the two that back out
## and open the menu, and a bare modifier, which is not a key anything could
## answer to on its own.
func reserved_key_reason(key: Key) -> String:
	if key == KEY_NONE:
		return "That is not a key."
	if key == KEY_ESCAPE:
		return "Escape backs out of whatever is open."
	if key == KEY_F10:
		return "F10 opens the game menu."
	if key in MODIFIER_KEYS:
		return "A modifier on its own is not a key."
	if _is_grid_key(key):
		return "%s is a command card square." % OS.get_keycode_string(key)
	if control_group_for_key(key) > 0:
		return "%s selects a control group." % OS.get_keycode_string(key)
	return ""


## Which rebindable action currently answers to a key, or null when none does.
##
## Asked by the options screen before it binds anything, so taking a key gives
## it up wherever it was - which is how every hotkey menu behaves, and the only
## way one key can be trusted to mean one command.
func action_holding_key(key: Key, ignore: HotkeyAction = null) -> HotkeyAction:
	if key == KEY_NONE:
		return null

	for action: HotkeyAction in hotkey_actions:
		if action == null || action == ignore:
			continue
		if action.matches(key):
			return action

	return null


## Whether a key lands on a command card square in EITHER layout.
func _is_grid_key(key: Key) -> bool:
	for row: String in command_hotkey_rows:
		for column: int in range(row.length()):
			var letter: String = row[column].to_upper()
			if OS.find_keycode_from_string(letter) == key:
				return true
			if OS.find_keycode_from_string(_swapped_letter(letter)) == key:
				return true
	return false


## How many control groups there are altogether: the numbered ones, and the
## mouse buttons that carry one each when they are switched on.
##
## The two kinds share ONE index space, the mouse groups coming after the
## numbers, so everything that draws or recalls a group works in group indexes
## and never has to ask which kind it is holding.
func control_group_total() -> int:
	var total: int = maxi(0, control_group_count)
	if control_group_mouse_buttons:
		total += MOUSE_GROUP_BUTTONS.size()
	return total


## Which group a key recalls, or 0 for a key that is not one of them. The
## numbered groups run from 1, so the count is how far along the row they reach.
func control_group_for_key(key: Key) -> int:
	if control_group_count <= 0:
		return 0
	var index: int = int(key) - int(KEY_1) + 1
	if index < 1 || index > mini(control_group_count, 9):
		return 0
	return index


## Which group a mouse button recalls, or 0 for a button that is not one of
## them - which is every button on the mouse while the setting is off.
func control_group_for_button(button: MouseButton) -> int:
	if !control_group_mouse_buttons:
		return 0
	var at: int = MOUSE_GROUP_BUTTONS.find(int(button))
	if at < 0:
		return 0
	return maxi(0, control_group_count) + at + 1


## What a group's square draws in its corner. The one authority on it, so the
## picture and the press cannot disagree about which group is which.
func control_group_label(index: int) -> String:
	var numbered: int = maxi(0, control_group_count)
	if index >= 1 && index <= numbered:
		return OS.get_keycode_string((int(KEY_1) + index - 1) as Key)

	var at: int = index - numbered - 1
	if control_group_mouse_buttons && at >= 0 && at < MOUSE_GROUP_LABELS.size():
		return MOUSE_GROUP_LABELS[at]

	return ""


## Squares one Research Center grid holds.
func research_slot_count() -> int:
	return maxi(0, research_columns) * maxi(0, research_rows)


## What a Research Center square draws and answers to, modifier included:
## "Q" for the top left, "S+Q" once the rows run out of unmodified letters.
func research_hotkey_label_for_slot(slot: int) -> String:
	var letter: String = _letter_at(research_hotkey_rows, research_columns, slot)
	if letter.is_empty() || !research_needs_shift(slot):
		return letter
	return "S+%s" % letter


## Whether a square's letter is pressed with Shift held.
func research_needs_shift(slot: int) -> bool:
	if slot < 0 || research_columns <= 0:
		return false

	@warning_ignore("integer_division")
	var row: int = slot / research_columns
	return row >= research_shift_from_row


## Which Research Center square a key press lands on, or -1 for a key that is
## not one of its hotkeys.
##
## The modifier is part of the answer rather than checked by the caller,
## because the same letter means two different squares with and without it -
## which is the whole reason the bottom rows can exist at all.
func research_slot_for_key(key: Key, shift_held: bool) -> int:
	if key == KEY_NONE:
		return -1

	for slot in range(research_slot_count()):
		if research_needs_shift(slot) != shift_held:
			continue
		var letter: String = _letter_at(research_hotkey_rows, research_columns, slot)
		if !letter.is_empty() && OS.find_keycode_from_string(letter) == key:
			return slot

	return -1


## The letter one square of a grid carries, from the rows of letters that grid
## was given. Shared by the command card and the Research Center, which lay
## their keys out by exactly the same rule.
##
## The player's board is applied HERE, once, so every reader of a square -
## the letter a slot draws, the key a press lands on, both grids - follows it
## without knowing it exists.
func _letter_at(rows: PackedStringArray, columns: int, slot: int) -> String:
	if slot < 0 || columns <= 0:
		return ""

	# Integer division is the point: the quotient is the row, the remainder the
	# column.
	@warning_ignore("integer_division")
	var row: int = slot / columns
	var column: int = slot % columns
	if row >= rows.size():
		return ""

	var letters: String = rows[row]
	if column >= letters.length():
		return ""
	return _layout_letter(letters[column].to_upper())


## One authored letter as the player's board actually prints it. Y and Z trade
## places on an American board and nothing else moves, which is why this is a
## swap of two letters rather than a second set of rows to keep in step.
func _layout_letter(letter: String) -> String:
	if UserSettings.keyboard_layout != UserSettings.KeyboardLayout.AMERICAN:
		return letter
	return _swapped_letter(letter)


## The letter that trades places with this one between the two boards, or the
## letter itself when it does not move.
func _swapped_letter(letter: String) -> String:
	match letter:
		"Y":
			return "Z"
		"Z":
			return "Y"
		_:
			return letter


## Logs every row that cannot fill the card's width, and answers whether the
## layout is complete. Meant for one call at boot, the same way the damage
## table is checked.
func validate() -> bool:
	var complete: bool = true

	if command_hotkey_rows.size() < command_rows:
		Log.err("Command card has more rows than there are hotkey rows", {
			"rows": command_rows,
			"hotkey_rows": command_hotkey_rows.size(),
		})
		complete = false

	for index in range(command_hotkey_rows.size()):
		if command_hotkey_rows[index].length() >= command_columns:
			continue
		Log.err("Command card hotkey row is too short for the grid", {
			"row": index,
			"letters": command_hotkey_rows[index].length(),
			"columns": command_columns,
		})
		complete = false

	return _validate_hotkey_actions() && _validate_research() && complete


## The rebindable actions: that each has an id of its own, and that no default
## key was authored onto something the game already answers.
##
## Both are boot-time mistakes rather than runtime ones - a duplicate id means
## two commands sharing one line of the settings file, and a default on a grid
## letter means a key that does two things for every player who never opens the
## options screen.
func _validate_hotkey_actions() -> bool:
	var complete: bool = true
	var seen: Dictionary = {}

	for action: HotkeyAction in hotkey_actions:
		if action == null:
			Log.err("Controls config lists an empty hotkey action")
			complete = false
			continue
		complete = _validate_one_action(action, seen) && complete

	if research_toggle_action != null && !hotkey_actions.has(research_toggle_action):
		Log.warn("Research Center toggle is not in hotkey_actions, so it cannot be rebound", {
			"action": research_toggle_action.action_id,
		})

	return complete


func _validate_one_action(action: HotkeyAction, seen: Dictionary) -> bool:
	if action.action_id.is_empty():
		Log.err("Hotkey action has no action_id, nothing can save it", action.display_name)
		return false

	if seen.has(action.action_id):
		Log.err("Two hotkey actions claim the same action_id", action.action_id)
		return false
	seen[action.action_id] = true

	if action.default_key.is_empty():
		return true

	var key: Key = OS.find_keycode_from_string(action.default_key.to_upper()) as Key
	if key == KEY_NONE:
		Log.err("Hotkey action has a default key that is not a key", {
			"action": action.action_id,
			"key": action.default_key,
		})
		return false

	var reason: String = reserved_key_reason(key)
	if !reason.is_empty():
		Log.err("Hotkey action has a default key the game already answers", {
			"action": action.action_id,
			"key": action.default_key,
			"reason": reason,
		})
		return false

	return true


## The same two checks over the Research Center grid, which is laid out by the
## same rule and can be short in the same two ways. Its toggle key is an action
## like any other and is checked with them.
func _validate_research() -> bool:
	var complete: bool = true

	if research_hotkey_rows.size() < research_rows:
		Log.err("Research Center has more rows than there are hotkey rows", {
			"rows": research_rows,
			"hotkey_rows": research_hotkey_rows.size(),
		})
		complete = false

	for index in range(research_hotkey_rows.size()):
		if research_hotkey_rows[index].length() >= research_columns:
			continue
		Log.err("Research Center hotkey row is too short for the grid", {
			"row": index,
			"letters": research_hotkey_rows[index].length(),
			"columns": research_columns,
		})
		complete = false

	return complete
