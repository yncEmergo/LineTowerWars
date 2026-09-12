class_name TutorialUpgradeStep
extends TutorialStep

## Finished once the player has upgraded a tower.
##
## Counted since the step opened, for the reason TutorialBuildStep's count is.
## Which tower and which branch are deliberately not checked: the lesson is that
## a tower carries the button that raises it, and a player who found that button
## on the wrong tower has learned it.

@export_group("Objective")
@export var upgrades: int = 1


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.upgrades_this_step() >= maxi(1, upgrades)
