class_name MatchSeats
extends RefCounted

## The seat table a MATCH PROCESS keeps, and every rule about claiming a seat
## in it (D44, `Docs/multi-match.md` §2 step 6).
##
## **The lobby's peer ids mean nothing here.** A peer id is chosen by the CLIENT,
## afresh on every connection, and every id is public - so the move from the
## lobby process to this one is an identity transfer, not an address change. A
## seat is identified by its TOKEN until a connection claims it, and by its peer
## id afterwards.
##
## A seat is in one of four states:
##
##   unclaimed   never admitted
##   claimed     admitted; peer id set; the ready flag is meaningful
##   dropped     inside D26's hold, and CLAIMABLE AGAIN with the same token
##   left        out of this match, for good
##
## **`dropped` is the D26 hold, and it is deliberately not called "held".** A
## dropped seat MAY be claimed again - that is the owner's rule, taken after the
## plan's review - while `SEAT_HELD` refuses a claim because somebody else has
## the seat right now. One word for both made a proof read as the opposite of
## the decision.
##
## Nothing here talks to the network. It answers questions and records answers;
## `MatchServer` owns the socket and `MatchStart` owns the gate.

enum State {
	UNCLAIMED,
	CLAIMED,
	DROPPED,
	LEFT,
}

## One row of the table. A plain inner class rather than a Dictionary so a
## misspelled field is a parse error rather than a silent null at three in the
## morning.
class Seat extends RefCounted:
	var slot: int = 0
	var token: PackedByteArray = PackedByteArray()
	var peer_id: int = 0
	var is_ready: bool = false
	var state: State = State.UNCLAIMED
	var hold_left: float = 0.0
	## How this seat's player went, for the RESULT. Set once, at the departure
	## that decided it.
	var outcome: String = ""
	## The relay turn that departure happened on, or -1 for one before the go
	## signal, when no turn exists yet.
	var outcome_turn: int = -1


## The setup as ANNOUNCED, whose slot numbering the table is keyed by. The go
## roster renumbers, so this is never the same numbering as the started match's
## once anybody has been left behind.
var _setup: MatchSetup = null
## slot -> Seat.
var _seats: Dictionary = {}
## peer id -> slot, for a connection that has passed the token check but has not
## been admitted yet. **A pending entry takes the seat**; it is not a claim.
var _pending: Dictionary = {}
## Set at the go signal. From then on no token is accepted at all.
var _closed: bool = false
## How long a dropped seat stays claimable (D26).
var _hold_seconds: float = 0.0


## Builds the table from the announced setup and the lobby's token map.
##
## A seat with no token is an AI seat (later) or a seat the lobby never filled.
## It is `left` from the start: nothing can claim it, and the gate never waits
## for it.
func build(setup: MatchSetup, tokens: Dictionary, hold_seconds: float) -> void:
	_setup = setup
	_hold_seconds = maxf(0.0, hold_seconds)
	_seats.clear()
	_pending.clear()
	_closed = false
	if setup == null:
		return

	for player: MatchPlayer in setup.players:
		if player == null || player.slot <= 0:
			continue
		var seat: Seat = Seat.new()
		seat.slot = player.slot
		seat.token = tokens.get(player.slot, PackedByteArray())
		if !MatchHandoff.is_valid_token(seat.token):
			seat.state = State.LEFT
			seat.outcome = "no_token"
		_seats[player.slot] = seat


## **The token check, and every rule that decides who may hold a seat.**
##
## Returns 0 to admit, or the `MatchHandoff.AUTH_*` status to refuse with.
##
## The caller completes auth on 0 and answers with the status otherwise. It does
## NOT hang up: the client hangs up once it has read the status, and the auth
## timeout closes the connection if it does not. A hang-up in the same breath
## delivered the reason zero times in six, measured (`CLAUDE.md`).
func check_token(peer_id: int, token: PackedByteArray) -> int:
	# From the go signal on, nothing is admitted. In practice ENet has already
	# reset a dial made after go, before any of this runs - this covers a
	# connection that was still PENDING when the signal went out.
	if _closed:
		return MatchHandoff.AUTH_TOO_LATE
	if !MatchHandoff.is_valid_token(token):
		return MatchHandoff.AUTH_WRONG_TOKEN
	# One connection claims at most one seat, so a second message from a
	# connection that already passed is refused rather than moving it.
	if _pending.has(peer_id) || _slot_of_peer(peer_id) != 0:
		return MatchHandoff.AUTH_WRONG_TOKEN

	var seat: Seat = _seat_for_token(token)
	if seat == null:
		return MatchHandoff.AUTH_WRONG_TOKEN
	if seat.state == State.LEFT:
		return MatchHandoff.AUTH_TOO_LATE
	# **A pending entry TAKES the seat**, which is the whole of C1/C4/I4 from the
	# plan's check pass. Without it the seat still reads `unclaimed` between this
	# check and the admission that follows, so two connections presenting one
	# token within a round trip would both pass and both be admitted - and the
	# retry rule produces exactly that with no attacker at all, whenever a
	# client's dial timer fires after the server has already accepted it.
	if seat.state == State.CLAIMED || _is_pending_for(seat.slot):
		return MatchHandoff.AUTH_SEAT_HELD

	_pending[peer_id] = seat.slot
	return 0


