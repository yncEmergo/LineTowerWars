class_name LockstepService
extends Node

## Turn scheduling and per-turn agreement, for the lockstep model (D2 under
## review, `multiplayer.md` 4.1).
##
## **ASLEEP until `NetworkConfig.lockstep_enabled` is turned on, and that is not
## caution.** It counts turns, collects the commands belonging to each one,
## exchanges them between peers and compares world checksums per turn. It
## executes nothing: `CommandService` still applies orders exactly as it did and
## `ReplicationService` still sends the world.
##
## **The checksum half CANNOT run under D2, and finding that out cost a live
## match.** This file was first written believing it could sit beside the real
## system and answer "would lockstep have worked on this turn?". Half of that
## was wrong. A client under D2 does not simulate - `MatchSession.is_authority()`
## stops every gameplay loop on it - so its world is a REPLICA assembled from
## snapshots, and it holds none of the state `Unit.checksum_state()` reports:
## no path index, no aura values, no banked ability state. Comparing it against
## the server's therefore disagrees the moment anything happens, and on
## 2026-09-04 the first tower built ended the match with a desync popup.
##
## The lesson is worth more than the bug: **"do two machines agree" is not a
## question that has an answer while only one of them is computing.** It starts
## having one on the day every peer simulates, which is the same day the flag
## goes on.
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

# --- server state ---------------------------------------------------------
## Checksums reported per turn, keyed by turn then by peer id.
var _turn_checksums: Dictionary = {}
## Peers already told their world diverged, so each is told once per match.
var _told: Dictionary = {}


func _ready() -> void:
	# Last in the tick, after the simulation has moved: a turn's checksum
	# describes the world at the END of that turn, and reading it before the
	# match scene has run would describe the previous one. process_physics_
	# priority, NOT process_priority - Godot 4.3 split them and only the second
	# one orders the tick (CLAUDE.md).
	process_physics_priority = 1000
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if !_is_live():
		return

	var turn: int = current_turn()
	if turn != _last_sent_turn:
		_send_turn(turn)
		_last_sent_turn = turn

	_close_finished_turns(turn)
	_maybe_report_checksum(turn)


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
func scheduled_turn() -> int:
	return current_turn() + _input_delay()


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
	var scheduled: int = turn + _input_delay()
	var payload: Array = _outgoing.get(scheduled, [])
	_outgoing.erase(scheduled)

	# Sent even when empty. "I have nothing for this turn" is what closes it;
	# silence cannot be told apart from a dropped packet.
	if Net.is_server():
		_record(scheduled, 1, payload)
		receive_turn.rpc(scheduled, payload)
		return
	submit_turn.rpc_id(NetworkService.SERVER_PEER_ID, scheduled, payload)


## A client's orders for a turn, arriving at the server. Relayed on rather than
## applied: every peer needs every peer's orders, which is the whole shape of
## lockstep and the reason the server stops being an authority under it.
@rpc("any_peer", "reliable")
func submit_turn(turn: int, payload: Array) -> void:
	if !multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_record(turn, sender, payload)
	receive_turn.rpc(turn, payload)


@rpc("any_peer", "call_remote", "reliable")
func receive_turn(turn: int, payload: Array) -> void:
	_record(turn, multiplayer.get_remote_sender_id(), payload)


func _record(turn: int, peer: int, payload: Array) -> void:
	if !_incoming.has(turn):
		_incoming[turn] = {}
	(_incoming[turn] as Dictionary)[peer] = payload


## A turn is finished once the match has walked past it. Whether every peer
## reported in time is the question lockstep would block on, and today is only
## reported.
func _close_finished_turns(now: int) -> void:
	for turn: Variant in _incoming.keys():
		if int(turn) >= now:
			continue
		var by_peer: Dictionary = _incoming[turn]
		var missing: PackedInt32Array = _missing_peers(by_peer)
		if missing.is_empty():
			turn_ready.emit(int(turn), commands_for(int(turn)))
		else:
			turn_stalled.emit(int(turn), missing)
		_incoming.erase(turn)


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
