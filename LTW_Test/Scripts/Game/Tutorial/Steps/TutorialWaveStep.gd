class_name TutorialWaveStep
extends TutorialStep

## Finished once every wave this lesson sends has gone out and the player's lane
## is empty again.
##
## EMPTY rather than a kill count, and the difference is what keeps it
## finishable: a creep that gets through the maze steals a life and walks on or
## leaves, so an empty lane always arrives, where a kill count would wait for
## ever on a creep that leaked.
##
## Its progress counts WAVES KILLED - a wave being every entry sharing one delay
## - which is what a player watching them come in can follow. See TutorialWaves.
##
## Pair it with waves on the same step. Without a wave there is nothing to
## clear, and the step finishes the tick it opens.


func is_complete(director: TutorialDirector) -> bool:
	if director == null || !director.waves().all_sent():
		return false
	var area: PlayerArea = _local_area()
	return area == null || area.creeps().is_empty()


func progress(director: TutorialDirector) -> Vector2i:
	if director == null:
		return Vector2i.ZERO
	return Vector2i(director.waves().killed(_local_area()), director.waves().total())
