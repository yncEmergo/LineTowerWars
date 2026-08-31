class_name SendBar
extends PanelContainer

## The row of four squares over the unit panel, one per creep tier.
##
## The senders stopped being buildings standing on a strip, so this row is what
## replaced walking the camera up to one. Left to right it is Tier I to Tier
## IV, always four squares whatever is built, so the square a player learned to
## reach for never moves when a tier is filled in. See SendBuilding.
##
## PRESENTATION. It selects, and selecting is local - nothing here sends
## anything, spends anything or crosses a wire. The card the selection puts on
## screen is what does that, through Commands.submit() like every other order.
##
## It binds LATE and keeps trying. The HUD is a child of the match scene, so
## every node in here is ready before Main has built a single area - which is
## where the senders live. Rather than reach for a signal that would exist only
## for this, it asks once a tick until the local area answers and then stops.
##
## ON THE PHYSICS TICK rather than the render frame, and that is not a detail:
## the tick is the beat the world appears on, and a render frame is whatever
## the machine felt like doing. A headless run barely has render frames at all,
## which is exactly where polling on _process left every square dead.

@export_group("References")
## The four squares, in tier order. Each says which tier it is, so this array
## is only the list of what to bind.
@export var _buttons: Array[SendTierButton] = []

## Whether every square has been offered its sender. Once true this stops
## looking: senders are placed with the area and never appear later.
var _bound: bool = false

var _selection: SelectionController:
	get:
		return References.selection_controller


func _ready() -> void:
	if _buttons.is_empty():
		Log.err("SendBar has no buttons in its prefab", name)

	for button in _buttons:
		if button != null:
			button.sender_picked.connect(_on_sender_picked)

	var selection: SelectionController = _selection
	if selection != null:
		selection.selection_changed.connect(_on_selection_changed)

	# Once here as well as on the tick, for a HUD that arrives after the world
	# rather than with it. Costs one failed lookup in the ordinary case.
	_bind()


func _physics_process(_delta: float) -> void:
	if _bound:
		set_physics_process(false)
		return
	_bind()


## Offers each square the sender for its tier, and reports whether the local
## area was there to ask at all.
##
## Senders are matched by their own send_tier rather than by order, so a tier
## that is not built leaves its square dead instead of shifting the ones after
## it up a place.
func _bind() -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return

	var area: PlayerArea = manager.area_for(manager.local_player_id())
	if area == null:
		return

	var by_tier: Dictionary = {}
	for sender in area.send_buildings():
		by_tier[sender.send_tier] = sender

	for button in _buttons:
		if button != null:
			button.bind(by_tier.get(button.send_tier, null) as SendBuilding)

	_bound = true
	set_physics_process(false)


## A square was pressed: select its sender, which is what puts the creep card
## on the unit panel.
##
## select_single rather than adding to the selection, because a sender joins no
## selection at all - see Unit.allows_multi_selection().
func _on_sender_picked(sender: SendBuilding) -> void:
	var selection: SelectionController = _selection
	if selection == null:
		return
	selection.select_single(sender)


## Lights whichever square opened the card currently on screen, including when
## the sender was reached by a control group rather than by a press.
func _on_selection_changed(units: Array) -> void:
	var shown: Node = units[0] if units.size() == 1 else null
	for button in _buttons:
		if button != null:
			button.set_active(button.opens(shown))
