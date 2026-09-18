class_name TutorialBeatRivalStep
extends TutorialStep

## Finished once an opponent is out of the match.
##
## The long lessons: everything before one of these is taught, and this is the
## player playing it. They carry the tips worth having to hand while doing that,
## and the match ends this one on its own either way.

@export_group("Objective")
@export var rival: Rival = Rival.FIRST


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.is_rival_beaten(rival)


func progress_text(director: TutorialDirector) -> String:
	if director == null:
		return ""
	var lives: int = director.rival_lives(rival)
	return "" if lives < 0 else "Their lives: %d" % lives


func validate() -> bool:
	var complete: bool = super()
	if rival == Rival.NONE:
		Log.err("A lesson waits for an opponent to be beaten and names none", title)
		complete = false
	return complete
