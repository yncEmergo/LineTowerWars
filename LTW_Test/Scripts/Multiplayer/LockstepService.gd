class_name LockstepService
extends Node

## Turn scheduling and per-turn agreement, for the lockstep model (D2 under
## review, `multiplayer.md` 4.1).
##
## **This is the whole model, and `NetworkConfig.lockstep_enabled` is the switch
## between it and D2.** Off, none of this runs and the game is
## server-authoritative exactly as before. On, three things change together and
## they only make sense together:
##
## 1. `MatchSession.is_authority()` answers TRUE on every peer, so every machine
##    simulates the whole world rather than drawing a replica of it
## 2. an order is not applied when it is given. It is booked for a turn a little
##    ahead, exchanged, and run by every peer on that turn - `CommandService`
##    sends it here instead of to the server
## 3. `ReplicationService` goes silent. There is no state stream at all
##
## **A turn may only be simulated once every peer's orders for it have arrived**,
## and until they have, the world is held still. That hold IS lockstep: it is
## what guarantees no machine ever simulates a tick on inputs another machine
## did not have.
##
## ## What the checksums are for, and why they cannot lie now
##
## With no authoritative server there is nothing to compare a world against
## except another peer's. So each machine hashes its world on a turn boundary
## and the relay compares them - detection only, since there is no correction
## anybody would be entitled to send.
##
## This half **could not work under D2, and finding that out cost a live match**:
## a client there does not simulate, so its world is a replica holding none of
## the state `Unit.checksum_state()` reports, and comparing the two disagreed as
## soon as a tower was built. The lesson outlived the bug - **"do two machines
## agree" has no answer while only one of them is computing** - and it is exactly
## what changes on the day this flag goes on.
##
## ## What a TURN is
##
## Lockstep cannot simulate a tick until every peer's orders for it have
## arrived, and waiting on the network every 50 ms would be absurd. So orders
## are batched into TURNS of `ticks_per_turn` ticks, and an order given during
## turn T is scheduled to run on turn T + `input_delay_turns`. That delay is
## what buys the packets time to land, and it is the one number a player feels.
##
## Every peer sends its orders for a turn even when it has none, because
## "nothing" is the message that lets the turn close. Silence is
## indistinguishable from a lost packet.
##
## ## Why this is an autoload
##
## It owns @rpc endpoints, and Godot routes those by node path - the client's
## match root is /root/Main and the server's is /root/ServerMatch, so no node
## inside a match scene can receive one. See `CLAUDE.md`.

## Every peer's orders for a turn have arrived, and it could be simulated. Not
## acted on yet: see the note at the top.
signal turn_ready(turn: int, commands: Array)

## A turn closed with somebody missing. Under lockstep this is where the match
## would stall waiting; today it is only worth knowing about.
signal turn_stalled(turn: int, missing: PackedInt32Array)

## The turn a match-start comparison belongs to, which is before any turn has
## run. Mirrors MatchStartService.DESYNC_START_TICK.
const NO_TURN: int = -1

# --- local state, on every machine ----------------------------------------
## Orders this machine has issued that have not been sent yet, keyed by the
## turn they are scheduled to run on.
var _outgoing: Dictionary = {}
## Orders received per turn, keyed by turn then by peer id.
var _incoming: Dictionary = {}
## The last turn this machine sent for, so it sends exactly once per turn.
var _last_sent_turn: int = NO_TURN
## The last turn this machine checksummed, on the same reasoning.
var _last_checksum_turn: int = NO_TURN
## The last turn whose orders were actually run, so a turn runs exactly once.
var _last_run_turn: int = NO_TURN
## Whether the world is being held still waiting for a turn, and which one.
var _stalling: bool = false
var _stalled_on: int = NO_TURN
## Whether the first turns have been primed. See _send_turn.
var _primed: bool = false

