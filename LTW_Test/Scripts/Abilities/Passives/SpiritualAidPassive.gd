class_name SpiritualAidPassive
extends CreepPassive

## Spends a full pool on healing and permanently thickening one packmate.
##
## The Spirit Walker trait. unit_data.md 6.6: "at full mana (6), heals a creep
## within 500 for 1% of its max health (cap 2,000) and grants +1 armour, up to
## 12."
##
## The ARMOUR is the half that matters, and it is why the ceiling belongs to the
## receiving creep rather than to this one: a Spirit Walker walked with a pack
## for long enough turns everything around it into something the maze was not
## built for, and twelve points is where that stops.
##
## The HEAL is deliberately small - one percent of a maximum, capped - because
## what it lands on is a tier 3 creep with six figures of health. It is a top-up
## between hits rather than anything a tower has to out-damage.
##
## The pool fills on the creep own clock, see CreepStats.mana_regen_per_second.
## Nothing here holds any mana: this resource is every Spirit Walker at once.

@export_group("Settings")
## How far the aid reaches, in player cells. The source states 500, which is
## 3.91 cells at the divisor every other reach uses - see unit_data.md 3.
@export var radius_cells: float = 3.906
## Share of the target MAXIMUM health restored.
@export_range(0.0, 1.0, 0.005) var heal_share: float = 0.01
## The most one heal may ever be worth, however large the target is.
@export var heal_cap: int = 2000
## Armour points handed over, permanently.
@export var armor_bonus: float = 1.0
## The most this may ever raise one creep armour by, over its whole life.
@export var armor_ceiling: float = 12.0


func on_tick(creep: Creep, _delta: float) -> void:
	var pool: CreepMana = creep.mana()
	if pool == null || !pool.is_full() || !creep.is_alive():
		return

	var target: Creep = _pick_target(creep)
	if target == null:
		return

	pool.drain()
	target.heal(minf(float(target.max_health()) * heal_share, float(heal_cap)))
	# The ceiling is read off the TARGET rather than counted here, for the
	# reason every "once per creep" rule in this game is: this resource stands
	# in for every Spirit Walker on the field, so a tally kept here would be
	# all of theirs added together.
	if target.status().granted_armor() < armor_ceiling:
		target.status().bless_armor(self, armor_bonus)


## One creep in range, preferring the one this can still do the most for.
##
## The creep FURTHEST from the armour ceiling wins, itself included. Random
## would waste most casts on whatever had already topped out, and nearest would
## spend a whole walk on one packmate; this spreads the twelve points across a
## pack and then goes on healing rather than stopping.
func _pick_target(creep: Creep) -> Creep:
	var best: Creep = null
	var best_room: float = -1.0
	for other: Creep in TargetFinder.creeps_in_radius(
			creep.area, creep.global_position, radius_cells):
		var room: float = armor_ceiling - other.status().granted_armor()
		if room > best_room:
			best = other
			best_room = room
	return best


func effect_text() -> String:
	return ("At full mana, heals a creep within %s cells for %s%% of its maximum"
		+ " health, up to %d, and permanently grants it +%s armor - up to %s"
		+ " points on any one creep.") % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(heal_share * 100.0), heal_cap,
		StringUtil.trim_number(armor_bonus),
		StringUtil.trim_number(armor_ceiling),
	]
