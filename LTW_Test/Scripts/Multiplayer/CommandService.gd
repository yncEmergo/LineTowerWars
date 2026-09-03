class_name CommandService
extends Node

## The one road a player order takes. **Registered as the autoload `Commands`**,
## for the same reason as `Net`, `Lobby` and `MatchStart`.
##
## **An autoload rather than a node in the match scene, and that is forced.**
## Godot routes an `@rpc` by NODE PATH, and the two match scenes have different
## roots - `/root/Main/...` on a client, `/root/ServerMatch/...` on the server -
## so no node inside them can be an rpc endpoint. Only an autoload sits at the
## same path on both. Same lesson as D21.
##
## Three machines run this code and it branches on which one is asking:
##
##   single player   apply straight away. Nothing changes for a solo run, which
##                   is how the game is still mostly tested.
##   client          send, and do NOT apply. The order takes a round trip and
##                   comes back as world state (D17: feedback now, prediction
##                   later - the click is confirmed, the outcome is not claimed)
##   server          validate against ITS world, then apply.
##
## **The server trusts nothing in the message.** The sender's slot is looked up
## from the peer id the transport supplies, never read from the command, so a
## client cannot order somebody else's units by writing their number in. What
## it can honestly ask for is then checked twice over: that it owns each unit,
## and that the ability is really on that unit's card RIGHT NOW.
##
## Everything past those two checks is already enforced by the simulation
## itself - gold, creep stock, placement legality, the maze-blocking rule - so
## the server does not re-implement any of it. It runs the same
## `ability.execute()` the client would have run, over its own authoritative
## world, and that world refuses what it always refused.

## Two shapes travel down it. Nearly every order is given TO something - a
## builder, a tower, a selection of creeps - and is checked against who owns
## those units and what card they are showing. A PLAYER order is given to
## nobody: a Research Center press names a technology rather than a unit, so
## the only ownership question left is the slot, which the server has already
## taken from the peer id. See Command.PlayerAction.

## Server side: a command was accepted and applied. Carries the command so 3.2
## has something to broadcast from.
signal command_applied(command: Command)
## Server side: a command was thrown out, and why. One signal rather than a
## silent drop, because "nothing happened" is the hardest bug to see.
signal command_rejected(command: Command, reason: String)

## Commands that arrived between two ticks, applied in arrival order at the top
## of the next one. Server side only.
##
## Queued rather than applied on arrival because an rpc lands whenever the
## packet does, which is somewhere in the middle of a frame. Applying there
## would let one player's order land before another's purely by network jitter,
## and would put a world change halfway through a tick that other machines run
## whole. A tick boundary is the only place every machine agrees on.
var _pending: Array[Command] = []

var _session: MatchSession:
	get:
		return References.match_session


func _ready() -> void:
	# Keeps running while the world is held still (StartingTech's draft). The
	# order that ENDS the pause travels down this road, so a road that paused
	# with everything else would never carry it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Only the server has a queue to drain.
	set_physics_process(false)


## The entry point every player order goes through, replacing the direct
## `ability.execute()` calls that used to sit in CommandController.
func submit(ability: UnitAbility, units: Array, target: AbilityTarget,
		queued: bool = false) -> void:
	if ability == null || units.is_empty():
		return

	var session: MatchSession = _session
	if session == null:
		Log.err("Commands.submit with no MatchSession, the order goes nowhere")
		return

	var command: Command = Command.create(ability.ability_id, units, target, queued)
	command.tick = session.tick()
	command.player_slot = session.local_slot()

	if command.unit_ids.is_empty():
		# Every unit named was already gone, or never registered.
		return

	# Offline is not a special case so much as the absence of one: with no peer
	# there is nobody to ask, so this machine is its own authority.
	if !Net.is_online():
		_apply(command, ability, units)
		return

	if multiplayer.is_server():
		_queue(command)
		return

	if ability.ability_id == AbilityRegistry.NO_ABILITY:
		Log.err("Ability has no id and cannot be ordered over a network",
			ability.display_name)
		return
	submit_command.rpc_id(NetworkService.SERVER_PEER_ID, command.to_dict())


