class_name CommandController
extends Node

## Owns ability activation and world-click targeting.
##
## Two input paths, both standard RTS:
##   right click          the unit's default ability, resolved from whatever
##                        was clicked. Ground gives Move today, a unit under
##                        the cursor will give Attack once that exists.
##   ability, then click  choosing an ability from the card or pressing its
##                        key arms it, and the next LEFT click supplies the
##                        target. Right click or Escape cancels.
##
## While an ability is armed the left click belongs here rather than to
## selection, so SelectionController checks is_armed() and stands down.
##
## **It decides what was ordered, and nothing else.** Every order leaves here
## through `Commands.submit()` rather than by calling `ability.execute()`, so
## the same click means the same thing in a solo run and over a network - the
## difference is whose world answers it. Everything on this screen that is not
## an order stays local: the selection, the build ghost, the range overlay and
## the markers below are feedback, and feedback never leaves the machine.

## Emitted when an ability starts waiting for a target.
signal ability_armed(ability: UnitAbility)
## Emitted when an armed ability resolves or is cancelled, and on Escape.
## The unit panel uses this to drop back to the unit's root card.
signal command_ended()
## Emitted when Escape was pressed with nothing armed and no submenu to leave.
## The game menu opens on this rather than binding Escape for itself, so the key
## keeps its RTS meaning - back out of whatever you are doing - and only reaches
## the menu once there is nothing left to back out of.
signal escape_unused()

var _armed: UnitAbility
var _active_marker: MoveOrderMarker

## Live only while a PLACEMENT ability is armed.
var _preview: BuildPreview = null
## Live only while an attack order is being aimed, or while Show Ranges is up.
## One overlay for the whole selection, so overlapping ranges never stack into
## a darker patch, and one for BOTH so the two can never be drawn over
## each other either.
var _range_overlay: AttackRangeOverlay = null
## Seconds left on a TIMED range reveal, or 0 when the overlay is not on a
## clock - which is what an armed attack's ranges are, since those belong to
## the order and go when it does.
var _range_reveal_left: float = 0.0
## Footprint of the armed placement in internal cells. Cached on arming so the
## per-frame preview never has to probe the prefab again.
var _armed_footprint: Vector2i = Vector2i.ZERO
## Whether what is armed will be a WALL. Cached alongside the footprint and for
## the same reason, and it decides whether the preview runs the route test at
## all - a technology disc is walkable, so no placement of one can ever be
## refused for sealing the maze. See PlayerArea.can_place.
var _armed_blocks: bool = true
## Cursor position taken from the input stream rather than polled from the
## viewport, so the preview follows the events the game actually received.
var _last_mouse_position: Vector2 = Vector2.ZERO
## Whether what is armed is armed only because SHIFT IS STILL DOWN, having
## already been fired once. Letting go of shift ends it - see _process.
##
## Without that the ability would outlive the gesture that meant it: the player
## places the last tower of a row, lets go, clicks somewhere to pick something
## up, and places a tower there instead. Holding the key is the whole of the
## intent, so it is also the whole of the lifetime.
var _held_by_chain: bool = false

# Everything shared comes through References rather than a second @export
# pointing at the same node.
var _camera: RTSCamera:
	get:
		return References.rts_camera

## Parent for short lived world effects such as the move order marker.
var _effects_root: Node3D:
	get:
		return References.effects_root

var _selection_controller: SelectionController:
	get:
		return References.selection_controller


func _ready() -> void:
	if _camera == null:
		Log.err("CommandController found no camera on References, commands are disabled")
	if _effects_root == null:
		Log.err("CommandController found no effects root on References, markers are disabled")

	# Everything this node puts on screen belongs to the SELECTION it was aimed
	# from, so a selection that changes underneath it takes the lot away.
	var selection: SelectionController = _selection_controller
	if selection != null:
		selection.selection_changed.connect(_on_selection_changed)


