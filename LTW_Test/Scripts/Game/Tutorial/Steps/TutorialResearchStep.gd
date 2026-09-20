class_name TutorialResearchStep
extends TutorialStep

## Finished once the player owns every technology this task NAMES, and nothing
## else has to happen.
##
## The technologies are `TutorialStep.tech_ids`, which is also the only list the
## Research Center will accept while the task is up - so what the border points
## at and what the task waits for are one list and cannot drift apart. Every
## other square is dimmed, and the Ultimate shortcuts are refused, which is how
## the tutorial makes sure the player ends up with the Ultimate the rest of it
## is written around.
##
## ONE technology per task, in practice. A free technology and the tower it
## unlocks were one task for a while and it read as two things stacked in one
## line; the tower it pays for is the task after it, and each is a tick of its
## own. See TutorialOwnStep for those.


func is_complete(director: TutorialDirector) -> bool:
	var counted: Vector2i = progress(director)
	return counted.y > 0 && counted.x >= counted.y


func progress(director: TutorialDirector) -> Vector2i:
	return Vector2i(techs_owned(director), tech_ids.size())


func validate() -> bool:
	var complete: bool = super()
	if tech_ids.is_empty():
		Log.err("A research task names no technology, nothing would finish it", resource_path)
		complete = false
	return complete