# --- server state ---------------------------------------------------------
## Checksums reported per turn, keyed by turn then by peer id.
var _turn_checksums: Dictionary = {}
## Peers already told their world diverged, so each is told once per match.
var _told: Dictionary = {}


func _ready() -> void:
	# **Immune to the pause it causes itself**, and this is not optional: a stall
	# holds the tree still, and a node that stopped with it could never notice
	# the turn it was waiting for had arrived. The match would hold forever on
	# the first hiccup. Same reason every other network autoload sets this.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# FIRST in the tick, deliberately, and no priority is set to get it: an
	# autoload is added to the root before the match scene, so it already runs
	# ahead of everything it has to run ahead of. `CommandService` depends on
	# exactly the same thing and says so.
	#
	# It has to be first because a turn's orders must land BEFORE the world
	# moves on the tick they belong to. A build order applied after the tick it
	# was scheduled for would take effect a tick later on this machine than the
	# schedule says - and every machine has to agree about that to the tick.
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if !_is_live():
		return

	var turn: int = current_turn()
	_advance_turn(turn)

	# After the turn, so a machine held on a stall does not go on announcing
	# turns it has not reached. Its own clock is frozen while held, so the turn
	# number here does not move either.
	if turn != _last_sent_turn:
		_send_turn(turn)
		_last_sent_turn = turn


## The heart of lockstep: a turn may only be SIMULATED once every peer's orders
## for it have arrived.
##
## Two things happen on the first tick of a turn and nothing happens on the
## other three. If the turn is complete its orders are applied and the world is
## allowed to move. If it is not, **the whole match is held still** until it is
## - which is the stutter every lockstep game has when somebody's connection
## hiccups, and is strictly better than the alternative of simulating ahead and
## discovering later that everyone computed a different world.
##
## `MatchSession.set_paused` is what does the holding, and it is exactly the
## right tool: it pauses the TREE, so every gameplay loop stops at once without
## any of them being asked, and it gives the match clock back what the hold took
## so no creep unlock silently serves its time during a stall.
func _advance_turn(turn: int) -> void:
	if turn == _last_run_turn:
		return
	if _session_tick() != first_tick_of(turn):
		return

	if !_is_complete(turn):
		if !_stalling:
			_stalling = true
			_stalled_on = turn
			var missing: PackedInt32Array = _missing_for(turn)
			Log.warn("Waiting on a turn", {"turn": turn, "missing": missing})
			turn_stalled.emit(turn, missing)
			_set_held(true)
		return

	if _stalling:
		Log.info("Turn arrived, resuming", {
			"turn": turn, "waited_on": _stalled_on,
		})
		_stalling = false
		_stalled_on = NO_TURN
		_set_held(false)

	_last_run_turn = turn

	# **Checksummed BEFORE the orders are applied**, so the number describes a
	# point every machine can name without ambiguity: the boundary of this turn,
	# with everything up to it done and nothing of it started. Taking it after
	# would be equally valid and equally consistent; what would NOT be valid is
	# taking it at a moment the machines could reach differently.
	_maybe_report_checksum(turn)

	var orders: Array = commands_for(turn)
	_incoming.erase(turn)
	turn_ready.emit(turn, orders)
	if !orders.is_empty():
		Commands.apply_turn(orders)


## Whether every peer has said what it is doing on this turn.
func _is_complete(turn: int) -> bool:
	var by_peer: Dictionary = _incoming.get(turn, {})
	for peer: int in _expected_peers():
		if !by_peer.has(peer):
			return false
	return true


func _missing_for(turn: int) -> PackedInt32Array:
	return _missing_peers(_incoming.get(turn, {}))


## Holds or releases the world. Routed through the session so the match clock is
## corrected, and so a stall and the technology draft cannot fight over the
## tree - whoever wants it held has it held.
func _set_held(held: bool) -> void:
	var session: MatchSession = References.match_session
	if session != null:
		session.set_paused(held)


# --- the turn clock -------------------------------------------------------