## A different selection ends whatever was being aimed at the old one.
##
## Two things go with it and both were bugs without this. The card is left on
## its lone CANCEL for a unit that armed nothing - ordering the builder and
## then switching to a send building showed one dead square instead of its
## creeps - and the range circles are left on the ground around units nobody is
## looking at any more.
##
## Guarded rather than called blind, so an ordinary click that only changes
## what is selected does not push a redraw through the panel for nothing.
func _on_selection_changed(_units: Array) -> void:
	if !is_armed() && !is_instance_valid(_range_overlay):
		return
	cancel()


func is_armed() -> bool:
	return _armed != null


## Whether this order is being CHAINED onto whatever the selection is already
## doing, rather than replacing it.
##
## Live keyboard state rather than an event's modifier flag, for the same
## reason SelectionController samples it that way: a click arriving through
## the panel carries no modifiers at all, and one habit has to work everywhere.
##
## Shift is already the additive-selection key and there is no clash: a left
## click that lands on something orderable is an ORDER before it is ever a
## selection - see try_attack_click - and the two gestures were never both
## available on the same click.
func _is_chaining() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


## Whether Escape has work to do here: an armed ability to drop, or a submenu
## on the card to leave. False hands the key on to the game menu.
func _has_something_to_cancel() -> bool:
	if is_armed():
		return true
	var panel: UnitPanel = References.unit_panel
	return panel != null && panel.is_in_submenu()


func armed_ability() -> UnitAbility:
	return _armed


## Entry point from the unit panel, for both slot clicks and hotkeys.
func activate_ability(ability: UnitAbility) -> void:
	if ability == null:
		return

	match ability.targeting:
		UnitAbility.Targeting.PASSIVE:
			return
		UnitAbility.Targeting.SUBMENU:
			# Pure card navigation, the panel handles it.
			return
		UnitAbility.Targeting.IMMEDIATE:
			_execute_on_selection(ability, AbilityTarget.none())
		_:
			_arm(ability)


func cancel() -> void:
	var was_armed: bool = _armed != null
	_armed = null
	_held_by_chain = false
	_end_placement()
	_set_range_circles(false)
	if was_armed:
		Log.info("Ability cancelled")
	command_ended.emit()


func _arm(ability: UnitAbility) -> void:
	_armed = ability
	# Chosen from the card, so it lives until it is fired or called off rather
	# than until a key comes up.
	_held_by_chain = false
	if ability.targeting == UnitAbility.Targeting.PLACEMENT:
		_begin_placement(ability)
	if ability.shows_attack_range():
		_set_range_circles(true)
	Log.info("Ability armed, waiting for target", {"ability": ability.display_name})
	ability_armed.emit(ability)


## Puts every selected unit's reach on the ground for as long as an order is
## being aimed, or takes it away again.
##
## Driven from here rather than from the units, because whether a range matters
## is a property of the ORDER being aimed and not of the tower. It is also ONE
## overlay for the whole selection rather than a circle each, so overlapping
## ranges cannot stack into a darker patch where two towers cover the same
## ground. See Effects/AttackRangeOverlay.gd.
func _set_range_circles(value: bool) -> void:
	# An order takes the overlay over from a reveal that was still counting
	# down, rather than the two fighting over one mesh. The newest thing the
	# player asked for is the thing they are looking at.
	_range_reveal_left = 0.0
	if !value:
		_free_range_overlay()
		return

	var overlay: AttackRangeOverlay = _ensure_range_overlay()
	if overlay != null:
		overlay.show_attack_ranges(_selected_units())


## Puts every range the selection carries - attack reach AND the radius of each
## ability that has one - on the ground for `seconds`, then takes it away.
##
## The Show Ranges ability, which is on every tower's card. Local from end to
## end: nothing here is an order, so it never reaches Commands and the server
## is never told. Safe to call again while it is already up; it redraws and
## restarts the clock.
func reveal_ranges(seconds: float) -> void:
	var overlay: AttackRangeOverlay = _ensure_range_overlay()
	if overlay == null:
		return

	overlay.show_all_ranges(_selected_units())
	_range_reveal_left = maxf(0.0, seconds)


