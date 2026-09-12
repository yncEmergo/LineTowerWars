class_name TutorialWaitStep
extends TutorialStep

## Finished after a number of seconds, whatever the player does.
##
## For the moments the tutorial wants somebody to WATCH: a wave walking a maze,
## an income tick landing, a creep leaking. A step like this never pauses the
## world - that would be the one thing it must not do - so pauses_world should
## be left off wherever one is authored.

@export_group("Objective")
@export var seconds: float = 6.0


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.seconds_on_step() >= maxf(0.1, seconds)