## The same road, for an order given to nobody: a Research Center press.
##
## A second entry point rather than a null unit through submit(), because the
## two really are different shapes - one names an ability and the units it runs
## on, the other names an action and a technology - and a submit() that started
## accepting an empty selection would stop refusing the mistake it is there to
## refuse.
func submit_player_action(action: Command.PlayerAction, tech_id: int = 0) -> void:
	if action == Command.PlayerAction.NONE:
		return

	var session: MatchSession = _session
	if session == null:
		Log.err("Commands.submit_player_action with no MatchSession, the order goes nowhere")
		return

	var command: Command = Command.create_player_action(action, tech_id)
	command.tick = session.tick()
	command.player_slot = session.local_slot()

	# Same three machines, same branch as submit(): offline is its own
	# authority, a server queues for the tick, a client asks and waits.
	if !Net.is_online():
		_apply_player_order(command)
		return
	if multiplayer.is_server():
		_queue(command)
		return
	submit_command.rpc_id(NetworkService.SERVER_PEER_ID, command.to_dict())


# --- server ---------------------------------------------------------------

## An order arriving from a client.
##
## The slot is OVERWRITTEN from the peer id rather than read out of the
## message. That single line is what makes the whole command layer safe to
## expose: whatever a client writes into it is discarded, so the worst a
## modified client can do is issue orders as itself.
@rpc("any_peer", "reliable")
func submit_command(payload: Dictionary) -> void:
	if !multiplayer.is_server():
		return

	var command: Command = Command.from_dict(payload)
	command.player_slot = _slot_of_peer(multiplayer.get_remote_sender_id())
	if command.player_slot == 0:
		Log.warn("Command from a peer that plays no slot, dropped", {
			"peer": multiplayer.get_remote_sender_id(),
		})
		return
	_queue(command)


func _queue(command: Command) -> void:
	_pending.append(command)
	set_physics_process(true)


## The top of a simulation tick, before anything in the match scene moves.
## Autoloads sit above the current scene in the tree, so this ordering is free
## rather than arranged.
func _physics_process(_delta: float) -> void:
	if _pending.is_empty():
		set_physics_process(false)
		return

	# Taken whole first: applying a command can queue nothing today, but a
	# scripted or chained order later must land on the NEXT tick rather than
	# extending this one indefinitely.
	var batch: Array[Command] = _pending
	_pending = []
	for command in batch:
		_validate_and_apply(command)


func _validate_and_apply(command: Command) -> void:
	var session: MatchSession = _session
	if session == null:
		return

	# A player order names no units and no ability, so nothing below applies to
	# it: there is no unit to own and no card to be on. Who sent it is the
	# whole of the question, and that was answered the moment it arrived.
	if command.is_player_order():
		_apply_player_order(command)
		return

	# Nothing may be ordered of a UNIT while the world is held still for the
	# draft. A legitimate client cannot press anything - its whole HUD is
	# paused - so this only ever answers one that was modified.
	if _is_drafting():
		_reject(command, "the match is paused")
		return

	var ability: UnitAbility = session.abilities().ability_for(command.ability_id)
	if ability == null:
		# The registry holds every ability this build contains (D12), so a miss
		# means the other machine is running content this one does not have.
		_reject(command, "no such ability in this build")
		return

	var units: Array = _authorised_units(command, ability, session)
	if units.is_empty():
		return
	_apply(command, ability, units)


## Every named unit this player is actually allowed to order with this ability.
##
## Two questions, and they are different: whether the unit is THEIRS, and
## whether the ability is on its card. The first stops a player ordering an
## opponent's builder; the second stops them using an ability that unit does not
## have, or one it has only in another state - Cancel Build on a tower that has
## already finished going up.
##
## A named unit that has since died is dropped silently. That is not an attack,
## it is a message that was in flight when a tower was sold.
func _authorised_units(
	command: Command, ability: UnitAbility, session: MatchSession
) -> Array:
	var allowed: Array = []
	for unit_id in command.unit_ids:
		var unit: Unit = session.unit_for(unit_id)
		if unit == null:
			continue
		if unit.owner_player_id != command.player_slot:
			_reject(command, "unit %d belongs to player %d" % [
				unit_id, unit.owner_player_id,
			])
			continue
		if !_is_on_card(unit, ability):
			_reject(command, "ability %d is not on unit %d's card" % [
				command.ability_id, unit_id,
			])
			continue
		allowed.append(unit)
	return allowed


