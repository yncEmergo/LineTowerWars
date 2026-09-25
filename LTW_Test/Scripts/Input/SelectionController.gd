class_name SelectionController
extends Node

## RTS selection: click to pick a unit, drag for a selection box.
##
## Orders and abilities live on CommandController. Move used to be handled
## here, but Move is an ability like any other, so this script now does
## selection and nothing else.
##
## Units are found through the UNIT_GROUP group and only ever duck-typed, so
## any future selectable unit works here without changing this script as long
## as it exposes selection_anchor(), selection_radius(), set_selected(),
## selection_class(), sweeps_with() and an owner_player_id.
##
## What may be selected TOGETHER is asked of the unit rather than decided here,
## and the two gestures ask two different questions. A SWEEP - a box, or a
## double click - takes one sweep group, asked with sweeps_with() against the
## unit the player actually aimed at: the type, and on a building also what
## that building is busy with. SHIFT takes anything of the same
## selection_class(), so a mixture of tower types is assembled by hand while a
## tower and the builder are never both in one selection either way.
##
## The split is deliberate: a sweep is a gesture nobody aimed at each unit it
## caught, so it has to come back with a set one command card can describe;
## shift is a player naming each unit and may mix whatever the card can still
## draw.
##
## A mixture assembled that way can then be narrowed to a SUBGROUP - one type's
## worth of it - without the selection changing at all, which is how a per-type
## command is reached without taking the selection apart. See active_subgroup.
##
## Everything it needs is shared, so it all comes through References.

## Emitted whenever the selection changes, with the currently selected units.
signal selection_changed(units: Array)
## Emitted when the active SUBGROUP changes without the selection itself
## changing, with the subgroup's units - empty for the whole selection.
##
## Separate from selection_changed deliberately. That one is what
## CommandController cancels an armed ability on, so cycling through it would
## drop an order mid-aim and reset the card stack on every press, which is the
## exact opposite of "the selection does not change".
signal subgroup_changed(units: Array)

const UNIT_GROUP: StringName = &"selectable_units"
## Pointer travel below this counts as a click rather than a drag.
const DRAG_THRESHOLD_PX: float = 6.0
## Slack added to a unit's projected radius so clicking is forgiving.
const CLICK_PADDING_PX: float = 6.0
## Floor for the projected radius, for units that project very small.
const MIN_CLICK_RADIUS_PX: float = 8.0

var _selected: Array = []
## The unit whose sweep group the command card is currently narrowed to, or
## null while the whole selection is active.
##
## The LEAD UNIT rather than an index into the groups, because the groups are
## recomputed every time the selection is pruned - an index into a set that is
## rebuilt quietly means something else afterwards, while a lead survives a
## tower of its own type dying and follows one across an upgrade.
var _subgroup_lead: Node = null

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
## Whether this click or box adds to the selection, sampled when the button
## goes down so letting go of shift mid drag cannot change what a drag means.
var _drag_additive: bool = false

var _control_groups: ControlGroups = ControlGroups.new()
## Last unit clicked and when, for spotting a double click on the same unit.
var _last_clicked_unit: Node = null
var _last_click_time: float = -1.0
## Last control group recalled and when, for spotting a double tap.
var _last_group_index: int = 0
var _last_group_time: float = -1.0

var _controls_config: ControlsConfig:
	get:
		return References.controls_config

# Everything shared comes through References rather than a second @export
# pointing at the same node.
var _camera: Camera3D:
	get:
		return References.rts_camera

var _overlay: SelectionBoxOverlay:
	get:
		return References.selection_box_overlay

var _command_controller: CommandController:
	get:
		return References.command_controller


func _ready() -> void:
	if _camera == null:
		Log.err("SelectionController found no camera on References, input is disabled")
	if _overlay == null:
		Log.err("SelectionController found no selection box overlay on References")

	# An upgraded tower is a different NODE and the same tower, so the selection
	# and the control groups both have to follow it across. References is filled
	# in _enter_tree, so the session is already there to listen to.
	var session: MatchSession = References.match_session
	if session != null:
		session.unit_replaced.connect(_on_unit_replaced)

	# DEFERRED rather than on the tick, and it has to be: this node is ready
	# before Main has built the areas, and a match opens PAUSED for its grace
	# period, which stops this node's tick while a deferred call still runs.
	# The tick stays as the fallback for a world that arrives later than that.
	_try_sender_groups.call_deferred()


