class_name GameMenu
extends Control

## The in-match menu: resume, options, leave, quit - and, in a networked match,
## pause.
##
## **It pauses two completely different ways, because the two matches are
## different things.**
##
##   OFFLINE   opening this menu holds the world for as long as it is open.
##             There is nobody to agree with, so the hold is taken here and
##             released when the menu closes. A single player reads their
##             options with the game standing still, which is what every other
##             game does.
##   NETWORKED opening it holds NOTHING. Nine other people are playing, and a
##             world this machine held on its own would not be the same world
##             any more - under lockstep it would not even be a divergence
##             worth diagnosing, it would be this peer simulating fewer ticks
##             than everybody else. The menu instead offers a PAUSE BUTTON,
##             which sends an order that pauses the match for everybody on one
##             agreed turn. See MatchPause.
##
## So the old note here - that this is deliberately not a pause menu, because
## nothing a single player does can pause a served match - was right about the
## networked half and has been answered for the offline one.
##
## Escape is shared with the command card rather than taken from it. The card
## owns the key first: Escape cancels an armed ability, then backs out of a
## submenu, and only reaches this menu once there is nothing left to back out
## of. CommandController says so by emitting escape_unused. F10 opens it
## regardless, which is also the Warcraft III binding.
##
## The options screen continues that chain one link further. It is a child of
## this node rather than a screen of its own so the key never has to be handed
## over: Escape reaches the same handler either way and close() peels whichever
## layer is on top. Two nodes both watching for Escape would have to agree on
## who goes first, and _input ordering is not a thing to build a menu on.

## The name the OFFLINE hold is taken under. Its own, so it can neither release
## nor be released by a draft or a lockstep stall - see MatchSession.hold.
const HOLD_REASON: StringName = &"menu"

@export_group("References")
@export var _resume_button: Button
## Pauses the match for everybody, or asks for it back. Hidden outright in a
## match that cannot be paused, which is every offline one - see MatchPause.
@export var _pause_button: Button
@export var _options_button: Button
@export var _leave_button: Button
@export var _quit_button: Button
## Fullscreen and opaque, so it covers this menu rather than replacing it.
@export var _options_menu: OptionsMenu

## Whether this menu is currently holding the world still. Kept rather than
## derived so the release cannot be skipped by a session that went away first.
var _holding: bool = false

var _commands: CommandController:
	get:
		return References.command_controller

var _pause: MatchPause:
	get:
		return References.match_pause


func _ready() -> void:
	hide()
	_connect_buttons()

	if _commands != null:
		_commands.escape_unused.connect(open)
	else:
		Log.err("GameMenu found no CommandController on References, Escape will not open it")

	var pause: MatchPause = _pause
	if pause != null:
		pause.pause_changed.connect(_refresh_pause_button)
	_refresh_pause_button()


## Belt and braces: a road out of the match taken with this open must not leave
## the tree paused for the rest of the process. MatchSession clears its own
## holds on the way out, and this keeps the flag honest for a menu that is
## somehow re-entered.
func _exit_tree() -> void:
	_holding = false


## Handled in _input rather than _unhandled_input so an open menu always wins
## the key, whatever the world underneath would have done with it.
func _input(event: InputEvent) -> void:
	if !(event is InputEventKey):
		return

	var key: InputEventKey = event as InputEventKey
	if !key.pressed || key.echo:
		return

	if key.keycode == KEY_F10:
		toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE && visible:
		close()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE && _world_is_paused():
		# **Escape has to reach this menu directly while the match is PAUSED.**
		# Ordinarily it arrives second hand - the command card gets the key
		# first and emits escape_unused once there is nothing left to back out
		# of - and CommandController is paused with the world, so that chain is
		# dead exactly when the button that ends the pause lives in here. The
		# guard keeps it to that case: in ordinary play this branch is never
		# reached and the card still owns the key.
		open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return
	show()
	_refresh_pause_button()
	_hold_world(true)


