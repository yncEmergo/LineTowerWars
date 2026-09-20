class_name TutorialTaskRow
extends HBoxContainer

## THE ONE TASK on screen: what to do, and a tickbox that fills when it is done.
##
## **One task at a time, not a list.** A lesson can be sixteen rungs of an
## upgrade chain, and sixteen rows of which fifteen are faded is a wall of text
## where the one line that matters has to be hunted for. What the player needs
## is the next thing to press; how far through the lesson they are is a count in
## the header. So this prefab is instanced ONCE and rewritten as the lesson
## moves, rather than once per task.
##
## It owns the moment a task is FINISHED, which is the one piece of feedback the
## board cannot do without: the tick pops in and the line goes green, and only
## then does TutorialPanel fade the block out and bring the next one in. A task
## that vanished the instant it was done left the player unsure whether what they
## pressed was what was asked for.
##
## See Docs/ui.md section 2 for the animator components and what they may safely
## move on a node a Container lays out - the tick is SCALED rather than moved for
## exactly that reason.

## The tick's pop: from small, past full size, and back. Bigger overshoot than
## the board's own pop, because this one is meant to catch the eye.
const TICK_POP_START: float = 0.3
const TICK_POP_PEAK: float = 1.45
const TICK_POP_UP_SECONDS: float = 0.13
const TICK_POP_DOWN_SECONDS: float = 0.14
## The line's colour while it is the thing to do, and once it is done.
const TODO_COLOR: Color = Color(0.86, 0.88, 0.92, 1.0)
const DONE_COLOR: Color = Color(0.4, 0.9, 0.45, 1.0)
## How long the line takes to turn green when it is ticked.
const COLOR_SECONDS: float = 0.18

@export_group("References")
@export var _label: Label
@export var _tick: TutorialTickBox
## Pops the tick. A child of the tick, which is what it animates.
@export var _tick_pop: ScaleAnimation2D

var _color_tween: Tween


## What this row says now, set with no animation at all - the fade that brings
## the block back in is what the player sees. See TutorialPanel.
func show_task(task: TutorialStep.Task) -> void:
	if _label != null:
		_label.text = task.text
		_label.add_theme_color_override(&"font_color", DONE_COLOR if task.done else TODO_COLOR)
	if _tick != null:
		_tick.checked = task.done
		_tick.scale = Vector2.ONE


## Rewrites the words and touches NOTHING else - not the tick, not the colour,
## no animation at all.
##
## For a task whose text is its own progress: "Kill 1 / 4" becoming "Kill 2 / 4"
## is the same task counting, not a new one. show_task() would be wrong for it
## twice over - it resets the tick, and it slams the colour rather than easing
## it, which would rob the completion of the tween that makes the pop and the
## line going green read as one thing.
func update_text(text: String) -> void:
	if _label != null:
		_label.text = text


## The task just became done: the tick appears with a pop and the line turns
## green. Returns when the pop has finished, so the board can fade it out after.
func play_complete() -> void:
	if _label != null:
		_tint(DONE_COLOR)
	if _tick == null || _tick_pop == null:
		return
	# About its own middle, or the pop throws it sideways out of the row.
	_tick.pivot_offset = _tick.size * 0.5
	_tick.checked = true
	await _tick_pop.do_pop(Vector2.ONE * TICK_POP_START, Vector2.ONE * TICK_POP_PEAK,
		Vector2.ONE, TICK_POP_UP_SECONDS, TICK_POP_DOWN_SECONDS)


## Eases the line's colour rather than swapping it, so the tick's pop and the
## line going green read as one thing happening.
func _tint(to: Color) -> void:
	if _color_tween != null && _color_tween.is_running():
		_color_tween.kill()
	# A theme override cannot be tweened directly, so the value is tweened
	# through a setter. One tween rather than a per-frame lerp in _process,
	# which would run for every frame of every lesson to serve a fifth of a
	# second once a task.
	var from: Color = _label.get_theme_color(&"font_color")
	_color_tween = create_tween()
	_color_tween.tween_method(_set_label_color, from, to, COLOR_SECONDS)


func _set_label_color(value: Color) -> void:
	if _label != null:
		_label.add_theme_color_override(&"font_color", value)
