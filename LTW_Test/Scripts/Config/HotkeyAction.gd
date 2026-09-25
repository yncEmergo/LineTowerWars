class_name HotkeyAction
extends Resource

## One command the player may give a key of their own. Docs/hotkeys.md 3.
##
## The command card is a GRID: an ability's key is read off the square it sits
## in, so nothing on a card names a key and the whole layout is learned once.
## This is the deliberate exception, and it is a small one. It exists for the
## handful of commands that mean the same thing on every card - Sell, Build,
## Cancel - which a player reaches for by NAME rather than by position, and for
## the commands that are on no card at all. Rebinding every ability in the game
## is not on offer and never will be: there are hundreds of them and twelve
## squares, which is the whole reason the grid exists.
##
## Two kinds, told apart by card_square:
##   - a command ON THE CARD keeps its square whatever it is bound to, and out
##     of the box answers to that square's key. Binding it moves its KEY only
##   - a command on NO card answers to default_key out of the box
##
## An action is SHARED, exactly as an ability is: several abilities may answer
## to one of these, which is how the four Cancels are one line in the options
## screen and one key to learn rather than four.
##
## It holds no state of its own, for the same reason an ability holds none: one
## .tres is one object for the whole game. What the player chose lives in
## UserSettings under action_id, and every key here is a key POSITION - see
## KeyPosition.

## Scene tree group every node that DRAWS or ANSWERS a hotkey joins, so the
## options screen can tell all of them at once that one moved.
##
## A group rather than a signal, for the reason UserSettings has no signals at
## all: nothing here is a node and nothing routes to it. It is the same shape
## the health bar setting already uses to reach the bars standing in the world.
const READERS_GROUP: String = "hotkey_readers"

## Given to card_square for a command that is on no card.
const NOT_ON_CARD: int = -1

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
## The key a command on NO card answers to out of the box, as a key POSITION
## named the way Godot names a physical key: "G", "Tab", "B". See KeyPosition.
##
## Empty for a command on the card, which answers to its square instead, and
## never a key the game already answers - ControlsConfig refuses both at boot.
@export var default_key: String = ""
## The square every ability answering to this command sits on, or NOT_ON_CARD.
##
## The square is what a command on the card answers to until the player binds
## another key, and it is a RULE as well as a default: CardLayout refuses an
## ability naming this action on any other square, so "Sell is on S on every
## card" is a check the build runs rather than a thing the files happen to
## agree on.
@export var card_square: int = NOT_ON_CARD


## Whether this command sits on the card, and so keeps a square whatever key it
## answers to.
func is_on_card() -> bool:
	return card_square >= 0


## The key this command answers to right now, as a position: what the player
## bound, or what it has out of the box when they have not bound anything.
##
## KEY_NONE is a real answer rather than a missing one: an UNBOUND command. The
## player took its key away, or gave it to another command, and a command on
## the card does NOT fall back to its square when that happens - a player who
## moved Sell off S so as to stop selling by accident must not quietly get S
## back. The options screen says so in red instead.
func current_key(config: ControlsConfig) -> Key:
	if UserSettings.has_hotkey_override(action_id):
		return KeyPosition.from_stored(UserSettings.hotkey_override(action_id))
	return default_key_for(config)


## What this command answers to out of the box: its square's key for one on the
## card, default_key for one on no card. KEY_NONE without a config, which is
## a stripped-down test scene with no grid to read a square off.
func default_key_for(config: ControlsConfig) -> Key:
	if !is_on_card():
		return KeyPosition.from_stored(default_key)
	if config == null:
		return KEY_NONE
	return config.grid_key(card_square)


## Whether a press is this command's key. False for an unbound command, which
## is what stops a stray KEY_NONE from matching everything that is not a key.
func matches(config: ControlsConfig, physical: Key) -> bool:
	if physical == KEY_NONE:
		return false
	return current_key(config) == physical


## What a square, a button or a tooltip draws for this command: the letter the
## player's own keyboard prints on its key. Empty for an unbound command.
func label(config: ControlsConfig) -> String:
	return KeyPosition.printed_label(current_key(config))


## Whether this command has no key at all right now.
func is_unbound(config: ControlsConfig) -> bool:
	return current_key(config) == KEY_NONE


## Whether the player has moved this off what it had out of the box.
func is_customised() -> bool:
	return UserSettings.has_hotkey_override(action_id)
