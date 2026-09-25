class_name ResearchCenter
extends Control

## The technology screen: a grid of everything a player can research, a button
## over the unit panel that opens it, and the two buttons at its foot.
##
## Laid out exactly like a command card and for the same reasons - a grid of
## squares, the key read off the POSITION, the letter drawn in the corner - but
## deeper than a card can be, so its bottom rows are the same keys with Shift
## held. ControlsConfig owns both shapes and both sets of keys.
##
## **It counts as the SELECTION.** Opening it clears whatever was selected, and
## selecting anything closes it; closing it any other way puts the old selection
## back. So the card and this grid are never both live, and while it is open it
## owns every key its grid covers - including keys that mean something
## everywhere else, like the builder's. Docs/hotkeys.md 4.
##
## **It gives no orders of its own.** A press goes to `Commands`, the one road
## every player order takes, and comes back as world state like anything else.
## Nothing here spends gold, grants a technology or checks a price: it asks
## TechManager what to grey out and hands the press over.
##
## Built on FIRST OPEN rather than in _ready, and that is forced: the HUD is a
## child of Main, a child's _ready runs before its parent's, and the technology
## registry does not exist until Main has built it. Lazy is also simply
## correct - a player who never opens the screen never pays for thirty squares.

## Grid shape used only when no ControlsConfig is wired. The real shape, and
## the letters that go with it, live there - it is how the player drives the
## game rather than a rule of it.
const FALLBACK_COLUMNS: int = 6
const FALLBACK_ROWS: int = 5

@export_group("References")
## Everything that is hidden while the screen is closed. Separate from this
## node, which stays in the tree answering the toggle key.
##
## What OPENS it is not in here: the button lives on the ActionBar, beside the
## builder and the send squares, because that is where a player looks for a
## button. This screen is opened by whoever asks, and answers its own key.
@export var _panel: Control
@export var _grid: GridContainer
## Rolls one of the twenty Ultimate towers and buys what it still needs.
@export var _random_button: Button
## Takes back the most recent press, while its window is still open. Takes back
## a whole Ultimate the same way, because that is one press too.
@export var _undo_button: Button
## Ticks the row of Ultimates below the grid on and off.
@export var _ultimates_toggle: BaseButton
## One square per Ultimate tower in the build. Hidden until the toggle is
## ticked, and it IS the row - there is no wrapper around it, so hiding it
## hides the whole feature.
@export var _ultimates_grid: GridContainer
## Made up from this when the grid is short of squares, the same way the
## command card makes up its own.
@export var _tech_slot_scene: PackedScene
## One per Ultimate. Built in code rather than authored, unlike the grid above:
## how many there are is a property of the CONTENT - one per path technology -
## where the grid's shape is a property of the KEYBOARD, which ControlsConfig
## owns and a player can change.
@export var _ultimate_button_scene: PackedScene
## Closes the screen, in its top right corner. Needed because the key that
## opens it cannot close it: while the screen is up that key is one of its
## squares.
@export var _close_button: BaseButton

var _slots: Array[TechSlot] = []
var _ultimate_buttons: Array[UltimateButton] = []
var _built: bool = false
## Whose screen this is. Fixed for the life of the match: a player never looks
## at somebody else's research.
var _player_id: int = 0
## What was selected when the screen opened, to be put back when it closes
## without anything else having been selected. Kept in step with towers that
## finish an upgrade meanwhile, which are new nodes - see _on_unit_replaced.
var _selection_before: Array = []
## True while this screen is clearing the selection itself, so it does not take
## its own clearing for the player selecting something and close again.
var _clearing_selection: bool = false

var _controls: ControlsConfig:
	get:
		return References.controls_config

var _selection: SelectionController:
	get:
		return References.selection_controller

var _manager: TechManager:
	get:
		return References.tech_manager


func _ready() -> void:
	if _panel == null || _grid == null:
		Log.err("ResearchCenter is missing its panel or its grid")
		return

	_panel.hide()
	set_process(false)
	add_to_group(HotkeyAction.READERS_GROUP)
	if _ultimates_grid != null:
		_ultimates_grid.hide()
	if _ultimates_toggle != null:
		_ultimates_toggle.toggled.connect(_on_ultimates_toggled)
	if _random_button != null:
		_random_button.pressed.connect(_on_random_pressed)
	if _undo_button != null:
		_undo_button.pressed.connect(_on_undo_pressed)
	if _close_button != null:
		_close_button.pressed.connect(close)

	var selection: SelectionController = _selection
	if selection != null:
		selection.selection_changed.connect(_on_selection_changed)
	var session: MatchSession = References.match_session
	if session != null:
		session.unit_replaced.connect(_on_unit_replaced)


