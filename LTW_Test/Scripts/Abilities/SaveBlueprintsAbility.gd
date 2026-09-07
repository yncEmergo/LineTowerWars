class_name SaveBlueprintsAbility
extends UnitAbility

## The builder's Save Blueprint button: opens the nine save slots.
##
## A plain SUBMENU, unlike its opposite number. Show Blueprints has to push its
## own card because a lit toggle must be able to refuse to open one; there is
## nothing to refuse here, so this is card navigation and the panel does it.
##
## The slots sit on the same squares the Show card puts its slots on, so slot 4
## answers to the same key whichever of the two cards is open. That is not a
## rule this file enforces - each slot names its own square - it is what the
## two sets of .tres are authored to, and content.md says so.

@export_group("Blueprints")
## The nine slots, in card order. Every entry should be a SaveBlueprintAbility.
@export var slots: Array[UnitAbility] = []


func execute(_unit: Unit, _target: AbilityTarget) -> void:
	pass


func submenu_abilities() -> Array[UnitAbility]:
	return slots


## Only a unit standing in an area has a maze to save. Which is every builder,
## and no tower - a tower's card must never grow this by accident.
func can_execute(unit: Unit) -> bool:
	return unit != null && unit.area != null && !slots.is_empty()


func validate(seen: Dictionary) -> bool:
	# super() first, because the base check is not about paths at all: it refuses
	# a SUBMENU that opens onto nothing, which is what an emptied .tres array
	# looks like. An override that skips it skips that. See CLAUDE.md.
	var complete: bool = super(seen)
	for entry in slots:
		var ability: UnitAbility = entry as UnitAbility
		if ability != null && !ability.validate(seen):
			complete = false
	return complete
