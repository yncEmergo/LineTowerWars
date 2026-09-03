class_name PrimalDiscPassive
extends DiscPassive

## Primal's disc: friendly towers in range reach further.
##
## unit_data.md 5.2, and the one disc whose stacking rule is written down as a
## rule rather than left implied: "a weaker Primal disc must not override the
## range bonus of a nearby stronger one", which was a real bug fixed in 12.3a.
##
## Nothing here enforces it. TowerBuffs keeps the STRONGEST grant of every boon
## and lets the weaker one expire underneath it, so the rule is true for this
## disc, for the other nine, and for any disc added later, without one line
## anywhere knowing it is a rule.

@export_group("Far Sight")
## Cells added to the attack range of every tower in range.
@export var range_bonus_cells: float = 0.75


func _reach_towers(disc: Building) -> void:
	for tower: Building in _towers_in_range(disc):
		_lend(tower, TowerBuffs.Kind.RANGE, range_bonus_cells)


func effect_text() -> String:
	return "Friendly towers within %s reach %s further." % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(range_bonus_cells)]
