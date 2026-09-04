class_name CheatController
extends Node

## Developer cheats, bound to the numpad and silent unless GameConfig says
## cheats are on.
##
## The NUMPAD because the number row is already control groups. NumLock may be
## either way round: the keys are matched physically, see _action_for(). One
## side effect of NumLock being OFF is that the key also reaches the camera as
## an arrow, so a cheat press nudges the view by a frame's worth of panning.
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
##
## SINGLE PLAYER ONLY unless somebody deliberately says otherwise, which is
## GameConfig.cheats_allowed rather than a rule of this file's. A cheat is a
## real player order the authority grants, so in a networked match one player
## could hand themselves the gold to end it - and the file that would have
## refused it is the SERVER's copy, not the one they are looking at.

## Numpad 1: hands the player gold.
const GOLD_KEY: Key = KEY_KP_1
## Numpad 2: waives every creep's start delay and fills every reserve, so the
## whole send card is available at once.
const UNLOCK_CREEPS_KEY: Key = KEY_KP_2
## Numpad 3: grants every technology in the build, free of charge.
const UNLOCK_TECHS_KEY: Key = KEY_KP_3
## Numpad 4: builds the saved layout into the player's area, free and
## finished. The file is read HERE and sent with the order, so a networked
## match builds one maze rather than one per machine. See TowerLayout.
const LOAD_LAYOUT_KEY: Key = KEY_KP_4
## Numpad 5: saves the player's current maze to that same file.
##
## Next to the key that loads it rather than somewhere out of the way, because
## the two are one tool used in one order - and the destructive-looking one of
## the pair is the SAVE, which overwrites the file the last maze went into.
const SAVE_LAYOUT_KEY: Key = KEY_KP_5

var _config: GameConfig:
	get:
		return References.game_config


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null || !key.pressed || key.echo:
		return

	var config: GameConfig = _config
	if config == null || !MatchSession.cheats_permitted():
		return

	var action: Command.PlayerAction = _action_for(key)
	if action == Command.PlayerAction.NONE:
		return

	# The layout cheat is the one press that carries a payload, and the file it
	# comes from is on THIS machine - so it is read here and travels with the
	# order. Every peer then builds the same maze rather than opening its own
	# user:// folder and finding a different one, or nothing. See Command.layout.
	var maze: TowerLayout = null
	if action == Command.PlayerAction.CHEAT_LOAD_LAYOUT:
		maze = TowerLayout.load_file(config.cheat_layout_path)
		if maze == null:
			# load_file has already said where it looked. Same job as the
			# cheats-off check above: it saves a packet that would only come
			# back as a rejection line.
			get_viewport().set_input_as_handled()
			return

	Commands.submit_player_action(action, 0, maze)
	get_viewport().set_input_as_handled()


## Which cheat a key press is, or NONE for anything else.
##
## Matched on the PHYSICAL key rather than on what NumLock has made of it. With
## NumLock off the engine reports numpad 1 as End and numpad 2 as the DOWN
## ARROW, and the down arrow is already the camera - so a keycode match would
## hang a cheat on a key the player pans with. The physical code is the numpad
## key itself either way round.
##
## One match rather than a chain of ifs, so the next cheat is one arm rather
## than a rewrite.
func _action_for(key: InputEventKey) -> Command.PlayerAction:
	match key.physical_keycode:
		GOLD_KEY:
			return Command.PlayerAction.CHEAT_GOLD
		UNLOCK_CREEPS_KEY:
			return Command.PlayerAction.CHEAT_UNLOCK_CREEPS
		UNLOCK_TECHS_KEY:
			return Command.PlayerAction.CHEAT_UNLOCK_TECHS
		LOAD_LAYOUT_KEY:
			return Command.PlayerAction.CHEAT_LOAD_LAYOUT
		SAVE_LAYOUT_KEY:
			return Command.PlayerAction.CHEAT_SAVE_LAYOUT
	return Command.PlayerAction.NONE
