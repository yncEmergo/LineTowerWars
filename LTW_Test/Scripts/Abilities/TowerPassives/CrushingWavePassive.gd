class_name CrushingWavePassive
extends TowerPassive

## Water base towers: every fourth attack throws a wave over the creeps around
## the target.
##
## unit_data.md 4.10: a flat amount of Spell Damage on a fixed cadence rather
## than a roll, which is what makes the Splasher the most predictable of the
## base towers - and the reason Water is the element you take when a lane is
## already leaking rather than when it might.

const COUNT_KEY: String = "wave_count"

@export_group("Crushing Wave")
## Attacks between one wave and the next.
@export var every: int = 4
## Spell Damage the wave deals.
@export var damage: int = 12
## Radius it covers, in player cells.
@export var radius_cells: float = 1.17


func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	if !is_primary || target == null:
		return

	var count: int = int(tower.ability_state.get(COUNT_KEY, 0)) + 1
	tower.ability_state[COUNT_KEY] = count
	if every <= 0 || count % every != 0:
		return
	spell_burst(tower.area, target.global_position, radius_cells, damage)


func effect_text() -> String:
	return ("Every %d%s attack unleashes a Crushing Wave dealing %s Spell"
		+ " Damage within %s cells.") % [
		every, StringUtil.ordinal_suffix(every),
		StringUtil.compact_number(damage),
		StringUtil.trim_number(radius_cells),
	]
