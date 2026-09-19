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
## Its progress counts WAVES killed - a wave being every entry sharing one
## delay - or, with counts_creeps, the CREEPS, for one big wave where "1 / 1"
## says nothing. See TutorialWaves.
##
## Pair it with waves on the same step. Without a wave there is nothing to
## clear, and the step finishes the tick it opens.

@export_group("Objective")
## Whether the count is of creeps rather than of waves.
@export var counts_creeps: bool = false


func is_complete(director: TutorialDirector) -> bool:
	if director == null || !director.waves().all_sent():
		return false
	var area: PlayerArea = _local_area()
	return area == null || area.creeps().is_empty()


func progress(director: TutorialDirector) -> Vector2i:
	if director == null:
		return Vector2i.ZERO
	var waves: TutorialWaves = director.waves()
	if counts_creeps:
		return Vector2i(waves.killed_creeps(_local_area()), waves.total_creeps())
	return Vector2i(waves.killed(_local_area()), waves.total())
