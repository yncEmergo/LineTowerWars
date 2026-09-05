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

## What a command asks of the PLAYER rather than of any unit.
##
## Nearly every order in the game is given TO something: a builder, a tower, a
## selection of creeps. Researching a technology is not - it is bought by the
## player, with no unit involved at all, so there is nothing to name in
## unit_ids and nothing whose card it could be checked against.
##
## That leaves exactly one ownership question, which the server already
## answers for every command: WHO sent it. The slot is taken from the peer id
## rather than read out of the message, so a player order can only ever be
## given as oneself. Everything past that - the price, the prerequisite, the
## undo window - is refused by TechManager, in the same code a single player
## run runs.
##
## An enum rather than one ability id per technology, because a technology is
## not an ability: it sits on no card, takes no target and runs on no unit.
## See TechDefinition.
enum PlayerAction {
	## The ordinary case: this command is given to units.
	NONE,
	## Buy the technology named by tech_id.
	RESEARCH,
	## Take back the most recent technology press, inside its window.
	UNDO_RESEARCH,
	## Roll one of the twenty Ultimate towers and buy what it still needs.
	RANDOM_ULTIMATE,
	## Take one of the three Ultimates a DRAFT is offering, named by tech_id.
	## The one order a paused match still accepts, because it is what the
	## match is paused FOR. See StartingTech.
	PICK_DRAFT_TECH,
	## Developer cheat: hand the sender GameConfig.cheat_gold_amount. Refused
	## outright by an authority whose GameConfig has cheats off, so it is a
	## real order on the same road rather than a second way into the world.
	CHEAT_GOLD,
	## Developer cheat: waive every creep's start delay for the sender and fill
	## every reserve, so the whole send card is available at once. Refused on
	## the same terms as the gold one, and granted to the SENDER rather than to
	## the match - a cheat belongs to whoever pressed it.
	CHEAT_UNLOCK_CREEPS,
	## Developer cheat: hand the sender every technology in the build, free of
	## charge. Same terms again, and the sender's alone - the other player's
	## Research Center is untouched.
	CHEAT_UNLOCK_TECHS,
	## Developer cheat: write the sender's maze out to the layout file, as
	## building types and grid cells. The one cheat that changes nothing about
	## the world - it only reads it - and it still takes this road because the
	## world it has to read is the AUTHORITY's. See TowerLayout.
	CHEAT_SAVE_LAYOUT,
	## Developer cheat: build the layout file into the sender's area, free and
	## finished. Same terms as the rest; what it places is refused cell by cell
	## by the area itself, so it can no more seal a maze than a build order can.
	CHEAT_LOAD_LAYOUT,
	## A player has left for good, and every peer must erase their maze ON THE
	## SAME TURN (D14).
	##
	## **The only order the SERVER issues.** It is a world event, not a player's
	## intent - but a world event that has to happen at one agreed moment, and a
	## turn is the only thing this system has that means "one agreed moment". A
	## plain broadcast rpc would land on a different tick on each peer, which is
	## the same divergence arriving more slowly.
	##
	## `player_slot` carries WHO left rather than who is asking. A modified
	## client can forge this, and gains nothing by it: the relay stamps the
	## sender's own slot over the field, so the worst it can do is erase its own
	## maze - which is a slow way of doing what leaving already does.
	PLAYER_LEFT,
}

## Which values of PlayerAction the SERVER may issue and a player may not.
## Read by CommandService, which is where the distinction has to be enforced.
const SERVER_ACTIONS: Array[PlayerAction] = [PlayerAction.PLAYER_LEFT]

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
## Whether the player was holding shift, which CHAINS this order behind
## whatever those units are already doing instead of replacing it.
##
## Intent, like everything else here: it says which of the two things was
## asked for, and the server decides what that means against its own world.
## An order naming an ability that cannot be chained ignores it.
var queued: bool = false
## What this asks of the player, or NONE for an order given to units. The two
## are exclusive: a player order names no units and a unit order names no
## action.
var player_action: PlayerAction = PlayerAction.NONE
## Which technology a RESEARCH names, by its authored id (TechRegistry).
## Resolves to null on a machine whose content does not contain it, which is a
## mismatched build and gets rejected.
var tech_id: int = 0
## The maze a CHEAT_LOAD_LAYOUT is asking for, or null on every other order.
##
## The one thing a command carries that is not a bare id or number, and it is
## still intent rather than state: it says WHICH MAZE was asked for, exactly as
## target_position says which spot was clicked. The world it lands in refuses
## it cell by cell, so it can claim nothing.
##
## It has to travel because the layout FILE lives on the machine that pressed
## the key, and under lockstep every peer runs every order. A peer reading the
## path out of its own config would read a different maze or no maze at all -
## which is a desync on the turn the key was pressed. See TowerLayout.to_dict.
var layout: TowerLayout = null


