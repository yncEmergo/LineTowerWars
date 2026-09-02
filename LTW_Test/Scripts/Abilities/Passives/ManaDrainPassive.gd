class_name ManaDrainPassive
extends CreepPassive

## Empties a tower and keeps far more than it took.
##
## The second Chaos Wardens trait. unit_data.md 6.6: "at 0 mana, drains 33% of
## a tower mana within 180 AoE and gains 500% of the amount, up to a maximum of
## 75 mana. Can only trigger on the same tower once every 7 sec."
##
## It is what keeps Chaos Barrier standing. That trait bleeds the creep pool
## dry in twenty seconds and this refills it out of the maze, so a Chaos Warden
## walked past a lane of mana towers is far harder to kill than the same creep
## walked past a lane without any - which is a real decision for the defender
## rather than a stat.
##
## AT ZERO MANA, deliberately, and not "whenever it can". The creep has to
## spend the whole barrier before it may steal another, so the two traits take
## turns rather than running together.
##
## The PER TOWER gate lives on the TOWER, not here and not on the creep: what
## the source states is that one tower cannot be drained twice in seven
## seconds, whichever creep does it - so three Chaos Wardens walking past one
## Sorcerer get one drain between them. See TowerStatus.set_immune.

## Key the per-tower gate is stored under. One shared key rather than one per
## creep, which is what makes the rule "this tower was drained" rather than
## "this tower was drained by that creep".
const GATE_KEY: String = "mana_drain"

@export_group("Settings")
## How far it reaches, in player cells. The source states 180, which is 1.41
## cells at the divisor every other reach uses - unit_data.md 3.
@export var radius_cells: float = 1.406
## Share of the tower current mana taken.
@export_range(0.0, 1.0, 0.01) var drain_share: float = 0.33
## Multiplier on what was taken, for what the creep gains.
@export var gain_multiplier: float = 5.0
## The most the creep may gain from one drain.
@export var gain_cap: int = 75
## Seconds before the same tower may be drained again, by anything.
@export var tower_gate_seconds: float = 7.0


func on_tick(creep: Creep, _delta: float) -> void:
	var pool: CreepMana = creep.mana()
	if pool == null || pool.current > 0 || !creep.is_alive():
		return

	var tower: Building = _pick_tower(creep)
	if tower == null:
		return

	var taken: int = int(floor(float(tower.current_mana) * drain_share))
	if taken <= 0:
		return
	if !tower.spend_mana(taken):
		return

	tower.status().set_immune(GATE_KEY, tower_gate_seconds)
	pool.gain(mini(int(round(float(taken) * gain_multiplier)), gain_cap))


## The fullest tower in reach that is not still shut out from the last drain.
##
## FULLEST rather than random, unlike Bombardment, and for the opposite reason:
## a rocket is trying to hurt the maze wherever it can, and this is trying to
## come away with as much mana as possible. A tower with an empty pool is worth
## nothing to it and is skipped rather than wasting the tick.
func _pick_tower(creep: Creep) -> Building:
	var best: Building = null
	var best_mana: int = 0
	for tower: Building in TargetFinder.buildings_in_radius(
			creep.area, creep.global_position, radius_cells):
		if tower.current_mana <= best_mana:
			continue
		var status: TowerStatus = tower.status_or_null()
		if status != null && status.is_immune(GATE_KEY):
			continue
		best = tower
		best_mana = tower.current_mana
	return best


func effect_text() -> String:
	return ("Once out of mana, drains %d%% of the mana of a tower within %s"
		+ " cells and gains %d%% of what it took, up to %d. The same tower"
		+ " cannot be drained again for %s seconds.") % [
		roundi(drain_share * 100.0), StringUtil.trim_number(radius_cells),
		roundi(gain_multiplier * 100.0), gain_cap,
		StringUtil.trim_number(tower_gate_seconds),
	]
