class_name NamePrompt
extends Control

## Asks the player what to call themselves, and will not take no for an answer
## the first time.
##
## A prefab rather than nodes built into the browser, because it is a thing that
## gets opened from more than one place: multiplayer opening for the first time,
## and the button that changes a name already chosen. Both are the same dialog
## with one difference - whether Cancel is on it.
##
## **MODAL, and that is the whole shape of it.** The dim covers the screen and
## eats every click, so nothing behind it can be pressed while it is up. A
## player who has never chosen a name cannot leave it at all: there is no
## Cancel, Escape does nothing, and the only way on is to type something legal.
## A player who is CHANGING one can back out, because they already have a name
## and nothing is waiting on them.
##
## It decides nothing about what a legal name is. Every rule is
## `LobbyIdentity.rejection()`, which is also what `choose_name` gates on, so the
## message under the box and the refusal behind it can never disagree.

## The name was accepted and is now stored. Whoever opened this carries on.
signal name_chosen(player_name: String)
## Closed without choosing, which only a player who already had a name can do.
signal cancelled()

@export_group("References")
@export var _title_label: Label
@export var _name_input: LineEdit
## Says why the name in the box will not do, or what the rules are while it is
## empty. Never blank: an empty line under an input reads as a broken dialog.
@export var _hint_label: Label
@export var _confirm_button: Button
## Hidden entirely for a player who has no name yet, rather than disabled. A
## greyed Cancel invites clicking to find out why it is greyed.
@export var _cancel_button: Button

@export_group("Settings")
## What the title says in each of the two cases.
@export var _first_title: String = "Choose a Player Name"
@export var _change_title: String = "Change Player Name"
## What the hint says while the name in the box is fine, so the line never goes
## blank and never has to be measured around.
@export var _accepted_hint: String = "Looks good."

## Whether this player already had a name when the prompt opened. Decides
## whether Cancel is there and whether Escape is worth anything.
var _may_cancel: bool = false


func _ready() -> void:
	hide()
	if _confirm_button != null:
		_confirm_button.pressed.connect(_on_confirm_pressed)
	if _cancel_button != null:
		_cancel_button.pressed.connect(_on_cancel_pressed)
	if _name_input != null:
		_name_input.max_length = LobbyIdentity.MAX_NAME_LENGTH
		_name_input.text_changed.connect(_on_text_changed)
		# Enter is the same as pressing Confirm, and is refused the same way:
		# the handler re-asks rather than trusting the button's disabled state.
		_name_input.text_submitted.connect(_on_submitted)


## Opens it. `may_cancel` is false for a player who has never chosen, which is
## what takes the way out away.
##
## The box opens with what they already have, or with the OS user name as a
## suggestion when they have nothing - and the suggestion is dropped silently
## if it happens to break a rule, rather than being cleaned into a name nobody
## typed. See LobbyIdentity.suggested_name.
func open(may_cancel: bool) -> void:
	_may_cancel = may_cancel
	if _title_label != null:
		_title_label.text = _change_title if may_cancel else _first_title
	if _cancel_button != null:
		_cancel_button.visible = may_cancel
	if _name_input != null:
		_name_input.text = (
			LobbyIdentity.display_name() if LobbyIdentity.has_name()
			else LobbyIdentity.suggested_name()
		)
	_refresh()
	show()
	if _name_input != null:
		_name_input.grab_focus()
		_name_input.select_all()


## Escape closes it only for somebody who has a name already. Handled here
## rather than left to the browser, because this is the node that knows whether
## there is a way out - and it is marked handled either way, so an unanswered
## prompt swallows the key instead of letting the screen behind it act on one.
func _input(event: InputEvent) -> void:
	if !visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null || !key.pressed || key.echo || key.keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _may_cancel:
		_on_cancel_pressed()


func _on_text_changed(_text: String) -> void:
	_refresh()


func _on_submitted(_text: String) -> void:
	_on_confirm_pressed()


## Redraws the hint and the button off the one rule. Called on every keystroke,
## which is why LobbyIdentity keeps its regex compiled.
func _refresh() -> void:
	var reason: String = LobbyIdentity.rejection(_entered())
	var accepted: bool = reason.is_empty()
	if _hint_label != null:
		_hint_label.text = _accepted_hint if accepted else reason
	if _confirm_button != null:
		_confirm_button.disabled = !accepted


func _on_confirm_pressed() -> void:
	var wanted: String = _entered()
	# Asked again rather than trusting the button: Enter reaches here too, and
	# a disabled button is a courtesy rather than a gate.
	if !LobbyIdentity.choose_name(wanted):
		_refresh()
		return
	hide()
	name_chosen.emit(LobbyIdentity.display_name())


func _on_cancel_pressed() -> void:
	if !_may_cancel:
		return
	hide()
	cancelled.emit()


func _entered() -> String:
	return "" if _name_input == null else _name_input.text.strip_edges()
