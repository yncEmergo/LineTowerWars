class_name TutorialInfoPanel
extends Control

## Everything the tutorial says while the world STANDS STILL, in the middle of
## the screen: a page of an explanation (see TutorialExplainStep) and a moment
## (see TutorialMoment). A few words and a Continue button, with everything
## around it dimmed but what the words are about.
##
## One panel for both, so every stop in the tutorial looks and answers the same
## way. The middle rather than the lesson panel's corner, because nothing else
## is happening: the words are the one thing on screen to read. It sits ABOVE
## the dims in the HUD, which is what keeps it lit.
##
## It owns nothing. Which page or moment is up is TutorialDirector's; Continue
## asks the director to move on.

@export_group("References")
## A moment's name - "Life stealing". Hidden on a page, which has none.
@export var _title_label: Label
@export var _text_label: Label
## "1 / 3" on an explanation, so a player knows how much of it there is.
## Hidden on a moment, which is one page.
@export var _count_label: Label
@export var _continue_button: Button

var _director: TutorialDirector:
	get:
		return References.tutorial_director


func _ready() -> void:
	# Read while the world is held, which every page and moment does.
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
	if director == null:
		hide()
		return
	var moment: TutorialMoment = director.current_moment()
	if moment != null:
		# Which side set it off decides the wording, because two of the three
		# are about what the player can do and read backwards in front of
		# somebody else's creep. See TutorialMoment.incoming_body.
		_show_words(moment.title, moment.body_for(director.moment_is_incoming()), "")
		return
	var page: TutorialPage = director.current_page()
	if page == null:
		hide()
		return
	var explain: TutorialExplainStep = director.current_step() as TutorialExplainStep
	var count: String = "" if explain == null \
		else "%d / %d" % [director.pages_read() + 1, explain.pages.size()]
	_show_words("", page.text, count)


func _show_words(title: String, text: String, count: String) -> void:
	show()
	if _title_label != null:
		_title_label.text = title
		_title_label.visible = !title.is_empty()
	if _text_label != null:
		_text_label.text = text
	if _count_label != null:
		_count_label.text = count
		_count_label.visible = !count.is_empty()


func _on_continue_pressed() -> void:
	var director: TutorialDirector = _director
	if director == null:
		return
	if director.current_moment() != null:
		director.dismiss_moment()
	else:
		director.acknowledge()
