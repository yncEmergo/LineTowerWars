class_name IgnitePassive
extends TowerPassive

## Fire base towers: sets a creep alight on a clock of its own, whether or not
## the tower is shooting anything.
##
## unit_data.md 4.3: the Fire Pit ignites a ground creep every 2.1 seconds
## within its radius for 5 Spell Damage a second over 8 seconds, and the Magma
## Well does the same for 13. One script, two .tres files.
##
## The clock is the TOWER's, kept in Building.ability_state, because this
## resource is every Fire Pit on the field at once.

## Key this passive keeps its countdown under. Named after the ability rather
## than after the element, so two Fire passives on one tower cannot share it.
const TIMER_KEY: String = "ignite_timer"

@export_group("Ignite")
## Seconds between one creep being set alight and the next.
@export var interval_seconds: float = 2.1
## How far the tower reaches to pick one, in player cells. Its own attack range
## is deliberately not used: unit_data.md states a separate AoE for this.
@export var radius_cells: float = 3.12
## Spell Damage a second the fire deals.
@export var damage_per_second: float = 5.0
## How long it burns for.
@export var duration_seconds: float = 8.0


func on_tick(tower: Building, delta: float) -> void:
	var left: float = float(tower.ability_state.get(TIMER_KEY, 0.0)) - delta
	if left > 0.0:
		tower.ability_state[TIMER_KEY] = left
		return
	tower.ability_state[TIMER_KEY] = interval_seconds

	if tower.area == null || tower.stats == null || !tower.can_attack():
		return
	var creep: Creep = HitPattern.random_in_radius(
		tower.area, tower.global_position, radius_cells, tower.stats.attack)
	if creep != null:
		creep.status().burn(self, damage_per_second, duration_seconds)


func effect_text() -> String:
	return ("Sets a creep within %s cells alight every %ss, dealing %s Spell"
		+ " Damage per second for %ss.") % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(interval_seconds),
		StringUtil.trim_number(damage_per_second),
		StringUtil.trim_number(duration_seconds),
	]