## Whether a unit can really reach an ability from the card it is showing.
##
## **The card is a TREE, not a list.** `current_abilities()` answers the top
## row, and Build sits there as a submenu holding the four towers - so a
## perfectly ordinary "build a sniper tower" names an ability that is nowhere
## in that row. Checking only the row rejected every build order, which is how
## this was found.
##
## Walked rather than flattened once and cached, because the card CHANGES: a
## building under construction shows only Cancel, and an order has to be
## checked against what the unit offers at the moment it arrives.
func _is_on_card(unit: Unit, wanted: UnitAbility) -> bool:
	return _reaches(unit.current_abilities(), wanted, {})


## Recursive rather than one level deep, so a submenu inside a submenu is
## covered the day somebody authors one. `seen` guards against a card that
## refers back into itself, which would otherwise be an infinite descent rather
## than a rejected order.
func _reaches(entries: Array, wanted: UnitAbility, seen: Dictionary) -> bool:
	for entry in entries:
		var ability: UnitAbility = entry as UnitAbility
		if ability == null || seen.has(ability):
			continue
		seen[ability] = true
		if ability == wanted:
			return true
		if _reaches(ability.submenu_abilities(), wanted, seen):
			return true
	return false


## Runs the order. Everything left to refuse - gold, stock, a blocked maze, a
## taken cell - is refused by the simulation itself, in the same code a single
## player run uses. There is deliberately no second copy of those rules here.
##
## An ORDER - Move, Attack, Build - goes through the unit's queue rather than
## straight to execute(), because those are the three that take time and can
## therefore be chained. Shift ADDS to the chain, no shift REPLACES it, and
## everything that is not an order leaves the chain alone: pressing Prioritize
## must not cost a tower the creeps it was told to shoot. See
## UnitAbility.is_queueable.
func _apply(command: Command, ability: UnitAbility, units: Array) -> void:
	var acted: bool = false
	for unit in units:
		if !is_instance_valid(unit):
			continue
		if _run_on(unit, ability, command):
			acted = true

	if acted:
		command_applied.emit(command)


## One unit's share of an order. Answers whether it was taken, so a command
## that every named unit refused emits nothing.
func _run_on(unit: Unit, ability: UnitAbility, command: Command) -> bool:
	var target: AbilityTarget = command.to_target(_session)

	if !ability.is_queueable():
		if !ability.can_execute(unit):
			return false
		ability.execute(unit, target)
		return true

	# Chained. Asked with can_queue, which is the same question as can_execute
	# everywhere except a build - a tower is paid for when the builder reaches
	# it, so a chain may be longer than the gold in hand.
	if command.queued:
		if !ability.can_queue(unit):
			return false
		OrderQueue.of(unit).enqueue(ability, target)
		return true

	if !ability.can_execute(unit):
		return false
	OrderQueue.of(unit).replace(ability, target)
	return true


## A Research Center press, applied against this machine's own world.
##
## Every rule of it is TechManager's and is refused there, in the same code a
## single player run reaches - exactly as a build order's rules belong to the
## area it would be placed in. There is deliberately no copy of the price or
## the prerequisite here, for the same reason there is no copy of the gold
## check for a tower.
func _apply_player_order(command: Command) -> void:
	# A match held still for the DRAFT accepts exactly one order: the choice it
	# is being held for. Every other screen is frozen on a legitimate client,
	# so this is what a modified one is refused with.
	if _is_drafting() && command.player_action != Command.PlayerAction.PICK_DRAFT_TECH:
		_reject(command, "the draft is not finished")
		return

	match command.player_action:
		Command.PlayerAction.PICK_DRAFT_TECH:
			_apply_draft_pick(command)
			return
		Command.PlayerAction.CHEAT_GOLD:
			_apply_cheat_gold(command)
			return
		Command.PlayerAction.CHEAT_UNLOCK_CREEPS:
			_apply_cheat_unlock_creeps(command)
			return
		Command.PlayerAction.CHEAT_UNLOCK_TECHS:
			_apply_cheat_unlock_techs(command)
			return
		Command.PlayerAction.CHEAT_SAVE_LAYOUT:
			_apply_cheat_save_layout(command)
			return
		Command.PlayerAction.CHEAT_LOAD_LAYOUT:
			_apply_cheat_load_layout(command)
			return

	var tech: TechManager = References.tech_manager
	if tech == null:
		_reject(command, "this scene has no TechManager")
		return

	var reason: String = tech.apply_order(
		command.player_slot, command.player_action, command.tech_id
	)
	if reason.is_empty():
		command_applied.emit(command)
	else:
		_reject(command, reason)


