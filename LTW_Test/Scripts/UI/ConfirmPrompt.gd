class_name ConfirmPrompt
extends Control

## "Are you sure?", as one prefab anything in a match can borrow.
##
## **MODAL, and that is the whole shape of it.** The dim covers the screen and
## eats every click that does not land on the box, and every KEY while it is up
## belongs to this node - so a hotkey cannot build a tower, send a creep or
## open the Research Center behind an unanswered question. Escape is Cancel and
## Enter is Confirm, because those are the two keys a player will reach for
## without being told.
##
## Deliberately NOT a pause. It does not touch get_tree().paused, for the
## reason GameMenu does not: the match belongs to the server and keeps running
## whether this is open or not, and a dialog that stopped the world locally
## would only be unbuilt later. What it blocks is INPUT, not time - a creep
## still walks while the box is up, and it was always going to.
##
## It carries no wording of its own. Whoever opens it says what the question is
## and what the buttons say, so the same box asks about overwriting a blueprint
## today and about anything else tomorrow without growing a branch per caller.
##
## **It is not the other dim panels, and deliberately.** StallPanel has no
## button at all, DesyncNotice has one that only leaves, and NamePrompt wraps a
## text input with rules of its own. Those are three different things that
## happen to darken the screen; this is the one that asks a yes-or-no question,
## and folding them together would mean a base class whose subclasses share
## nothing but a ColorRect.

## The player said yes. Fired after the box has closed, so a handler is free to
## open another one.
signal confirmed()
## The player backed out, by the button or by Escape.
signal cancelled()

@export_group("References")
@export var _title_label: Label
@export var _message_label: Label
@export var _confirm_button: Button
@export var _cancel_button: Button

## What runs on yes, when the caller passed one to ask(). Cleared the moment
## the box closes either way, so a cancelled question can never fire the answer
## the NEXT one was opened for.
var _on_confirm: Callable = Callable()


func _ready() -> void:
	hide()
	if _confirm_button != null:
		_confirm_button.pressed.connect(_on_confirm_pressed)
	if _cancel_button != null:
		_cancel_button.pressed.connect(_on_cancel_pressed)


## Asks a question and runs `on_confirm` if the answer is yes.
##
## A callable rather than the `confirmed` signal for the ordinary case, because
## a signal has to be connected one-shot and disconnected again on a cancel -
## and a caller that forgets the second half leaves a live handler waiting to
## fire on whatever question is asked next. The signals are still there for
## anything that would rather listen than hand work over.
##
## Refuses to open over an open box rather than replacing it: two questions on
## screen at once is a question the player cannot answer, and the second caller
## finding out here is better than the first one's answer being thrown away.
func ask(title: String, message: String, on_confirm: Callable,
		confirm_text: String = "Confirm", cancel_text: String = "Cancel") -> void:
	if visible:
		Log.warn("A confirmation is already open, the new one was dropped", title)
		return

	_on_confirm = on_confirm
	if _title_label != null:
		_title_label.text = title
	if _message_label != null:
		_message_label.text = message
	if _confirm_button != null:
		_confirm_button.text = confirm_text
	if _cancel_button != null:
		_cancel_button.text = cancel_text

	show()
	# Cancel takes the focus, not Confirm. The box is only ever opened for
	# something that cannot be undone, so leaning on Enter or Space should do
	# the harmless thing.
	if _cancel_button != null:
		_cancel_button.grab_focus()


## Whether a question is on screen. Asked by anything that wants to know the
## input it is about to read has already been spoken for.
func is_open() -> bool:
	return visible


## **Every key belongs to this node while it is up.**
##
## In _input rather than _unhandled_input, and marked handled whatever the key
## was: the point of a modal is that nothing behind it acts, and letting the
## unrecognised keys through would leave the command card, the Research Center
## and the control groups all live under an unanswered question. Mouse events
## are deliberately NOT swallowed here - the dim ColorRect eats the clicks that
## miss the box, and the box's own buttons need the ones that do not.
func _input(event: InputEvent) -> void:
	if !visible || !(event is InputEventKey):
		return

	get_viewport().set_input_as_handled()
	var key: InputEventKey = event as InputEventKey
	if !key.pressed || key.echo:
		return

	if key.keycode == KEY_ESCAPE:
		_on_cancel_pressed()
	elif key.keycode == KEY_ENTER || key.keycode == KEY_KP_ENTER:
		_on_confirm_pressed()


func _on_confirm_pressed() -> void:
	var answer: Callable = _close()
	if answer.is_valid():
		answer.call()
	confirmed.emit()


func _on_cancel_pressed() -> void:
	_close()
	cancelled.emit()


## Closes the box and hands back whatever was to run on yes, having already
## forgotten it. One place, so neither answer can leave the callable behind for
## the next question to fire.
func _close() -> Callable:
	var answer: Callable = _on_confirm
	_on_confirm = Callable()
	hide()
	return answer