## The turn the match is in right now, counting from 0 alongside the tick.
func current_turn() -> int:
	return turn_for_tick(_session_tick())


func turn_for_tick(tick: int) -> int:
	return tick / _ticks_per_turn()


## The first tick of a turn, which is when its orders would be applied.
func first_tick_of(turn: int) -> int:
	return turn * _ticks_per_turn()


## The turn an order given RIGHT NOW should run on.
##
## Never the current turn: its inputs are already being exchanged, and an order
## added to it now would reach some peers after they had simulated it. That is
## the desync lockstep exists to make impossible, so the delay is not tunable
## down to zero - see NetworkConfig.input_delay_turns.
##
## **Counted from the next turn this machine will SEND for, not from the turn it
## is in**, and the difference is not academic. Orders arrive on render frames;
## sending happens on the physics tick that opens a turn. An order given after
## that tick but still inside the same turn would be booked for a turn whose
## packet had already gone out empty - so it sat in the outgoing pile forever
## and simply never happened. It cost a full two-peer run to see, because
## nothing errors: the turns all run, the checksums all agree, and the orders
## are quietly dropped.
func scheduled_turn() -> int:
	return maxi(current_turn(), _last_sent_turn + 1) + _input_delay()


# --- collecting orders ----------------------------------------------------

## Books a command for the turn it should run on, and answers which that is.
##
## Called ALONGSIDE the existing submit path rather than instead of it, so a
## command still travels and still applies exactly as it does today. What this
## adds is a record of which turn it would have belonged to.
func schedule(command: Command) -> int:
	if command == null || !_is_live():
		return NO_TURN

	var turn: int = scheduled_turn()
	if !_outgoing.has(turn):
		_outgoing[turn] = []
	(_outgoing[turn] as Array).append(command.to_dict())
	return turn


## Every command known for a turn, in a deterministic order.
##
## **Sorted by the peer that sent it**, because a Dictionary's own order is not
## something two machines may be trusted to agree on - and if two peers applied
## the same turn's orders in different orders they would diverge, which is the
## exact failure this whole file exists to prevent.
func commands_for(turn: int) -> Array:
	var by_peer: Dictionary = _incoming.get(turn, {})
	var peers: Array = by_peer.keys()
	peers.sort()

	var ordered: Array = []
	for peer: Variant in peers:
		ordered.append_array(by_peer[peer] as Array)
	return ordered


# --- exchanging them ------------------------------------------------------

func _send_turn(turn: int) -> void:
	# **The pipeline has to be primed or nothing ever starts.** An order given
	# now is booked `input_delay` turns ahead, so the first `input_delay` turns
	# can never carry one - and nobody would ever send for them. Every peer then
	# reaches turn 0, waits for orders that by definition do not exist, and the
	# match holds forever on its first tick. Cost a full two-peer run to find,
	# and it looked exactly like a networking failure.
	if !_primed:
		_primed = true
		for early: int in range(turn, turn + _input_delay()):
			_emit(early, [])

	var scheduled: int = turn + _input_delay()
	var payload: Array = _outgoing.get(scheduled, [])
	_outgoing.erase(scheduled)
	_emit(scheduled, payload)


## Sent even when EMPTY. "I have nothing for this turn" is the message that lets
## the turn close; silence cannot be told apart from a dropped packet.
func _emit(turn: int, payload: Array) -> void:
	if Net.is_server():
		_record(turn, NetworkService.SERVER_PEER_ID, payload)
		receive_turn.rpc(turn, NetworkService.SERVER_PEER_ID, payload)
		return
	submit_turn.rpc_id(NetworkService.SERVER_PEER_ID, turn, payload)