## Counts a reveal down and takes it away when it runs out. An attack still
## being aimed underneath it gets its own circles back rather than the ground
## going blank, since that order is still waiting for its click.
func _tick_range_reveal(delta: float) -> void:
	if _range_reveal_left <= 0.0:
		return

	_range_reveal_left -= delta
	if _range_reveal_left > 0.0:
		return

	_range_reveal_left = 0.0
	if _armed != null && _armed.shows_attack_range():
		_set_range_circles(true)
	else:
		_free_range_overlay()


## The overlay, built on first use and parented to the shared effects root so a
## tower sold while it is up cannot take it with it. Null only when there is no
## effects root to hang it on.
func _ensure_range_overlay() -> AttackRangeOverlay:
	if _effects_root == null:
		return null

	if !is_instance_valid(_range_overlay):
		_range_overlay = AttackRangeOverlay.new()
		_range_overlay.name = "AttackRangeOverlay"
		_effects_root.add_child(_range_overlay)
	return _range_overlay


func _free_range_overlay() -> void:
	if is_instance_valid(_range_overlay):
		_range_overlay.queue_free()
	_range_overlay = null


## Blinks a red ring on whatever an attack order was just given on.
##
## Parented to the target, so it walks with a creep and stands still on a
## tower, and goes when it does. This is the confirmation for an attack the way
## the move marker is for a move: what was chosen is the TARGET, so pointing at
## the ground would be answering a different question.
func _show_attack_marker(target: Unit) -> void:
	if target == null || !is_instance_valid(target):
		return

	var marker: AttackTargetMarker = AttackTargetMarker.new()
	marker.name = "AttackTargetMarker"
	target.add_child(marker)
	marker.setup(target.selection_radius())

# --- Placement preview --------------------------------------------------

## Spawns the ghost footprint and caches its size, so the per-frame update is
## just a snap plus a validity test.
func _begin_placement(ability: UnitAbility) -> void:
	_end_placement()

	var build: BuildTowerAbility = ability as BuildTowerAbility
	var area: PlayerArea = _selected_area()
	if build == null || area == null || _effects_root == null:
		return

	_armed_footprint = area.cells_to_internal(build.footprint_cells())
	_armed_blocks = build.blocks_movement()
	# Seed from the real cursor, then follow input events from here on.
	_last_mouse_position = get_viewport().get_mouse_position()

	_preview = BuildPreview.new()
	_preview.name = "BuildPreview"
	_effects_root.add_child(_preview)
	_preview.setup(build.model_scene())
	_update_preview()


func _end_placement() -> void:
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_armed_footprint = Vector2i.ZERO
	_armed_blocks = true


func _process(delta: float) -> void:
	# Before everything below, because it may take the preview away.
	if _held_by_chain && !_is_chaining():
		cancel()

	if _preview != null:
		_update_preview()
	if is_instance_valid(_range_overlay):
		# Costs nothing unless the selection holds something that walks; the
		# overlay answers that question itself.
		_range_overlay.follow_units()
	_tick_range_reveal(delta)


func _update_preview() -> void:
	var area: PlayerArea = _selected_area()
	if area == null || _camera == null || !is_instance_valid(_preview):
		return

	var point: Variant = _camera.ground_point_at(_last_mouse_position)
	if point == null:
		return

	var cell: Vector2i = area.snap_footprint(point, _armed_footprint)
	var center: Vector3 = area.footprint_world_center(cell, _armed_footprint)
	var legal: bool = area.can_place(cell, _armed_footprint, _armed_blocks) \
		&& !_ghost_in_the_way(area, cell) \
		&& _can_pay_for_armed(area)
	_preview.show_at(center,
		UnitModel.Tint.VALID if legal else UnitModel.Tint.INVALID)


