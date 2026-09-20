class_name TutorialOpenResearchStep
extends TutorialStep

## Finished once the Research Center is OPEN on screen.
##
## A task of its own because opening it is a thing to be shown once and never
## again: the button is in a corner the first half of the tutorial never asked
## anybody to look at, and every technology after this is bought in a screen the
## player has already found. The step that carries it is also the one that
## unlocks it - see TutorialStep.unlocks_research, which latches.
##
## **It is finished by a screen being open rather than by an order**, which is
## the one task in the tutorial that is true of the HUD rather than of the
## world. That is why it reads the panel directly: there is no order to count
## and nothing in MatchStats that would know.


func is_complete(_director: TutorialDirector) -> bool:
	var center: ResearchCenter = References.research_center
	return center != null && center.is_open()


func validate() -> bool:
	var complete: bool = super()
	# The task cannot be done while the Center is still shut to this player, and
	# nothing else in the script opens it.
	if !unlocks_research:
		Log.err("A task asks for the Research Center without unlocking it", resource_path)
		complete = false
	return complete