## Turns a pending entry into a claim, on `peer_connected`. Returns the slot, or
## 0 for a connection that has no pending entry - which cannot happen under
## `check_token`'s rules and is refused rather than guessed at.
func admit(peer_id: int) -> int:
	if !_pending.has(peer_id):
		return 0
	var slot: int = _pending[peer_id]
	_pending.erase(peer_id)

	var seat: Seat = _seats.get(slot)
	if seat == null:
		return 0
	# Belt and braces for the case `check_token` says cannot arise. Whoever has
	# the seat keeps it; the newcomer is the caller's to disconnect.
	if seat.state == State.CLAIMED:
		return 0

	seat.state = State.CLAIMED
	seat.peer_id = peer_id
	seat.is_ready = false
	seat.hold_left = 0.0
	return slot


## **Lets go of a seat, and ONLY for the peer that actually holds it.**
##
## Returns the slot released, or 0 for a departure that changes nothing.
##
## The naming is the point. A superseded or refused connection times out later,
## and without this its `peer_disconnected` would release the seat its live
## successor holds - dropping a seat into D26's hold while its player is sitting
## there connected.
##
## `deliberate` is a player who said they were leaving (D26): out at once. A link
## that merely broke gets the hold, inside which the same token may claim again.
func release(peer_id: int, deliberate: bool, turn: int) -> int:
	if _pending.get(peer_id, 0) != 0:
		# A pending entry is not a claim. Discarding it frees the seat for the
		# next attempt and changes no state.
		var pending_slot: int = _pending[peer_id]
		_pending.erase(peer_id)
		return pending_slot

	var slot: int = _slot_of_peer(peer_id)
	if slot == 0:
		return 0
	var seat: Seat = _seats[slot]
	seat.peer_id = 0
	seat.is_ready = false
	if deliberate || _hold_seconds <= 0.0:
		_mark_left(seat, "left" if deliberate else "timed_out", turn)
		return slot
	seat.state = State.DROPPED
	# Every drop starts a FRESH hold, so a player who reconnects and loses the
	# link again gets the same window rather than the remains of the last one.
	seat.hold_left = _hold_seconds
	return slot


## Marks a seat as out before the code closes its connection on purpose, so the
## `peer_disconnected` that follows does not read a deliberate close as a
## dropped link and start a hold for it.
func mark_left(slot: int, why: String, turn: int) -> void:
	var seat: Seat = _seats.get(slot)
	if seat != null:
		_mark_left(seat, why, turn)


## Counts down every hold, and returns the slots whose time ran out. Wall clock:
## there is no simulation running while the gate waits.
func advance_holds(delta: float) -> PackedInt32Array:
	var expired: PackedInt32Array = PackedInt32Array()
	for slot: int in _seats:
		var seat: Seat = _seats[slot]
		if seat.state != State.DROPPED:
			continue
		seat.hold_left -= delta
		if seat.hold_left <= 0.0:
			_mark_left(seat, "timed_out", -1)
			expired.append(slot)
	return expired


## Records that a seat's player has finished loading. Returns the slot, or 0 if
## that peer holds no seat - a report from a stranger, or from a connection
## whose seat has moved on.
func set_ready(peer_id: int) -> int:
	var slot: int = _slot_of_peer(peer_id)
	if slot == 0:
		return 0
	var seat: Seat = _seats[slot]
	if seat.is_ready:
		return 0
	seat.is_ready = true
	return slot


## Whether the gate may start EARLY: every seat that is not `left` is claimed
## and ready. An unclaimed or dropped seat blocks it, which is what makes the
## match wait out D26's hold for somebody whose link broke while loading.
func everyone_in() -> bool:
	for slot: int in _seats:
		var seat: Seat = _seats[slot]
		if seat.state == State.LEFT:
			continue
		if seat.state != State.CLAIMED || !seat.is_ready:
			return false
	return true


