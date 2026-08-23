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
	# Only the server has a queue to drain.
	set_physics_process(false)


## The entry point every player order goes through, replacing the direct
## `ability.execute()` calls that used to sit in CommandController.
func submit(ability: UnitAbility, units: Array, target: AbilityTarget) -> void:
	if ability == null || units.is_empty():
		return

	var session: MatchSession = _session
	if session == null:
		Log.err("Commands.submit with no MatchSession, the order goes nowhere")
		return

	var command: Command = Command.create(ability.ability_id, units, target)
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
func _apply(command: Command, ability: UnitAbility, units: Array) -> void:
	var acted: bool = false
	for unit in units:
		if !is_instance_valid(unit) || !ability.can_execute(unit):
			continue
		ability.execute(unit, command.to_target(_session))
		acted = true

	if acted:
		command_applied.emit(command)


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
