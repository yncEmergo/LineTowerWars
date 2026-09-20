class_name PausePanel
extends Control

## What a PAUSED match looks like from outside the menu: who paused it, and the
## countdown once somebody has asked for it back.
##
## **It exists because the button does not.** The pause is pressed in the game
## menu, so the player who pressed it knows what happened - and everybody else
## has a world that simply stopped. A freeze with nothing on screen to explain
## it is exactly what StallPanel was built to stop being, and a pause is a
## freeze somebody chose.
##
## **It runs while the tree is paused**, like the grace and draft screens, and
## for the same reason: the world is held for the whole of it. It decides
## nothing - what is held and how long is left is MatchPause's, counted in
## simulation ticks by the turn stream - and only draws the whole seconds of it.
##
## It takes no clicks (everything in it ignores the mouse) so the menu that owns
## the button can be opened straight through it.

@export_group("References")
## Which of the two states this is, in one word.
@export var _title_label: Label
## Who paused it, or what to press to get it back.
@export var _detail_label: Label
## The number counting down, hidden until there is one.
@export var _count_label: Label

var _pause: MatchPause:
	get:
		return References.match_pause


func _ready() -> void:
	# The world is held still for the whole of this, so the screen that explains
	# it has to keep running. See MatchSession.hold.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

	var pause: MatchPause = _pause
	if pause == null:
		# A HUD with no MatchPause is a scene run on its own, not a broken match.
		Log.warn("PausePanel found no MatchPause, a pause will not be shown")
		return
	pause.pause_changed.connect(_on_pause_changed)
	_on_pause_changed()


## Redrawn on the pause's own signal, which fires as each whole second passes
## rather than on every tick.
func _on_pause_changed() -> void:
	var pause: MatchPause = _pause
	if pause == null || !pause.is_holding():
		hide()
		return

	show()
	if pause.is_counting_down():
		_draw_countdown(pause)
		return
	_draw_paused(pause)


func _draw_countdown(pause: MatchPause) -> void:
	if _title_label != null:
		_title_label.text = "RESUMING"
	if _detail_label != null:
		_detail_label.text = ""
	if _count_label == null:
		return
	_count_label.show()
	# The same rounding the grace countdown draws: a number on screen counts
	# down to 1 and then the world moves, rather than sitting on 0.
	_count_label.text = str(maxi(1, ceili(pause.seconds_left())))


func _draw_paused(pause: MatchPause) -> void:
	if _title_label != null:
		_title_label.text = "PAUSED"
	if _count_label != null:
		_count_label.hide()
	if _detail_label != null:
		var who: String = _name_of(pause.paused_by())
		# The key is named because it is the only way in: the menu that carries
		# the Unpause button is opened with Escape or F10 and by nothing a
		# player can click, since the whole HUD is paused underneath this.
		_detail_label.text = "%s paused the match - press Esc to unpause" % who


## Who paused it, by the name the rest of the HUD calls them - which in an
## anonymous match is their colour rather than their name. MatchSession already
## answers that question for every other screen, so this asks it rather than
## reading the roster itself.
func _name_of(slot: int) -> String:
	var session: MatchSession = References.match_session
	if session == null || slot <= 0:
		return "Somebody"
	return session.display_name_for(slot)
