class_name TutorialMoveStep
extends TutorialStep

## Finished once the builder has moved a little way from where it stood when
## the lesson opened.
##
## Any move counts - a right click on the ground or the Move command, anywhere -
## because the lesson is that the builder goes where it is told, and a player
## who has told it once has learned that.

@export_group("Objective")
## How far the builder has to get from where it started, in world units.
@export var distance: float = 2.0


func is_complete(director: TutorialDirector) -> bool:
	if director == null:
		return false
	var builder: Unit = TutorialGuide.unit_for(Select.BUILDER)
	if builder == null:
		return false
	var moved: Vector3 = builder.global_position - director.builder_at_open()
	moved.y = 0.0
	return moved.length() >= distance
