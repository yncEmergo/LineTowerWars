class_name CancelUpgradeAbility
extends UnitAbility

## Calls off an upgrade that is still counting down.
##
## Refunds the TIER that was being paid for and nothing else: the tower never
## left, so everything sunk into it before the upgrade stays sunk into it. The
## tower goes back to shooting and its normal card returns.
##
## A separate ability to Cancel Sale because the two hand back different money,
## and one button that meant either would be the wrong button half the time.


func execute(unit: Unit, _target: AbilityTarget) -> void:
	if unit == null || !unit.has_method("cancel_upgrade"):
		return
	unit.cancel_upgrade()


func can_execute(unit: Unit) -> bool:
	return unit != null && unit.has_method("cancel_upgrade")