## Whether there is still gold for the tower being aimed, once everything
## already ordered and not yet started has been counted as spent.
##
## The ghost under the CURSOR answers the same question the ghosts already on
## the ground do, and goes red on the same terms. A single order says it too:
## the moment the gold for one drops away - a queued tower ahead of it starting
## and paying, a send going out - the thing you are aiming turns red before it
## is placed rather than after.
##
## Deliberately does NOT refuse the click. Betting on income arriving during the
## walk is a legitimate thing to ask for and is exactly what shift is already
## allowed to do (see BuildTowerAbility.can_queue), so this is a warning rather
## than a gate. A plain order is still refused by the card, which greys the
## button on the gold in hand.
func _can_pay_for_armed(area: PlayerArea) -> bool:
	var build: BuildTowerAbility = _armed as BuildTowerAbility
	var manager: PlayerManager = References.player_manager
	if build == null || area == null || manager == null:
		return true

	var state: PlayerState = manager.state_for(area.player_id)
	if state == null:
		return true

	var overlay: OrderOverlay = References.order_overlay
	var reserved: int = 0 if overlay == null else overlay.reserved_gold(area.player_id)
	return state.gold - reserved >= build.gold_cost()


## Whether a tower this player has already QUEUED is standing where the next
## one is being aimed.
##
## Local, and it has to be: the grid knows about towers that exist, and a
## queued one does not exist yet on any machine. Without this, placing a chain
## of five draws five green ghosts on top of each other and four of them fail
## on arrival for a reason the player was never shown.
func _ghost_in_the_way(area: PlayerArea, cell: Vector2i) -> bool:
	var overlay: OrderOverlay = References.order_overlay
	if overlay == null:
		return false
	return overlay.is_reserved(area, cell, _armed_footprint)


## Area of the current selection, which is whose grid a placement snaps to.
func _selected_area() -> PlayerArea:
	for unit in _selected_units():
		if is_instance_valid(unit) && unit.area != null:
			return unit.area
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return

	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed && !key.echo && key.keycode == KEY_ESCAPE:
			if _has_something_to_cancel():
				cancel()
			else:
				escape_unused.emit()
			# Consumed either way: the key was answered, by the card or by the
			# menu, and nothing below should see it a second time.
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_last_mouse_position = (event as InputEventMouseMotion).position
		return

	if !(event is InputEventMouseButton):
		return

	var button: InputEventMouseButton = event as InputEventMouseButton
	_last_mouse_position = button.position
	if !button.pressed:
		return

	if button.button_index == MOUSE_BUTTON_RIGHT:
		if is_armed():
			cancel()
		else:
			_issue_default_command(button.position)
		get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_LEFT && is_armed():
		_confirm_armed(button.position)
		get_viewport().set_input_as_handled()


# --- Execution ----------------------------------------------------------

## Left click while an ability is armed.
##
## Holding shift CHAINS the order and LEAVES THE ABILITY ARMED, exactly as it
## was: the card keeps showing it, the ghost keeps following the cursor and the
## reach stays drawn, so a row of towers is one press of the button and one
## click per tower rather than a trip back to the card between each.
##
## **The arm lasts exactly as long as SHIFT IS HELD**, which is the whole of the
## rule and is what WC3 does. Letting go releases it - the chain carries on, it
## was given to the unit and has nothing to do with the card any more, and the
## player is free to start something else on the same unit. Without that the
## ability outlives the gesture that meant it: place the last tower of a row,
## let go, click to pick something up, and place a tower there instead. See
## _process, which is where the key coming up is noticed.
func _confirm_armed(screen_pos: Vector2) -> void:
	var ability: UnitAbility = _armed
	var queued: bool = _is_chaining()
	var was_placement: bool = ability.targeting == UnitAbility.Targeting.PLACEMENT

	var target: AbilityTarget = _build_target(ability, screen_pos)
	if target != null:
		_execute_on_selection(ability, target, queued)
		_show_order_feedback(ability, target, was_placement)

	# Stays armed only for an order that could really be chained, and only when
	# one was really given: a click that landed on nothing must put the card
	# back rather than leaving the player aiming at nothing.
	_held_by_chain = queued && target != null && ability.is_queueable()
	if _held_by_chain:
		return

	_armed = null
	_set_range_circles(false)
	_end_placement()
	command_ended.emit()


