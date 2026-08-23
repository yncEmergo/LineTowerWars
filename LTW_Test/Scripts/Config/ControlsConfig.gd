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
	if slot < 0 || command_columns <= 0:
		return ""

	# Integer division is the point: the quotient is the row, the remainder the
	# column.
	@warning_ignore("integer_division")
	var row: int = slot / command_columns
	var column: int = slot % command_columns
	if row >= command_hotkey_rows.size():
		return ""

	var letters: String = command_hotkey_rows[row]
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

	return complete
