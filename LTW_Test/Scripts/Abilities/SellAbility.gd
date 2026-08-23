class_name SellAbility
extends UnitAbility

## Sells a building, removing it and refunding part of its invested gold.
##
## The refund share lives on GameConfig, and how much was invested lives on
## the building, so upgrades will be included automatically once they add to
## that total.


func execute(unit: Unit, _target: AbilityTarget) -> void:
	if unit == null || !unit.has_method("sell"):
		return
	unit.sell()


func can_execute(unit: Unit) -> bool:
	return unit != null && unit.has_method("sell")
