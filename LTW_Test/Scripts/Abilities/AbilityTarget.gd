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
	return target