## Closes ONE layer: the options screen if it is up, this menu otherwise. So
## Escape out of Video lands back on Resume rather than in the game, which is
## the same one-step-at-a-time rule the command card follows.
func close() -> void:
	if _options_menu != null && _options_menu.visible:
		_options_menu.close()
		return
	if !visible:
		return
	release_focus()
	hide()
	_hold_world(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Holds the world while this menu is open, in a match where that is this
## machine's to decide. **Offline only, and the guard is the whole point**: a
## networked peer that paused its own tree would run fewer ticks than every
## other machine in the match, which under lockstep is a desync rather than a
## pause. What a networked player presses instead is the button below.
func _hold_world(held: bool) -> void:
	if held == _holding:
		return
	if Net.is_online():
		return

	var session: MatchSession = References.match_session
	if session == null:
		return
	_holding = held
	session.hold(HOLD_REASON, held)


## The one button whose LABEL is a reading of the world rather than a fixed
## word, so it is redrawn whenever the pause changes and whenever this opens.
##
## Three states and only two words: a match that is counting down to resuming
## offers PAUSE again, because pressing it there is how a countdown is called
## off - and a button that read "Unpause" while the world was already on its way
## back would be the one press that does nothing.
## Whether the world is being held still by a PAUSE somebody pressed, which is
## the one state where this menu answers Escape on its own.
func _world_is_paused() -> bool:
	var pause: MatchPause = _pause
	return pause != null && pause.is_holding()


func _refresh_pause_button() -> void:
	if _pause_button == null:
		return

	var pause: MatchPause = _pause
	if pause == null || !pause.can_pause():
		_pause_button.hide()
		return

	_pause_button.show()
	# An opening holds the world for its own reasons and refuses every order but
	# a draft pick, so there is nothing to press until it is over.
	var opening: StartingTech = References.starting_tech
	_pause_button.disabled = opening != null && opening.is_holding()
	var unpausing: bool = pause.is_holding() && !pause.is_counting_down()
	_pause_button.text = "Unpause" if unpausing else "Pause"


func _connect_buttons() -> void:
	if _resume_button != null:
		_resume_button.pressed.connect(close)
	if _pause_button != null:
		_pause_button.pressed.connect(_on_pause_pressed)
	if _leave_button != null:
		_leave_button.pressed.connect(_on_leave_pressed)
	if _quit_button != null:
		_quit_button.pressed.connect(_on_quit_pressed)

	if _options_menu == null:
		if _options_button != null:
			# A button that does nothing is worse than one that says it cannot
			# be pressed.
			_options_button.disabled = true
		Log.err("GameMenu has no OptionsMenu assigned, its Options button is dead")
		return

	if _options_button != null:
		_options_button.pressed.connect(_options_menu.open)


## The menu deliberately STAYS OPEN on a pause press. The order takes a turn to
## land, so closing here would leave the player looking at a world that stops a
## moment later for no reason they can see - and whoever wants to unpause wants
## the button they just pressed to still be there.
func _on_pause_pressed() -> void:
	var pause: MatchPause = _pause
	if pause == null:
		return
	pause.request_toggle()


## Back to the main menu, hanging up on the way: the menu is offline territory,
## and a connection left open there would have nothing driving it.
##
## Once a match is a real server session this has to tell the server the player
## is forfeiting rather than merely disconnecting, and land in the lobby rather
## than the menu.
func _on_leave_pressed() -> void:
	# Goodbye first, socket second - MatchStart owns that ordering, because
	# getting it wrong makes a deliberate leave look exactly like a crash and
	# costs the other player a ten second hold (3.6). Not awaited: it finishes
	# on its own a frame or two after this screen is gone.
	MatchStart.leave_match()
	MenuNavigation.to_main_menu(self)


func _on_quit_pressed() -> void:
	MenuNavigation.quit_game(self)