## Whether any seat is still worth waiting for. False means every seat has left,
## and the process has nothing left to do.
func any_live() -> bool:
	for slot: int in _seats:
		if _seats[slot].state != State.LEFT:
			return true
	return false


## The slots that are claimed, connected and ready - the go roster, before it is
## renumbered.
func ready_slots() -> PackedInt32Array:
	var slots: PackedInt32Array = PackedInt32Array()
	for slot: int in _seats:
		var seat: Seat = _seats[slot]
		if seat.state == State.CLAIMED && seat.is_ready && seat.peer_id != 0:
			slots.append(slot)
	slots.sort()
	return slots


## Every peer currently holding a seat. **This is what a match process means by
## "the players"** - never `multiplayer.get_peers()`, which also answers for a
## connection that has authenticated and claimed nothing.
func claimed_peers() -> PackedInt32Array:
	var peers: PackedInt32Array = PackedInt32Array()
	for slot: int in _seats:
		var seat: Seat = _seats[slot]
		if seat.state == State.CLAIMED && seat.peer_id != 0:
			peers.append(seat.peer_id)
	return peers


## The peer holding a seat, or 0.
func peer_of(slot: int) -> int:
	var seat: Seat = _seats.get(slot)
	return 0 if seat == null else seat.peer_id


## The seat a peer holds, or 0.
func slot_of(peer_id: int) -> int:
	return _slot_of_peer(peer_id)


## Whether a peer holds a seat at all, which is a match process's answer to
## "is this one of my players".
func has_peer(peer_id: int) -> bool:
	return _slot_of_peer(peer_id) != 0


## The announced slots that have reported ready, for the loading screens. Sent as
## SLOTS rather than peer ids because the clients never saw the new ids.
func ready_flags() -> PackedInt32Array:
	return ready_slots()


## **Shuts the door at the go signal.** Every seat outside the roster becomes
## `left`, its hold is discarded, and no PLAYER_LEFT is issued for it, because it
## never had an area to erase. From here nothing is admitted.
func close_for_go(started: PackedInt32Array) -> void:
	_closed = true
	for slot: int in _seats:
		var seat: Seat = _seats[slot]
		if slot in started:
			continue
		if seat.state != State.LEFT:
			_mark_left(seat, "not_loaded" if seat.state == State.CLAIMED else "never_claimed", -1)
	_pending.clear()


## Whether the door is shut.
func is_closed() -> bool:
	return _closed


## The announced setup this table was built from.
func setup() -> MatchSetup:
	return _setup


## Every seat as the RESULT records it: per ANNOUNCED slot, who was in it and
## how they went. The go slot is filled in by the caller, which is the only
## place that knows the renumbering.
func result_rows() -> Array:
	var rows: Array = []
	var slots: Array = _seats.keys()
	slots.sort()
	for slot: int in slots:
		var seat: Seat = _seats[slot]
		var player: MatchPlayer = _player_at(slot)
		rows.append({
			"slot": slot,
			"name": "" if player == null else player.display_name,
			"colour": 0 if player == null else player.color_index,
			"outcome": seat.outcome,
			"turn": seat.outcome_turn,
		})
	return rows


func _mark_left(seat: Seat, why: String, turn: int) -> void:
	seat.state = State.LEFT
	seat.peer_id = 0
	seat.is_ready = false
	seat.hold_left = 0.0
	if seat.outcome.is_empty():
		seat.outcome = why
		seat.outcome_turn = turn


func _seat_for_token(token: PackedByteArray) -> Seat:
	for slot: int in _seats:
		var seat: Seat = _seats[slot]
		if MatchHandoff.tokens_equal(seat.token, token):
			return seat
	return null


func _is_pending_for(slot: int) -> bool:
	for peer_id: int in _pending:
		if _pending[peer_id] == slot:
			return true
	return false


func _slot_of_peer(peer_id: int) -> int:
	if peer_id == 0:
		return 0
	for slot: int in _seats:
		var seat: Seat = _seats[slot]
		if seat.state == State.CLAIMED && seat.peer_id == peer_id:
			return slot
	return 0


func _player_at(slot: int) -> MatchPlayer:
	if _setup == null:
		return null
	for player: MatchPlayer in _setup.players:
		if player != null && player.slot == slot:
			return player
	return null
