class_name FreeOnTimeout
extends Node

## Frees the node it is attached to when a Timer beside it runs out.
##
## PRESENTATION ONLY, for the one-shot effects that have no script of their own
## to clean up after. A CPUParticles3D burst stops emitting when it is done and
## then simply stays there, so without this a maze full of grinders piles up one
## dead node per swing until the match ends.
##
## Frees its PARENT rather than itself, because the parent is the effect and
## this is a part of it.

@export_group("References")
## The timer to listen to. A sibling in every prefab so far, wired explicitly
## rather than walked to, like every other reference in the project.
@export var _timer: Timer


func _ready() -> void:
	if _timer == null:
		Log.err("FreeOnTimeout has no timer assigned in its prefab", name)
		return
	_timer.timeout.connect(_on_timeout)


func _on_timeout() -> void:
	var effect: Node = get_parent()
	if effect != null:
		effect.queue_free()