## The fallback for _try_sender_groups, for as long as it has not happened.
func _physics_process(_delta: float) -> void:
	_try_sender_groups()


## Fills the default control groups once the world has the local player's send
## buildings, and then stops asking for the rest of the match.
func _try_sender_groups() -> void:
	if is_physics_processing() && _assign_sender_groups():
		set_physics_process(false)


## Puts the local player's send buildings on the first control groups - tier 1
## on group 1, and on - when the player has that option on, so a send is a
## number and a letter from the first second of a match. See game_rules.md,
## Controls.
##
## Answers whether it is DONE, either way - a machine playing nobody, or a
## player with the option off, stops asking at once.
func _assign_sender_groups() -> bool:
	if !UserSettings.sender_groups:
		return true
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return false
	var local: int = manager.local_player_id()
	if local <= 0:
		return true
	var area: PlayerArea = manager.area_for(local)
	if area == null || area.send_buildings().is_empty():
		return false

	var assigned: int = 0
	for sender: SendBuilding in area.send_buildings():
		var group: int = sender.send_tier
		if group < 1 || (_controls_config != null && group > _controls_config.control_group_count):
			continue
		_control_groups.assign(group, [sender])
		assigned += 1
	Log.info("Send buildings put on control groups", {"groups": assigned})
	return true


## The current selection. Read by CommandController when issuing orders.
func get_selection() -> Array:
	return _selected


## The numbered groups themselves, so the HUD can draw them and hear when one
## changes. Handed over rather than mirrored: a second copy of the membership
## is a second thing to keep right.
func control_groups() -> ControlGroups:
	return _control_groups


# --- Subgroups ----------------------------------------------------------

## The part of the selection the command card is currently narrowed to, or
## EMPTY while the whole selection is active.
##
## A selection holding more than one kind of unit draws only what all of them
## share, which is the right card for ordering them together and has nothing to
## say about what one KIND of them can do on its own. A subgroup is how the
## player reaches that without giving up the selection they built: the card
## swaps to one type's own abilities and the selection stays exactly as it was.
##
## Presentation plus one consequence, and nothing crosses the wire. The server
## is never told which subgroup is up - it only ever sees the units an order
## names, and narrowing them is what a card press already does. See
## CommandController.commanded_units.
func active_subgroup() -> Array:
	if _subgroup_lead == null || !is_instance_valid(_subgroup_lead):
		return []

	var group: Array = []
	for unit in _selected:
		if is_instance_valid(unit) && unit.sweeps_with(_subgroup_lead):
			group.append(unit)
	return group


## Whether a subgroup is narrowing the card right now. Asked rather than
## derived from active_subgroup().is_empty(), so a caller that only wants the
## answer does not walk the selection to get it.
func has_subgroup() -> bool:
	return _subgroup_lead != null && is_instance_valid(_subgroup_lead)


## Steps the active subgroup on by one, or back by one.
##
## The cycle is [the whole selection, group 0, ... group n-1] and wraps. That
## first state is real HERE and does not exist in Warcraft, because this panel
## draws what a mixed selection SHARES rather than one type's card: there is
## something to come back to, and a player who cycled once would otherwise have
## to rebuild their selection to reach it again.
##
## Nothing to cycle while the selection holds fewer than two groups, which
## covers every single unit and every selection of one type - narrowing to a
## group that IS the selection would change the card for no reason.
func cycle_subgroup(backwards: bool) -> void:
	var groups: Array = _subgroups()
	if groups.size() < 2:
		return

	# The whole selection sits at 0 and the groups after it, so the arithmetic
	# is one wrap over n + 1 states rather than a special case for either end.
	var at: int = 0
	if _subgroup_lead != null:
		at = _subgroup_index(groups) + 1

	var step: int = -1 if backwards else 1
	var next: int = posmod(at + step, groups.size() + 1)

	_subgroup_lead = null if next == 0 else groups[next - 1][0]
	Log.info("Subgroup changed", {"index": next, "groups": groups.size()})
	subgroup_changed.emit(active_subgroup())


