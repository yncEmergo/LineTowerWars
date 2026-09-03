class_name HardenedSkinPassive
extends CreepPassive

## Armour that starts absurdly high and only yields to HEAVY BLOWS.
##
## The creep's own stats hold the starting number - this passive never states
## it, for the same reason nothing else restates a stat it does not own. What
## it owns is the erosion: every single hit that lands for enough takes one
## point of armour off, permanently, down to a floor it never falls below.
##
## PER HIT, NEVER CUMULATIVE, and that is the entire design. A thousand small
## hits do nothing at all - they do not add up, and the armour is exactly as
## thick after them as before. What gets through is one blow big enough, so
## stripping a fresh one is a question of bringing the right towers rather than
## of waiting long enough with the wrong ones.
##
## Which makes it a WALL EARLY and a normal creep late, in a way the player
## has a lever on. The armour it starts with is high enough that almost nothing
## lands hard enough to count, so the way in is to make hits bigger rather than
## more numerous: anything that eats armour - a Firelord's eruption, an Ancient
## Warden, a Leviathan - lifts every later hit over the line and the thing comes
## apart quickly once it starts.
##
## The threshold is read against the damage that ACTUALLY LANDED, so the
## creep's own armour, its resistances and anything amplifying damage on it have
## all already been applied. A hit that is heavy on paper and arrives as a
## scratch does not count.
##
## The erosion is PERMANENT for that creep's life rather than a debuff with a
## duration, so nothing about it belongs in StatusEffects: it is not something
## a tower applied and it cannot be dispelled or waited out. It is read back out
## of one number the creep was already going to keep - how many heavy hits have
## landed - which is why this passive holds no state and stays the shared
## resource every other one is.

@export_group("Settings")
## Damage a SINGLE hit must land for to strip a point of armour. A hit below
## this does nothing whatever, however many of them there are.
@export var damage_per_point: float = 50.0
## Armour this can never erode below, however long the creep is shot at.
@export var armor_floor: int = 6


## Points to take OFF the creep's own armour right now, always zero or less.
##
## Derived rather than stored, so there is nothing to keep in step: the creep
## carries the damage total, its stats carry the starting armour, and the
## answer falls out of the two. Capped at the floor rather than clamped after
## the fact, because an aura standing over the creep must be able to lift it
## back above one - the floor is what THIS erodes to, not a minimum armour.
func armor_delta(creep: Creep) -> int:
	if creep == null || creep.stats == null || damage_per_point <= 0.0:
		return 0

	var strippable: int = maxi(0, creep.stats.armor - armor_floor)
	return -mini(creep.heavy_hits_taken(), strippable)


## What the creep counts as a heavy hit, which is the same number a point of
## armour costs. One value rather than two: "hits this hard" and "hits that
## count" are the same question asked from the two ends.
func heavy_hit_threshold() -> float:
	return damage_per_point


func effect_text() -> String:
	return ("Every single hit that lands for %s or more permanently strips 1"
		+ " point of armor, down to %d. A hit below that strips nothing.") % [
		StringUtil.trim_number(damage_per_point), armor_floor,
	]
