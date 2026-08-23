class_name StopAbility
extends UnitAbility

## Cancels whatever the unit is currently doing.
##
## For now that only means halting movement. As orders queue up and buildings
## gain construction, this is the single place that clears them.


func execute(unit: Unit, _target: AbilityTarget) -> void:
	if unit == null:
		return
	if unit.has_method("stop"):
		unit.stop()


func can_execute(unit: Unit) -> bool:
	return unit != null && unit.has_method("stop")