## The order a player just gave, before it has a slot. The server overwrites
## player_slot on arrival, so setting it here would only be a suggestion.
static func create(id: int, units: Array, target: AbilityTarget,
		is_queued: bool = false) -> Command:
	var command: Command = Command.new()
	command.ability_id = id
	command.queued = is_queued

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


## A press in the Research Center, which is given to nobody. The slot is filled
## in the same way it is for a unit order, and overwritten by the server on
## arrival for the same reason.
static func create_player_action(action: PlayerAction, tech: int = 0,
		maze: TowerLayout = null) -> Command:
	var command: Command = Command.new()
	command.player_action = action
	command.tech_id = tech
	command.layout = maze
	return command


## Whether this asks something of the player rather than of any unit, which
## decides which half of CommandService it goes through.
func is_player_order() -> bool:
	return player_action != PlayerAction.NONE


static func from_dict(data: Dictionary) -> Command:
	var command: Command = Command.new()
	# Absent from the wire since 2026-09-05; the default is the whole story for
	# anything that arrives from a peer.
	command.tick = int(data.get("tick", 0))
	command.player_slot = int(data.get("slot", 0))
	command.ability_id = int(data.get("ability", 0))
	command.unit_ids = PackedInt32Array(data.get("units", PackedInt32Array()))
	command.target_unit_id = int(data.get("target_unit", MatchSession.NO_UNIT))
	command.target_position = data.get("at", Vector3.ZERO)
	command.has_target_position = bool(data.get("has_at", false))
	command.queued = bool(data.get("q", false))
	command.player_action = int(data.get("act", PlayerAction.NONE)) as PlayerAction
	command.tech_id = int(data.get("tech", 0))
	if data.has("lay"):
		command.layout = TowerLayout.from_dict(data["lay"])
	return command


## Short keys, because this is the one message sent per player action rather
## than per lobby refresh. Vector3 travels as itself: Godot encodes it as 12
## bytes, where three named floats would cost the names as well.
func to_dict() -> Dictionary:
	# `tick` is deliberately NOT here. It is set on every order, by every peer,
	# every turn, and read by nothing - the authority applies a command on the
	# turn it was scheduled for, not on the tick the sender claims. It survives
	# as a field because DeterminismBench writes its own record and wants it.
	var data: Dictionary = {
		"slot": player_slot,
		"ability": ability_id,
		"units": unit_ids,
		"target_unit": target_unit_id,
		"at": target_position,
		"has_at": has_target_position,
	}
	# Left out unless it is true, on the same grounds as the player-order keys
	# below: nearly every order in a match is a plain one, and from_dict fills
	# the common answer in from its default.
	if queued:
		data["q"] = true
	# Left out entirely on a unit order rather than sent as zeroes. This is the
	# one message sent per player action, and a player order is rare next to
	# every move and every build, so the common case should not carry the keys
	# of the rare one. from_dict fills both in from its defaults.
	if is_player_order():
		data["act"] = player_action
		data["tech"] = tech_id
	# Only the layout cheat ever carries one, and it is by far the largest
	# thing a command can hold - so it is written only when it is really there
	# rather than as an empty block on every order in the match.
	if layout != null:
		data["lay"] = layout.to_dict()
	return data


## Rebuilds what the ability is aimed at, resolved against THIS machine's unit
## registry. A named unit that has already died comes back null, which every
## ability has to expect anyway: a tower can be sold while the order is in
## flight.
func to_target(session: MatchSession) -> AbilityTarget:
	var target: AbilityTarget = AbilityTarget.new()
	target.position = target_position
	target.has_position = has_target_position
	target.unit_id = target_unit_id
	if session != null && target_unit_id != MatchSession.NO_UNIT:
		target.unit = session.unit_for(target_unit_id)
	return target


## For logs. Ids rather than names on purpose - the point of reading this line
## is usually to compare it with the same line on the other machine.
func describe() -> String:
	if is_player_order():
		return "slot %d, player action %d, tech %d, tick %d" % [
			player_slot, player_action, tech_id, tick,
		]
	return "slot %d, ability %d, units %s, tick %d%s" % [
		player_slot, ability_id, str(unit_ids), tick,
		", queued" if queued else "",
	]
