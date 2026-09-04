class_name DesyncNotice
extends Control

## The one screen that says a match has stopped being trustworthy, and ends it.
##
## **A desync is not recoverable and this screen does not pretend otherwise.**
## There is no Resume and no Retry, because there is nothing to resume into:
## this machine's world and the server's have already diverged, and every tick
## after that point widens the gap. The only honest options are to read what
## happened and leave, so those are the only two things here.
##
## It is deliberately MODAL in the strongest sense the project has - it dims the
## world, swallows every mouse event, and eats keyboard input including the keys
## that would otherwise open the game menu or send a creep. A player who can
## still order units in a desynced match is being lied to, and the orders would
## be refused or, worse, applied to a world nobody else can see.
##
## Raised by `MatchStart.desync_detected` and by nothing else. See
## `MatchStartService.receive_desync`, which is where the server tells this
## machine that its world is wrong.

@export_group("References")
@export var _detail_label: Label
@export var _menu_button: Button


func _ready() -> void:
	hide()
	# Above the HUD and above the game menu, since neither is reachable once
	# this is up and both would draw over it otherwise.
	z_index = 100

	if _menu_button != null:
		_menu_button.pressed.connect(_on_menu_pressed)

	MatchStart.desync_detected.connect(_on_desync_detected)


## Every key while this is up, including the ones the world would have taken.
##
## `_input` rather than `_unhandled_input` for the reason `GameMenu` gives: an
## open modal has to win the key before anything under it sees it. The
## difference is that this one never lets ANY key through, where the game menu
## deliberately passes most of them on.
func _input(event: InputEvent) -> void:
	if !visible:
		return
	if event is InputEventKey || event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _on_desync_detected(tick: int, detail: String) -> void:
	if visible:
		# Already up. The first divergence is the one worth reading; everything
		# after it is a consequence of it, and rewriting the label would replace
		# the true cause with its own aftermath.
		return

	if _detail_label != null:
		_detail_label.text = detail

	Log.info("Desync notice shown", {"tick": tick})
	show()
	if _menu_button != null:
		_menu_button.grab_focus()


func _on_menu_pressed() -> void:
	# The same order GameMenu leaves in, and for the same reason: say goodbye
	# before closing the socket, or a deliberate exit looks like a crash and
	# costs the other player the full grace period.
	MatchStart.leave_match()
	MenuNavigation.to_main_menu(self)
