class_name TutorialTaskRow
extends HBoxContainer

## One task in the lesson box: what to do and how far along it is, with a
## tickbox on the right that fills when it is done. A prefab, instanced once per
## task by TutorialPanel.

## How faded a task still to come is drawn.
const PENDING_ALPHA: float = 0.4

@export_group("References")
@export var _label: Label
@export var _tick: TutorialTickBox


func show_task(task: TutorialStep.Task) -> void:
	if _label != null:
		_label.text = task.text
	if _tick != null:
		_tick.checked = task.done
	modulate.a = PENDING_ALPHA if task.pending else 1.0
