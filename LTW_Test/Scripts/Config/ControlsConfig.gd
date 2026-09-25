class_name ControlsConfig
extends Resource

## Input timings, the two key grids, the fixed keys and control group setup.
##
## Separate from GameConfig because none of this is a rule of the game - it is
## how the player drives it. Docs/hotkeys.md is the whole model; this is where
## it is authored and asked.
##
## **Every key here is a POSITION, never a letter.** A grid is a shape the hand
## learns, so a square is the key in one place on the keyboard, named the way
## Godot names a physical key - the US QWERTY key in that place. The bottom left
## of the card is "z" here on every board, and draws whatever the player's own
## keyboard prints there: Y on a German one. See KeyPosition.

## Keys that are only ever held WITH another one, so binding a command to one
## alone would give it a key that never arrives on its own.
const MODIFIER_KEYS: Array[int] = [
	KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK,
]

## The keys the game answers wherever the player is, beyond the grid, the
## camera and the control groups, and why each is refused for binding. Together
## with those three this IS the fixed-key table of Docs/hotkeys.md 5:
## fixed_key_reason asks all of them, and both the Hotkeys page and the boot
## check ask it, so no key can be answered somewhere and forgotten here.
const FIXED_KEYS: Dictionary = {
	KEY_ESCAPE: "Escape backs out of whatever is open.",
	KEY_F10: "F10 opens the game menu.",
	KEY_BACKSPACE: "Backspace takes a command's key away on this page.",
	KEY_DELETE: "Delete takes a command's key away on this page.",
	KEY_KP_0: "The numpad digits are developer keys.",
	KEY_KP_1: "The numpad digits are developer keys.",
	KEY_KP_2: "The numpad digits are developer keys.",
	KEY_KP_3: "The numpad digits are developer keys.",
	KEY_KP_4: "The numpad digits are developer keys.",
	KEY_KP_5: "The numpad digits are developer keys.",
	KEY_KP_6: "The numpad digits are developer keys.",
	KEY_KP_7: "The numpad digits are developer keys.",
	KEY_KP_8: "The numpad digits are developer keys.",
	KEY_KP_9: "The numpad digits are developer keys.",
}

