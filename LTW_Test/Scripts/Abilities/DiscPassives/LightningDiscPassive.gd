class_name LightningDiscPassive
extends DiscPassive

## Lightning's disc: friendly towers in range become STATIC.
##
## unit_data.md 5.2, and the largest single effect in the disc roster - three
## mechanics under one word. A static tower heals for a share of the physical
## damage it deals, returns a multiple of the damage an attacking creep does to
## it, and has a chance to stun that creep for two seconds.
##
## It is the one disc whose value depends on being ATTACKED, which is why its
## radius is the wide one: 500 rather than 300, alongside Holy. Two of its
## three halves are worth nothing at all until an attacker creep arrives, and
## the third is worth nothing to a Spell Damage tower. Where it goes is the
## front of a maze, which is exactly what its numbers are shaped for.
##
## The 9.4 sheet records the return damage as 300% / 350%. Those figures
## predate the healing rework and are wrong; the values here are the ones
## unit_data.md records as correct.
##
## All three numbers are lent to the tower and read back from there rather than
## being applied from here, because two of them fire on a hit this disc has no
## part in. See Combat/TowerBuffs.gd, which is where the stun length lives too:
## it is two seconds at every tier, so it is a constant rather than a number
## authored three times.

@export_group("Static")
## Share of the PHYSICAL damage dealt that the tower heals for, 0.0175 for
## 1.75%. Spell Damage heals nothing, which is the source's own word.
@export var heal_share: float = 0.01
## Multiple of the damage an attacking creep just did that is dealt back to it,
## 5.0 for 500%.
@export var return_share: float = 5.0
## Chance that same creep is also stunned, 0.15 for 15%.
@export var stun_chance: float = 0.15


func _reach_towers(disc: Building) -> void:
	for tower: Building in _towers_in_range(disc):
		_lend(tower, TowerBuffs.Kind.HEAL, heal_share)
		_lend(tower, TowerBuffs.Kind.RETURN, return_share)
		_lend(tower, TowerBuffs.Kind.STUN, stun_chance)


func effect_text() -> String:
	return ("Friendly towers within %s cells become static: they heal for %s%%"
		+ " of the physical damage they deal, return %s%% of the damage an"
		+ " attacking creep does to them, and have a %s%% chance to stun it"
		+ " for %ss.") % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(heal_share * 100.0),
		StringUtil.trim_number(return_share * 100.0),
		StringUtil.trim_number(stun_chance * 100.0),
		StringUtil.trim_number(TowerBuffs.STUN_SECONDS)]
