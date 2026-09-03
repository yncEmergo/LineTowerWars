class_name EarthDiscPassive
extends DiscPassive

## Earth's disc: friendly towers in range attack faster.
##
## unit_data.md 5.2. The simplest aura of the ten and the one to read first if
## an eleventh is ever added - a single number lent to every tower in reach,
## re-granted on the beat, expiring on its own once the disc stops calling.

@export_group("Quickening")
## Share added to the attack speed of every tower in range, 0.08 for +8%.
@export var attack_speed_bonus: float = 0.08


func _reach_towers(disc: Building) -> void:
	for tower: Building in _towers_in_range(disc):
		_lend(tower, TowerBuffs.Kind.SPEED, attack_speed_bonus)


func effect_text() -> String:
	return "Friendly towers within %s attack %s%% faster." % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(attack_speed_bonus * 100.0)]
