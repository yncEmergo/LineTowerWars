class_name BlockedPassive
extends CreepPassive

## Hits softer the more of its own kind are standing around it.
##
## The Mountain Giant trait, and the only DOWNSIDE trait in the roster.
## unit_data.md 6.6: "attack damage -8% for every Mountain Giant within 200 AoE
## (no effect at 3 or fewer), capped at -50%."
##
## What it exists to stop is the obvious play. A Mountain Giant is an attacker
## sent three at a time for 600,000 gold with no income at all, so the way to
## use it is to send a great pile of them and delete a maze from the front -
## and this is what makes the fourth one worth less than the third, and the
## tenth worth almost nothing. A player wanting more pressure has to spread it
## rather than stack it.
##
## Counted per TICK rather than cached, because the count is the whole point
## and it changes as the pile spreads out over a maze. It is the same linear
## scan every creep aura already runs and is paid by the handful of attackers
## on the field rather than by a lane.

@export_group("Settings")
## How far it looks, in player cells. The source states 200, which is 1.56
## cells at the divisor every other reach uses - unit_data.md 3.
@export var radius_cells: float = 1.563
## How many of its own kind may stand together before this bites at all.
@export var free_count: int = 3
## Share taken off attack damage per crowding neighbour past that.
@export_range(0.0, 1.0, 0.01) var share_each: float = 0.08
## The most it may ever take off.
@export_range(0.0, 1.0, 0.01) var max_share: float = 0.5


## Only its OWN KIND crowds it, which is what the source states and is also
## what keeps it from firing on a Mountain Giant walked in with a pack of
## anything else. is_same_type_as compares the stats resource, so it cannot be
## fooled by two creeps that merely look alike.
func attack_damage_ratio(creep: Creep) -> float:
	if creep == null || creep.area == null:
		return 1.0

	var crowd: int = 0
	for other: Creep in TargetFinder.creeps_in_radius(
			creep.area, creep.global_position, radius_cells):
		if other != creep && other.is_same_type_as(creep):
			crowd += 1

	var over: int = crowd + 1 - maxi(0, free_count)
	if over <= 0:
		return 1.0
	return 1.0 - minf(float(over) * share_each, max_share)


func effect_text() -> String:
	return ("Deals %d%% less damage for every one of its own kind past %d"
		+ " standing within %s cells, up to %d%% less.") % [
		roundi(share_each * 100.0), free_count,
		StringUtil.trim_number(radius_cells), roundi(max_share * 100.0),
	]
