class_name CancelBuildAbility
extends UnitAbility

## Aborts a building that is still going up.
##
## Refunds the full price rather than the sell share, because nothing was
## gained: the tower never finished and never blocked anything for long.


func execute(unit: Unit, _target: AbilityTarget) -> void:
	if unit == null || !unit.has_method("cancel_construction"):
		return
	unit.cancel_construction()


func can_execute(unit: Unit) -> bool:
	return unit != null && unit.has_method("cancel_construction")
