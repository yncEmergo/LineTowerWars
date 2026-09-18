class_name TutorialBuildStep
extends TutorialStep

## Finished once the lesson's BLUEPRINT is built, or once the player has put up
## a number of towers.
##
## **With a blueprint it reads the GROUND, not a counter.** Every cell the plan
## names has to have a tower of the player's standing on it - started is
## enough, the builder is free the moment it starts one. A count would be wrong
## here in both directions: a tower started and cancelled counts once and stands
## nowhere, and a plan whose first row was the last lesson's already has towers
## the count would not see. What is standing is the only honest answer to "is
## the shape there".
##
## Without one it counts towers put up SINCE THE STEP OPENED, for a lesson that
## only wants a button pressed.

@export_group("Objective")
## How many towers have to go up, for a lesson with no blueprint. Ignored when
## the lesson has one: then it is every cell of the plan.
@export var towers: int = 1


func is_complete(director: TutorialDirector) -> bool:
	if director == null:
		return false
	var plan: TowerLayout = blueprint()
	if plan != null:
		return _built_on(plan) >= plan.entry_count()
	return director.towers_built_this_step() >= maxi(1, towers)


func progress_text(director: TutorialDirector) -> String:
	if director == null:
		return ""
	var plan: TowerLayout = blueprint()
	if plan != null:
		return "%d / %d" % [_built_on(plan), plan.entry_count()]
	return "%d / %d" % [mini(director.towers_built_this_step(), towers), towers]


## How many of the plan's cells have one of the player's towers on them.
##
## Walks the player's own buildings, which in the lessons that ask this is a
## few dozen at most. Matched on the footprint's top-left cell, which is how a
## TowerLayout names a cell and how Building.cell stores one.
func _built_on(plan: TowerLayout) -> int:
	var area: PlayerArea = _local_area()
	if area == null:
		return 0
	var wanted: Dictionary = {}
	for cell: Vector2i in plan.cells:
		wanted[cell] = true
	var count: int = 0
	for child in area.get_children():
		var building: Building = child as Building
		if building != null && wanted.has(building.cell):
			count += 1
	return count
