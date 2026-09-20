class_name TutorialPanel
extends Control

## The lesson on screen: what it says, the ONE task that is open, and the way
## on.
##
## **It runs while the tree is paused**, which is what its PROCESS_MODE_ALWAYS
## is for: a lesson that holds the world still must still be readable, and the
## only two things that answer a click then are this and the game menu. The
## animations run then too, for the same reason - a tween is paused with the
## node that owns it, and these nodes are never paused.
##
## **It sits down the LEFT EDGE**, unlike the draft and the result board, which
## fill the middle. Those two are decisions that stop everything; a lesson has
## to be readable while the player is doing the thing it is talking about, so it
## may not cover the lane and it absolutely may not cover the COMMAND CARD. It
## is pinned to the TOP of that edge and grows DOWNWARDS.
##
## **ONE TASK AT A TIME, and the board says so out loud.** A task that is done
## gets its tick popped in and its line turned green where it stands, and only
## then does the block carrying it slide out and the next one slide in. The
## alternative - the whole list drawn with the done ones ticked and the coming
## ones faded - was what this did first, and it does not survive a lesson with
## sixteen rungs in it: the one line that matters is somewhere in a wall of
## text. How far through the lesson the player is moved into the header instead,
## where it is a number rather than fifteen sentences.
##
## What the block does is three animator components rather than an
## AnimationPlayer, which is how the rest of the project animates a Control.
## See Docs/ui.md section 2, which also says why the block may be MOVED at all
## while the task row inside it may not be.
##
## It owns nothing else. Which lesson is open and whether it is finished are
## TutorialDirector's. There is no skip button - see TutorialDirector.advance.

## The pop a new LESSON arrives with: from a touch small, past full size, and
## back. The peak is kept small and the board pops about its own middle, so it
## never grows past the screen's edge - the board sits a margin in from the
## left, and the overshoot is a few pixels of that margin.
const POP_START: float = 0.94
const POP_PEAK: float = 1.03
const POP_UP_SECONDS: float = 0.12
const POP_DOWN_SECONDS: float = 0.14
## The block carrying the body and the task: how far it travels coming in and
## going out, how long each takes, and how small it starts.
##
## IN from the right and OUT to the left, so a lesson reads as a queue moving
## past rather than as one panel flickering.
const SLIDE_IN: float = 28.0
const SLIDE_OUT: float = 22.0
const ENTER_SECONDS: float = 0.24
const EXIT_SECONDS: float = 0.18
const BLOCK_SCALE: float = 0.96
## How far right of the open Research Center the board steps, so a research task
## can be read beside the squares it names rather than on top of them.
const CLEAR_OF_RESEARCH: float = 12.0
## What the button says on a lesson that is read.
const CONTINUE_TEXT: String = "Continue"

@export_group("References")
## The board that pops, which is everything drawn.
@export var _board: Control
## Drives the pop. A child of the board.
@export var _pop: ScaleAnimation2D
## "Lesson 3 of 7 - Task 4 of 16", so a player knows how much of this is left.
@export var _progress_label: Label
@export var _title_label: Label
## What the CURRENT TASK says and the task itself, animated as one thing: the
## sentence explaining a rung belongs to that rung, so it arrives and leaves
## with it.
@export var _step_block: Control
@export var _block_fade: FadeAnimation2D
@export var _block_move: MoveAnimation2D
@export var _block_scale: ScaleAnimation2D
@export var _body_label: Label
## The one task row, instanced into the block rather than built here.
@export var _task_row: TutorialTaskRow
## Finishes a lesson that is only read. Hidden on one with something to do,
## where pressing it would mean skipping the thing.
@export var _continue_button: Button
## The row the button sits in, hidden with it - an empty HBox still asks the
## column for its separation, which reads as a band of dead space under a
## one-line task.
@export var _footer: Control

