class_name FrenziedFlamesPassive
extends TowerPassive

## Fire 1, Ultimate Moonbeam: the decay is gone and the mana is spent instead.
##
## unit_data.md 4.3: it regenerates mana, and every attack spends whatever has
## built up to spew flames over the ground its shot landed on. The damage
## scales with the mana SPENT, so a tower firing constantly does a little each
## time and one that has been idle does a great deal at once.
##
## Implemented as a burn on everything standing in the radius rather than as a
## lingering patch of ground, which is the same damage over the same window
## without a second kind of thing having to exist in the world. What that costs
## is that a creep walking INTO the flames afterwards is not caught - noted
## rather than hidden, and worth revisiting when ground effects exist.

@export_group("Frenzied Flames")
## Mana regained per second.
@export var regen_per_second: float = 10.0
## Spell Damage a second at FULL mana.
@export var max_damage_per_second: float = 1575.0
## How long the flames last.
@export var duration_seconds: float = 3.0
## Radius they cover, in player cells.
@export var radius_cells: float = 2.25


func mana_per_second(_tower: Building) -> float:
	return regen_per_second


func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	if !is_primary || target == null || tower.max_mana <= 0:
		return

	var spent: int = tower.drain_mana()
	if spent <= 0:
		return

	var per_second: float = max_damage_per_second * (float(spent) / float(tower.max_mana))
	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, target.global_position, radius_cells):
		creep.status().burn(self, per_second, duration_seconds)


func effect_text() -> String:
	return ("Regenerates %s mana per second. Every attack spends all of it to"
		+ " spew flames over %s for %ss, dealing up to %s Spell Damage"
		+ " per second scaled by the mana spent.") % [
		StringUtil.trim_number(regen_per_second),
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(duration_seconds),
		StringUtil.trim_number(max_damage_per_second),
	]
