class_name HotkeyRow
extends HBoxContainer

## One rebindable command in the options screen, and the button that takes its
## key.
##
## A prefab rather than a row built in code, for the reason every other element
## of the HUD is one: it carries real behaviour - listening for a press, saying
## what it refused and why - and that behaviour only grows. Which action it
## shows is handed in rather than authored, because the list of them lives on
## ControlsConfig and one screen builds a row per entry.
##
## It DECIDES NOTHING. A press leaves here as a request and the options screen
## answers it, because taking a key means taking it off whoever had it, and
## only the screen can see the other rows.

## The row wants this key. Refusing it, and clearing whoever else held it, is
## the screen's job.
signal key_chosen(action: HotkeyAction, key: Key)
## The row wants no key at all, leaving its ability on the grid square it sits
## in. Backspace and Delete, the way every hotkey menu spells it.
signal key_cleared(action: HotkeyAction)

## Drawn while the row is waiting for a press, so it is obvious which of them
## the next key belongs to.
const LISTENING_TEXT: String = "Press a key"
## Drawn for an action with no key at all. Not empty: an empty button looks
## like a row that failed to load rather than one deliberately unbound.
const UNBOUND_TEXT: String = "-"

@export_group("References")
@export var _name_label: Label
## Shows the current key, and takes the next press once clicked.
@export var _key_button: Button

var _action: HotkeyAction = null
var _listening: bool = false


func _ready() -> void:
	set_process_input(false)
	if _key_button == null:
		Log.err("HotkeyRow has no key button assigned in its prefab", name)
		return
	_key_button.pressed.connect(_on_key_pressed)


## Fills the row from an action. Called by the screen right after instancing
## it, before anything is drawn.
func setup(action: HotkeyAction) -> void:
	_action = action
	if _name_label != null:
		_name_label.text = "Action" if action == null else action.display_name
	refresh()


## Pulls the stored binding back onto the button. Called on every row after any
## rebind, because taking a key gives it up wherever else it was.
func refresh() -> void:
	_stop_listening()
	if _key_button == null:
		return
	if _action == null:
		_key_button.text = UNBOUND_TEXT
		_key_button.disabled = true
		return

	_key_button.disabled = false
	var key: String = _action.label()
	_key_button.text = UNBOUND_TEXT if key.is_empty() else key


## Stops waiting for a press without changing anything, for a screen closing
## under a row that was still listening.
func cancel() -> void:
	if _listening:
		refresh()


func _on_key_pressed() -> void:
	if _action == null:
		return
	_listening = true
	set_process_input(true)
	_key_button.text = LISTENING_TEXT


## Handled in _input rather than _unhandled_input because the whole point is to
## take a key nothing else should see - including Escape, which would otherwise
## close the screen out from under the row.
##
## Only ever listens while a button is armed: set_process_input is switched off
## the rest of the time, so a row that is not waiting for a key cannot swallow
## one.
func _input(event: InputEvent) -> void:
	if !_listening:
		return

	var key: InputEventKey = event as InputEventKey
	if key == null || !key.pressed || key.echo:
		return

	get_viewport().set_input_as_handled()
	var code: Key = key.keycode
	if code == KEY_ESCAPE:
		refresh()
		return

	_stop_listening()
	if code == KEY_BACKSPACE || code == KEY_DELETE:
		key_cleared.emit(_action)
		return
	key_chosen.emit(_action, code)


func _stop_listening() -> void:
	_listening = false
	set_process_input(false)
