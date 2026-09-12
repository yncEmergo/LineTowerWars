class_name MainMenu
extends Control

## The screen the game boots into.
##
## The ways out are the game modes and nothing else: the tutorial, a match
## against computer opponents, a match against people, and the way out of the
## game entirely. Nothing here knows anything about networking or about AI -
## every one of them is a scene change like any other.
##
## The test scene is still reachable and is still not a game mode: it opens the
## match scene with no setup in front of it, which stands a single player one in
## from GameConfig. It is how the prototype is iterated on and it says so.
##
## The title comes off MenuConfig rather than being typed into the scene, because
## the game has no name yet and there will be more than one screen showing it.
## The corner line comes off BuildInfo, which is the file the build script
## stamps - so what a tester reads back is the build they are actually running.

@export_group("References")
@export var _title_label: Label
@export var _version_label: Label
## Opens the match scene with no setup at all, which stands in a one player
## match from GameConfig. A development shortcut rather than a mode.
@export var _play_button: Button
@export var _tutorial_button: Button
@export var _singleplayer_button: Button
@export var _multiplayer_button: Button
@export var _options_button: Button
@export var _quit_button: Button
## The same screen the in-match menu opens, instanced here too.
##
## Instanced rather than routed to as a scene of its own, because it edits
## UserSettings directly and has nothing to say back - so there is no state to
## carry across a scene change, and coming BACK from it would otherwise mean
## rebuilding this menu.
@export var _options_menu: OptionsMenu

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

	# The first thing a new player should press, and the first thing a returning
	# one skips past. Focus starts here rather than on the development shortcut
	# above it.
	if _tutorial_button != null:
		_tutorial_button.grab_focus()
	elif _play_button != null:
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
	if _tutorial_button != null:
		_tutorial_button.pressed.connect(_on_tutorial_pressed)
	if _singleplayer_button != null:
		_singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	if _multiplayer_button != null:
		_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	if _quit_button != null:
		_quit_button.pressed.connect(_on_quit_pressed)

	if _options_menu == null:
		if _options_button != null:
			# A button that does nothing is worse than one that says it cannot
			# be pressed - the same call GameMenu makes.
			_options_button.disabled = true
		Log.err("MainMenu has no OptionsMenu assigned, its Options button is dead")
		return

	_options_menu.closed.connect(_on_options_closed)
	if _options_button != null:
		_options_button.pressed.connect(_options_menu.open)


## Focus goes back to the button that opened the screen rather than to the top of
## the menu, so backing out with the keyboard leaves the cursor where the player
## left it.
func _on_options_closed() -> void:
	if _options_button != null:
		_options_button.grab_focus()


func _on_play_pressed() -> void:
	MenuNavigation.to_game(self)


## Straight into the teaching match. It has one shape and one roster, so there
## is nothing to set up first - see TutorialSetup.
##
## Down the SAME road a single player match takes: through the loading screen,
## which warms every unit, model and sound the match can spawn before the world
## is built. A tutorial that skipped that would freeze the first time it put a
## creep in front of somebody being taught what a creep is.
func _on_tutorial_pressed() -> void:
	MenuNavigation.to_match_loading(
		self, TutorialSetup.create(References.game_config, References.ai_config)
	)


func _on_singleplayer_pressed() -> void:
	MenuNavigation.to_skirmish_setup(self)


func _on_multiplayer_pressed() -> void:
	MenuNavigation.to_lobby_browser(self)


func _on_quit_pressed() -> void:
	MenuNavigation.quit_game(self)
