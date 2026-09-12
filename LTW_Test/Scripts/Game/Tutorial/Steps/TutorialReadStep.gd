class_name TutorialReadStep
extends TutorialStep

## A lesson that is only READ: a paragraph, and a button that says go on.
##
## The commonest step in the tutorial and the one that carries the explaining,
## so everything else can be a short instruction. It holds the world still by
## default - see TutorialStep.pauses_world - which is what makes it safe to put
## a paragraph in front of somebody in the middle of a match.
##
## It is finished when the player says it is, which is what the panel's Continue
## button reports. Nothing about the world can end it.


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.was_acknowledged()
