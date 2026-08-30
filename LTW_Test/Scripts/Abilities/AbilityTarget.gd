class_name AbilityTarget
extends RefCounted

## What an ability was aimed at.
##
## Immediate abilities get an empty target, ground abilities a position, and
## unit abilities a unit. Passing one object rather than a pile of optional
## arguments keeps execute() stable as new targeting kinds arrive.

var position: Vector3 = Vector3.ZERO
var unit: Unit = null
var has_position: bool = false
## The named unit's id, which OUTLIVES the reference above.
##
## The two say different things and a queued order needs both: `unit` is who is
## being aimed at right now and goes null the moment that unit dies, while this
## still says the order NAMED somebody. An attack task reads the difference -
## a creep that is gone finishes the task, where an order that never named one
## is an attack-move that is still walking. See AttackAbility.is_task_complete.
var unit_id: int = MatchSession.NO_UNIT


static func none() -> AbilityTarget:
	return AbilityTarget.new()


static func at_position(world_position: Vector3) -> AbilityTarget:
	var target: AbilityTarget = AbilityTarget.new()
	target.position = world_position
	target.has_position = true
	return target


static func at_unit(target_unit: Unit) -> AbilityTarget:
	var target: AbilityTarget = AbilityTarget.new()
	target.unit = target_unit
	if target_unit != null:
		target.position = target_unit.global_position
		target.has_position = true
		target.unit_id = target_unit.unit_id
	return target
