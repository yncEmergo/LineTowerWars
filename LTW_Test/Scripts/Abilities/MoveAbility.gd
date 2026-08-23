class_name MoveAbility
extends UnitAbility

## Walks the unit to a ground position.
##
## Also the default ability behind a right click on the ground, so the same
## resource serves both the command card and the context-sensitive right click.


func execute(unit: Unit, target: AbilityTarget) -> void:
	if unit == null || !target.has_position:
		return
	if !unit.has_method("move_to"):
		return
	unit.move_to(target.position)


func can_execute(unit: Unit) -> bool:
	return unit != null && unit.has_method("move_to")