## The lesson last drawn, so a new one pops and a redraw of the same one does not.
var _shown_lesson: int = 0
## The task last drawn, and whether it was drawn as done - the two readings the
## state machine in _process works from.
var _shown_text: String = ""
var _shown_done: bool = false
## The step the task on screen belongs to, which is what says whether a task
## whose TEXT has changed is a new task or the same one counting. See _swap_to.
var _shown_step: int = -1
## Whether the block has already been taken off screen for the task it is
## showing, so a finished task is not slid out twice.
var _exited: bool = false
## Whether an animation is running. The poll below leaves the block alone until
## it finishes, so nothing is rewritten half way through a slide.
var _busy: bool = false
## Where the column puts the block, taken once it has been laid out. Stable: the
## header above it is one line whatever the lesson says.
var _block_rest: Vector2 = Vector2.INF
## Where the board is authored, so it can step aside and come back.
var _home_x: float = 0.0

var _director: TutorialDirector:
	get:
		return References.tutorial_director


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	if _board != null:
		_home_x = _board.position.x
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


## The HEADER, redrawn whenever the lesson or the step changes. The block below
## it is not touched here - it is swapped by _process, which is the only place
## that knows whether an animation is already running.
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
	# A moment has the middle of the screen too, in the same panel.
	if step is TutorialExplainStep || director.current_moment() != null:
		hide()
		return
	show()
	# A lesson can be many steps, one per task: the title comes from the
	# lesson's first step, and every task's own words come from its own.
	var lessons: TutorialScript = director.script_resource
	var head: TutorialStep = lessons.step_at(lessons.lesson_range(director.step_index()).x)
	var place: Vector2i = lessons.lesson_position(director.step_index())
	if _title_label != null:
		_title_label.text = head.title if head != null else step.title
	if _progress_label != null:
		_progress_label.text = _progress_text(director, place)

	if _continue_button != null:
		# Offered only where pressing it is what finishes the lesson. On a
		# lesson with something to do, the thing IS the button.
		_continue_button.visible = step is TutorialReadStep && !director.is_between_lessons()
		_continue_button.text = CONTINUE_TEXT
		if _footer != null:
			_footer.visible = _continue_button.visible

	if place.x != _shown_lesson:
		_shown_lesson = place.x
		_play_pop()


## "Lesson 6 of 7 - Task 4 of 16". The second half is only worth drawing on a
## lesson that has more than one task, which is what the list used to say by
## being a list.
func _progress_text(director: TutorialDirector, place: Vector2i) -> String:
	var lesson: String = "Lesson %d of %d" % [place.x, place.y]
	var tasks: Vector2i = _task_place(director)
	if tasks.y <= 1:
		return lesson
	return "%s - Task %d of %d" % [lesson, tasks.x, tasks.y]


## Which task of this lesson is open, and how many it has. Counted off the steps
## with something to do, so a step that only explains is not a task.
func _task_place(director: TutorialDirector) -> Vector2i:
	var lessons: TutorialScript = director.script_resource
	var current: int = director.step_index()
	var bounds: Vector2i = lessons.lesson_range(current)
	var total: int = 0
	var at: int = 0
	for index in range(bounds.x, bounds.y + 1):
		var step: TutorialStep = lessons.step_at(index)
		if step == null || step.objective.is_empty():
			continue
		total += 1
		if index <= current:
			at = total
	return Vector2i(at, total)


## The task counts move with the world, so they are polled - and so is the
## SWAP, because a task finishing is something the world did rather than
## something the director announced.
func _process(_delta: float) -> void:
	if !visible:
		return
	_keep_clear_of_research()
	if _busy:
		return
	var director: TutorialDirector = _director
	if director == null || !director.is_running() || director.current_moment() != null:
		return
	var step: TutorialStep = director.current_step()
	if step == null:
		return
	var tasks: Array[TutorialStep.Task] = step.tasks(director)
	if tasks.is_empty():
		if _step_block != null:
			_step_block.visible = false
		return
	_swap_to(tasks[0], step, director)


