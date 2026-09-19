class_name TutorialDefeatPanel
extends Control

## What the tutorial shows when the player runs out of lives: the world held, a
## full-screen dim that swallows every click, and two ways out - try again from
## the first lesson, or back to the main menu.
##
## Its own screen rather than the result board, because a tutorial lost is not a
## match to be summarised: the match usually has two opponents still standing,
## and what the player wants is another go. TutorialDirector holds the world and
## says when; this only draws it and leaves.

@export_group("References")
## Everything drawn. Hidden until the tutorial is lost.
@export var _panel: Control
@export var _retry_button: Button
@export var _menu_button: Button

var _director: TutorialDirector:
	get:
		return References.tutorial_director


func _ready() -> void:
	# Up while the world is held, which it is from the moment this opens.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _panel != null:
		_panel.hide()
	if _retry_button != null:
		_retry_button.pressed.connect(_on_retry_pressed)
	if _menu_button != null:
		_menu_button.pressed.connect(_on_menu_pressed)
	var director: TutorialDirector = _director
	if director != null:
		director.lost.connect(_open)


func _open() -> void:
	if _panel != null:
		_panel.show()


## From the first lesson, down the same road the main menu's Tutorial button
## takes - the loading screen, which warms the match before it is built.
func _on_retry_pressed() -> void:
	MatchStart.leave_match()
	MenuNavigation.to_match_loading(
		self, TutorialSetup.create(References.game_config, References.ai_config)
	)


func _on_menu_pressed() -> void:
	MatchStart.leave_match()
	MenuNavigation.to_main_menu(self)
