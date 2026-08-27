class_name CheatController
extends Node

## Developer cheats, bound to the numpad and silent unless GameConfig says
## cheats are on.
##
## The NUMPAD because the number row is already control groups, and NumLock
## has to be OFF.
##
## A cheat is a PLAYER ORDER like a Research Center press, and goes down the
## same road - Commands.submit_player_action. So the AUTHORITY grants the gold
## and a client's press takes the same round trip every other order takes,
## which is what makes a cheat work in a networked test instead of only
## redrawing a number the server never agreed to.
##
## The config is read here as well as on the authority. That is not the check
## that matters - the server's is - it only keeps a disabled cheat from
## sending a packet that would come back as a rejection line in the log.

## Which key hands the player gold. One match arm today; the point of the
## match is that the next cheat is one line rather than a rewrite.
const GOLD_KEY: Key = KEY_END

var _config: GameConfig:
	get:
		return References.game_config


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null || !key.pressed || key.echo:
		return

	var config: GameConfig = _config
	if config == null || !config.cheats_enabled:
		return

	match key.keycode:
		GOLD_KEY:
			Commands.submit_player_action(Command.PlayerAction.CHEAT_GOLD)
			get_viewport().set_input_as_handled()
