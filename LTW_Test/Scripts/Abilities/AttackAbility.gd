class_name AttackAbility
extends UnitAbility

## Orders a unit onto one specific target.
##
## UNIT targeting, so choosing it arms the order and the next left click names
## the target. It is also the ability behind a right click on one, which is
## the same resource serving the command card and the context sensitive right
## click, exactly as Move does for the ground.
##
## What a given unit may be aimed at is the ATTACK's question and not this
## one's: a tower refuses anything that is not a creep it can reach, and an
## attacker creep refuses anything that is not a tower. So one resource sits on
## both cards and neither has to know about the other.
##
## Giving the order to a whole selection is safe: a unit that cannot reach the
## creep refuses quietly and carries on with whatever it was already shooting,
## so one click across twenty towers switches only the ones that can actually
## help. That decision lives on the attack component, which is the only thing
## that knows the range.
##
## A tower with no order still picks its own targets. This never turns the
## automatic behaviour off, it only overrides which creep is current.


func execute(unit: Unit, target: AbilityTarget) -> void:
	if unit == null || target == null:
		return
	if target.unit == null || unit.attack_component == null:
		return

	unit.attack_component.order_target(target.unit)


func can_execute(unit: Unit) -> bool:
	return unit != null && unit.attack_component != null && unit.can_attack()


## Aiming this is the one moment a player is asking how far a tower reaches,
## so arming it puts every selected unit's range circle on the ground.
func shows_attack_range() -> bool:
	return true
