class_name HolyDiscPassive
extends DiscPassive

## Holy's disc: friendly towers in range gain armour and heal faster.
##
## unit_data.md 5.2, and the one disc whose two numbers climb differently -
## only the armour scales past the Advanced tier, and the regeneration
## deliberately stops. Both are authored per tier, so nothing here has to know
## that; it is visible in the three .tres files instead.
##
## The regeneration is a SHARE of what the tower already restores rather than
## flat points, because that is how the source states it and because a flat
## rate would mean two completely different things to a 100 health Elemental
## Core and to a 3,000 health Ultimate. See Building._health_regen_per_second.

@export_group("Sanctuary")
## Armour points added to every tower in range.
@export var armor_bonus: float = 3.0
## Share added to their own health regeneration, 1.65 for +165%.
@export var regen_bonus_share: float = 1.65


func _reach_towers(disc: Building) -> void:
	for tower: Building in _towers_in_range(disc):
		_lend(tower, TowerBuffs.Kind.ARMOR, armor_bonus)
		_lend(tower, TowerBuffs.Kind.REGEN, regen_bonus_share)


func effect_text() -> String:
	return ("Friendly towers within %s cells gain %s armor and regenerate"
		+ " %s%% faster.") % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(armor_bonus),
		StringUtil.trim_number(regen_bonus_share * 100.0)]