## Re-reads every key this screen draws, because the player changed one in the
## options screen. Each square's letter is otherwise written once when the grid
## is built.
func refresh_hotkeys() -> void:
	if _built:
		_fill_slots()


## Opens the screen, which becomes the SELECTION: whatever was selected is
## remembered and let go, so the card empties and an order being aimed is called
## off, the same as selecting anything else does.
func open() -> void:
	if _panel == null || _panel.visible:
		return
	# A lesson can keep the Research Center shut until it is what is being
	# taught - see ActionLimits. Every road to this screen comes through here.
	var players: PlayerManager = References.player_manager
	if players != null && !ActionLimits.permits_research(players.local_player_id()):
		return
	_build()
	_take_selection()
	_panel.show()
	# This node's own processing is the two buttons at the foot. Each square
	# looks after itself and stops the moment it is off screen, so a closed
	# Research Center costs nothing either way.
	set_process(true)
	_refresh_buttons()


## Closes the screen and puts back what was selected when it opened - minus
## anything that has died since - so a look at research does not cost the
## player their builder. Escape, the close button and the action bar square all
## come here.
func close() -> void:
	if !_hide_panel():
		return
	var selection: SelectionController = _selection
	var back: Array = []
	for unit in _selection_before:
		if is_instance_valid(unit) && (unit as Node).is_inside_tree():
			back.append(unit)
	_selection_before = []
	if selection != null && !back.is_empty():
		selection.select_units(back)


func toggle() -> void:
	if _panel != null && _panel.visible:
		close()
	else:
		open()


func is_open() -> bool:
	return _panel != null && _panel.visible


## Where the open screen is drawn, in the canvas, for anything that must keep
## clear of it - the tutorial's lesson panel shares its corner. Empty while shut.
func screen_rect() -> Rect2:
	if !is_open():
		return Rect2()
	return _panel.get_global_rect()


## The square showing one technology, or null - for the tutorial to frame the
## one it wants pressed. Null before the screen has first been opened, which is
## when the squares are built.
func slot_for_tech(tech_id: int) -> Control:
	for slot in _slots:
		if slot.tech != null && slot.tech.tech_id == tech_id:
			return slot
	return null


## Handled in _input rather than _unhandled_input because a square is not a
## Control that could take a press for itself, so an open screen has to see the
## key before the world does.
##
## **While it is open it owns every key its grid covers**, and ahead of every
## key that means something everywhere else - its own key and the builder's
## included, which press the square under them. Nothing competes with the card,
## because the card is empty: the screen is the selection. Keys its grid does
## not cover keep their meaning, so a control group still recalls, and in doing
## so closes the screen. Docs/hotkeys.md 4.
##
## While it is closed the only key it answers is the one that opens it.
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null || !key.pressed || key.echo:
		return

	var config: ControlsConfig = _controls
	var physical: Key = KeyPosition.of_press(key)
	if !is_open():
		if config != null && !key.ctrl_pressed && !key.alt_pressed \
				&& config.is_research_toggle_key(physical):
			open()
			get_viewport().set_input_as_handled()
		return

	if key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return

	if config == null:
		return
	var index: int = config.research_slot_for_key(physical, key.shift_pressed)
	if index < 0:
		return

	# A key the grid covers is the grid's even on a square with nothing on it,
	# rather than falling through to whatever it means with the screen shut.
	get_viewport().set_input_as_handled()
	if index < _slots.size() && _slots[index].tech != null:
		_on_tech_activated(_slots[index].tech)


## Remembers the selection and lets it go, as opening the screen does. Guarded,
## so the screen does not mistake its own clearing for the player selecting
## something and close again.
func _take_selection() -> void:
	var selection: SelectionController = _selection
	if selection == null:
		return
	_selection_before = selection.get_selection().duplicate()
	_clearing_selection = true
	selection.clear_selection()
	_clearing_selection = false


