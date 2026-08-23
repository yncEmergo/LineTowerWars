class_name BuildMenuAbility
extends UnitAbility

## Opens the build menu on the command card.
##
## Pure card navigation: pressing it swaps the card for the list of towers the
## unit can build, exactly as WC3 does. The card pops back to the unit's own
## abilities once a tower is placed or the order is cancelled, which the unit
## panel handles through CommandController.command_ended.

@export_group("Build menu")
## Towers offered by this menu, in slot order. Every entry should be a
## BuildTowerAbility.
@export var buildable: Array[UnitAbility] = []


## A submenu never executes. Opening it is the whole behaviour.
func execute(_unit: Unit, _target: AbilityTarget) -> void:
	pass


func submenu_abilities() -> Array[UnitAbility]:
	return buildable


## Pointless to offer a build menu to something that cannot build.
func can_execute(unit: Unit) -> bool:
	return unit != null && unit.has_method("order_build") && !buildable.is_empty()


## Everything the menu can build, so a tower reachable only through the build
## card is still checked at boot.
func validate(seen: Dictionary) -> bool:
	var complete: bool = true
	for entry in buildable:
		var ability: UnitAbility = entry as UnitAbility
		if ability != null && !ability.validate(seen):
			complete = false
	return complete
