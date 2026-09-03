class_name TraitPassive
extends CreepPassive

## A trait that is REAL but is not implemented here: flying, attacking, being a
## Boss. Its whole job is to appear on the creep's card and in its send tooltip.
##
## Those three are answered by CreepStats - is_flying, is_attacker, pack_size
## and lives_stolen - and they have to be, because each one decides something
## structural before any passive could be asked: how the creep moves, whether
## its prefab carries an attack at all, how many the send spawns. A passive
## holding the same answer would be a second copy of it.
##
## So this carries no mechanics on purpose. It is the card entry for a trait
## the stats file owns, and its text is authored rather than generated for the
## same reason: there is no number here to generate it from.
##
## What it DOES do is fill the numbers in. A Boss steals two lives and an
## Obsidian Statue costs three population, and both of those figures live on the
## creep's stats - so the .tres writes {lives} and {population} and they are
## replaced with whatever that creep really carries. See
## UnitAbility.description_text.


func effect_text() -> String:
	return ""


## The stats file's own numbers, for a trait description to quote without
## copying. Empty when there is no creep behind the tooltip, which leaves the
## placeholders standing rather than inventing a figure.
func description_values(context: UnitStats = null) -> Dictionary:
	var stats: CreepStats = context as CreepStats
	if stats == null:
		return {}
	return {
		"lives": stats.lives_stolen,
		"population": stats.population,
		"pack": stats.pack_size,
	}
