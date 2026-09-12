class_name TutorialSendStep
extends TutorialStep

## Finished once the player has sent creeps at somebody.
##
## The first lesson where the player does something to another player rather
## than to their own lane, which is why the step before it is the one explaining
## who they are sending into.

@export_group("Objective")
@export var sends: int = 1


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.sends_this_step() >= maxi(1, sends)
