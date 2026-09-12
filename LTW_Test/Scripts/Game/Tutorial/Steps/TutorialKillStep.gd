class_name TutorialKillStep
extends TutorialStep

## Finished once creeps have died in the player's own maze.
##
## The payoff step: a player who has built a maze and been sent something
## watches it work. It is the one step whose objective the player does not
## really DO - they wait, and the maze does it - which is why it is worth
## keeping short.

@export_group("Objective")
@export var kills: int = 1


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.kills_this_step() >= maxi(1, kills)
