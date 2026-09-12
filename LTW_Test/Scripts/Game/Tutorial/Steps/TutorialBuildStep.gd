class_name TutorialBuildStep
extends TutorialStep

## Finished once the player has put up a number of towers.
##
## COUNTED SINCE THE STEP OPENED rather than in total, which is the whole
## difference between "build three towers" and "have three towers": a player who
## already has three from the last lesson would otherwise walk straight past
## this one. The director keeps that count, because "since when" is a fact about
## the run rather than about the lesson.
##
## What it does NOT check is WHERE. The blueprint on the ground says where, the
## maze lesson explains why, and a player who builds somewhere else has built a
## tower and learned what the button does - which is what this step is for. The
## step that cares about the shape is the one that watches a creep walk it.

@export_group("Objective")
## How many towers have to go up. One is enough for the first lesson; a maze
## lesson asks for the row.
@export var towers: int = 1


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.towers_built_this_step() >= maxi(1, towers)