## The selection split into sweep groups, in the order they first appear.
##
## Keyed on Unit.sweeps_with rather than on the stats resource, because that is
## the question the selection box already asks to come back with a set ONE
## command card can describe - and on a building it is finer than the type: a
## tower mid-upgrade and an idle one of the same type share a stats resource
## and share no card at all. Keyed on the type alone, that pair would land in
## one group whose own card is the intersection of two different cards, which
## is empty, and the feature would draw a blank card for no visible reason.
##
## FIRST-APPEARANCE order rather than an authored priority per unit type, which
## is what Warcraft uses. There are no heroes here to float to the front, and a
## mixture in this game is assembled by hand with shift - so the order the
## player built it in is the order they meant. An authored int on UnitStats is
## the fallback if play ever asks for one.
##
## Recomputed on demand and never cached: this is read on a key press and on a
## card press, never per frame, and a cache of it would need invalidating
## everywhere the selection is pruned.
func _subgroups() -> Array:
	var groups: Array = []
	var taken: Dictionary = {}

	for unit in _selected:
		if !is_instance_valid(unit) || taken.has(unit):
			continue

		var group: Array = [unit]
		taken[unit] = true
		for other in _selected:
			if other == unit || taken.has(other) || !is_instance_valid(other):
				continue
			if other.sweeps_with(unit):
				group.append(other)
				taken[other] = true
		groups.append(group)

	return groups


## Where the active lead sits in a freshly computed list of groups, or -1 when
## it is in none of them - which then reads as the whole selection, since
## cycle_subgroup adds one to it.
func _subgroup_index(groups: Array) -> int:
	for index in range(groups.size()):
		if (groups[index] as Array).has(_subgroup_lead):
			return index
	return -1


## Drops back to the whole selection. Silent, because every caller is already
## emitting selection_changed and the panel rebuilds from scratch on that.
func _clear_subgroup() -> void:
	_subgroup_lead = null


## Keeps the subgroup pointing at something real after a unit left the
## selection without going through _set_selection.
##
## The subgroup follows the TYPE rather than the unit, so one tower of it dying
## re-leads onto its neighbours and the player keeps the group they were
## working with. It only falls back to the whole selection when there is
## nothing of that type left, or when the selection no longer holds enough
## kinds for a subgroup to mean anything.
func _reseat_subgroup(departed: Node) -> void:
	if _subgroup_lead == null:
		return

	if _subgroup_lead == departed:
		_subgroup_lead = null
		for unit in _selected:
			if is_instance_valid(unit) && unit.sweeps_with(departed):
				_subgroup_lead = unit
				break

	if _subgroup_lead != null && _subgroups().size() < 2:
		_subgroup_lead = null


## Selects a group, the same way pressing its number does - including the
## double tap that also snaps the camera to it, so clicking the button twice
## behaves like pressing the key twice.
func recall_control_group(index: int) -> void:
	_recall_control_group(index)


## Narrows the selection to one unit. Used by the multi-selection panel when a
## unit's tile is clicked.
func select_single(unit: Node) -> void:
	if unit == null || !is_instance_valid(unit):
		return
	_set_selection([unit])


## Selects exactly these units, as they are. For putting back a selection that
## was set aside - the Research Center hands back what was selected when it
## opened - so no sweep and no narrowing: what was selected before is what the
## player gets back. Anything freed since is skipped.
func select_units(units: Array) -> void:
	var alive: Array = []
	for unit in units:
		if unit != null && is_instance_valid(unit):
			alive.append(unit)
	_set_selection(alive)


## Lets go of everything, as a click on empty ground does. The Research Center
## does this when it opens, because it becomes the selection itself.
func clear_selection() -> void:
	_set_selection([])