## Hides the screen, and answers whether it was open to hide.
func _hide_panel() -> bool:
	if _panel == null || !_panel.visible:
		return false
	_panel.hide()
	set_process(false)
	# The mouse never leaves a square that is taken out from under it, so the
	# frames it lit would otherwise still be there on the next open.
	_highlight_none()
	return true


## Selecting anything while the screen is open replaces it, the way selecting
## anything replaces a unit: a click on a unit or on empty ground, a box, a
## control group, a send square, the builder square. Nothing is put back - the
## player has just said what they want selected instead.
func _on_selection_changed(_units: Array) -> void:
	if _clearing_selection || !is_open():
		return
	_selection_before = []
	_hide_panel()


## A tower that finishes an upgrade while the screen is open is a new node, and
## the one remembered would be freed a moment later. Follow it across, the way
## the selection and the control groups already do.
func _on_unit_replaced(old_unit: Unit, new_unit: Unit) -> void:
	var at: int = _selection_before.find(old_unit)
	if at >= 0:
		_selection_before[at] = new_unit


## The two buttons at the foot move on their own - the undo window runs out on
## a clock, and what can be rolled moves with gold - so they are re-read while
## the screen is open, the same way each square is.
func _process(_delta: float) -> void:
	_refresh_buttons()


# --- building it ----------------------------------------------------------

## Claims the authored squares, makes up any the configured shape is short of,
## and fills each from the technology that claims it.
##
## Runs once. The grid never changes after that: which technology sits on which
## square is authored on the technology and cannot move mid-match.
func _build() -> void:
	if _built:
		return
	_built = true

	var columns: int = FALLBACK_COLUMNS
	var wanted: int = FALLBACK_COLUMNS * FALLBACK_ROWS
	var config: ControlsConfig = _controls
	if config != null:
		columns = maxi(1, config.research_columns)
		wanted = config.research_slot_count()

	_grid.columns = columns
	for child in _grid.get_children():
		var authored: TechSlot = child as TechSlot
		if authored != null:
			_slots.append(authored)
	_fit_slot_count(wanted)

	_player_id = _local_player_id()
	for index in range(_slots.size()):
		_slots[index].name = "TechSlot%d" % index
		_slots[index].tech_activated.connect(_on_tech_activated)
	_fill_slots()
	_build_ultimates()


## One square per Ultimate tower, which is one per PATH technology - twenty of
## them, and the registry answers in ascending id order so every machine builds
## the same row.
##
## Four to a line on purpose: the ids run three to an element, so a row of four
## holds exactly the two elements that the grid above puts on one of its own
## rows of six. The two rows line up element for element without either having
## to know the other's shape.
func _build_ultimates() -> void:
	if _ultimates_grid == null || _ultimate_button_scene == null:
		return

	var session: MatchSession = References.match_session
	if session == null:
		return

	for tech in session.techs().path_techs():
		var button: UltimateButton = _ultimate_button_scene.instantiate() as UltimateButton
		if button == null:
			Log.err("Ultimate button scene does not have an UltimateButton script")
			return
		_ultimates_grid.add_child(button)
		button.set_tech(tech, _player_id)
		button.hovered.connect(_on_ultimate_hovered)
		button.unhovered.connect(_on_ultimate_unhovered)
		button.chosen.connect(_on_ultimate_chosen)
		_ultimate_buttons.append(button)

	if _ultimate_buttons.is_empty():
		Log.warn("Research Center found no Ultimates to show")


## Brings the authored squares in line with the shape ControlsConfig asks for.
## Loud when it has to, because the scene matching the config is the normal
## case and a mismatch means one of the two was changed without the other.
func _fit_slot_count(wanted: int) -> void:
	while _slots.size() > wanted:
		var extra: TechSlot = _slots.pop_back()
		_grid.remove_child(extra)
		extra.queue_free()

	if _slots.size() == wanted:
		return
	if _tech_slot_scene == null:
		Log.err("ResearchCenter has too few authored squares and no slot scene", {
			"authored": _slots.size(),
			"wanted": wanted,
		})
		return

	Log.warn("research_center.tscn does not match the configured grid shape", {
		"authored": _slots.size(),
		"wanted": wanted,
	})
	while _slots.size() < wanted:
		var slot: TechSlot = _tech_slot_scene.instantiate() as TechSlot
		if slot == null:
			Log.err("Technology slot scene does not have a TechSlot script")
			return
		_grid.add_child(slot)
		_slots.append(slot)


