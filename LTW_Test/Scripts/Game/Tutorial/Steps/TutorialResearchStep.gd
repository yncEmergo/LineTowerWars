class_name TutorialResearchStep
extends TutorialStep

## Finished once the player has researched something.
##
## Any technology at all rather than a named one, deliberately: the lesson is
## that the Research Center is where an element is bought and that an Ultimate
## is four of them, and a tutorial that refused every element but one would be
## teaching the wrong thing. Which one they took is theirs.

@export_group("Objective")
## How many technologies have to be owned before this is finished. Four is one
## whole Ultimate, which is what the opening allowance buys.
@export var technologies: int = 1


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.technologies_owned() >= maxi(1, technologies)
