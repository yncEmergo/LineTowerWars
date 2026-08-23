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
## Live only while an attack order is being aimed. One overlay for the whole
## selection, so overlapping ranges never stack into a darker patch.
var _range_overlay: AttackRangeOverlay = null
## Footprint of the armed placement in internal cells. Cached on arming so the
## per-frame preview never has to probe the prefab again.
var _armed_footprint: Vector2i = Vector2i.ZERO
## Cursor position taken from the input stream rather than polled from the
## viewport, so the preview follows the events the game actually received.
var _last_mouse_position: Vector2 = Vector2.ZERO

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


func is_armed() -> bool:
	return _armed != null


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
	_end_placement()
	_set_range_circles(false)
	if was_armed:
		Log.info("Ability cancelled")
	command_ended.emit()


func _arm(ability: UnitAbility) -> void:
	_armed = ability
	if ability.targeting == UnitAbility.Targeting.PLACEMENT:
		_begin_placement(ability)
	if ability.shows_attack_range():
		_set_range_circles(true)
	Log.info("Ability armed, waiting for target", {"ability": ability.display_name})
	ability_armed.emit(ability)


## Puts every selected unit's reach on the ground, or takes it away again.
##
## Driven from here rather than from the units, because whether a range matters
## is a property of the ORDER being aimed and not of the tower. It is also ONE
## overlay for the whole selection rather than a circle each, so overlapping
## ranges cannot stack into a darker patch where two towers cover the same
## ground. See Effects/AttackRangeOverlay.gd.
func _set_range_circles(value: bool) -> void:
	if !value:
		if is_instance_valid(_range_overlay):
			_range_overlay.queue_free()
		_range_overlay = null
		return

	if _effects_root == null:
		return

	if !is_instance_valid(_range_overlay):
		_range_overlay = AttackRangeOverlay.new()
		_range_overlay.name = "AttackRangeOverlay"
		_effects_root.add_child(_range_overlay)

	_range_overlay.show_ranges(_selected_units())


## Blinks a red ring on the creep an attack order was just given on.
##
## Parented to the creep, so it walks with it and goes with it. This is the
## confirmation for an attack the way the move marker is for a move: what was
## chosen is the TARGET, so pointing at the ground would be answering a
## different question.
func _show_attack_marker(creep: Creep) -> void:
	if creep == null || !is_instance_valid(creep):
		return

	var marker: AttackTargetMarker = AttackTargetMarker.new()
	marker.name = "AttackTargetMarker"
	creep.add_child(marker)
	marker.setup(creep.selection_radius())

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


func _process(_delta: float) -> void:
	if _preview != null:
		_update_preview()


func _update_preview() -> void:
	var area: PlayerArea = _selected_area()
	if area == null || _camera == null || !is_instance_valid(_preview):
		return

	var point: Variant = _camera.ground_point_at(_last_mouse_position)
	if point == null:
		return

	var cell: Vector2i = area.snap_footprint(point, _armed_footprint)
	var center: Vector3 = area.footprint_world_center(cell, _armed_footprint)
	_preview.show_at(center, area.can_place(cell, _armed_footprint))


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
func _confirm_armed(screen_pos: Vector2) -> void:
	var ability: UnitAbility = _armed
	_armed = null
	var was_placement: bool = ability.targeting == UnitAbility.Targeting.PLACEMENT
	_set_range_circles(false)
	_end_placement()

	var target: AbilityTarget = _build_target(ability, screen_pos)
	if target != null:
		_execute_on_selection(ability, target)
		_show_order_feedback(ability, target, was_placement)

	command_ended.emit()


## Tells the player what the order landed on.
##
## A creep gets the blinking ring, because for an attack the thing that was
## chosen is the target rather than a spot on the floor. Ground orders get the
## usual marker. A build order needs neither: the tower appearing IS the
## feedback, so a marker there would only be noise.
func _show_order_feedback(
	ability: UnitAbility, target: AbilityTarget, was_placement: bool
) -> void:
	if ability.targeting == UnitAbility.Targeting.UNIT:
		_show_attack_marker(target.unit as Creep)
		return

	if target.has_position && !was_placement:
		_show_move_marker(target.position)