## One player taking an Ultimate from the three a draft is offering.
##
## Its own branch rather than another case in TechManager, because which three
## are on offer and who is still to choose is StartingTech's - what the pick
## COSTS is TechManager's, and StartingTech asks it for that itself.
func _apply_draft_pick(command: Command) -> void:
	var draft: StartingTech = References.starting_tech
	if draft == null:
		_reject(command, "this scene has no StartingTech")
		return

	var reason: String = draft.pick(command.player_slot, command.tech_id)
	if reason.is_empty():
		command_applied.emit(command)
	else:
		_reject(command, reason)


## Whether the match is being held still for a draft. Asked before anything
## else a command could ask for, since a paused world must not be moved by an
## order that was pressed on a screen that should have been frozen.
func _is_drafting() -> bool:
	var draft: StartingTech = References.starting_tech
	return draft != null && draft.is_drafting()


## A developer cheat, applied by the authority exactly as every other player
## order is - which is the whole reason it takes this road rather than adding
## gold where the key was pressed. A client would only have redrawn a number
## the server never agreed to.
func _apply_cheat_gold(command: Command) -> void:
	var state: PlayerState = _cheat_target(command)
	if state == null:
		return

	# Read straight through: _cheat_target has already refused a machine with
	# no GameConfig, which is the same one this asks for the amount.
	var amount: int = References.game_config.cheat_gold_amount
	state.gain(amount)
	Log.info("Cheat: gold granted", {"slot": command.player_slot, "amount": amount})
	command_applied.emit(command)


## The other developer cheat: every creep's start delay counts as served for
## the sender from here on, and every reserve is filled to go with it. It sets
## a flag rather than winding a clock back, because the match clock is the tick
## counter itself and nothing may move it.
##
## Both halves ride down to a client in the snapshot the same tick - the flag
## in the player record, the counts in the stock records - so a card that has
## been cheated open says so on every machine rather than only on the one the
## key was pressed on.
func _apply_cheat_unlock_creeps(command: Command) -> void:
	var state: PlayerState = _cheat_target(command)
	if state == null:
		return

	state.creeps_unlocked = true

	# Reached through the area, the same way replication finds them. Every
	# building on the strip, since the cheat is "open the whole card" and a
	# player with one tier full and another empty is not what was asked for.
	var manager: PlayerManager = References.player_manager
	if manager != null:
		var area: PlayerArea = manager.area_for(command.player_slot)
		if area != null:
			for building in area.send_buildings():
				building.fill_all_stocks()

	Log.info("Cheat: creeps unlocked and stocked", {"slot": command.player_slot})
	command_applied.emit(command)


## The third developer cheat: every technology in the build, granted free to
## the sender. The grant itself is TechManager's, in the same way a research
## press is - this end only asks whether cheats are on and who pressed it.
##
## What rides down to a client is nothing new: the owned ids are already in
## every snapshot, so a cheated Research Center fills in on both machines the
## tick after the key.
func _apply_cheat_unlock_techs(command: Command) -> void:
	if _cheat_target(command) == null:
		return

	var manager: TechManager = References.tech_manager
	if manager == null:
		_reject(command, "this scene has no TechManager")
		return

	var reason: String = manager.grant_all(command.player_slot)
	if reason.is_empty():
		command_applied.emit(command)
	else:
		_reject(command, reason)


