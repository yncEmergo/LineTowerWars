class_name TutorialSendStep
extends TutorialStep

## Finished once the player has sent a number of packs at somebody.
##
## The first lesson where the player does something to another player rather
## than to their own lane. Counted since the step opened, so a lesson asking
## for four sends is four from here rather than four ever.

@export_group("Objective")
@export var sends: int = 1


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.sends_this_step() >= maxi(1, sends)


func progress_text(director: TutorialDirector) -> String:
	if director == null || sends <= 1:
		return ""
	return "%d / %d" % [mini(director.sends_this_step(), sends), sends]
