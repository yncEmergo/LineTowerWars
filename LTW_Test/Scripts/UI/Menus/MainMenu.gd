class_name MainMenu
extends Control

## The screen the game boots into.
##
## Three ways out: straight into the prototype test scene, into the lobby
## browser, or out of the game entirely. Nothing here knows anything about
## networking - "Multiplayer" is a scene change like any other.
##
## The title comes off MenuConfig rather than being typed into the scene, because
## the game has no name yet and there will be more than one screen showing it.
## The corner line comes off BuildInfo, which is the file the build script
## stamps - so what a tester reads back is the build they are actually running.

@export_group("References")
@export var _title_label: Label
@export var _version_label: Label
@export var _play_button: Button
@export var _multiplayer_button: Button
@export var _quit_button: Button

var _config: MenuConfig:
	get:
		return References.menu_config


func _ready() -> void:
	if _config == null:
		Log.err("MainMenu found no MenuConfig on References, no button leads anywhere")
	else:
		# Once, here, rather than when a player presses the button that turns
		# out to point at nothing. The editor does not maintain path strings.
		_config.validate()
		_apply_branding()

	_connect_buttons()

	if _play_button != null:
		_play_button.grab_focus()


func _apply_branding() -> void:
	if _title_label != null:
		_title_label.text = _config.game_title
	if _version_label != null:
		_version_label.text = _build_label()


## What the corner says: the stage the project is at, and the stamp the build
## script wrote. One answer from one file - the stage word used to sit in
## MenuConfig, and a second place to say it is a second place for it to be wrong.
##
## Empty rather than a guess when the resource is missing, because a menu that
## states the wrong build is worse than one that states none.
func _build_label() -> String:
	var info: BuildInfo = References.build_info
	if info == null:
		Log.err("MainMenu found no BuildInfo on References, the corner cannot name this build")
		return ""
	return info.label_text()


func _connect_buttons() -> void:
	if _play_button != null:
		_play_button.pressed.connect(_on_play_pressed)
	if _multiplayer_button != null:
		_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	if _quit_button != null:
		_quit_button.pressed.connect(_on_quit_pressed)


func _on_play_pressed() -> void:
	MenuNavigation.to_game(self)


func _on_multiplayer_pressed() -> void:
	MenuNavigation.to_lobby_browser(self)


func _on_quit_pressed() -> void:
	MenuNavigation.quit_game(self)