## The camera's pan actions. Their keys are read out of the InputMap rather than
## typed here a second time, so a key moved there is refused here without
## anybody having to remember to.
const CAMERA_ACTIONS: Array[StringName] = [
	RTSCamera.ACTION_PAN_LEFT, RTSCamera.ACTION_PAN_RIGHT,
	RTSCamera.ACTION_PAN_UP, RTSCamera.ACTION_PAN_DOWN,
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
## What steps through the subgroups of a selection holding more than one kind
## of unit, and back to the whole selection. Held with SHIFT it steps back.
##
## A command with a key of its own rather than a command card square, because it
## is not an ability and sits on no card. Nothing NAMES this action the way an
## ability names its own hotkey_action, so the reader has to be able to find it:
## hence the export.
##
## Belongs in hotkey_actions as well, which is what puts it in the options
## screen beside the others. Null, or an action with no key, leaves subgroups
## unreachable and everything else working.
@export var subgroup_cycle_action: HotkeyAction
## What selects the local player's builder, and the key its square in the
## action bar draws.
##
## Off the grid like every command with a key of its own, so it means the same
## thing whatever is selected. The one place it does not is the open Research
## Center, whose grid wins every key it covers - Docs/hotkeys.md 4.
##
## Belongs in hotkey_actions as well, for the options screen. Null, or an
## action with no key, leaves the builder reachable by its square alone.
@export var builder_select_action: HotkeyAction

@export_group("Command card")
## Shape of the command card grid, in squares.
@export var command_columns: int = 4
@export var command_rows: int = 3
## The keys of the grid, one row of key POSITIONS per row of the card, left to
## right, named as Godot names a physical key. So the bottom row reads "zxcv"
## here and draws Y X C V on a German board.
##
## The card is a grid and a square's key is read straight off its POSITION, WC3
## grid style, so an ability never names a key of its own - it names the square
## it sits in and the key follows from that. Learn the shape once and it holds
## for every unit in the game.
##
## Empty in the script on purpose: the .tres is the authority, and a default
## matching it would be stripped from it on the editor's next save.
@export var command_key_rows: PackedStringArray = PackedStringArray()
## The squares a PASSIVE may take, in the order a card fills them. CardLayout
## refuses one anywhere else, which is what keeps where to read a unit's rule in
## one place across every tower and every creep. Docs/hotkeys.md 2.
@export var passive_squares: PackedInt32Array = PackedInt32Array()
## The squares a TRAIT may take - the facts a creep's stats own, drawn on its
## card so they can be read. The bottom row. See TraitPassive.
@export var trait_squares: PackedInt32Array = PackedInt32Array()

@export_group("Rebindable keys")
## Every command that answers to a key of its own rather than to a square, in
## the order the options screen lists them.
##
## THE LIST IS THE FEATURE. The card is a grid precisely so that hundreds of
## abilities need no keys of their own, and this is the short, authored set of
## exceptions - the commands that mean the same thing on every card, plus the
## ones that are on no card. An ability joins it by naming one of these in its
## own hotkey_action, and several abilities may name the same one.
@export var hotkey_actions: Array[HotkeyAction] = []
## What every Cancel answers to. Named here because its SQUARE is a rule of its
## own: the panel puts Cancel there on every menu a card opens, so CardLayout
## keeps that square free on all of them.
@export var cancel_action: HotkeyAction

@export_group("Research Center")
## What opens the screen, and the key its button draws.
##
## Only OPENS it. While the screen is up its grid wins every key it covers, and
## this key is one of them - so it is closed by Escape, by its own close button,
## by its square on the action bar, or by selecting something. Docs/hotkeys.md 4.
##
## Belongs in hotkey_actions as well, which is what puts it in the options
## screen beside the others; this export is how the screen itself finds it.
@export var research_toggle_action: HotkeyAction
## Shape of the Research Center grid, in squares. Ten elements, five to each
## half of the grid, and three technologies across for each of them.
@export var research_columns: int = 6
@export var research_rows: int = 5
## Its keys, one row of key POSITIONS per row of the grid, named as the command
## card's are. Same rule as the card: the key belongs to the SQUARE, so a
## technology names where it sits and never which key it answers to.
##
## Empty in the script for the reason command_key_rows is.
@export var research_key_rows: PackedStringArray = PackedStringArray()
## First row whose keys are pressed with SHIFT held, drawn as "S+Q".
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


## Squares one command card holds.
func command_slot_count() -> int:
	return maxi(0, command_columns) * maxi(0, command_rows)


## The key POSITION of one square of the card, counting from 0 at the top left
## and running left to right, then down. KEY_NONE past the authored rows, which
## leaves a square usable by mouse and simply unbound.
func grid_key(square: int) -> Key:
	return _key_at(command_key_rows, command_columns, square)


## Which square of the card a key position is, or -1 for a key the grid does
## not carry.
func grid_square_for_key(physical: Key) -> int:
	if physical == KEY_NONE:
		return -1
	for square: int in range(command_slot_count()):
		if grid_key(square) == physical:
			return square
	return -1


## What one square of the card draws in its corner: the letter the player's own
## keyboard prints on that square's key.
##
## The square's OWN key. What a given square of a given card draws can differ -
## a command bound to a key of its own draws that one - which is the card's
## answer, because only the card knows what is on it. See UnitPanel.
func grid_label(square: int) -> String:
	return KeyPosition.printed_label(grid_key(square))


## Whether a press is the key that opens the Research Center. Whether the
## screen is already open, in which case its grid has the key, is the screen's
## own question.
func is_research_toggle_key(physical: Key) -> bool:
	return research_toggle_action != null && research_toggle_action.matches(self, physical)


## Whether a press is the key that steps the subgroup of a selection on. Shift
## only picks the direction, so it is not part of the question.
func is_subgroup_cycle_key(physical: Key) -> bool:
	return subgroup_cycle_action != null && subgroup_cycle_action.matches(self, physical)


## Whether a press is the key that selects the builder.
func is_builder_select_key(physical: Key) -> bool:
	return builder_select_action != null && builder_select_action.matches(self, physical)


## Why a key can never be given to a command, or empty when it can.
##
## Every key refused here is one a player must not be ABLE to take, rather than
## one it would merely be odd to take: a key the game already answers wherever
## the player is, so binding it would make one press mean two things. The grid
## keys first among them - no command may borrow a square's key, which is what
## keeps the grid learnable. The one exception, a command on the card being put
## back on its OWN square, is the caller's to allow, since only it knows which
## command is being bound. See Docs/hotkeys.md 5.
func fixed_key_reason(physical: Key) -> String:
	if physical == KEY_NONE:
		return "That is not a key."
	if int(physical) in MODIFIER_KEYS:
		return "A modifier on its own is not a key."
	if FIXED_KEYS.has(int(physical)):
		return str(FIXED_KEYS[int(physical)])
	return _answered_key_reason(physical)


## Which command currently answers to a key, or null when none does.
##
## Asked by the options screen before it binds anything, so taking a key takes
## it off whichever command had it - which is how every hotkey menu behaves,
## and the only way one key can be trusted to mean one command.
func action_holding_key(physical: Key, ignore: HotkeyAction = null) -> HotkeyAction:
	if physical == KEY_NONE:
		return null

	for action: HotkeyAction in hotkey_actions:
		if action == null || action == ignore:
			continue
		if action.matches(self, physical):
			return action

	return null


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


## Which group a key position recalls, or 0 for a key that is not one of them.
## The numbered groups run from 1, so the count is how far along the row they
## reach. Positions like every other key, so the digit row works on a board
## that types something else on it without Shift.
func control_group_for_key(physical: Key) -> int:
	if control_group_count <= 0:
		return 0
	var index: int = int(physical) - int(KEY_1) + 1
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
		return KeyPosition.printed_label((int(KEY_1) + index - 1) as Key)

	var at: int = index - numbered - 1
	if control_group_mouse_buttons && at >= 0 && at < MOUSE_GROUP_LABELS.size():
		return MOUSE_GROUP_LABELS[at]

	return ""


## Squares one Research Center grid holds.
func research_slot_count() -> int:
	return maxi(0, research_columns) * maxi(0, research_rows)


## What a Research Center square draws and answers to, modifier included:
## "Q" for the top left, "S+Q" once the rows run out of unmodified keys.
func research_label_for_slot(slot: int) -> String:
	var label: String = KeyPosition.printed_label(
		_key_at(research_key_rows, research_columns, slot))
	if label.is_empty() || !research_needs_shift(slot):
		return label
	return "S+%s" % label


## Whether a square's key is pressed with Shift held.
func research_needs_shift(slot: int) -> bool:
	if slot < 0 || research_columns <= 0:
		return false

	@warning_ignore("integer_division")
	var row: int = slot / research_columns
	return row >= research_shift_from_row


## Which Research Center square a key position lands on, or -1 for a key that
## is not one of its keys.
##
## The modifier is part of the answer rather than checked by the caller,
## because the same key means two different squares with and without it -
## which is the whole reason the bottom rows can exist at all.
func research_slot_for_key(physical: Key, shift_held: bool) -> int:
	if physical == KEY_NONE:
		return -1

	for slot in range(research_slot_count()):
		if research_needs_shift(slot) != shift_held:
			continue
		if _key_at(research_key_rows, research_columns, slot) == physical:
			return slot

	return -1


## The key position of one square of a grid, from the rows of positions that
## grid was given. Shared by the command card and the Research Center, which
## lay their keys out by exactly the same rule.
func _key_at(rows: PackedStringArray, columns: int, slot: int) -> Key:
	if slot < 0 || columns <= 0:
		return KEY_NONE

	# Integer division is the point: the quotient is the row, the remainder the
	# column.
	@warning_ignore("integer_division")
	var row: int = slot / columns
	var column: int = slot % columns
	if row >= rows.size():
		return KEY_NONE

	var keys: String = rows[row]
	if column >= keys.length():
		return KEY_NONE
	return KeyPosition.from_stored(keys[column])


## The fixed keys a SYSTEM answers rather than the table: a square of the grid,
## a control group, the camera. Empty for a key none of them answers.
func _answered_key_reason(physical: Key) -> String:
	var what: String = ""
	if grid_square_for_key(physical) >= 0:
		what = "is a command card square"
	elif control_group_for_key(physical) > 0:
		what = "selects a control group"
	elif _is_camera_key(physical):
		what = "pans the camera"
	if what.is_empty():
		return ""
	return "%s %s." % [KeyPosition.printed_label(physical), what]


## Whether a key is one the camera pans on, read out of the InputMap.
func _is_camera_key(physical: Key) -> bool:
	for action: StringName in CAMERA_ACTIONS:
		if !InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var key: InputEventKey = event as InputEventKey
			if key != null && (key.physical_keycode == physical || key.keycode == physical):
				return true
	return false


## Logs everything about the two grids and the commands that would leave a key
## unreachable or meaning two things, and answers whether the layout is
## complete. Meant for one call at boot, the same way the damage table is
## checked.
func validate() -> bool:
	var complete: bool = _validate_grid(command_key_rows, command_columns, command_rows,
		command_rows, "Command card")
	complete = _validate_grid(research_key_rows, research_columns, research_rows,
		research_shift_from_row, "Research Center") && complete
	complete = _validate_squares(passive_squares, "passive") && complete
	complete = _validate_squares(trait_squares, "trait") && complete
	return _validate_hotkey_actions() && complete


## One grid: a row of keys for every row of squares, each long enough, each key
## a real one, and no key twice on one layer - a layer being the rows pressed
## alone, or the rows pressed with Shift. A key on two squares of a layer would
## draw on both and press only the first.
func _validate_grid(rows: PackedStringArray, columns: int, row_count: int,
		shift_from_row: int, what: String) -> bool:
	var complete: bool = true
	if rows.size() < row_count:
		Log.err("A key grid has more rows than there are rows of keys", {
			"grid": what,
			"rows": row_count,
			"key_rows": rows.size(),
		})
		complete = false

	var seen: Dictionary = {}
	for row: int in range(mini(rows.size(), row_count)):
		if rows[row].length() < columns:
			Log.err("A row of keys is too short for its grid", {
				"grid": what,
				"row": row,
				"keys": rows[row].length(),
				"columns": columns,
			})
			complete = false
		for column: int in range(mini(rows[row].length(), columns)):
			var key: Key = KeyPosition.from_stored(rows[row][column])
			var layer_key: String = "%s:%d" % [row >= shift_from_row, key]
			if key == KEY_NONE || seen.has(layer_key):
				Log.err("A key grid names a key that is not one, or one key twice", {
					"grid": what,
					"row": row,
					"column": column,
					"key": rows[row][column],
				})
				complete = false
			seen[layer_key] = true

	return complete


func _validate_squares(squares: PackedInt32Array, what: String) -> bool:
	if squares.is_empty():
		Log.err("The command card names no squares for a kind of passive", what)
		return false
	for square: int in squares:
		if square < 0 || square >= command_slot_count():
			Log.err("A passive square is off the command card", {"kind": what, "square": square})
			return false
	return true


## The commands with a key of their own: an id each, a square on the card for
## the ones that sit on it, and no default key the game already answers.
##
## All boot-time mistakes rather than runtime ones - a duplicate id means two
## commands sharing one line of the settings file, and a default on a fixed key
## means a key that does two things for every player who never opens the
## options screen.
func _validate_hotkey_actions() -> bool:
	var complete: bool = true
	var ids: Dictionary = {}
	var defaults: Dictionary = {}

	for action: HotkeyAction in hotkey_actions:
		if action == null:
			Log.err("Controls config lists an empty hotkey action")
			complete = false
			continue
		complete = _validate_one_action(action, ids, defaults) && complete

	for named: HotkeyAction in [research_toggle_action, subgroup_cycle_action,
			builder_select_action, cancel_action]:
		if named != null && !hotkey_actions.has(named):
			Log.warn("A named command is not in hotkey_actions, so it cannot be rebound", {
				"action": named.action_id,
			})

	if cancel_action == null || !cancel_action.is_on_card():
		Log.err("Controls config names no Cancel on the card, menus have nowhere to put one")
		complete = false

	return complete


func _validate_one_action(action: HotkeyAction, ids: Dictionary,
		defaults: Dictionary) -> bool:
	if action.action_id.is_empty():
		Log.err("Hotkey action has no action_id, nothing can save it", action.display_name)
		return false
	if ids.has(action.action_id):
		Log.err("Two hotkey actions claim the same action_id", action.action_id)
		return false
	ids[action.action_id] = true

	var complete: bool = _validate_card_square(action) if action.is_on_card() \
		else _validate_default_key(action)
	return _claim_default(action, defaults) && complete


## A command on the card: its square is on the card. Its default_key goes
## unread, since the square is what it answers to out of the box.
func _validate_card_square(action: HotkeyAction) -> bool:
	if !action.default_key.is_empty():
		Log.warn("A command on the card answers to its square, its default_key is unused",
			action.action_id)
	if action.card_square < command_slot_count():
		return true
	Log.err("A command's square is off the command card", {
		"action": action.action_id,
		"square": action.card_square,
	})
	return false


## A command on no card: its default is a real key, and not one the game
## already answers wherever the player is. None at all is allowed.
func _validate_default_key(action: HotkeyAction) -> bool:
	if action.default_key.is_empty():
		return true
	var reason: String = fixed_key_reason(action.default_key_for(self))
	if reason.is_empty():
		return true
	Log.err("Hotkey action has a default key it cannot be given", {
		"action": action.action_id,
		"key": action.default_key,
		"reason": reason,
	})
	return false


## Two commands shipping on one key would leave one of them dead for every
## player who never opens the options screen.
func _claim_default(action: HotkeyAction, defaults: Dictionary) -> bool:
	var key: int = int(action.default_key_for(self))
	if key == KEY_NONE:
		return true
	if defaults.has(key):
		Log.err("Two commands ship on the same key", {
			"key": KeyPosition.to_stored(key as Key),
			"actions": [defaults[key], action.action_id],
		})
		return false
	defaults[key] = action.action_id
	return true
