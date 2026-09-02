class_name EarthShieldPassive
extends CreepPassive

## Wipes the slow off one packmate every so often and mends it as it goes.
##
## The Ogre Magi trait. unit_data.md 6.6: "every 14 sec shields a creep within
## 400 radius, removing chill/slow and healing 10% of max health over 12 sec.
## Also removes Ultimate Lich Frostbite."
##
## The DISPEL is the point and the heal is the sweetener. A maze built on
## chill wins by keeping a pack inside its towers for long enough, and this
## takes one creep straight back out of that - the towers that had accumulated
## up to their cap on it start again from nothing, exactly as they would if the
## creep had walked out of range and back in.
##
## Frostbite needs no special case: it is a chill like every other one, so
## clearing the chills clears it. See StatusEffects.clear_slows.
##
## The heal is spread over TWELVE seconds rather than handed over at once, so
## it is worth most on a creep a maze is chewing at slowly and worth nothing at
## all on one about to be deleted by a single shot. The clock lives on the
## creep, see Creep.advance_passive_clock.

@export_group("Settings")
## Seconds between shields.
@export var interval_seconds: float = 14.0
## How far it reaches, in player cells. The source states 400, which is 3.125
## cells at the divisor every other reach uses - unit_data.md 3.
@export var radius_cells: float = 3.125
## Share of the target MAXIMUM health restored over the whole window.
@export_range(0.0, 1.0, 0.01) var heal_share: float = 0.10
## Seconds that healing is spread over.
@export var heal_seconds: float = 12.0


func on_tick(creep: Creep, delta: float) -> void:
	if !creep.is_alive():
		return
	if !creep.advance_passive_clock(self, interval_seconds, delta):
		return

	var target: Creep = _pick_target(creep)
	if target == null:
		return

	target.status().clear_slows()
	if heal_seconds > 0.0:
		target.status().mend(self,
			float(target.max_health()) * heal_share / heal_seconds, heal_seconds)


## The most slowed creep in range, itself included, and null when nothing near
## it is slowed at all - in which case the shield is held rather than wasted.
##
## Deliberately NOT "anything in range". The whole worth of this is taking a
## creep out of a chill, and spending it on an unslowed packmate for the heal
## alone would throw away the fourteen second wait for a top-up.
func _pick_target(creep: Creep) -> Creep:
	var best: Creep = null
	var best_slow: float = 0.0
	for other: Creep in TargetFinder.creeps_in_radius(
			creep.area, creep.global_position, radius_cells):
		var status: StatusEffects = other.status_or_null()
		if status == null:
			continue
		var slow: float = 1.0 - status.move_ratio()
		if slow > best_slow:
			best = other
			best_slow = slow
	return best


func effect_text() -> String:
	return ("Every %s seconds, strips every slow off the most slowed creep"
		+ " within %s cells and heals it for %d%% of its maximum health over %s"
		+ " seconds.") % [
		StringUtil.trim_number(interval_seconds),
		StringUtil.trim_number(radius_cells),
		roundi(heal_share * 100.0),
		StringUtil.trim_number(heal_seconds),
	]
