class_name Command
extends RefCounted

## One player order, on its way to the server.
##
## **A command is intent, never state.** It says "I pressed Build Cannon here",
## and it can say nothing else - not "I now have 300 gold", not "this tower
## exists". Everything a command could lie about is decided by the server from
## its own copy of the world, which is what makes lying pointless rather than
## merely forbidden. See multiplayer.md 5.3.
##
## Made of ids and numbers, never of object references, because it has to
## survive a trip over the wire and arrive somewhere the sender's objects do
## not exist. A unit is a `unit_id` (0.4), an ability is an `ability_id` (D12),
## and both are resolved on the far side against that machine's own registry.
##
## RefCounted rather than Resource, unlike MatchSetup and LobbyInfo: those are
## also authored in the editor and exported on nodes, and a command never is -
## it is created, sent and dropped. AbilityTarget, its closest relative, is
## RefCounted for the same reason.

## Which simulation tick the client issued this on. Not trusted for anything
## yet: the server applies commands on the tick it receives them. It is here
## because 3.5 needs it to say how late a command arrived, and adding it later
## would mean a wire format change for no reason.
var tick: int = 0
## Who is ordering, as a MATCH SLOT rather than a peer id. The server fills
## this in from the sender's peer id and ignores whatever arrived in it, so a
## client cannot issue orders as somebody else.
var player_slot: int = 0
## Which ability, by its authored id (D12). Resolves to null on a machine whose
## content does not contain it, which is a mismatched build and gets rejected.
var ability_id: int = 0
## The units being ordered. Several because one click orders a whole selection,
## and splitting that into one message each would multiply the traffic by the
## size of the selection for no gain.
var unit_ids: PackedInt32Array = PackedInt32Array()
## The unit being targeted, or NO_UNIT. Separate from unit_ids: those are who
## is acting, this is who it is being done to.
var target_unit_id: int = MatchSession.NO_UNIT
var target_position: Vector3 = Vector3.ZERO
var has_target_position: bool = false


## The order a player just gave, before it has a slot. The server overwrites
## player_slot on arrival, so setting it here would only be a suggestion.
static func create(id: int, units: Array, target: AbilityTarget) -> Command:
	var command: Command = Command.new()
	command.ability_id = id

	for unit in units:
		var entry: Unit = unit as Unit
		if entry != null && is_instance_valid(entry) && entry.unit_id != MatchSession.NO_UNIT:
			command.unit_ids.append(entry.unit_id)

	if target != null:
		command.has_target_position = target.has_position
		command.target_position = target.position
		if target.unit != null && is_instance_valid(target.unit):
			command.target_unit_id = target.unit.unit_id
	return command


static func from_dict(data: Dictionary) -> Command:
	var command: Command = Command.new()
	command.tick = int(data.get("tick", 0))
	command.player_slot = int(data.get("slot", 0))
	command.ability_id = int(data.get("ability", 0))
	command.unit_ids = PackedInt32Array(data.get("units", PackedInt32Array()))
	command.target_unit_id = int(data.get("target_unit", MatchSession.NO_UNIT))
	command.target_position = data.get("at", Vector3.ZERO)
	command.has_target_position = bool(data.get("has_at", false))
	return command


## Short keys, because this is the one message sent per player action rather
## than per lobby refresh. Vector3 travels as itself: Godot encodes it as 12
## bytes, where three named floats would cost the names as well.
func to_dict() -> Dictionary:
	return {
		"tick": tick,
		"slot": player_slot,
		"ability": ability_id,
		"units": unit_ids,
		"target_unit": target_unit_id,
		"at": target_position,
		"has_at": has_target_position,
	}


## Rebuilds what the ability is aimed at, resolved against THIS machine's unit
## registry. A named unit that has already died comes back null, which every
## ability has to expect anyway: a tower can be sold while the order is in
## flight.
func to_target(session: MatchSession) -> AbilityTarget:
	var target: AbilityTarget = AbilityTarget.new()
	target.position = target_position
	target.has_position = has_target_position
	if session != null && target_unit_id != MatchSession.NO_UNIT:
		target.unit = session.unit_for(target_unit_id)
	return target


## For logs. Ids rather than names on purpose - the point of reading this line
## is usually to compare it with the same line on the other machine.
func describe() -> String:
	return "slot %d, ability %d, units %s, tick %d" % [
		player_slot, ability_id, str(unit_ids), tick,
	]