## A client's orders for a turn, arriving at the server. Relayed on rather than
## applied: every peer needs every peer's orders, which is the whole shape of
## lockstep and the reason the server stops being an authority under it.
##
## **Every order is STAMPED with the sender's slot on the way through, and that
## is the one thing the relay must not stop doing.** Under D2 the same line
## lived in `CommandService.submit_command`, and its comment is worth repeating
## because it matters more here: whatever a client writes into the slot field is
## discarded, so the worst a modified client can do is issue orders as itself.
##
## Without it lockstep is WEAKER than replication, not stronger. A forged slot
## does not desync - every peer would apply the same forged order and agree
## perfectly about a maze somebody else paid for. Desync catches a peer that
## simulates differently; it cannot catch one that lies about who it is. Only
## the relay knows which peer owns which slot, so only the relay can refuse it.
@rpc("any_peer", "reliable")
func submit_turn(turn: int, payload: Array) -> void:
	if !multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var stamped: Array = _stamped(payload, _slot_of_peer(sender))
	_record(turn, sender, stamped)
	# **The origin travels with the orders.** Relaying without it recorded every
	# peer's turn under the SERVER's id, because that is who
	# get_remote_sender_id() names on the second hop - so two clients' orders
	# overwrote each other under one key and no turn was ever complete.
	receive_turn.rpc(turn, sender, stamped)


## Rewrites the slot on every order in a turn to the one its sender really owns.
func _stamped(payload: Array, slot: int) -> Array:
	var out: Array = []
	for entry: Variant in payload:
		var data: Dictionary = (entry as Dictionary).duplicate()
		data["slot"] = slot
		out.append(data)
	return out


## Which slot a peer plays, from the setup rather than from anything it said.
## 0 for the server itself, which plays none.
func _slot_of_peer(peer_id: int) -> int:
	var session: MatchSession = References.match_session
	if session == null || session.setup() == null:
		return 0
	for player: MatchPlayer in session.setup().players:
		if player != null && player.network_id == peer_id:
			return player.slot
	return 0


## Orders reaching a peer, named by WHOSE they are rather than by who forwarded
## them. `from_peer` is stamped by the server and cannot be set by the sender:
## a client only ever talks to the server, and the server names the sender from
## the connection it arrived on.
@rpc("any_peer", "call_remote", "reliable")
func receive_turn(turn: int, from_peer: int, payload: Array) -> void:
	if multiplayer.get_remote_sender_id() != NetworkService.SERVER_PEER_ID:
		return
	_record(turn, from_peer, payload)


func _record(turn: int, peer: int, payload: Array) -> void:
	if !_incoming.has(turn):
		_incoming[turn] = {}
	(_incoming[turn] as Dictionary)[peer] = payload


func _missing_peers(by_peer: Dictionary) -> PackedInt32Array:
	var missing: PackedInt32Array = PackedInt32Array()
	for peer: int in _expected_peers():
		if !by_peer.has(peer):
			missing.append(peer)
	return missing


## Everyone whose orders a turn is waiting on: every connected peer, plus the
## server itself, which plays no slot but still relays.
func _expected_peers() -> PackedInt32Array:
	var peers: PackedInt32Array = PackedInt32Array([NetworkService.SERVER_PEER_ID])
	for id: int in multiplayer.get_peers():
		if id != NetworkService.SERVER_PEER_ID:
			peers.append(id)
	return peers


# --- agreeing on the result ----------------------------------------------

## The world at the end of a turn, hashed and sent to the server to compare.
##
## This is the ONLY thing that detects a desync once the server stops holding an
## authoritative world, which is what lockstep makes true. It cannot repair
## anything - there is no correction to send, and no machine entitled to send
## one. All it can do is say WHICH TURN the worlds parted on, early enough that
## the answer is still traceable.
func _maybe_report_checksum(turn: int) -> void:
	if turn == _last_checksum_turn || turn % _checksum_every() != 0:
		return
	_last_checksum_turn = turn

	var session: MatchSession = References.match_session
	if session == null:
		return
	var sum: int = WorldChecksum.of(session.setup(), _areas(), session)

	if Net.is_server():
		_compare_turn(turn, NetworkService.SERVER_PEER_ID, sum)
		return
	report_turn_checksum.rpc_id(NetworkService.SERVER_PEER_ID, turn, sum)


