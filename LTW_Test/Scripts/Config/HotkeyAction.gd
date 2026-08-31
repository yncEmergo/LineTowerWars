class_name HotkeyAction
extends Resource

## One command that answers to a key of its OWN rather than to the grid, and
## that the player may rebind.
##
## The command card is a GRID: an ability's key is read off the square it sits
## in, so nothing on a card names a key and the whole layout is learned once.
## This is the deliberate exception, and it is a small one. It exists for the
## handful of commands that mean the same thing on every card - Sell, Build,
## Cancel - which a player reaches for by NAME rather than by position, and for
## the one screen that is not a card at all. Rebinding every ability in the game
## is not on offer and never will be: there are hundreds of them and twelve
## squares, which is the whole reason the grid exists.
##
## An action is SHARED, exactly as an ability is: several abilities may answer
## to one of these, which is how the three Cancels are one line in the options
## screen and one key to learn rather than three.
##
## It holds no state of its own, for the same reason an ability holds none: one
## .tres is one object for the whole game. What the player chose lives in
## UserSettings under action_id and is read back through current_key().

## Scene tree group every node that DRAWS or ANSWERS a hotkey joins, so the
## options screen can tell all of them at once that one moved.
##
## A group rather than a signal, for the reason UserSettings has no signals at
## all: nothing here is a node and nothing routes to it. It is the same shape
## the health bar setting already uses to reach the bars standing in the world.
const READERS_GROUP: String = "hotkey_readers"

@export_group("Identity")
## The name this action is saved under in the settings file.
##
## Must be unique across every action and must never change once it has
## shipped: a player's settings.cfg names their binding by this string, so a
## rename silently throws their choice away and hands them the default back.
##
## A readable string rather than the authored int an ability_id is, because
## nothing here ever crosses the wire - a hotkey is a fact about the machine
## somebody is sitting at - and settings.cfg is a file a player may open.
@export var action_id: String = ""
## What the options screen calls it.
@export var display_name: String = "Action"

@export_group("Input")
## The key it answers to out of the box, written the way Godot spells a
## keycode: "T", "F5", "Space". Empty starts the action unbound, which for an
## ability means it stays on the grid square it sits in.
##
## May never be a key the command card grid already carries - see
## ControlsConfig.is_key_reserved, which refuses one at boot as well as
## refusing the player one in the options screen. A key that meant two things
## at once would mean the grid stopped being learnable.
@export var default_key: String = ""


## The key this action answers to right now: what the player bound, or the
## authored default when they have not bound anything.
##
## Empty means NO KEY, which is a real answer rather than a missing one - both
## an action that ships unbound and one the player deliberately cleared.
func current_key() -> String:
	if UserSettings.has_hotkey_override(action_id):
		return UserSettings.hotkey_override(action_id)
	return default_key


## The same answer as a keycode, or KEY_NONE for an action with no key. Asked
## by everything that compares a press, so the string is parsed in one place.
func current_keycode() -> Key:
	var key: String = current_key()
	if key.is_empty():
		return KEY_NONE
	return OS.find_keycode_from_string(key.to_upper()) as Key


## Whether a press is this action's key. False for an unbound action, which is
## what stops a stray KEY_NONE from matching everything that is not a key.
func matches(key: Key) -> bool:
	if key == KEY_NONE:
		return false
	return current_keycode() == key


## What a slot, a button or a tooltip draws for this action. Upper case, so it
## reads the same as a grid letter beside it.
func label() -> String:
	return current_key().to_upper()


## Whether the player has moved this off its authored default.
func is_customised() -> bool:
	return UserSettings.has_hotkey_override(action_id)