## The whole of what is drawn below the header, in the order it happens: a task
## that has just been finished is TICKED where it stands and then taken off
## screen, and a task that is new is written in and brought on.
##
## A coroutine rather than a state enum, because the order is the whole of the
## logic: tick, out, rewrite, in. _busy is what keeps the poll above out of it
## while it runs.
func _swap_to(task: TutorialStep.Task, step: TutorialStep, director: TutorialDirector) -> void:
	if _step_block == null || _task_row == null:
		return
	_step_block.visible = true

	# **A COUNTED TASK REWRITES ITS OWN TEXT AS IT PROGRESSES**, so the text is
	# not an identity: "Kill 1 / 4" becoming "Kill 2 / 4" is one task counting,
	# and comparing the words made every tick of the count look like a whole new
	# task and slide the block out and back in for it.
	#
	# What does identify it is that the block is still showing a LIVE task from
	# this same step. A move to the next task can only happen through the
	# completion below, which sets both _shown_done and _exited - so those two
	# being clear is what says nothing has finished since this task was written.
	var place: int = director.step_index()
	var same_task: bool = place == _shown_step && !_exited && !_shown_done

	if same_task && task.done:
		# It finished. The words go in first so the count reads 4 / 4 under the
		# tick that is about to pop, rather than 3 / 4 with a tick on it.
		_task_row.update_text(task.text)
		_shown_text = task.text
		_shown_done = true
		_busy = true
		await _task_row.play_complete()
		await _play_exit()
		_exited = true
		_busy = false
		return

	if task.text == _shown_text:
		return

	if same_task:
		# The same task, counting. The words change where they stand and
		# nothing moves - which is the whole of this fix.
		_task_row.update_text(task.text)
		_shown_text = task.text
		return

	_busy = true
	if !_shown_text.is_empty() && !_exited:
		await _play_exit()
	if !is_instance_valid(_task_row):
		_busy = false
		return
	# Written while the block is off screen, so the column has re-laid it out
	# before anything about it moves. See Docs/ui.md section 2.
	if _body_label != null:
		var head: TutorialStep = director.script_resource.step_at(
			director.script_resource.lesson_range(director.step_index()).x)
		_body_label.text = step.body if !step.body.is_empty() || head == null else head.body
	_task_row.show_task(task)
	_shown_text = task.text
	_shown_done = task.done
	_shown_step = place
	_exited = false
	await _play_enter()
	_busy = false


## The Research Center opens in the same corner as this board; while it is up
## the board sits to its right instead of over it.
func _keep_clear_of_research() -> void:
	if _board == null:
		return
	var center: ResearchCenter = References.research_center
	var rect: Rect2 = Rect2() if center == null else center.screen_rect()
	var wanted: float = _home_x
	if rect.size.x > 0.0:
		wanted = maxf(_home_x, rect.end.x - get_global_rect().position.x + CLEAR_OF_RESEARCH)
	_board.position.x = wanted


## Brings the block on: in from the right, up from a touch small, and in from
## nothing, all on the one beat.
func _play_enter() -> void:
	if _step_block == null:
		return
	# A frame, so the column has placed the block for the text just written
	# into it before its resting place is read off it.
	await get_tree().process_frame
	if !is_instance_valid(_step_block):
		return
	if _block_rest == Vector2.INF:
		_block_rest = _step_block.position
	_step_block.pivot_offset = Vector2(0.0, _step_block.size.y * 0.5)
	_step_block.position = _block_rest + Vector2(SLIDE_IN, 0.0)
	_step_block.scale = Vector2.ONE * BLOCK_SCALE
	if _block_scale != null:
		_block_scale.scale_to(Vector2.ONE, ENTER_SECONDS, Tween.EASE_OUT,
			Tween.TRANS_CUBIC, false)
	if _block_fade != null:
		_block_fade.fade(0.0, 1.0, ENTER_SECONDS, true)
	if _block_move != null:
		await _block_move.move_to(_block_rest, ENTER_SECONDS, Tween.EASE_OUT, Tween.TRANS_CUBIC)


## Takes it off: out to the left, down a touch, and out to nothing.
func _play_exit() -> void:
	if _step_block == null || _block_rest == Vector2.INF:
		return
	if _block_scale != null:
		_block_scale.scale_to(Vector2.ONE * BLOCK_SCALE, EXIT_SECONDS, Tween.EASE_IN,
			Tween.TRANS_CUBIC, false)
	if _block_move != null:
		_block_move.move_to(_block_rest - Vector2(SLIDE_OUT, 0.0), EXIT_SECONDS,
			Tween.EASE_IN, Tween.TRANS_CUBIC)
	if _block_fade != null:
		await _block_fade.fade_out(EXIT_SECONDS)


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
	if director != null:
		director.acknowledge()