## One unit became another - a tower finished an upgrade - so everything
## holding the old one swaps to the new one in place.
##
## Called while the OLD unit is still in the tree, deliberately. Its
## tree_exiting would otherwise erase it from the selection and from every
## group a moment before this could put the replacement where it stood, and the
## player would watch their selection empty for no reason they can see.
func _on_unit_replaced(old_unit: Unit, new_unit: Unit) -> void:
	_control_groups.replace(old_unit, new_unit)

	var at: int = _selected.find(old_unit)
	if at < 0:
		return

	_stop_watching(old_unit)
	_selected[at] = new_unit
	# The subgroup follows the tower across too, the same way a control group
	# does. Its new tier is a different stats resource and so a group of its
	# own, which is right - the card it draws really has changed.
	if _subgroup_lead == old_unit:
		_subgroup_lead = new_unit
	new_unit.set_selected(true)
	_watch(new_unit)
	# A copy, for the reason every other emit here makes one.
	selection_changed.emit(_selected.duplicate())


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null || _overlay == null:
		return

	# Control groups are handled before the armed check, because recalling a
	# group is about what is selected rather than about aiming an ability.
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed && !key.echo && _handle_selection_key(key):
			get_viewport().set_input_as_handled()
		return

	# The mouse SIDE buttons carry a group each, so they are asked here for the
	# same reason and ahead of everything a mouse button otherwise means.
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null && button.pressed && _handle_control_group_button(button):
		get_viewport().set_input_as_handled()
		return

	# While an ability is armed the left click confirms its target instead of
	# selecting. Checked here as well as consumed there, so this never depends
	# on which controller happens to see the event first.
	if _command_controller != null && _command_controller.is_armed():
		_abort_drag()
		return

	if button != null && button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_begin_drag(button.position)
		else:
			_end_drag(button.position)

	elif event is InputEventMouseMotion && _dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_update_drag(motion.position)


# --- Drag selection -----------------------------------------------------

func _begin_drag(screen_pos: Vector2) -> void:
	_dragging = true
	_drag_start = screen_pos
	_drag_current = screen_pos
	# Live keyboard state rather than the event's modifier flag, for the same
	# reason as the control group keys.
	_drag_additive = Input.is_key_pressed(KEY_SHIFT)


func _update_drag(screen_pos: Vector2) -> void:
	_drag_current = screen_pos
	var rect: Rect2 = _drag_rect()
	# Only show the box once the pointer has actually travelled, so a plain
	# click never flashes a one-pixel rectangle.
	if _is_click(rect):
		_overlay.hide_box()
	else:
		_overlay.show_box(rect)


func _end_drag(screen_pos: Vector2) -> void:
	if !_dragging:
		return
	_dragging = false
	_drag_current = screen_pos
	_overlay.hide_box()

	var rect: Rect2 = _drag_rect()
	if _is_click(rect):
		# A deliberate click on a building selects it. Only the box gets the
		# units-over-buildings rule.
		_select_at_point(_drag_start, _drag_additive)
	else:
		_select_in_rect(rect, _drag_additive)


func _abort_drag() -> void:
	if !_dragging:
		return
	_dragging = false
	_overlay.hide_box()


func _drag_rect() -> Rect2:
	return Rect2(_drag_start, Vector2.ZERO).expand(_drag_current)


func _is_click(rect: Rect2) -> bool:
	return maxf(rect.size.x, rect.size.y) < DRAG_THRESHOLD_PX


# --- Selection ----------------------------------------------------------

## A click selects the unit under it. A second click on that same unit inside
## the double click window instead selects everything it sweeps with - its own
## type, and on a building only the ones busy with the same thing - which is
## the usual RTS shortcut for grabbing all your archers at once. See
## Unit.sweeps_with.
##
## Holding shift adds instead of replacing, so double click tracking is skipped
## there: shift is for assembling a selection by hand, not for grabbing a type.
func _select_at_point(screen_pos: Vector2, additive: bool) -> void:
	# A click on a creep is an attack ORDER whenever the selection holds
	# anything that can shoot it, exactly like the right click. The command
	# controller answers whether it took the click, so a creep clicked while
	# the builder or nothing is selected still simply selects, and reading a
	# creep never stops working.
	if _command_controller != null && _command_controller.try_attack_click(screen_pos):
		_forget_click()
		return

	var unit: Node = unit_at(screen_pos)
	if unit == null:
		_forget_click()
		# Shift clicking empty ground keeps what you have, so a near miss while
		# picking units apart never wipes the selection you were building.
		if !additive:
			_set_selection([])
		return

	# A creep or an enemy unit can be looked at but never commanded, so it only
	# ever selects on its own: no double click sweep, and nothing to add it to.
	if !_is_commandable(unit):
		_forget_click()
		_set_selection([unit])
		return

	if additive:
		_forget_click()
		_toggle_in_selection(unit)
		return

	if unit == _last_clicked_unit && _within_double_click(_last_click_time):
		_forget_click()
		_set_selection(_units_sweeping_with(unit))
		return

	_last_clicked_unit = unit
	_last_click_time = _now()
	_set_selection([unit])


