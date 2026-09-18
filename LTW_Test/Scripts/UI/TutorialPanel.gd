class_name TutorialPanel
extends Control

## The lesson on screen: what it says, what to do, and the way on.
##
## **It runs while the tree is paused**, which is what its PROCESS_MODE_ALWAYS
## is for and is the whole reason a lesson can hold the world at all. A lesson
## that is only READ stops the match while it is up, so the player is not being
## leaked on while they read a paragraph - and the only two things that answer a
## click are this and the menu that lets them leave.
##
## **It sits down the LEFT EDGE**, unlike the draft and the result board, which
## fill the middle. Those two are decisions that stop everything; a lesson has
## to be readable while the player is doing the thing it is talking about, so it
## may not cover the lane and it absolutely may not cover the COMMAND CARD -
## which the first version did, while telling the player to press a button on
## it. The left edge is the one part of this HUD with nothing in it but the
## minimap.
##
## It is pinned to the TOP of that edge and grows DOWNWARDS, rather than sitting
## centred: a long lesson then runs towards empty screen instead of into the
## send bar - which the sending lesson points an arrow at.
##
## It owns nothing. Which lesson is open and whether it is finished are
## TutorialDirector's; the two buttons report a press and nothing else.

@export_group("References")
## "3 of 14", so a player knows how much of this is left.
@export var _progress_label: Label
@export var _title_label: Label
@export var _body_label: Label
## The one line saying what to do NOW, hidden on a lesson that only explains.
@export var _objective_label: Label
## Finishes a lesson that is only read. Hidden on one with something to do,
## where pressing it would mean skipping the thing.
@export var _continue_button: Button
## The way past a lesson that will not finish. Appears on its own after a while
## - see TutorialDirector.may_skip - rather than being offered at once, which
## would read as an invitation.
@export var _skip_button: Button

## The progress reading last drawn, so the label is only rewritten when it
## moves. "-" is a value no step returns, which forces the first draw.
var _progress_shown: String = "-"

var _director: TutorialDirector:
	get:
		return References.tutorial_director


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	if _continue_button != null:
		_continue_button.pressed.connect(_on_continue_pressed)
	if _skip_button != null:
		_skip_button.pressed.connect(_on_skip_pressed)

	var director: TutorialDirector = _director
	if director == null:
		# A HUD with no director is a match that is not a tutorial, or this
		# scene opened on its own. Neither is broken: there is simply never a
		# lesson to show.
		return
	director.lesson_changed.connect(_refresh)
	_refresh()


## Redrawn whole when the lesson changes. It changes a few dozen times in a
## whole tutorial, so there is nothing here worth being clever about.
func _refresh() -> void:
	var director: TutorialDirector = _director
	if director == null || !director.is_running():
		hide()
		return

	var step: TutorialStep = director.current_step()
	if step == null:
		hide()
		return

	show()
	if _progress_label != null:
		_progress_label.text = "Lesson %d of %d" % [
			director.lesson_number(), director.lesson_count(),
		]
	if _title_label != null:
		_title_label.text = step.title
	if _body_label != null:
		_body_label.text = step.body
	_progress_shown = "-"
	_draw_objective(step, director)

	if _continue_button != null:
		# Offered only where pressing it is what finishes the lesson. On a
		# lesson with something to do, the thing IS the button.
		_continue_button.visible = step is TutorialReadStep
	if _skip_button != null:
		_skip_button.hide()


## The skip button appears on its own once the lesson has been open long enough,
## which is why this is polled rather than drawn once with the rest.
##
## _process rather than _physics_process: it is a button appearing, and the beat
## it appears on is a render frame. The reading behind it is the director's
## simulation clock either way.
func _process(_delta: float) -> void:
	if !visible:
		return
	var director: TutorialDirector = _director
	if _skip_button != null:
		_skip_button.visible = director != null && director.may_skip()
	if director != null && director.current_step() != null:
		_draw_objective(director.current_step(), director)


## The objective line, with how far along it is when the step can count that -
## "Build a Lesser Sentry on each blue square.  3 / 7". Redrawn only when the
## count moves, since this is asked every frame.
func _draw_objective(step: TutorialStep, director: TutorialDirector) -> void:
	if _objective_label == null:
		return
	var progress: String = step.progress_text(director)
	if progress == _progress_shown:
		return
	_progress_shown = progress
	_objective_label.visible = !step.objective.is_empty()
	if progress.is_empty():
		_objective_label.text = step.objective
	else:
		_objective_label.text = "%s   %s" % [step.objective, progress]


func _on_continue_pressed() -> void:
	var director: TutorialDirector = _director
	if director != null:
		director.acknowledge()


func _on_skip_pressed() -> void:
	var director: TutorialDirector = _director
	if director != null:
		director.skip()
