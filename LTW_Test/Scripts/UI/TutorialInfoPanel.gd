class_name TutorialInfoPanel
extends Control

## The page of an explanation, in the middle of the screen: a few words and a
## Continue button, while everything around it is dimmed but the one HUD element
## the page is about. See TutorialExplainStep.
##
## The middle rather than the lesson panel's corner, because an explanation
## holds the world: nothing else is happening, and the page is the one thing on
## screen to read. It sits ABOVE the pointer's dim in the HUD, which is what
## keeps it lit.
##
## It owns nothing. Which page is up is TutorialDirector's; Continue asks the
## director to turn it.

@export_group("References")
@export var _text_label: Label
## "1 / 3", so a player knows how much of this there is.
@export var _count_label: Label
@export var _continue_button: Button

var _director: TutorialDirector:
	get:
		return References.tutorial_director


func _ready() -> void:
	# Read while the world is held, which every explanation does.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	if _continue_button != null:
		_continue_button.pressed.connect(_on_continue_pressed)
	var director: TutorialDirector = _director
	if director == null:
		return
	director.lesson_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var director: TutorialDirector = _director
	var page: TutorialPage = null if director == null else director.current_page()
	visible = page != null
	if page == null:
		return
	var explain: TutorialExplainStep = director.current_step() as TutorialExplainStep
	if _text_label != null:
		_text_label.text = page.text
	if _count_label != null && explain != null:
		_count_label.text = "%d / %d" % [director.pages_read() + 1, explain.pages.size()]


func _on_continue_pressed() -> void:
	var director: TutorialDirector = _director
	if director != null:
		director.acknowledge()