## Tells the player what the order landed on.
##
## A creep gets the blinking ring, because for an attack the thing that was
## chosen is the target rather than a spot on the floor. Ground orders get the
## usual marker, and that now includes an attack aimed at the FLOOR - an
## attack-move is a walk with a temper, so it is confirmed like a walk. A build
## order needs neither: the grey ghost that appears IS the feedback, so a
## marker there would only be noise.
##
## Which of the two an attack gets is decided by what the click LANDED ON
## rather than by the ability, which is the whole point of UNIT_OR_GROUND.
func _show_order_feedback(
	ability: UnitAbility, target: AbilityTarget, was_placement: bool
) -> void:
	if target.unit != null:
		_show_attack_marker(target.unit)
		return
	if ability.targeting == UnitAbility.Targeting.UNIT:
		return

	if target.has_position && !was_placement:
		_show_move_marker(target.position)


## A left click that lands on something the selection could attack, which is an
## attack order rather than a selection.
##
## Asked by SelectionController before it selects anything, and it answers
## whether it took the click. So the same click still SELECTS whenever nothing
## in the selection could attack what was clicked - reading a creep with the
## builder selected works exactly as before, and so does clicking one of your
## own towers while attacker creeps are out in somebody else's lane.
func try_attack_click(screen_pos: Vector2) -> bool:
	if is_armed():
		return false

	var target: Unit = _unit_at(screen_pos)
	if target == null:
		return false

	return _order_attack_on(_selected_units(), target, _is_chaining())


## A right click on the MINIMAP, which hands over a WORLD point rather than a
## screen one: the square is a picture of ground the camera may be nowhere
## near, so there is no cursor to project and nothing under it to pick.
##
## Same meaning as a right click on the world otherwise - it cancels whatever
## is armed, it chains behind the current orders while shift is held, and each
## unit resolves its own default ability. What it does NOT do is attack: a dot
## on the minimap is a few pixels wide and every unit in a lane sits inside the
## same handful of them, so a click there cannot honestly claim to have picked
## one.
func issue_ground_command(world_pos: Vector3) -> void:
	if is_armed():
		cancel()
		return

	var units: Array = _selected_units()
	if units.is_empty():
		return

	var queued: bool = _is_chaining()
	var marker_at: Variant = null

	# One order per AREA, because the point is resolved inside each unit's own
	# one - see _reachable_point_in. A selection standing in two lanes at once
	# is rare but real: your creeps walk in somebody else's maze while your
	# builder is at home in yours.
	var by_area: Dictionary = _group_by_area(units)
	for area in by_area:
		var destination: Vector3 = _reachable_point_in(area as PlayerArea, world_pos)
		var target: AbilityTarget = AbilityTarget.at_position(destination)
		var by_ability: Dictionary = _group_by_default_ability(by_area[area], queued)
		for ability in by_ability:
			Commands.submit(ability as UnitAbility, by_ability[ability], target, queued)
		if marker_at == null && !by_ability.is_empty():
			marker_at = destination

	# One marker for the whole click even when two lanes were ordered, because
	# only one ever exists at a time. The first is the one nearest to hand:
	# groups keep selection order, so it belongs to whatever was picked first.
	if marker_at != null:
		_show_move_marker(marker_at as Vector3)