## The fourth developer cheat: the sender's maze written out to a file, as
## building types and grid cells (TowerLayout).
##
## The one cheat that changes nothing at all, and it still comes down this road
## rather than reading the world where the key was pressed - because the world
## worth saving is the AUTHORITY's. On a client the towers on screen are a
## drawing of it, and in single player, which is the only place cheats normally
## answer, the two are the same machine anyway.
##
## Which means that in a deliberately cheat-enabled networked test the file
## lands on the SERVER, next to its own logs. That is where the world is; it is
## worth knowing before hunting for it in the wrong user:// folder.
func _apply_cheat_save_layout(command: Command) -> void:
	var area: PlayerArea = _cheat_area(command)
	if area == null:
		return

	# Read straight through: _cheat_area has already refused a machine with no
	# GameConfig, by way of _cheat_target.
	var path: String = References.game_config.cheat_layout_path
	var layout: TowerLayout = TowerLayout.capture(area)
	if !layout.save_file(path):
		_reject(command, "the layout file could not be written")
		return

	# Globalized as well as raw, because the raw one is the path the config
	# carries and the other is the folder somebody has to open.
	Log.info("Cheat: layout saved", {
		"slot": command.player_slot,
		"buildings": layout.entry_count(),
		"path": path,
		"folder": ProjectSettings.globalize_path(path).get_base_dir(),
	})
	command_applied.emit(command)


## The fifth: that file built back into the sender's area, free and finished.
##
## Nothing here decides what may be placed. Every entry is offered to the area
## and refused by the same can_place a build order goes through, so a cell that
## is taken, under rubble or outside the buildable zone is skipped - and a
## layout cannot seal an area any more than building it by hand could. What the
## cheat waives is the price, the build timer and the walk, which is the whole
## of what makes it a cheat.
##
## It does NOT close the technology undo window the way a real construction
## does (TechManager.notify_construction_started). No gold went onto the field,
## so nothing was committed.
func _apply_cheat_load_layout(command: Command) -> void:
	var area: PlayerArea = _cheat_area(command)
	if area == null:
		return

	var path: String = References.game_config.cheat_layout_path
	var layout: TowerLayout = TowerLayout.load_file(path)
	if layout == null:
		_reject(command, "there is no readable layout at %s" % path)
		return

	var placed: int = layout.restore(area)
	Log.info("Cheat: layout built", {
		"slot": command.player_slot,
		"placed": placed,
		"of": layout.entry_count(),
	})
	command_applied.emit(command)


## The area a layout cheat reads or writes, or null once it has been refused.
##
## Asks _cheat_target first and throws its answer away: what that call is for
## here is the two questions every cheat has to pass - whether cheats are
## allowed on THIS machine, and whether anybody is playing that slot - and a
## layout happens to want the area rather than the purse.
func _cheat_area(command: Command) -> PlayerArea:
	if _cheat_target(command) == null:
		return null

	var manager: PlayerManager = References.player_manager
	var area: PlayerArea = null
	if manager != null:
		area = manager.area_for(command.player_slot)
	if area == null:
		_reject(command, "slot %d has no area" % command.player_slot)
	return area


## Who a cheat applies to, or null once it has already been refused.
##
## Both cheats ask the same two questions and neither trusts the sender's
## answer to either: are cheats allowed HERE - so a server built with them off
## refuses one however the client asking was built - and is there a player in
## that slot to apply it to.
##
## "Allowed here" is two things rather than one, and the second is what makes
## a cheat a single player tool: a NETWORKED match refuses them unless the
## server's own config deliberately says otherwise. See
## GameConfig.cheats_allowed. This is the check that counts - the one in
## CheatController only saves a packet.
func _cheat_target(command: Command) -> PlayerState:
	var config: GameConfig = References.game_config
	if config == null || !config.cheats_allowed(Net.is_online()):
		_reject(command, "cheats are off")
		return null

	var manager: PlayerManager = References.player_manager
	var state: PlayerState = null
	if manager != null:
		state = manager.state_for(command.player_slot)
	if state == null:
		_reject(command, "slot %d has no player state" % command.player_slot)
	return state


func _reject(command: Command, reason: String) -> void:
	Log.warn("Command rejected", {"command": command.describe(), "why": reason})
	command_rejected.emit(command, reason)


## Which slot a peer plays, from the match roster. The transport supplies the
## peer id and a client cannot forge it, which is what makes this the identity
## rather than anything in the message.
func _slot_of_peer(peer_id: int) -> int:
	var session: MatchSession = _session
	if session == null || session.setup() == null:
		return 0
	for player in session.setup().players:
		if player != null && player.network_id == peer_id:
			return player.slot
	return 0
