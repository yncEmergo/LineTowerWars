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


## Lives taken of the lives it started with - "(3/10)".
func progress(director: TutorialDirector) -> Vector2i:
	if director == null || director.script_resource == null:
		return Vector2i.ZERO
	var lives: int = director.rival_lives(rival)
	var start: int = director.script_resource.rival_lives
	if lives < 0 || start <= 0:
		return Vector2i.ZERO
	return Vector2i(clampi(start - lives, 0, start), start)


func validate() -> bool:
	var complete: bool = super()
	if rival == Rival.NONE:
		Log.err("A lesson waits for an opponent to be beaten and names none", title)
		complete = false
	return complete
