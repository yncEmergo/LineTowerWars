class_name QueuedOrder
extends RefCounted

## One task in a unit's chain: an ability and what it was aimed at.
##
## The ability is held as a REFERENCE, because an ability is a shared resource
## that outlives every unit using it - there is nothing to dangle, and holding
## it saves a registry lookup on every tick of the task.
##
## The TARGET is named by id instead, exactly as Command names one and for the
## same two reasons: the creep a queued attack points at can die while the task
## is still waiting its turn, and an id resolves to null on its own rather than
## leaving a freed node behind. It is also already the form the wire wants.
##
## RefCounted rather than Resource, like Command and AbilityTarget: it is
## created, run and dropped, and nothing ever authors one in the editor.

## The ability this task runs. Never null on a task that reached a queue.
var ability: UnitAbility = null
## What it was aimed at, or NO_UNIT for a task aimed at the ground.
var target_unit_id: int = MatchSession.NO_UNIT
var target_position: Vector3 = Vector3.ZERO
var has_target_position: bool = false
## Whether execute() has already been called for this task. The head of a queue
## is started once and then only supervised - see OrderQueue.advance.
var started: bool = false


static func of(order_ability: UnitAbility, target: AbilityTarget) -> QueuedOrder:
	var order: QueuedOrder = QueuedOrder.new()
	order.ability = order_ability
	if target != null:
		order.target_position = target.position
		order.has_target_position = target.has_position
		if target.unit != null && is_instance_valid(target.unit):
			order.target_unit_id = target.unit.unit_id
	return order


## The same task rebuilt from what a snapshot carried, which is the drawing
## half of one and nothing else - see OrderQueue.set_replicated.
static func replicated(order_ability: UnitAbility, at: Vector3) -> QueuedOrder:
	var order: QueuedOrder = QueuedOrder.new()
	order.ability = order_ability
	order.target_position = at
	order.has_target_position = true
	return order


## What the ability is aimed at, resolved against THIS machine's registry.
##
## Rebuilt per call rather than cached, because a named unit that has since
## died has to come back null: a queued attack on a creep somebody else killed
## is a task that is already finished, and a stale AbilityTarget would hide
## that behind a reference to a freed node.
func to_target() -> AbilityTarget:
	var target: AbilityTarget = AbilityTarget.new()
	target.position = target_position
	target.has_position = has_target_position
	target.unit_id = target_unit_id
	if target_unit_id != MatchSession.NO_UNIT:
		var session: MatchSession = References.match_session
		if session != null:
			target.unit = session.unit_for(target_unit_id)
	return target


## Whether this task puts something on the ground for its owner to see: a
## waypoint dot for a walk, a grey ghost for a tower not started yet.
##
## The rule is the task's SHAPE rather than a list of abilities: a task aimed
## at a POINT is a place the unit is going, and a task aimed at a UNIT is not.
## So an attack ordered onto one creep draws nothing - its confirmation is the
## ring that blinks on the creep - while the same ability aimed at the ground
## is an attack-move and draws the walk like any other.
##
## It is also what decides what crosses the wire: a task nobody can see is a
## task no client has to be told about.
func draws_marker() -> bool:
	return has_target_position && target_unit_id == MatchSession.NO_UNIT \
		&& ability != null && ability.is_queueable()
