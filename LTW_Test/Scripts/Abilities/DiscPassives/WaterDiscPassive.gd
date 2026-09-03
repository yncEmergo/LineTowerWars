class_name WaterDiscPassive
extends DiscPassive

## Water's disc: friendly towers in range regenerate mana.
##
## unit_data.md 5.2, and that is the WHOLE effect - the whirlpool the 9.4 sheet
## records, pulling ground creeps to the disc's centre and stunning them, was
## removed from the source game and must not be built.
##
## The one disc worth nothing at all next to the wrong maze: half the roster
## has no mana to fill. Building sums it OUTSIDE the "has any passives at all"
## gate for exactly that reason - a tower with mana and no passive of its own
## would otherwise be handed nothing.

@export_group("Wellspring")
## Mana points granted per second to every tower in range.
##
## NOT named mana_per_second: that is TowerPassive's own hook, which answers
## what a passive gives the tower CARRYING it, and a field of that name would
## shadow the method and fail to parse.
@export var mana_regen_per_second: float = 2.0


func _reach_towers(disc: Building) -> void:
	for tower: Building in _towers_in_range(disc):
		_lend(tower, TowerBuffs.Kind.MANA, mana_regen_per_second)


func effect_text() -> String:
	return "Friendly towers within %s regenerate %s mana per second." % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(mana_regen_per_second)]
