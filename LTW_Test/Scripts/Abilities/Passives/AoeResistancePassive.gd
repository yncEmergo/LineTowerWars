class_name AoeResistancePassive
extends CreepPassive

## Takes less from attacks that cover ground than from attacks aimed at it.
##
## Which attacks those are is the ATTACK's answer, not this one's: see
## AttackStats.is_aoe_damage, and note that any splash counts whatever its
## attack says. Multishot is deliberately not area damage - it picks several
## single targets rather than covering ground.
##
## PHYSICAL area damage only, which is what the roster's Armored trait states:
## "physical splash damage taken reduced by 10%". A spell that covers ground is
## resisted by a SPELL resistance and by nothing else, which is the whole point
## of spell damage sitting outside the armour matrix - see unit_data.md 1.1.
##
## Applied after the damage matrix and before the creep's armour points, so it
## and the armour compound rather than one hiding the other.

@export_group("Settings")
## Share of physical area damage the creep takes. 0.5 is half; the roster's
## Armored (1) and (2) are 0.9 and 0.8.
@export_range(0.0, 1.0, 0.05) var damage_ratio: float = 0.5


func damage_taken_ratio(_creep: Creep, damage_type: DamageTable.DamageType,
		is_aoe: bool) -> float:
	if !is_aoe || DamageTable.is_spell(damage_type):
		return 1.0
	return damage_ratio


func effect_text() -> String:
	return "Takes %d%% less physical damage from attacks that hit an area." 		% roundi((1.0 - damage_ratio) * 100.0)
