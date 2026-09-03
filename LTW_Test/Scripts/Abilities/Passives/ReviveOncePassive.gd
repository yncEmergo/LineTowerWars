class_name ReviveOncePassive
extends CreepPassive

## Gets the creep back up the first time it would die, once per creep.
##
## The one use is recorded on the CREEP, never here. This resource is the same
## object for every skeleton on the field, so a flag stored on it would be
## spent for all of them the moment any single one used it.
##
## The creep does not come straight back. It goes DOWN for a moment first -
## hidden, still, and out of every target search - with a shaft of light over
## the spot. That wait is the whole point: a creep that popped back instantly
## at a fraction of its health was killed again by the very next shot, so
## nothing a player could see ever happened. It also gives a maze a real
## window: the tower that was shooting it moves on to the next creep.
##
## A revived creep did not die, so it pays no bounty and keeps walking the
## route it was already committed to. Killing it a second time pays as normal.

@export_group("Settings")
## Share of its maximum health the creep comes back with.
@export_range(0.05, 1.0, 0.05) var health_ratio: float = 0.4
## Seconds it lies down before getting up.
@export var revive_delay: float = 2.0


func on_death(creep: Creep) -> bool:
	if creep == null || creep.has_spent(self):
		return false

	creep.spend(self)
	creep.begin_revive(revive_delay, health_ratio)
	return true


func down_seconds() -> float:
	return revive_delay


func effect_text() -> String:
	return "The first time it dies it gets back up %s seconds later, with %d%% of its health." \
		% [StringUtil.trim_number(revive_delay), roundi(health_ratio * 100.0)]
