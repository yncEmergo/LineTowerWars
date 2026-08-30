class_name VolcanicEruptionPassive
extends TowerPassive

## Fire 2, the whole Firelord line: a proc that fires on a roll and eats armour.
##
## unit_data.md 4.3: a 40% chance to deal bonus Spell Damage to several targets
## and take a share of their armour. The Ultimate keeps all of that, guarantees
## it on every fifth attack, and adds damage for how much armour the target has
## already lost - which is what makes a Firelord worth more the longer it has
## been shooting the same pack.
##
## **Its targets are the creeps the tower's own SPLASH already covers**, up to
## the count this tier is worth. That is why no radius is authored here: the
## attack's splash IS the area, so the two cannot drift apart and a tier whose
## blast is widened is a tier whose eruption reaches further, with one number
## changed. A tower with no splash at all erupts on the creep it hit and
## nothing else, which is the same rule read at zero.
##
## The armour it takes is PERMANENT erosion rather than a debuff with a timer,
## and it is a share of the creep's MAXIMUM armour rather than of whatever is
## left - so two eruptions take the same number of points as each other, and
## the third one is not a rounding error. The source states no duration, and the
## Ultimate's bonus is written against "base armour the target is MISSING",
## which only means anything if what came off stays off.

## Where the tower counts its attacks for the guaranteed proc.
const COUNT_KEY: String = "eruption_count"

@export_group("Volcanic Eruption")
## Chance per attack, 0 to 1.
@export var chance: float = 0.4
## Creeps the eruption reaches, the primary target included. They are picked
## from inside the tower's own splash, nearest first.
@export var targets: int = 3
## Bonus Spell Damage as a share of the attack's own damage.
@export var bonus_share: float = 1.0
## Share of the target's MAXIMUM armour eaten, permanently, down to zero.
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
			_reach(tower), targets - 1, tower.stats.attack, skip):
		_erupt_on(creep, damage + _missing_armor_damage(creep, dealt))


## How far the eruption looks for its other targets: exactly as far as this
## tower's attack splashes, and 0 for a tower that does not splash at all.
func _reach(tower: Building) -> float:
	if tower.stats == null || tower.stats.attack == null:
		return 0.0
	return tower.stats.attack.splash_radius()


## Whether this attack proc'd, counting the attacks along the way. The counter
## runs whether or not the roll came up, because "every 5th attack" in the
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
		status.erode_armor(self, float(target.stats.armor) * armor_share, 0.0)


## The Ultimate's extra: more damage the more armour has already come off.
## Zero on every other tier, which is what leaves those tiers paying nothing
## for the question.
##
## Measured BEFORE this eruption's own erosion lands, so a proc is never paid
## for the armour it is in the middle of taking.
func _missing_armor_damage(target: Unit, dealt: int) -> int:
	if missing_armor_bonus <= 0.0 || target.stats == null || target.stats.armor <= 0:
		return 0

	var missing: float = float(target.stats.armor - target.armor_value())
	if missing <= 0.0:
		return 0
	var tenths: float = (missing / float(target.stats.armor)) * 10.0
	return int(round(float(dealt) * missing_armor_bonus * tenths))


## Written to read like the source card, in the source's own order: what the
## proc does, then a blank line, then what the Ultimate adds on top. The two
## things a player cannot work out from watching are spelled out rather than
## implied - that the targets come out of the tower's own splash, and that the
## armour taken is a share of the creep's maximum rather than of what is left.
func effect_text() -> String:
	var text: String = ("%d%% chance to deal %d%% bonus damage as Spell Damage"
		+ " to up to %d targets within its splash and permanently reduce their"
		+ " armor by %d%% of its maximum.") % [
		int(round(chance * 100.0)), int(round(bonus_share * 100.0)),
		targets, int(round(armor_share * 100.0)),
	]
	if guaranteed_every <= 0:
		return text

	text += "\n\nEvery %d%s attack always triggers %s" % [
		guaranteed_every, StringUtil.ordinal_suffix(guaranteed_every),
		display_name,
	]
	if missing_armor_bonus <= 0.0:
		return text + "."
	return text + (", which deals %d%% additional bonus Spell Damage for every"
		+ " 10%% of base armor missing from targets.") \
		% int(round(missing_armor_bonus * 100.0))