@rpc("any_peer", "reliable")
func report_turn_checksum(turn: int, checksum: int) -> void:
	if !multiplayer.is_server():
		return
	_compare_turn(turn, multiplayer.get_remote_sender_id(), checksum)


## The server holds the first answer it hears for a turn and measures every
## later one against it.
##
## **Under lockstep that first answer is not authoritative and this is not a
## verdict** - the server runs no simulation, so it is comparing two peers, not
## judging one. What it can say for certain is that they DIFFER, and which turn
## it started on. Who is wrong is a different question and may have no answer.
func _compare_turn(turn: int, peer: int, checksum: int) -> void:
	if !_turn_checksums.has(turn):
		_turn_checksums[turn] = {}
	var by_peer: Dictionary = _turn_checksums[turn]
	by_peer[peer] = checksum

	var reference: int = 0
	var has_reference: bool = false
	for id: Variant in by_peer.keys():
		if !has_reference:
			reference = int(by_peer[id])
			has_reference = true
			continue
		if int(by_peer[id]) == reference:
			continue

		# Once per peer per match, not once per checksum turn. A world that has
		# diverged stays diverged, so every later turn disagrees too - and
		# reporting each one buries the FIRST one, which is the only tick with
		# any diagnostic value. It also spammed a live log on 2026-09-04.
		if _told.has(int(id)):
			continue
		_told[int(id)] = true

		Log.err("Peers disagree about the world", {
			"turn": turn,
			"tick": first_tick_of(turn),
			"peer": id,
			"theirs": int(by_peer[id]),
			"reference": reference,
		})
		if int(id) != NetworkService.SERVER_PEER_ID:
			MatchStart.receive_desync.rpc_id(
				int(id), first_tick_of(turn), int(by_peer[id]), reference
			)

	_forget_old_turns(turn)


## Keeps the last few turns and drops the rest. A match is thousands of turns
## long and every one of them would otherwise be held forever.
func _forget_old_turns(now: int) -> void:
	for turn: Variant in _turn_checksums.keys():
		if now - int(turn) > _checksum_every() * 4:
			_turn_checksums.erase(turn)


# --- lookups --------------------------------------------------------------

## Off the network there are no turns to agree on, and a single player run must
## pay nothing at all for any of this.
##
## **Also gated on `lockstep_enabled`, which is OFF, and that gate is not
## caution - it is a correctness fix.** Comparing world checksums between
## machines is meaningless while only one of them simulates, which is exactly
## what D2 means: a client draws replicated snapshots and runs no gameplay loop
## of its own. Left ungated, this reported a desync as soon as a tower was built
## and ended a live match on 2026-09-04. See NetworkConfig.lockstep_enabled.
func _is_live() -> bool:
	if !Net.is_online() || References.match_session == null:
		return false
	var config: NetworkConfig = _config()
	return config != null && config.lockstep_enabled


func _session_tick() -> int:
	var session: MatchSession = References.match_session
	return 0 if session == null else session.tick()


func _areas() -> Array[PlayerArea]:
	var manager: PlayerManager = References.player_manager
	var areas: Array[PlayerArea] = []
	if manager == null:
		return areas
	for state: PlayerState in manager.states_in_slot_order():
		var area: PlayerArea = manager.area_for(state.player_id)
		if area != null:
			areas.append(area)
	return areas


func _config() -> NetworkConfig:
	return References.network_config


func _ticks_per_turn() -> int:
	var config: NetworkConfig = _config()
	return 4 if config == null else maxi(1, config.ticks_per_turn)


func _input_delay() -> int:
	var config: NetworkConfig = _config()
	return 2 if config == null else maxi(1, config.input_delay_turns)


func _checksum_every() -> int:
	var config: NetworkConfig = _config()
	return 5 if config == null else maxi(1, config.checksum_every_turns)
