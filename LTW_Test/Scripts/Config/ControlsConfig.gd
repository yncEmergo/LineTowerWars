class_name ControlsConfig
extends Resource

## Input timings, the command card layout and control group setup.
##
## Separate from GameConfig because none of this is a rule of the game - it is
## how the player drives it, and it will grow as hotkeys and rebinding arrive.

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
## which is exactly what the bottom left of the card should be. An American
## layout wants "zxcv" instead, and that swap belongs in a settings menu once
## one exists rather than being guessed at here.
@export var command_hotkey_rows: PackedStringArray = PackedStringArray([
	"qwer", "asdf", "yxcv",
])

@export_group("Research Center")
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


## Letter drawn on a slot and pressed to use it, e.g. "Q" for the top left.
## Empty when the hotkey rows do not reach that far, which leaves the slot
## usable by mouse and simply unbound.
func hotkey_letter_for_slot(slot: int) -> String:
	return _letter_at(command_hotkey_rows, command_columns, slot)


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
	return letters[column].to_upper()


## Which slot a key press lands on, or -1 for a key that is not a grid hotkey
## at all. -1 is what leaves every other key free for the rest of the game.
func slot_for_key(key: Key) -> int:
	if key == KEY_NONE:
		return -1

	for slot in range(command_slot_count()):
		var letter: String = hotkey_letter_for_slot(slot)
		if !letter.is_empty() && OS.find_keycode_from_string(letter) == key:
			return slot

	return -1


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

	return _validate_research() && complete


## The same two checks over the Research Center grid, which is laid out by the
## same rule and can be short in the same two ways.
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
