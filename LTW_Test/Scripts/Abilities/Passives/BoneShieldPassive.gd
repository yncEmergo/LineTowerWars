class_name BoneShieldPassive
extends CreepPassive

## Trades every point of the creep's armour away for health, and shrugs off
## nearly everything a spell can do to it.
##
## The Necromancer, and the strangest thing in tier 3 to read off a stats file:
## unit_data.md 6.4 lists it at 0 armour and 121,800 health and then says the
## creep really has 146,160, because "converts base armour into 4% max health
## per point" is applied to the five points its file gives it.
##
## Which is why the .tres carries the armour it started with rather than the
## zero it ends up at. The stats file says what the creep IS; this says what
## happens to that. Author the armour, and both halves - the points going away
## and the health arriving - fall out of one number that cannot drift.
##
## The three resistances are the same three every spell resistance in the
## roster carries and are authored the same way, so the only thing new here is
## the conversion.

@export_group("Resistance")
## Share of SPELL damage the creep still takes. 0.25 is "spell damage -75%".
@export_range(0.0, 1.0, 0.01) var spell_damage_ratio: float = 0.25
## Share of a harmful effect's clock it serves.
@export_range(0.0, 1.0, 0.05) var duration_ratio: float = 0.5
## Share of a chill's magnitude that lands. 0 is outright slow immunity.
@export_range(0.0, 1.0, 0.05) var chill_ratio: float = 0.0

@export_group("Conversion")
## Share of MAXIMUM health gained per point of the creep's base armour.
@export_range(0.0, 0.5, 0.001) var health_per_armor_point: float = 0.04


func damage_taken_ratio(_creep: Creep, damage_type: DamageTable.DamageType,
		_is_aoe: bool) -> float:
	return spell_damage_ratio if DamageTable.is_spell(damage_type) else 1.0


func harmful_duration_ratio() -> float:
	return duration_ratio


func chill_taken_ratio() -> float:
	return chill_ratio


## Every point of the creep's own armour, taken off. What is left is whatever
## an aura is granting it, which is correct: the conversion spends the armour
## the creep was AUTHORED with, and cannot reach a point somebody else gave it.
func armor_delta(creep: Creep) -> int:
	if creep == null || creep.stats == null:
		return 0
	return -creep.stats.armor


## and the other half of the same trade, read off the same number.
func max_health_ratio(creep: Creep) -> float:
	if creep == null || creep.stats == null:
		return 1.0
	return 1.0 + float(maxi(0, creep.stats.armor)) * health_per_armor_point


func effect_text() -> String:
	return ("Takes %d%% less spell damage, cannot be slowed, and harmful"
		+ " effects last %d%% less. Converts all of its own armor into health,"
		+ " %s%% of its maximum per point.") % [
		roundi((1.0 - spell_damage_ratio) * 100.0),
		roundi((1.0 - duration_ratio) * 100.0),
		StringUtil.trim_number(health_per_armor_point * 100.0),
	]