## Every technology into the square it claims. A technology claiming a square
## the grid does not have is reported rather than dropped quietly - it is a
## button the player would simply never find.
func _fill_slots() -> void:
	var session: MatchSession = References.match_session
	if session == null:
		Log.err("ResearchCenter found no MatchSession, it has nothing to show")
		return

	var config: ControlsConfig = _controls
	for tech in session.techs().all():
		if tech.slot < 0 || tech.slot >= _slots.size():
			Log.err("Technology claims a square outside the Research Center grid", {
				"tech": tech.display_name,
				"square": tech.slot,
				"squares": _slots.size(),
			})
			continue

		var hotkey: String = ""
		if config != null:
			hotkey = config.research_label_for_slot(tech.slot)
		_slots[tech.slot].set_tech(tech, _player_id, hotkey)


func _local_player_id() -> int:
	var players: PlayerManager = References.player_manager
	return 1 if players == null else players.local_player_id()


# --- presses --------------------------------------------------------------

## Every press leaves by the same door: a player order down the one road, which
## the server decides on. Nothing is greyed, spent or granted here, so a click
## the rules refuse simply changes nothing, exactly as a refused build does.
func _on_tech_activated(tech: TechDefinition) -> void:
	if tech != null:
		Commands.submit_player_action(Command.PlayerAction.RESEARCH, tech.tech_id)


func _on_random_pressed() -> void:
	Commands.submit_player_action(Command.PlayerAction.RANDOM_ULTIMATE)


func _on_undo_pressed() -> void:
	Commands.submit_player_action(Command.PlayerAction.UNDO_RESEARCH)


## Opening the row builds it on the first tick it is asked for, the same way
## the grid itself is built on first open, and closing it takes the frames with
## it - a square hidden under the mouse never gets its mouse_exited.
func _on_ultimates_toggled(shown: bool) -> void:
	if _ultimates_grid != null:
		_ultimates_grid.visible = shown
	if !shown:
		_highlight_none()


## Frames the four squares this Ultimate is made of. What the four ARE is
## TechManager's answer, never worked out here: the row must name the same set
## the press would buy, or it teaches the player something false.
func _on_ultimate_hovered(tech: TechDefinition) -> void:
	var manager: TechManager = _manager
	if manager == null:
		return

	var wanted: PackedInt32Array = PackedInt32Array()
	for needed in manager.ultimate_requirement(tech):
		wanted.append(needed.tech_id)
	for slot in _slots:
		slot.set_highlighted(slot.holds_any(wanted))


func _on_ultimate_unhovered(_tech: TechDefinition) -> void:
	_highlight_none()


func _highlight_none() -> void:
	for slot in _slots:
		slot.set_highlighted(false)


## Leaves by the same door every other press does. Whether the free allowance
## still covers it is TechManager's to refuse, so a click it will not take
## changes nothing - and the Undo button takes back a whole Ultimate exactly as
## it takes back one square, because the four were bought as one press.
func _on_ultimate_chosen(tech: TechDefinition) -> void:
	if tech != null:
		Commands.submit_player_action(Command.PlayerAction.CHOOSE_ULTIMATE, tech.tech_id)


## Greys the two buttons at the foot, and counts the undo window down on the
## button itself so the player can see how long they have rather than having to
## guess. Seconds rather than ticks, because a tick is not a thing a player has
## any reason to know about.
func _refresh_buttons() -> void:
	var manager: TechManager = _manager
	if manager == null:
		return

	if _random_button != null:
		_random_button.disabled = !manager.can_roll_random_ultimate(_player_id) \
			|| !ActionLimits.permits_research_shortcuts(_player_id)

	if _undo_button == null:
		return
	var ticks: int = manager.undo_ticks_left(_player_id)
	_undo_button.disabled = ticks <= 0 || !ActionLimits.permits_research_undo(_player_id)
	if ticks <= 0:
		_undo_button.text = "Undo"
	else:
		_undo_button.text = "Undo (%ds)" % ceili(ticks * MatchSession.tick_seconds())
