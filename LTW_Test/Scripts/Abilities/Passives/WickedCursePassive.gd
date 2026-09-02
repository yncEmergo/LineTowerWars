class_name WickedCursePassive
extends CreepPassive

## Curses the towers that killed it as it dies.
##
## The Harpy Windwitch trait. unit_data.md 6.6: "on death, curses up to 3
## towers within 200 AoE for 10 sec, reducing their attack speed by 30%."
##
## A creep that is worth something WHEN IT DIES, which is the point of sending
## a pack of them into a maze that can kill them: the first three open a hole
## in whatever killed them, and the next three walk through it. It is also the
## one trait in the roster that punishes concentration - three towers packed
## together are three towers cursed, and three spread out are one.
##
## Its own radius rather than the shared creep aura radius, on the same grounds
## every other burst here uses one: this is a blast at the spot it fell, not a
## field anything stands in over time.
##
## The curse lives on the TOWER, in the small status object creeps write into.
## See Combat/TowerStatus.gd.

@export_group("Settings")
## How far the curse reaches, in player cells. The source states 200, which is
## 1.56 cells at the divisor every other reach uses - unit_data.md 3.
@export var radius_cells: float = 1.563
## The most towers one death may curse.
@export var max_towers: int = 3
## Share taken off their attack speed.
@export_range(0.0, 1.0, 0.01) var speed_share: float = 0.30
## Seconds it lasts.
@export var duration_seconds: float = 10.0


## Runs on death and does not call it off: the Harpy still dies and still pays
## its bounty. Returning false is what says so.
func on_death(creep: Creep) -> bool:
	if creep.area == null || max_towers <= 0:
		return false

	var reachable: Array[Building] = TargetFinder.buildings_in_radius(
		creep.area, creep.global_position, radius_cells)
	# NEAREST first rather than at random, so the towers cursed are the ones
	# that were standing over the creep when it fell - which is what a player
	# watching it die expects, and what makes packing towers tightly the thing
	# this punishes.
	var origin: Vector3 = creep.global_position
	reachable.sort_custom(func(a: Building, b: Building) -> bool:
		return origin.distance_squared_to(a.global_position) \
			< origin.distance_squared_to(b.global_position))

	for index in range(mini(max_towers, reachable.size())):
		reachable[index].status().curse_speed(speed_share, duration_seconds, self)
	return false


func effect_text() -> String:
	return ("As it dies, curses up to %d towers within %s cells, slowing their"
		+ " attacks by %d%% for %s seconds.") % [
		max_towers, StringUtil.trim_number(radius_cells),
		roundi(speed_share * 100.0), StringUtil.trim_number(duration_seconds),
	]
