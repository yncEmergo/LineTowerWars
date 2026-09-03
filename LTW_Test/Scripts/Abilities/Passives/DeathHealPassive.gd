class_name DeathHealPassive
extends CreepPassive

## Heals every creep standing near this one as it dies.
##
## Its own death is not called off: it still pays bounty and still leaves. The
## heal lands where it FELL rather than where it was sent from, which is what
## makes walking one in the middle of a pack worth more than at the back.
##
## Its own radius rather than the shared creep aura radius, because this is a
## burst on death and not an aura. Nothing stands in it over time.

@export_group("Settings")
## Radius the heal reaches, in player cells.
##
## `?` A CHOICE. The source states no radius for Unholy Sacrifice at any tier,
## and ONE CELL is deliberately the tightest burst in the roster: the heal is
## meant to be worth something to creeps that really were walking beside the
## one that died, rather than to a whole wave standing loosely together.
@export var radius: float = 1.0
## Health restored to each creep caught, before any cap.
@export var heal_amount: int = 20


func on_death(creep: Creep) -> bool:
	if creep == null || creep.area == null || heal_amount <= 0 || radius <= 0.0:
		return false

	for other: Creep in TargetFinder.creeps_in_radius(creep.area, creep.global_position, radius):
		# Itself included in the search, and skipped: it is out of health and
		# about to go, so healing it here would be a silent second revive.
		if other != creep:
			other.heal(heal_amount)

	# The heal is all it does. It still dies.
	return false


func effect_text() -> String:
	return "Heals every creep within %s for %d as it dies." \
		% [StringUtil.trim_number(radius), heal_amount]
