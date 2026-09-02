class_name WindRushPassive
extends CreepPassive

## Spends a full pool on hurrying the slowest creep near it along.
##
## The second Shaman trait. unit_data.md 6.6: "at full mana (14, starting at
## 10), grants a creep within 400 AoE +40% movement speed for 3 sec; slower
## creeps are prioritised."
##
## SLOWER FIRST, and that is what makes it worth anything. The creep a maze has
## chilled to a crawl is the one about to be shot to pieces, and handing the
## burst to whichever packmate happened to be nearest would spend it on one
## that was leaving anyway. It is also why a haste is kept apart from a chill
## rather than cancelling one - see StatusEffects.haste: a creep that is both
## slowed and hurried ends up somewhere between the two, which is the same rule
## an aura and a chill already follow.
##
## It starts PART FULL, at 10 of 14, so the first rush lands a few seconds into
## the walk rather than a whole pool later. That number lives on the creep with
## the ceiling it is counting towards, not here.

@export_group("Settings")
## How far it reaches, in player cells. The source states 400, which is 3.125
## cells at the divisor every other reach uses - unit_data.md 3.
@export var radius_cells: float = 3.125
## Extra share of movement speed granted.
@export_range(0.0, 2.0, 0.05) var speed_bonus: float = 0.40
## Seconds it lasts.
@export var duration_seconds: float = 3.0


func on_tick(creep: Creep, _delta: float) -> void:
	var pool: CreepMana = creep.mana()
	if pool == null || !pool.is_full() || !creep.is_alive():
		return

	var target: Creep = _slowest_near(creep)
	if target == null:
		return

	pool.drain()
	target.status().haste(self, speed_bonus, duration_seconds)


## The creep in range moving slowest RIGHT NOW, itself included.
##
## Measured off what the creep is actually doing rather than off its authored
## speed, which is the point: a fast creep chilled to a third of its speed is
## the one in trouble, and a Shaman that read the stats file instead would hand
## the rush to whatever was already outrunning the maze.
func _slowest_near(creep: Creep) -> Creep:
	var best: Creep = null
	var best_speed: float = INF
	for other: Creep in TargetFinder.creeps_in_radius(
			creep.area, creep.global_position, radius_cells):
		var speed: float = other.current_move_speed()
		if speed < best_speed:
			best = other
			best_speed = speed
	return best


func effect_text() -> String:
	return ("At full mana, grants the slowest creep within %s cells +%d%%"
		+ " movement speed for %s seconds.") % [
		StringUtil.trim_number(radius_cells), roundi(speed_bonus * 100.0),
		StringUtil.trim_number(duration_seconds),
	]
