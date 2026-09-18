class_name TutorialPanel
extends Control

## The lesson on screen: what it says, its tasks with a tickbox each, and the
## way on.
##
## **It runs while the tree is paused**, which is what its PROCESS_MODE_ALWAYS
## is for: a lesson that holds the world still must still be readable, and the
## only two things that answer a click then are this and the game menu.
##
## **It sits down the LEFT EDGE**, unlike the draft and the result board, which
## fill the middle. Those two are decisions that stop everything; a lesson has
## to be readable while the player is doing the thing it is talking about, so it
## may not cover the lane and it absolutely may not cover the COMMAND CARD. It
## is pinned to the TOP of that edge and grows DOWNWARDS.
##
## **It says when a task is done and when a new lesson starts**, because a
## tutorial that moves on silently leaves the player unsure whether what they
## did counted. Each task's box gets a green tick the moment the lesson is done,
## and stays ticked through the beat before the next lesson; the next lesson
## then arrives with a POP of the whole board.
##
## It owns nothing. Which lesson is open and whether it is finished are
## TutorialDirector's. There is no skip button - see TutorialDirector.advance.

## The pop a new lesson arrives with: from a touch small, past full size, and
## back. The peak is kept small and the board pops about its own middle, so it
## never grows past the screen's edge - the board sits a margin in from the
## left, and the overshoot is a few pixels of that margin.
const POP_START: float = 0.94
const POP_PEAK: float = 1.03
const POP_UP_SECONDS: float = 0.12
const POP_DOWN_SECONDS: float = 0.14
## What the button says on a lesson that is read, and on a moment.
const CONTINUE_TEXT: String = "Continue"
const MOMENT_TEXT: String = "OK"

@export_group("References")
## The board that pops, which is everything drawn.
@export var _board: Control
## Drives the pop. A child of the board.
@export var _pop: ScaleAnimation2D
## "Lesson 3 of 14", so a player knows how much of this is left.
@export var _progress_label: Label
@export var _title_label: Label
@export var _body_label: Label
## "Tasks", over the list, shown only when there are any.
@export var _tasks_heading: Label
## Where the task rows go, one per task.
@export var _task_list: Container
## One task row, instanced per task.
@export var _task_row_scene: PackedScene
## Finishes a lesson that is only read. Hidden on one with something to do,
## where pressing it would mean skipping the thing.
@export var _continue_button: Button

## The lesson last drawn, so a new one pops and a redraw of the same one does not.
var _shown_lesson: int = 0
## Whether a moment is what is drawn, so the lesson pops back when it is over.
var _showing_moment: bool = false
## The tasks as last drawn, so the rows are only rewritten when something moved.
var _tasks_shown: String = ""
var _rows: Array[TutorialTaskRow] = []

var _director: TutorialDirector:
	get:
		return References.tutorial_director


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	if _continue_button != null:
		_continue_button.pressed.connect(_on_continue_pressed)

	var director: TutorialDirector = _director
	if director == null:
		# A HUD with no director is a match that is not a tutorial, or this
		# scene opened on its own. Neither is broken: there is simply never a
		# lesson to show.
		return
	director.lesson_changed.connect(_refresh)
	_refresh()


## Redrawn whole when the lesson changes - opens, or finishes and waits.
func _refresh() -> void:
	var director: TutorialDirector = _director
	if director == null || !director.is_running():
		hide()
		return

	var step: TutorialStep = director.current_step()
	if step == null:
		hide()
		return

	# An explanation has the middle of the screen to itself - see
	# TutorialInfoPanel - and this panel would only be dimmed beside it.
	if step is TutorialExplainStep && director.current_moment() == null:
		hide()
		return
	show()
	if director.current_moment() != null:
		_show_moment(director.current_moment())
		return
	if _showing_moment:
		_showing_moment = false
		_shown_lesson = 0
	# A lesson can be several steps, one per task: the title and the text come
	# from the lesson's first step, unless the current task has words of its own.
	var lessons: TutorialScript = director.script_resource
	var head: TutorialStep = lessons.step_at(lessons.lesson_range(director.step_index()).x)
	var position_in_script: Vector2i = lessons.lesson_position(director.step_index())
	if _progress_label != null:
		_progress_label.text = "Lesson %d of %d" % [position_in_script.x, position_in_script.y]
	if _title_label != null:
		_title_label.text = head.title if head != null else step.title
	if _body_label != null:
		_body_label.text = step.body if !step.body.is_empty() || head == null else head.body
	_tasks_shown = ""
	_draw_tasks(step, director)

	if _continue_button != null:
		# Offered only where pressing it is what finishes the lesson. On a
		# lesson with something to do, the thing IS the button.
		_continue_button.visible = step is TutorialReadStep && !director.is_between_lessons()
		_continue_button.text = CONTINUE_TEXT

	if position_in_script.x != _shown_lesson:
		_shown_lesson = position_in_script.x
		_play_pop()


