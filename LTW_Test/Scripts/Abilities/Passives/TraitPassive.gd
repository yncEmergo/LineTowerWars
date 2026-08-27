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


func effect_text() -> String:
	return ""
