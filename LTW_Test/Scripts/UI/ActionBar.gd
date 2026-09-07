class_name ActionBar
extends PanelContainer

## The two squares to the left of the send bar: select the builder, and open
## the Research Center.
##
## They are here rather than each beside the thing it reaches because a player
## looks for a BUTTON in the row of buttons. The Research Center's own toggle
## used to float on its own over the unit panel, in the same style as nothing
## else on screen; the builder had no button at all, so the only way back to it
## was to find it on the map.
##
## PRESENTATION, both of them. Selecting is local and opening a screen is local
## - nothing here spends, sends or crosses a wire. What the selection then puts
## on the unit panel is what gives orders, through Commands like everything
## else.
##
## It binds LATE and keeps trying, exactly as SendBar does and for the same
## reason: the HUD is a child of the match scene, so every node in here is ready
## before Main has created a single builder. ON THE PHYSICS TICK rather than the
## render frame, because a headless run barely has render frames at all - which
## is what left every square of the send bar dead when that was polled on
## _process.

@export_group("References")
## Selects the local player's builder. Nothing else - it gives no order and
## opens no screen.
@export var _builder_button: HudActionButton
## Opens and closes the Research Center.
@export var _research_button: HudActionButton

## The builder this bar selects, found once and held. Null until the world has
## one, and again once its owner is eliminated.
var _builder: Builder = null

var _controls: ControlsConfig:
	get:
		return References.controls_config

var _research: ResearchCenter:
	get:
		return References.research_center

var _selection: SelectionController:
	get:
		return References.selection_controller


func _ready() -> void:
	add_to_group(HotkeyAction.READERS_GROUP)
	if _builder_button != null:
		_builder_button.pressed.connect(_on_builder_pressed)
		_builder_button.tooltip_text = "Select your builder"
	if _research_button != null:
		_research_button.pressed.connect(_on_research_pressed)
		_research_button.tooltip_text = "Research Center"

	var selection: SelectionController = _selection
	if selection != null:
		selection.selection_changed.connect(_on_selection_changed)

	refresh_hotkeys()
	# Once here as well as on the tick, for a HUD that arrives after the world
	# rather than with it. Costs one failed lookup in the ordinary case.
	_bind()


## Re-reads the letter drawn on the Research Center square, because the player
## rebound it in the options screen. The builder square answers to no key, so
## it draws none.
func refresh_hotkeys() -> void:
	var config: ControlsConfig = _controls
	if _research_button == null || config == null:
		return
	_research_button.show_hotkey(config.research_toggle_label())


## The Research Center opens and closes from three places - this square, its own
## key and Escape - so which of them did it is asked rather than remembered.
func _process(_delta: float) -> void:
	if _research_button != null:
		var screen: ResearchCenter = _research
		_research_button.set_active(screen != null && screen.is_open())


func _physics_process(_delta: float) -> void:
	if _builder == null:
		_bind()


## Finds the local player's builder and takes its picture off its own stats, so
## the square shows the unit it selects rather than an icon authored twice.
##
## Scanned out of the world rather than handed over, because nothing keeps a
## builder anywhere a HUD could ask: Main creates one per player and drops them
## into the units root. It is a handful of units at the moment this runs, it
## runs once, and it stops the moment it succeeds.
func _bind() -> void:
	var session: MatchSession = References.match_session
	var players: PlayerManager = References.player_manager
	if session == null || players == null:
		return

	var local: int = players.local_player_id()
	for unit in session.live_units():
		var builder: Builder = unit as Builder
		if builder != null && builder.owner_player_id == local:
			_builder = builder
			break

	if _builder == null:
		return
	set_physics_process(false)
	if _builder_button != null && _builder.stats != null:
		_builder_button.show_icon(_builder.stats.icon)


## select_single rather than adding to the selection, because pressing this is
## how a player says "show me the builder" - joining it onto whatever was
## already selected would answer a question nobody asked.
func _on_builder_pressed() -> void:
	var selection: SelectionController = _selection
	if selection == null || _builder == null || !is_instance_valid(_builder):
		return
	selection.select_single(_builder)


func _on_research_pressed() -> void:
	var screen: ResearchCenter = _research
	if screen == null:
		Log.err("ActionBar found no ResearchCenter on References, its button does nothing")
		return
	screen.toggle()


## Lights the builder square whenever the builder is what is on the unit panel,
## including when it was reached by a click on the map or by a control group
## rather than by this button.
func _on_selection_changed(units: Array) -> void:
	if _builder_button == null:
		return
	var shown: Node = units[0] if units.size() == 1 else null
	_builder_button.set_active(_builder != null && shown == _builder)
