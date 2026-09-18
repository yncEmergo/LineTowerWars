class_name TutorialWaveStep
extends TutorialStep

## Finished once the wave this lesson put in the player's lane is gone from it.
##
## GONE rather than KILLED, and the difference is what keeps it finishable. A
## creep that gets through the maze steals a life and walks on - in a duel,
## straight back into the lane it just left - so it comes round again and the
## maze gets another go at it. Waiting for a kill count would wait for ever on a
## creep that leaked into nowhere; waiting for an empty lane cannot.
##
## Pair it with waves on the same step. Without a wave there is
## nothing to clear, and the step finishes the tick it opens.


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.wave_cleared()
