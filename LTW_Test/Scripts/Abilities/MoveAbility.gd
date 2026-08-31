class_name MoveAbility
extends UnitAbility

## Walks the unit to a ground position.
##
## Also the default ability behind a right click on the ground, so the same
## resource serves both the command card and the context-sensitive right click.
##
## An ORDER, so it can be chained behind another with shift and wipes the chain
## when it is given without one. Its task is finished when the unit stops
## moving, which is the same event whether it arrived or was stopped - both
## mean it is no longer walking to that point, and a chain that carried on
## afterwards would be walking somewhere nobody asked for.


func execute(unit: Unit, target: AbilityTarget) -> void:
	if unit == null || !target.has_position:
		return
	if !unit.has_method("move_to"):
		return
	unit.move_to(target.position)


func can_execute(unit: Unit) -> bool:
	return unit != null && unit.has_method("move_to")


func is_queueable() -> bool:
	return true


func is_task_complete(unit: Unit, _target: AbilityTarget) -> bool:
	if unit == null || !unit.has_method("is_moving"):
		return true
	return !unit.is_moving()
