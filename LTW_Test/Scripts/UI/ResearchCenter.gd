class_name ResearchCenter
extends Control

## The technology screen: a grid of everything a player can research, a button
## over the unit panel that opens it, and the two buttons at its foot.
##
## Laid out exactly like a command card and for the same reasons - a grid of
## squares, the key read off the POSITION, the letter drawn in the corner - but
## deeper than a card can be, so its bottom rows are the same letters with
## Shift held. ControlsConfig owns both shapes and both sets of letters.
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
## Opens and closes the screen. Sits over the unit panel, which is where the
## source game puts it.
@export var _toggle_button: Button
## Everything that is hidden while the screen is closed. Separate from this
## node, which stays visible so the toggle button does.
@export var _panel: Control
@export var _grid: GridContainer
## Rolls one of the twenty Ultimate towers and buys what it still needs.
@export var _random_button: Button
## Takes back the most recent press, while its window is still open.
@export var _undo_button: Button
## Made up from this when the grid is short of squares, the same way the
## command card makes up its own.
@export var _tech_slot_scene: PackedScene

var _slots: Array[TechSlot] = []
var _built: bool = false
## Whose screen this is. Fixed for the life of the match: a player never looks
## at somebody else's research.
var _player_id: int = 0

var _controls: ControlsConfig:
	get:
		return References.controls_config

var _manager: TechManager:
	get:
		return References.tech_manager


func _ready() -> void:
	if _panel == null || _grid == null:
		Log.err("ResearchCenter is missing its panel or its grid")
		return

	_panel.hide()
	set_process(false)
	if _toggle_button != null:
		_toggle_button.pressed.connect(toggle)
	if _random_button != null:
		_random_button.pressed.connect(_on_random_pressed)
	if _undo_button != null:
		_undo_button.pressed.connect(_on_undo_pressed)


func open() -> void:
	if _panel == null || _panel.visible:
		return
	_build()
	_panel.show()
	# This node's own processing is the two buttons at the foot. Each square
	# looks after itself and stops the moment it is off screen, so a closed
	# Research Center costs nothing either way.
	set_process(true)
	_refresh_buttons()


func close() -> void:
	if _panel == null || !_panel.visible:
		return
	_panel.hide()
	set_process(false)


func toggle() -> void:
	if _panel != null && _panel.visible:
		close()
	else:
		open()


func is_open() -> bool:
	return _panel != null && _panel.visible


## Handled in _input rather than _unhandled_input so an open screen wins its
## keys ahead of the command card, the way the game menu does. That is
## deliberate: while it is open, a letter is a technology rather than whatever
## the selected unit's card puts there.
##
## The BUILDER is the one exception, because it is what a player has selected
## while they research and taking its card away for as long as this screen is
## open would make building and researching mutually exclusive. So a key the
## builder's card answers is left to the builder, and only a key it leaves
## alone reaches a square here.
##
## Nothing is consumed while it is closed, and a key that lands on no square is
## left alone, so the rest of the game's keys are untouched either way.
func _input(event: InputEvent) -> void:
	if !is_open():
		return

	var key: InputEventKey = event as InputEventKey
	if key == null || !key.pressed || key.echo:
		return

	if key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return

	var config: ControlsConfig = _controls
	if config == null:
		return

	var index: int = config.research_slot_for_key(key.keycode, key.shift_pressed)
	if index < 0 || index >= _slots.size() || _slots[index].tech == null:
		return
	if _builder_answers(key):
		return

	_on_tech_activated(_slots[index].tech)
	get_viewport().set_input_as_handled()


## Whether the builder's command card would answer this press, in which case
## the press is the builder's and not this screen's.
##
## Only unmodified letters: the command card ignores Shift, so the shifted
## rows down here are letters no card can ever claim and stay reachable with
## the builder selected. A square the builder leaves empty is not claimed
## either, which is the same rule the card itself follows.
func _builder_answers(key: InputEventKey) -> bool:
	if key.shift_pressed:
		return false

	var panel: UnitPanel = References.unit_panel
	if panel == null:
		return false
	return panel.shown_unit() is Builder && panel.claims_key(key.keycode)


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
			hotkey = config.research_hotkey_label_for_slot(tech.slot)
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


## Greys the two buttons at the foot, and counts the undo window down on the
## button itself so the player can see how long they have rather than having to
## guess. Seconds rather than ticks, because a tick is not a thing a player has
## any reason to know about.
func _refresh_buttons() -> void:
	var manager: TechManager = _manager
	if manager == null:
		return

	if _random_button != null:
		_random_button.disabled = !manager.can_roll_random_ultimate(_player_id)

	if _undo_button == null:
		return
	var ticks: int = manager.undo_ticks_left(_player_id)
	_undo_button.disabled = ticks <= 0
	if ticks <= 0:
		_undo_button.text = "Undo"
	else:
		_undo_button.text = "Undo (%ds)" % ceili(ticks * MatchSession.tick_seconds())