## A box takes everything it touches. Holding shift folds that into the current
## selection rather than replacing it.
##
## Anything of the player's own outranks every creep in the box, so dragging
## across your maze still hands you the builder standing in it rather than the
## pack walking past. Only when the box caught nothing commandable at all does
## it fall back to the creeps, and then to exactly one of them.
func _select_in_rect(rect: Rect2, additive: bool) -> void:
	var caught: Array = _units_in_rect(rect)

	# Not while adding: shift is for assembling a selection by hand, and a
	# creep can never join one. Dropping through leaves the selection alone,
	# which is what shift dragging over empty ground already does.
	if caught.is_empty() && !additive:
		var creep: Node = _lone_unit_in_rect(rect)
		if creep != null:
			_set_selection([creep])
			return
		# No creep either, so this falls through to the normal path below and
		# a box over empty ground clears the selection exactly as it always has.

	if additive && !_selected.is_empty():
		var extended: Array = _selected.duplicate()
		for unit in caught:
			# The units-over-buildings rule is skipped here on purpose: the
			# existing selection already says which class is wanted, so there
			# is nothing left to disambiguate. Nor is the box narrowed to one
			# type - shift is assembling a selection by hand, so everything it
			# touched that may join, joins.
			if !extended.has(unit) && _can_join_selection(unit):
				extended.append(unit)
		_set_selection(extended)
		return

	# _drag_start rather than the rect, which has been normalised and no longer
	# remembers which of its corners the player aimed at.
	_set_selection(_sweep_group_nearest(_prefer_mobile_units(caught), _drag_start))


## The single unit a box comes back with when it caught nothing the player can
## command: the one nearest the middle of the box.
##
## One and only one, because a creep takes no orders and a panel describing a
## crowd of them would have nothing to say. Nearest the CENTRE rather than
## first found, so dragging a small box over the creep you meant reliably picks
## that creep and not whichever of its neighbours happened to be listed first.
##
## Mobile units are preferred the same way they are everywhere else, so a creep
## walking past an enemy tower wins the box over the tower.
func _lone_unit_in_rect(rect: Rect2) -> Node:
	var touched: Array = []
	for unit in _all_units():
		if _is_commandable(unit) || !_touches_rect(unit, rect):
			continue
		touched.append(unit)

	if touched.is_empty():
		return null

	return _nearest_to(_prefer_mobile_units(touched), rect.get_center())


## Whether a unit's projected circle touches the box at all. Shared by the
## commandable sweep and the single creep fallback, so both agree on what
## "inside the box" means.
func _touches_rect(unit: Node, rect: Rect2) -> bool:
	var anchor: Vector3 = unit.selection_anchor()
	if _camera.is_position_behind(anchor):
		return false

	var center: Vector2 = _camera.unproject_position(anchor)
	return _circle_touches_rect(center, _projected_radius(unit, anchor, center), rect)

## Shift clicking a unit adds it, and shift clicking one that is already
## selected takes it back out, the usual RTS way of trimming a selection down.
func _toggle_in_selection(unit: Node) -> void:
	if _selected.has(unit):
		var trimmed: Array = _selected.duplicate()
		trimmed.erase(unit)
		_set_selection(trimmed)
		return

	if !_can_join_selection(unit):
		Log.info("Unit not added, selection holds another class", {"unit": unit.name})
		return

	var extended: Array = _selected.duplicate()
	extended.append(unit)
	_set_selection(extended)


