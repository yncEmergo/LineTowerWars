class_name ShiftingPowerPassive
extends TowerPassive

## Arcane 2, the whole Arcane Orb line: an attack that bounces, feeds the tower
## on every creep it touches, and leaks that mana away again the moment it
## stops shooting.
##
## unit_data.md 4.1: bounces gain mana per target, damage rises with the mana
## PERCENTAGE, every other attack is dealt as Spell Damage, and flyers take
## more. Mana drains constantly, so the tower is only ever strong while it is
## busy - the mirror of the Moonbeam, which is only strong while it is new.
##
## The Ultimate adds a threshold: above most of its mana it bounces further and
## burns through the mana much faster, so it spikes and then falls back.

## Where the attack counter for the alternating damage type is kept.
const SHIFT_KEY: String = "shifting_parity"

@export_group("Shifting Power")
## Times the attack bounces onwards from its target.
@export var bounces: int = 3
## How far each bounce reaches, in player cells.
@export var bounce_cells: float = 1.56
## Mana gained per creep struck, bounces included.
@export var mana_per_target: float = 2.0
## Mana lost per second while nothing tops it up.
@export var drain_per_second: float = 2.0
## Extra damage at FULL mana, as a share, scaled down linearly by how full the
## tower actually is.
@export var max_mana_bonus: float = 0.5
## Extra damage against flying creeps, as a share.
@export var flying_bonus: float = 0.15
## Whether every other attack is dealt as Spell Damage.
@export var alternates_spell_damage: bool = true

@export_group("Arcane Surge")
## Mana share above which the Ultimate bounces further, or 0 for no threshold.
@export var surge_threshold: float = 0.0
## Extra bounces while above it.
@export var surge_bounces: int = 2
## Mana lost per second while above it, replacing the ordinary drain.
@export var surge_drain_per_second: float = 15.0


func mana_per_second(tower: Building) -> float:
	if _is_surging(tower):
		return -surge_drain_per_second
	return -drain_per_second


## The parity is flipped when the attack COMMITS rather than when it lands, so
## two shots in the air cannot both read the same value and come out the same
## type.
func on_attack(tower: Building, _target: Unit) -> void:
	tower.ability_state[SHIFT_KEY] = int(tower.ability_state.get(SHIFT_KEY, 0)) + 1


func damage_type_for(tower: Building, _target: Unit) -> int:
	if !alternates_spell_damage:
		return -1
	if int(tower.ability_state.get(SHIFT_KEY, 0)) % 2 != 0:
		return -1
	return DamageTable.DamageType.SPELL


func bonus_damage(tower: Building, target: Unit, rolled: int) -> int:
	var share: float = max_mana_bonus * tower.mana_ratio()
	var creep: Creep = target as Creep
	if creep != null && creep.is_flying():
		share += flying_bonus
	return int(round(float(rolled) * share))


## The bounce. Each creep it reaches takes the same damage the primary did and
## feeds the tower, which is what makes an Arcane Orb over a crowd fill up in
## one attack and one over a straggler never fill at all.
func on_hit(tower: Building, target: Unit, dealt: int, is_primary: bool) -> void:
	tower.gain_mana(mana_per_target)
	if !is_primary || target == null || tower.stats == null:
		return

	var hops: int = bounces + (surge_bounces if _is_surging(tower) else 0)
	for creep: Creep in HitPattern.chain(tower.area, target, hops,
			bounce_cells, tower.stats.attack):
		creep.take_damage(dealt, tower.stats.attack.damage_type)
		tower.gain_mana(mana_per_target)


func _is_surging(tower: Building) -> bool:
	return surge_threshold > 0.0 && tower.mana_ratio() >= surge_threshold


func effect_text() -> String:
	var text: String = ("Attacks bounce up to %d times within %s cells, gaining"
		+ " %s mana per creep hit. Damage rises by up to +%s%% with the mana"
		+ " held, and by +%s%% against flyers. Mana drains %s per second.") % [
		bounces,
		StringUtil.trim_number(bounce_cells),
		StringUtil.trim_number(mana_per_target),
		StringUtil.trim_number(max_mana_bonus * 100.0),
		StringUtil.trim_number(flying_bonus * 100.0),
		StringUtil.trim_number(drain_per_second),
	]
	if alternates_spell_damage:
		text += " Every other attack is dealt as Spell Damage."
	if surge_threshold > 0.0:
		text += (" Above %s%% mana it bounces to %d more creeps and drains %s"
			+ " per second instead.") % [
			StringUtil.trim_number(surge_threshold * 100.0), surge_bounces,
			StringUtil.trim_number(surge_drain_per_second)]
	return text
