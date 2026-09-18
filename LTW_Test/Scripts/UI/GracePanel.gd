class_name GracePanel
extends Control

## The countdown a match opens on: the world held still for a few seconds before
## anything can happen, so every machine reaches the first real turn together.
##
## **It runs while the tree is paused**, like the draft screen and the reveal, and
## for the same reason: the world is held for the whole of it. It decides nothing -
## how long is left is StartingTech's, counted in simulation ticks by the turn
## stream - and only draws the whole seconds of it.

@export_group("References")
## The number counting down.
@export var _count_label: Label

var _opening: StartingTech:
	get:
		return References.starting_tech


func _ready() -> void:
	# The world is held still for the whole of this, so the screen it is being
	# held for has to keep running. See MatchSession.hold.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

	var opening: StartingTech = _opening
	if opening == null:
		# A HUD with no StartingTech is a scene run on its own, not a broken match.
		Log.warn("GracePanel found no StartingTech, no countdown can be shown")
		return
	opening.opening_changed.connect(_on_opening_changed)
	_on_opening_changed()


## Redrawn on the opening's own signal, which fires as each whole second passes.
func _on_opening_changed() -> void:
	var opening: StartingTech = _opening
	if opening == null || !opening.is_in_grace():
		hide()
		return
	show()
	if _count_label != null:
		_count_label.text = str(maxi(1, ceili(opening.seconds_left())))