## A multi selection only ever holds one selection CLASS, which is coarser than
## the unit type: any tower joins any other tower, while a tower and the builder
## never share a selection. Unit.selection_class is where that line is drawn.
##
## The owner half of the rule is already covered by only ever searching the
## local player's own units.
##
## Some units refuse a shared selection outright, whatever class they are: the
## four senders each draw a different card, so one holding two of them would
## have to pick a card and quietly drop the other. Asked of BOTH sides, so
## adding anything to a sender is refused as firmly as adding a sender to
## anything - see Unit.allows_multi_selection().
func _can_join_selection(unit: Node) -> bool:
	if _selected.is_empty():
		return true
	if !unit.allows_multi_selection() || !_selected[0].allows_multi_selection():
		return false
	return unit.selection_class() == _selected[0].selection_class()


## Narrows a box to ONE SWEEP GROUP: whatever the unit nearest where the drag
## STARTED sweeps with, that unit first in the result. Usually its type, and on
## a building also what that building is currently busy with - see
## Unit.sweeps_with.
##
## The start of the gesture rather than the middle of the box or the type it
## caught most of, because the start is the one point the player actually
## aimed at - the box then grows to wherever they happened to let go, so both
## its centre and how many of each type fell inside it are accidents of how
## far they dragged. Putting the pointer on the Archer you want and sweeping
## across a mixture gives you the Archers.
##
## First in the result because _selected[0] is the unit the rest of the
## selection answers to: it is what a later shift click compares its class
## against, and it leads the panel.
##
## Only the box narrows like this. Assembling a mixture is what shift is for,
## and that goes through the coarser _can_join_selection instead.
func _sweep_group_nearest(units: Array, anchor: Vector2) -> Array:
	if units.size() <= 1:
		return units

	var lead: Node = _nearest_to(units, anchor)
	if lead == null:
		return units

	var result: Array = [lead]
	for unit in units:
		# The SAME question the double click asks, so the two gestures can never
		# come back with different sets - see Unit.sweeps_with. It is the type
		# plus, on a building, what that building is currently busy with:
		# a tower mid-upgrade and a tower standing idle share a stats resource
		# and share no command card at all.
		if unit != lead && unit.sweeps_with(lead):
			result.append(unit)
	return result


## The unit whose projected centre sits nearest a point on screen. Shared by
## the box's type anchor and the lone creep fallback, which differ only in
## which point they measure from - where the drag began, and the middle of the
## box it ended up as.
func _nearest_to(units: Array, point: Vector2) -> Node:
	var best: Node = null
	var best_distance: float = INF

	for unit in units:
		var screen_pos: Vector2 = _camera.unproject_position(unit.selection_anchor())
		var distance: float = screen_pos.distance_squared_to(point)
		if distance < best_distance:
			best = unit
			best_distance = distance

	return best


## Everything on the field this unit sweeps with. Ownership is already covered,
## both by only searching the local player's units and by the test itself.
func _units_sweeping_with(prototype: Node) -> Array:
	var result: Array = []
	for unit in _commandable_units():
		if unit.sweeps_with(prototype):
			result.append(unit)
	return result


func _forget_click() -> void:
	_last_clicked_unit = null
	_last_click_time = -1.0


## Monotonic, so it is unaffected by the wall clock or by pausing.
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _within_double_click(previous_time: float) -> bool:
	if previous_time < 0.0:
		return false

	var window: float = 0.5
	if _controls_config != null:
		window = _controls_config.double_click_seconds
	return (_now() - previous_time) <= window


# --- Control groups -----------------------------------------------------

## Every key this node answers, in the order it asks. The control groups come
## first because they have carried these keys since before there were
## subgroups, and a key that recalls a group can never also cycle one.
##
## Answers whether the press was taken, so a key neither of them wanted is left
## alone for the rest of the game to see.
func _handle_selection_key(key: InputEventKey) -> bool:
	if _handle_control_group_key(key):
		return true
	return _handle_subgroup_key(key)