## A left click that lands on a creep while something that can attack is
## selected, which is an attack order rather than a selection.
##
## Asked by SelectionController before it selects anything, and it answers
## whether it took the click. So the same click still selects a creep whenever
## nothing in the selection could attack it - clicking a creep to read it works
## exactly as before while the builder, or nothing, is selected.
func try_attack_click(screen_pos: Vector2) -> bool:
	if is_armed():
		return false

	var creep: Creep = _creep_at(screen_pos)
	if creep == null:
		return false

	return _order_attack_on(_selected_units(), creep)

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

	var creep: Creep = _creep_at(screen_pos)
	if creep != null && _order_attack_on(units, creep):
		return

	var point: Variant = _ground_point(screen_pos)
	if point == null:
		return

	var target: AbilityTarget = AbilityTarget.at_position(point)

	# Each unit resolves its OWN default, so a mixed selection is several
	# orders. Grouped by ability so it is still one message per ability rather
	# than one per unit.
	var by_ability: Dictionary = {}
	for unit in units:
		if !is_instance_valid(unit):
			continue
		var ability: UnitAbility = _default_ability_for(unit)
		if ability == null || !ability.can_execute(unit):
			continue
		if !by_ability.has(ability):
			by_ability[ability] = []
		by_ability[ability].append(unit)

	for ability in by_ability:
		Commands.submit(ability as UnitAbility, by_ability[ability], target)

	if !by_ability.is_empty():
		_show_move_marker(target.position)


## Hands a clicked creep to everything in the selection that can attack.
##
## Answers whether anything took the order at all, so a right click on a creep
## with only the builder selected falls through to a plain move rather than
## being swallowed - which is what the same click does in any RTS.
func _order_attack_on(units: Array, creep: Creep) -> bool:
	var target: AbilityTarget = AbilityTarget.at_unit(creep)

	# Grouped by ability rather than one order per unit: a mixed selection can
	# resolve to two different attacks, and each group travels as one command.
	var by_ability: Dictionary = {}
	for unit in units:
		if !is_instance_valid(unit) || unit.stats == null:
			continue
		var ability: UnitAbility = unit.stats.attack_ability()
		if ability == null || !ability.can_execute(unit):
			continue
		if !by_ability.has(ability):
			by_ability[ability] = []
		by_ability[ability].append(unit)

	for ability in by_ability:
		Commands.submit(ability as UnitAbility, by_ability[ability], target)

	var acted: bool = !by_ability.is_empty()
	if acted:
		_show_attack_marker(creep)
	return acted

## The creep under a screen point, or null. Only creeps: a right click on a
## tower is not an order, and there is no friendly fire to aim.
func _creep_at(screen_pos: Vector2) -> Creep:
	if _selection_controller == null:
		return null
	return _selection_controller.unit_at(screen_pos) as Creep

func _default_ability_for(unit: Unit) -> UnitAbility:
	if unit == null || unit.stats == null:
		return null
	# Attack is resolved by the caller from what was clicked, so this is only
	# ever the ground answer.
	return unit.stats.default_ability


func _execute_on_selection(ability: UnitAbility, target: AbilityTarget) -> void:
	var units: Array = _orderable(ability, _selected_units())

	# A local-only ability changes what THIS machine draws and nothing else, so
	# sending it would be asking a server with no grid, no selection and no
	# camera to decide something it cannot see. Run here, and stop.
	if ability.is_local_only():
		for unit in units:
			ability.execute(unit, target)
		return

	Commands.submit(ability, units, target)


## The units in a selection that could actually use an ability, which is what a
## card already greys out. Filtered here so an order names only units it makes
## sense for; the SERVER checks it again, because this answer was computed on
## the machine that wants the order to go through.
func _orderable(ability: UnitAbility, units: Array) -> Array:
	var able: Array = []
	for unit in units:
		if is_instance_valid(unit) && ability.can_execute(unit):
			able.append(unit)
	return able


func _selected_units() -> Array:
	if _selection_controller == null:
		return []
	return _selection_controller.get_selection()


# --- Targeting ----------------------------------------------------------

## Returns null when the click did not land on anything the ability accepts,
## which leaves the order unissued rather than guessing.
func _build_target(ability: UnitAbility, screen_pos: Vector2) -> AbilityTarget:
	if ability.targeting == UnitAbility.Targeting.UNIT:
		if _selection_controller == null:
			return null
		# Only the local player's units are pickable so far. Enemy targeting
		# needs a wider search once attacking exists.
		var picked: Node = _selection_controller.unit_at(screen_pos)
		if picked == null:
			return null
		return AbilityTarget.at_unit(picked as Unit)

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
