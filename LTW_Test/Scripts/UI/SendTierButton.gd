class_name SendTierButton
extends Button

## One of the four squares over the unit panel that select a creep sender.
##
## The senders have no bodies any more (see SendBuilding), so this square is
## the ONLY way to reach one with the mouse - it takes the place of walking the
## camera up to a building on a strip. Pressing it selects that sender, which
## puts its card of creeps on the unit panel like any other selection.
##
## A prefab rather than a button built in code, for the reason every other bit
## of this HUD is one: it already carries behaviour, and it will carry more.
##
## It shows a NUMERAL and no icon. There is nothing left to picture - the
## building it used to be a render of is gone - and the tier is the whole of
## what a player needs to read here.

## Emitted when a square holding a sender is pressed.
signal sender_picked(sender: SendBuilding)

## Tint for the square whose sender is currently selected, so the card on
## screen and the button that opened it agree at a glance. Above 1 on purpose:
## it brightens rather than recolours, the same way a toggled command slot does.
const ACTIVE_MODULATE: Color = Color(1.45, 1.3, 0.75, 1.0)

## Roman numerals, because the four squares are read as a row and "III" is
## told from "II" at a glance where "3" and "2" are one stroke apart.
const NUMERALS: PackedStringArray = ["I", "II", "III", "IV"]

@export_group("References")
@export var _tier_label: Label

## Which creep tier this square stands for, counting from 1. Authored per
## square in the bar's prefab rather than worked out from child order, so
## re-laying the row out cannot silently renumber it.
@export_group("Settings")
@export var send_tier: int = 1

## The sender this square opens, or null while that tier has none built.
var _sender: SendBuilding = null


func _ready() -> void:
	if _tier_label == null:
		Log.err("SendTierButton has no tier label in its prefab", name)
	else:
		_tier_label.text = _numeral()
	# **On PRESS, not on release, and that is an input-latency fix rather than a
	# preference.** Godot's default is ACTION_MODE_BUTTON_RELEASE, so a card
	# square sat on the order for as long as the player held the mouse down -
	# 60-120 ms of pure delay added to every build and every send, and paid
	# before the order even reached the turn scheduler. Hotkeys never had it,
	# which is why the two felt different for no visible reason.
	#
	# Nothing is lost by pressing early: an order is refused by the simulation
	# rather than by this button, so there is no half-committed state to back
	# out of if the player was wrong.
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	pressed.connect(_on_pressed)
	_apply_state()


## Hands this square its sender, or null for a tier with nothing implemented.
##
## A tier with no sender is DEAD rather than absent: the row is four squares
## whatever is built, so the one a player has learned to reach for never moves
## when a tier is added. See unit_data.md 6.1.
func bind(sender: SendBuilding) -> void:
	_sender = sender
	_apply_state()


## Whether this square still points at a live sender. A player who is
## eliminated loses theirs, so the button goes dead with them.
func has_sender() -> bool:
	return _sender != null && is_instance_valid(_sender)


## Lights the square whose card is on screen.
func set_active(value: bool) -> void:
	modulate = ACTIVE_MODULATE if value else Color.WHITE


## Whether this square opens the given unit, so the bar can light the right one
## without knowing which sender sits where.
func opens(unit: Node) -> bool:
	return has_sender() && unit == _sender


func _on_pressed() -> void:
	if !has_sender():
		return
	sender_picked.emit(_sender)


func _apply_state() -> void:
	disabled = !has_sender()
	tooltip_text = "Send Building %s" % _numeral() if has_sender() \
		else "Tier %s creeps are not in the game yet" % _numeral()
	if !has_sender():
		set_active(false)


func _numeral() -> String:
	var index: int = clampi(send_tier - 1, 0, NUMERALS.size() - 1)
	return NUMERALS[index]