## Tab, or whatever the player bound instead, steps the subgroup on; with shift
## it steps back.
##
## Shift is the DIRECTION here rather than a different key, which is why this
## does not ask the config about it the way the Research Center's toggle does.
##
## Refused while an ability is armed, and the key is left unconsumed: the card
## is already empty until that order resolves, so there is nothing to look at,
## and cycling underneath would quietly rewrite the set of units the player is
## part-way through aiming an order at.
func _handle_subgroup_key(key: InputEventKey) -> bool:
	if _controls_config == null \
			|| !_controls_config.is_subgroup_cycle_key(KeyPosition.of_press(key)):
		return false
	if _command_controller != null && _command_controller.is_armed():
		return false
	if _subgroups().size() < 2:
		return false

	# Live keyboard state rather than the event's own flag, for the same reason
	# the control groups and the drag read it that way.
	cycle_subgroup(Input.is_key_pressed(KEY_SHIFT))
	return true


## Control plus a number stores the selection, the number alone recalls it, and
## the number twice in quick succession also snaps the camera there.
##
## Read as raw keycodes rather than input actions because the control modifier
## would otherwise need a second action per group, doubling nine bindings to
## eighteen for no gain.
func _handle_control_group_key(key: InputEventKey) -> bool:
	if _controls_config == null:
		return false

	var index: int = _controls_config.control_group_for_key(KeyPosition.of_press(key))
	if index <= 0:
		return false

	_press_control_group(index)
	return true


## The mouse side buttons do exactly what the numbers do, and are told apart
## only by the lookup: past that point a group is a group.
func _handle_control_group_button(button: InputEventMouseButton) -> bool:
	if _controls_config == null:
		return false

	var index: int = _controls_config.control_group_for_button(button.button_index)
	if index <= 0:
		return false

	_press_control_group(index)
	return true


## What a press on a group means, whichever button carried it.
##
## Assigning NOTHING does nothing, rather than emptying the group: a habitual
## Ctrl press with nothing selected - which the open Research Center makes a
## press away, since it clears the selection - must not cost the player a group.
func _press_control_group(index: int) -> void:
	# Live keyboard state rather than the event's own modifier flag, so this
	# behaves the same for physical input and for injected events.
	if Input.is_key_pressed(KEY_CTRL):
		if _selected.is_empty():
			return
		_control_groups.assign(index, _selected)
		Log.info("Control group assigned", {"group": index, "units": _selected.size()})
		return

	_recall_control_group(index)


func _recall_control_group(index: int) -> void:
	var units: Array = _control_groups.recall(index)
	if units.is_empty():
		return

	var double_tap: bool = index == _last_group_index && _within_double_click(_last_group_time)
	_last_group_index = index
	_last_group_time = _now()

	_set_selection(units)

	# Nothing to fly to when the group holds something that stands nowhere: a
	# group of senders is a group of buttons, and snapping the camera at one
	# would throw the player's view away for no reason they could see.
	if double_tap && units[0].is_in_world():
		_center_camera_on(units[0])


func _center_camera_on(unit: Node) -> void:
	if !is_instance_valid(unit):
		return
	var camera: RTSCamera = References.rts_camera
	if camera != null:
		camera.center_on(unit.global_position)


## Topmost unit under a screen point, or null. Deliberately searches every
## unit rather than only the player's own: a creep or an enemy tower can be
## clicked to inspect it, and attack targeting will need the same pick.
## Public because ability targeting needs it too.
func unit_at(screen_pos: Vector2) -> Node:
	var best: Node = null
	var best_distance: float = INF

	for unit in _all_units():
		var anchor: Vector3 = unit.selection_anchor()
		if _camera.is_position_behind(anchor):
			continue
		var center: Vector2 = _camera.unproject_position(anchor)
		var distance: float = center.distance_to(screen_pos)
		var radius: float = _projected_radius(unit, anchor, center)
		if distance <= radius && distance < best_distance:
			best = unit
			best_distance = distance

	return best


## Converts a unit's world radius into a screen-space radius by projecting a
## point offset along the camera's right vector.
func _projected_radius(unit: Node, anchor: Vector3, center: Vector2) -> float:
	var right: Vector3 = _camera.global_transform.basis.x
	var edge_world: Vector3 = anchor + right * float(unit.selection_radius())
	if _camera.is_position_behind(edge_world):
		return MIN_CLICK_RADIUS_PX + CLICK_PADDING_PX
	var edge: Vector2 = _camera.unproject_position(edge_world)
	return maxf(center.distance_to(edge), MIN_CLICK_RADIUS_PX) + CLICK_PADDING_PX


