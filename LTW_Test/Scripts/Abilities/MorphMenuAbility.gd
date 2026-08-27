class_name MorphMenuAbility
extends UnitAbility

## Opens the Elemental Core's list of elements on the command card.
##
## The Core can become any of the ten, so ten buttons and its own three would
## want thirteen squares on a card that holds twelve. A submenu is the answer
## the game already has for exactly this - the builder's Build menu is one -
## and it is also the better read: which element you are choosing is a decision
## worth its own screen.
##
## **Not a BuildMenuAbility**, although the two are the same shape. That one is
## offered by whoever can PLACE a tower and refuses anything without
## `order_build`; this one is offered by a tower that is already standing and
## is about to be upgraded in place. Same card behaviour, different gate, and
## folding them together would mean one class asking both questions and
## answering "no" to half of them.
##
## Pure card navigation: pressing it swaps the card, and the card pops back
## when the morph is ordered or cancelled. The rules of the morph itself are
## the UpgradeTowerAbility entries inside it, which is where the technology
## gate and the price live.

@export_group("Morph menu")
## What this tower can become, in slot order. Every entry should be an
## UpgradeTowerAbility naming an element's base tower.
@export var morphs: Array[UnitAbility] = []


## A submenu never executes. Opening it is the whole behaviour.
func execute(_unit: Unit, _target: AbilityTarget) -> void:
	pass


func submenu_abilities() -> Array[UnitAbility]:
	return morphs


## Offered while the tower is standing and not already busy being something
## else, which is the same test each morph inside it makes. Deliberately NOT
## also greyed out when no element is researched: a player who has bought a
## Core and researched nothing needs to be able to open this and read what the
## ten of them would cost.
func can_execute(unit: Unit) -> bool:
	var building: Building = unit as Building
	if building == null || morphs.is_empty():
		return false
	return !building.is_under_construction() && !building.is_selling() \
		&& !building.is_upgrading()


## Everything the menu can become, so a tower reachable only through this card
## is still checked at boot - and so the whole elemental roster is reached from
## the builder in one walk. See AbilityRegistry.
func validate(seen: Dictionary) -> bool:
	var complete: bool = true
	for entry in morphs:
		var ability: UnitAbility = entry as UnitAbility
		if ability != null && !ability.validate(seen):
			complete = false
	return complete