## Where a unit standing in `area` really ends up when it is sent to a point
## that may be anywhere on the map, including in another player's lane, in the
## black beside it, or on top of a wall.
##
## The area answers both halves. A unit may never leave its own, so the point
## is clamped into it first - which is the same rule MobileUnit.move_to applies
## on arrival, asked here as well so the marker is dropped where the walk will
## really end rather than where the mouse was. Then, only if that spot is
## inside a wall, the nearest cell that is not.
func _reachable_point_in(area: PlayerArea, world_pos: Vector3) -> Vector3:
	if area == null:
		return world_pos

	var inside: Vector3 = area.clamp_point(world_pos)
	if area.is_point_free(inside):
		return inside
	return area.nearest_free_point(inside)


## The selection split by the area each unit is standing in. A unit that stands
## in none is left out: it has nowhere a ground point could mean anything.
func _group_by_area(units: Array) -> Dictionary:
	var by_area: Dictionary = {}
	for unit in units:
		if !is_instance_valid(unit) || unit.area == null:
			continue
		if !by_area.has(unit.area):
			by_area[unit.area] = []
		by_area[unit.area].append(unit)
	return by_area


## The units of a selection grouped by the default ability each one resolves
## to, dropping any that could not be given it. One entry is one command.
func _group_by_default_ability(units: Array, queued: bool) -> Dictionary:
	var by_ability: Dictionary = {}
	for unit in units:
		if !is_instance_valid(unit):
			continue
		var ability: UnitAbility = _default_ability_for(unit)
		if ability == null || !_can_order(ability, unit, queued):
			continue
		if !by_ability.has(ability):
			by_ability[ability] = []
		by_ability[ability].append(unit)
	return by_ability


## Right click with nothing armed. Each unit resolves its own default, so a
## mixed selection does the right thing per unit rather than one blanket order.
##
## What was CLICKED decides which ability that is: a creep gives Attack to
## anything that can attack, anything else gives the unit's default. That is
## the standard RTS right click, and it is why a tower needs no separate
## attack order in the common case.
func _issue_default_command(screen_pos: Vector2) -> void:
	var units: Array = _selected_units()
	if units.is_empty():
		return

	var queued: bool = _is_chaining()
	var target_unit: Unit = _unit_at(screen_pos)
	if target_unit != null && _order_attack_on(units, target_unit, queued):
		return

	var point: Variant = _ground_point(screen_pos)
	if point == null:
		return

	var target: AbilityTarget = AbilityTarget.at_position(point)

	# Each unit resolves its OWN default, so a mixed selection is several
	# orders. Grouped by ability so it is still one message per ability rather
	# than one per unit.
	var by_ability: Dictionary = _group_by_default_ability(units, queued)
	for ability in by_ability:
		Commands.submit(ability as UnitAbility, by_ability[ability], target, queued)

	if !by_ability.is_empty():
		_show_move_marker(target.position)


## Hands a clicked unit to everything in the selection that could attack it.
##
## Whether a given unit COULD is its attack's question, asked here before the
## order exists rather than refused after it arrives: a tower can be aimed at a
## creep and never at a tower, an attacker creep the other way round. So a
## click that nothing in the selection can act on is not swallowed at all.
##
## Answers whether anything took the order, so a right click with only the
## builder selected falls through to a plain move - which is what the same
## click does in any RTS.
func _order_attack_on(units: Array, target_unit: Unit, queued: bool) -> bool:
	var target: AbilityTarget = AbilityTarget.at_unit(target_unit)

	# Grouped by ability rather than one order per unit: a mixed selection can
	# resolve to two different attacks, and each group travels as one command.
	var by_ability: Dictionary = {}
	for unit in units:
		if !is_instance_valid(unit) || unit.stats == null:
			continue
		if unit.attack_component == null || !unit.attack_component.can_target(target_unit):
			continue
		var ability: UnitAbility = unit.stats.attack_ability()
		if ability == null || !_can_order(ability, unit, queued):
			continue
		if !by_ability.has(ability):
			by_ability[ability] = []
		by_ability[ability].append(unit)

	for ability in by_ability:
		Commands.submit(ability as UnitAbility, by_ability[ability], target, queued)

	var acted: bool = !by_ability.is_empty()
	if acted:
		_show_attack_marker(target_unit)
	return acted