## Catches any unit whose projected circle touches the box, rather than only
## those whose centre point falls inside it. Testing the point alone gives a
## unit a zero-sized target, so clipping a tower's base with the drag used to
## miss it. This is the same circle a click tests against, so both agree.
##
## Only what the player can actually command. A creep is never swept up here -
## it is the fallback the box takes when this comes back empty, and then only
## one of them. See _lone_unit_in_rect.
func _units_in_rect(rect: Rect2) -> Array:
	var result: Array = []
	for unit in _commandable_units():
		if _touches_rect(unit, rect):
			result.append(unit)
	return result

## Closest point on the rect to the circle's centre, then a radius test.
func _circle_touches_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest: Vector2 = Vector2(
		clampf(center.x, rect.position.x, rect.end.x),
		clampf(center.y, rect.position.y, rect.end.y)
	)
	return center.distance_squared_to(closest) <= radius * radius


## Every unit on the field, whoever owns it. Clicking is allowed to land on any
## of them, because looking at an enemy tower or at a creep is not commanding it.
##
## Only units that STAND somewhere are ever in this group, so the senders are
## absent from every pick, box and sweep below without any of them naming them.
## See Unit.is_in_world().
func _all_units() -> Array:
	return get_tree().get_nodes_in_group(UNIT_GROUP)


## Units the player can actually give orders to, which is what a selection box
## and a double click sweep are for. Both halves are asked of the unit rather
## than compared here, so there is one definition of "mine" and one of "takes
## orders".
##
## What a sweep may put TOGETHER is a separate question and is asked later, once
## there is something to compare against: see Unit.sweeps_with.
func _commandable_units() -> Array:
	var result: Array = []
	for unit in _all_units():
		if unit.is_owned_by_local_player() && unit.is_controllable():
			result.append(unit)
	return result


func _is_commandable(unit: Node) -> bool:
	return unit != null && unit.is_owned_by_local_player() && unit.is_controllable()


## A box that catches both units and buildings keeps only the units.
## Dragging across your maze should hand you the builder standing in it, not
## the twenty towers it is standing among. Buildings still box-select fine on
## their own, when nothing mobile was caught.
func _prefer_mobile_units(units: Array) -> Array:
	var mobile: Array = []
	for unit in units:
		if !unit.is_structure():
			mobile.append(unit)

	if mobile.is_empty():
		return units
	return mobile


func _set_selection(units: Array) -> void:
	# Every gesture that really changes what is selected funnels through here,
	# so one line puts the card back to what the new selection shares. A player
	# who selects something else is not still asking about the last one's type.
	_clear_subgroup()

	for unit in _selected:
		if is_instance_valid(unit) && !units.has(unit):
			unit.set_selected(false)
			_stop_watching(unit)

	for unit in units:
		unit.set_selected(true)
		_watch(unit)

	_selected = units
	Log.info("Selection changed", {"count": _selected.size()})
	# A copy, so listeners cannot end up holding the live array and seeing it
	# mutate under them when a unit later dies.
	selection_changed.emit(_selected.duplicate())


## A selected unit that dies or is sold has to leave the selection, otherwise
## the unit panel keeps describing something that no longer exists.
## The bound callable has to be rebuilt identically to test or remove it,
## because binding produces a different Callable to the bare method.
func _watch(unit: Node) -> void:
	var callback: Callable = _on_selected_unit_exiting.bind(unit)
	if !unit.tree_exiting.is_connected(callback):
		unit.tree_exiting.connect(callback)


func _stop_watching(unit: Node) -> void:
	var callback: Callable = _on_selected_unit_exiting.bind(unit)
	if unit.tree_exiting.is_connected(callback):
		unit.tree_exiting.disconnect(callback)


func _on_selected_unit_exiting(unit: Node) -> void:
	if !_selected.has(unit):
		return
	_selected.erase(unit)
	# The one path that prunes the selection without going through
	# _set_selection, so the subgroup has to be looked after by hand here.
	_reseat_subgroup(unit)
	# A copy, so listeners cannot end up holding the live array and seeing it
	# mutate under them when a unit later dies.
	selection_changed.emit(_selected.duplicate())
