class_name GameMenu
extends Control

## The in-match menu: resume, options, leave, quit.
##
## Deliberately NOT a pause menu. It does not touch get_tree().paused, because
## once the server owns the simulation there is nothing a single player can
## pause - the match keeps running whether this is open or not. Building it as
## a pause menu now would only mean unbuilding it later. See multiplayer.md.
##
## Escape is shared with the command card rather than taken from it. The card
## owns the key first: Escape cancels an armed ability, then backs out of a
## submenu, and only reaches this menu once there is nothing left to back out
## of. CommandController says so by emitting escape_unused. F10 opens it
## regardless, which is also the Warcraft III binding.

@export_group("References")
@export var _resume_button: Button
@export var _options_button: Button
@export var _leave_button: Button
@export var _quit_button: Button

var _commands: CommandController:
	get:
		return References.command_controller


func _ready() -> void:
	hide()
	_connect_buttons()

	if _commands != null:
		_commands.escape_unused.connect(open)
	else:
		Log.err("GameMenu found no CommandController on References, Escape will not open it")


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


func open() -> void:
	if visible:
		return
	show()
	if _resume_button != null:
		_resume_button.grab_focus()


func close() -> void:
	if !visible:
		return
	release_focus()
	hide()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _connect_buttons() -> void:
	if _resume_button != null:
		_resume_button.pressed.connect(close)
	if _leave_button != null:
		_leave_button.pressed.connect(_on_leave_pressed)
	if _quit_button != null:
		_quit_button.pressed.connect(_on_quit_pressed)
	if _options_button != null:
		# Nothing behind it yet, and a button that does nothing is worse than
		# one that says it cannot be pressed.
		_options_button.disabled = true


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