## The unit under a screen point, or null. Any unit: what may be attacked is
## decided per attacking unit in _order_attack_on, not by narrowing the pick to
## one type here.
func _unit_at(screen_pos: Vector2) -> Unit:
	if _selection_controller == null:
		return null
	return _selection_controller.unit_at(screen_pos) as Unit

func _default_ability_for(unit: Unit) -> UnitAbility:
	if unit == null || unit.stats == null:
		return null
	# Attack is resolved by the caller from what was clicked, so this is only
	# ever the ground answer.
	return unit.stats.default_ability


func _execute_on_selection(ability: UnitAbility, target: AbilityTarget,
		queued: bool = false) -> void:
	var units: Array = _orderable(ability, _selected_units(), queued)

	# A local-only ability changes what THIS machine draws and nothing else, so
	# sending it would be asking a server with no grid, no selection and no
	# camera to decide something it cannot see. Run here, and stop.
	if ability.is_local_only():
		for unit in units:
			ability.execute(unit, target)
		return

	Commands.submit(ability, units, target, queued)


## The units in a selection that could actually use an ability, which is what a
## card already greys out. Filtered here so an order names only units it makes
## sense for; the SERVER checks it again, because this answer was computed on
## the machine that wants the order to go through.
func _orderable(ability: UnitAbility, units: Array, queued: bool) -> Array:
	var able: Array = []
	for unit in units:
		if is_instance_valid(unit) && _can_order(ability, unit, queued):
			able.append(unit)
	return able


## Whether one unit may be given one order, asked the way the SERVER will ask
## it. The two differ for a queued build and nothing else - a tower is paid for
## when the builder reaches it - so this is the one place that knows which of
## the two questions applies, rather than every call site guessing.
func _can_order(ability: UnitAbility, unit: Unit, queued: bool) -> bool:
	if queued && ability.is_queueable():
		return ability.can_queue(unit)
	return ability.can_execute(unit)


func _selected_units() -> Array:
	if _selection_controller == null:
		return []
	return _selection_controller.get_selection()


# --- Targeting ----------------------------------------------------------

## Returns null when the click did not land on anything the ability accepts,
## which leaves the order unissued rather than guessing.
func _build_target(ability: UnitAbility, screen_pos: Vector2) -> AbilityTarget:
	var wants_unit: bool = ability.targeting == UnitAbility.Targeting.UNIT \
		|| ability.targeting == UnitAbility.Targeting.UNIT_OR_GROUND

	if wants_unit && _selection_controller != null:
		var picked: Node = _selection_controller.unit_at(screen_pos)
		if picked != null:
			return AbilityTarget.at_unit(picked as Unit)
		# UNIT alone insists on one and leaves the order unissued. Attack takes
		# the floor instead and becomes an attack-MOVE, which is the whole
		# difference between the two modes.
		if ability.targeting == UnitAbility.Targeting.UNIT:
			return null

	var point: Variant = _ground_point(screen_pos)
	if point == null:
		return null
	return AbilityTarget.at_position(point)


## Where the cursor lands on the ground, or null if it misses.
## The projection itself lives on the camera, so there is one copy of it.
func _ground_point(screen_pos: Vector2) -> Variant:
	return _camera.ground_point_at(screen_pos)


## Drops a marker where the player clicked. Any previous one is removed first,
## so repeat orders never pile markers on top of each other.
func _show_move_marker(world_position: Vector3) -> void:
	if _effects_root == null:
		return

	if is_instance_valid(_active_marker):
		_active_marker.queue_free()

	var marker: MoveOrderMarker = MoveOrderMarker.new()
	_effects_root.add_child(marker)
	marker.place_at(world_position)
	_active_marker = marker
