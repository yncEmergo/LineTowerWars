class_name TutorialReadStep
extends TutorialStep

## A lesson that is only READ: a paragraph, and a button that says go on.
##
## Kept for the rare thing that cannot be taught by doing it. The tutorial is
## meant to be DONE rather than read, so reach for a task first - and when a
## read lesson is the answer, keep it to a couple of lines. It does not hold the
## world by default any more; set pauses_world only where something would go
## wrong while the player reads.
##
## It is finished when the player says it is, which is what the panel's Continue
## button reports. Nothing about the world can end it.


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.was_acknowledged()