## A moment in place of the lesson: its words and an OK, and no tasks - the
## lesson's are still there when it is dismissed.
func _show_moment(moment: TutorialMoment) -> void:
	if _progress_label != null:
		_progress_label.text = ""
	if _title_label != null:
		_title_label.text = moment.title
	if _body_label != null:
		_body_label.text = moment.body
	if _task_list != null:
		_task_list.visible = false
	if _tasks_heading != null:
		_tasks_heading.visible = false
	_tasks_shown = ""
	if _continue_button != null:
		_continue_button.visible = true
		_continue_button.text = MOMENT_TEXT
	if !_showing_moment:
		_showing_moment = true
		_play_pop()


## The task counts move with the world, so they are polled.
func _process(_delta: float) -> void:
	if !visible:
		return
	var director: TutorialDirector = _director
	if director != null && director.current_moment() == null \
			&& director.current_step() != null:
		_draw_tasks(director.current_step(), director)


## One row per task, rewritten only when a task's text or tick changed, since
## this is asked every frame.
func _draw_tasks(step: TutorialStep, director: TutorialDirector) -> void:
	if _task_list == null || _task_row_scene == null:
		return
	var tasks: Array[TutorialStep.Task] = _lesson_tasks(step, director)
	var signature: String = ""
	for task: TutorialStep.Task in tasks:
		signature += "%s|%s|%s;" % [task.text, task.done, task.pending]
	if signature == _tasks_shown:
		return
	_tasks_shown = signature

	while _rows.size() < tasks.size():
		var row: TutorialTaskRow = _task_row_scene.instantiate() as TutorialTaskRow
		if row == null:
			Log.err("The tutorial task row scene is not a TutorialTaskRow")
			return
		_task_list.add_child(row)
		_rows.append(row)
	for index in range(_rows.size()):
		var shown: bool = index < tasks.size()
		_rows[index].visible = shown
		if shown:
			_rows[index].show_task(tasks[index])
	_task_list.visible = !tasks.is_empty()
	if _tasks_heading != null:
		_tasks_heading.visible = !tasks.is_empty()


## Every task of the lesson the current step belongs to, in order: the ones
## before it done, its own as it stands, and the ones after it still to come.
func _lesson_tasks(step: TutorialStep, director: TutorialDirector) -> Array[TutorialStep.Task]:
	var tasks: Array[TutorialStep.Task] = []
	var lessons: TutorialScript = director.script_resource
	var current: int = director.step_index()
	var lesson: Vector2i = lessons.lesson_range(current)
	for index in range(lesson.x, lesson.y + 1):
		var other: TutorialStep = lessons.step_at(index)
		if other == null || other.objective.is_empty():
			continue
		if index == current:
			tasks.append_array(step.tasks(director))
		else:
			tasks.append(TutorialStep.Task.new(other.objective, index < current, index > current))
	return tasks


## The board pops about its own middle. Deferred a frame so the board has been
## laid out for the new lesson's text before its middle is taken.
func _play_pop() -> void:
	if _board == null || _pop == null:
		return
	await get_tree().process_frame
	if !is_instance_valid(_board):
		return
	_board.pivot_offset = _board.size * 0.5
	_pop.do_pop(Vector2.ONE * POP_START, Vector2.ONE * POP_PEAK, Vector2.ONE,
		POP_UP_SECONDS, POP_DOWN_SECONDS)


func _on_continue_pressed() -> void:
	var director: TutorialDirector = _director
	if director == null:
		return
	if director.current_moment() != null:
		director.dismiss_moment()
	else:
		director.acknowledge()

