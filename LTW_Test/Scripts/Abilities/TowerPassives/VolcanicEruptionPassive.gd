class_name VolcanicEruptionPassive
extends TowerPassive

## Fire 2, the whole Firelord line: a proc that fires on a roll and eats armour.
##
## unit_data.md 4.3: a 40% chance to deal bonus Spell Damage to several targets
## and take a share of their armour. The Ultimate keeps all of that, guarantees
## it on every third attack, and adds damage for how much armour the target has
## already lost - which is what makes a Firelord worth more the longer it has
## been shooting the same pack.
##
## The armour it takes is PERMANENT erosion rather than a debuff with a timer.
## The source states no duration, and the Ultimate's bonus is written against
## "base armour the target is MISSING", which only means anything if what came
## off stays off.

## Where the tower counts its attacks for the guaranteed proc.
const COUNT_KEY: String = "eruption_count"

@export_group("Volcanic Eruption")
## Chance per attack, 0 to 1.
@export var chance: float = 0.4
## Creeps the eruption reaches, the primary target included.
@export var targets: int = 3
## Radius it looks for them in, in player cells.
@export var radius_cells: float = 2.34
## Bonus Spell Damage as a share of the attack's own damage.
@export var bonus_share: float = 1.0
## Share of the target's BASE armour eaten, permanently, down to zero.
@export var armor_share: float = 0.07
## Every Nth attack procs whatever the roll says, or 0 for none of them.
@export var guaranteed_every: int = 0
## Extra Spell Damage per 10% of base armour the target has already lost, as a
## share of the damage. 0 on every tier but the Ultimate.
@export var missing_armor_bonus: float = 0.0


func on_hit(tower: Building, target: Unit, dealt: int, is_primary: bool) -> void:
	if !is_primary || target == null || tower.area == null || tower.stats == null:
		return
	if !_procs(tower):
		return

	var damage: int = int(round(float(dealt) * bonus_share))
	_erupt_on(target, damage + _missing_armor_damage(target, dealt))

	var skip: Dictionary = {target: true}
	for creep: Creep in HitPattern.nearest(tower.area, target.global_position,
			radius_cells, targets - 1, tower.stats.attack, skip):
		_erupt_on(creep, damage + _missing_armor_damage(creep, dealt))


## Whether this attack proc'd, counting the attacks along the way. The counter
## runs whether or not the roll came up, because "every 3rd attack" in the
## source is a property of the attack rather than of the proc.
func _procs(tower: Building) -> bool:
	var count: int = int(tower.ability_state.get(COUNT_KEY, 0)) + 1
	tower.ability_state[COUNT_KEY] = count
	if guaranteed_every > 0 && count % guaranteed_every == 0:
		return true
	return MatchSession.match_rng().randf() < chance


func _erupt_on(target: Unit, damage: int) -> void:
	target.take_damage(damage, DamageTable.DamageType.SPELL, true)
	var status: StatusEffects = status_of(target)
	if status != null && target.stats != null:
		status.erode_armor(float(target.stats.armor) * armor_share, 0.0)


## The Ultimate's extra: more damage the more armour has already come off.
## Zero on every other tier, which is what leaves those tiers paying nothing
## for the question.
func _missing_armor_damage(target: Unit, dealt: int) -> int:
	if missing_armor_bonus <= 0.0 || target.stats == null || target.stats.armor <= 0:
		return 0

	var missing: float = float(target.stats.armor - target.armor_value())
	if missing <= 0.0:
		return 0
	var tenths: float = (missing / float(target.stats.armor)) * 10.0
	return int(round(float(dealt) * missing_armor_bonus * tenths))


func effect_text() -> String:
	var text: String = ("%d%% chance to deal +%d%% bonus Spell Damage to %d"
		+ " targets and permanently eat %d%% of their armor.") % [
		int(round(chance * 100.0)), int(round(bonus_share * 100.0)),
		targets, int(round(armor_share * 100.0)),
	]
	if guaranteed_every > 0:
		text += " Every %d%s attack triggers it outright." % [
			guaranteed_every, StringUtil.ordinal_suffix(guaranteed_every)]
	if missing_armor_bonus > 0.0:
		text += (" Adds +%d%% bonus damage for every 10%% of base armor the"
			+ " target is missing.") % int(round(missing_armor_bonus * 100.0))
	return text
