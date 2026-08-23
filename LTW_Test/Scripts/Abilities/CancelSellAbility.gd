class_name CancelSellAbility
extends UnitAbility

## Calls off a sale that is still counting down.
##
## Nothing is refunded or charged: the building never left, so cancelling
## simply puts its normal command card back.


func execute(unit: Unit, _target: AbilityTarget) -> void:
	if unit == null || !unit.has_method("cancel_sell"):
		return
	unit.cancel_sell()


func can_execute(unit: Unit) -> bool:
	return unit != null && unit.has_method("cancel_sell")
