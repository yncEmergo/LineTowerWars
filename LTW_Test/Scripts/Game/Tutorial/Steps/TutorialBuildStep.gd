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
## the count would not see.
##
## Its PROGRESS counts only what this lesson asked for: a plan that is the last
## lesson's four towers plus ten more reads 0 / 10 when it opens, not 4 / 14.
##
## Without a blueprint it counts towers put up SINCE THE STEP OPENED, for a
## lesson that only wants a button pressed.

@export_group("Objective")
## How many towers have to go up, for a lesson with no blueprint. Ignored when
## the lesson has one: then it is every cell of the plan.
@export var towers: int = 1


func is_complete(director: TutorialDirector) -> bool:
	if director == null:
		return false
	var plan: TowerLayout = blueprint()
	if plan != null:
		return blueprint_built() >= plan.entry_count()
	return director.towers_built_this_step() >= maxi(1, towers)


func progress(director: TutorialDirector) -> Vector2i:
	if director == null:
		return Vector2i.ZERO
	var plan: TowerLayout = blueprint()
	if plan != null:
		var already: int = director.blueprint_built_at_open()
		return Vector2i(blueprint_built() - already, plan.entry_count() - already)
	return Vector2i(director.towers_built_this_step(), maxi(1, towers))
