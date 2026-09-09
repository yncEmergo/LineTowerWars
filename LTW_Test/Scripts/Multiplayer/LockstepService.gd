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
## ## What a TURN is, and where the input delay really comes from
##
## A TURN is a group of `ticks_per_turn` simulation ticks - one tick, in
## practice - and it is the unit orders are scheduled in. Every peer says its
## final word on every turn, even when that word is "nothing", because silence
## cannot be told apart from a lost packet.
##
## An order is booked for the first turn this machine has NOT yet closed, and it
## runs when that turn comes up. So what a player waits is:
##
##     however long until that turn runs  =  the delay, plus up to one turn
##
## and the delay is simply how far ahead of itself this machine chooses to
## close turns. **That is the whole of it.** There is no other term. A delay of
## four turns at 100 ms a turn is 400 ms of input lag and buys 400 ms of wire
## time that a 20 ms link does not want.
##
## **The delay is a LIVENESS parameter, never a CORRECTNESS one**, and getting
## that backwards is what made this expensive. It decides which turn an order is
## booked for; it has no say in what that turn then does. Every peer applies
## turn N's orders on tick N regardless of how far ahead anybody chose to close
## it. So the delay may be changed mid-match, and two peers may hold different
## values, without any risk of divergence whatsoever - the worst a wrong value
## can do is stall (too low) or feel heavy (too high).
##
## That is what lets it be MEASURED rather than guessed. See `delay_turns()`.
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

## How often a stall repeats itself, in physics frames. Two seconds at 20 Hz.
const STALL_REPORT_FRAMES: int = 40


## How far ahead of what it has SEEN a relay books a system order. One second at
## 20 Hz. See inject().
const SYSTEM_LEAD_TURNS: int = 20

## How often a peer tells the relay it is still alive, in physics frames. Twice a
## second at 20 Hz, against a timeout measured in seconds - so a dozen of these
## have to go missing before anybody is given up on. See _beat.
const HEARTBEAT_FRAMES: int = 10

## How many tick intervals the local-jitter window remembers. Three seconds at
## 20 Hz: long enough to hold a hitch that matters, short enough that the delay
## comes back down once the machine recovers.
const JITTER_SAMPLES: int = 60

## How many of those must be collected before the window is believed. A match
## opens with the world being built, which is not what a settled tick costs.
const JITTER_MIN_SAMPLES: int = 20

## How often the percentile is recomputed, in frames. Sorting sixty floats is
## cheap, and doing it four times a second rather than twenty keeps it off the
## hot path entirely.
const JITTER_REFRESH_FRAMES: int = 5

## How many arrival samples per peer the lead window remembers. Ten seconds at
## 20 Hz - long enough that a p99 means something, short enough to follow a link
## that changes during a match.
const LEAD_SAMPLES: int = 200

## How often the relay reports drift, in frames. Five seconds at 20 Hz, matching
## the peer-side health line so the two logs join on the same cadence.
const DRIFT_EVERY_FRAMES: int = 100

## How far outside the turns anybody could plausibly be on a word is refused.
## Generous, because the honest spread between two peers is `max_delay_turns` and
## this only has to catch a number that is wrong by orders of magnitude.
const TURN_SLACK: int = 200

## How many recent turns ride along in every unreliable echo. See _emit.
##
## **Two, not four.** Two covers a single loss with one to spare, which is the
## case that actually happens; four covered three consecutive losses, which is a
## connection that has already failed for other reasons. It matters because the
## relay re-sends each peer's whole window to everybody, so this is the dominant
## term in the echo's traffic and halving it halves that.
const ECHO_TURNS: int = 2

## How often the server re-measures the connections, in physics frames. One
## second at 20 Hz, and it only says anything when the answer has moved - a
## link that is behaving costs one comparison a second and no traffic at all.
const MEASURE_EVERY_FRAMES: int = 20

## How many un-answered presses a peer holds while waiting to hear its own
## orders come back. A flood guard on a diagnostic queue, not a gameplay limit:
## it only fills if orders are sent and never sealed, which is a broken match.
const MAX_PRESSES_HELD: int = 256


# --- local state, on every machine ----------------------------------------
## Orders this machine has issued that have not been sent yet, keyed by the
## turn they are scheduled to run on.
## Orders received per turn, keyed by turn then by peer id.
## The highest turn this machine has said its final word on. Everything above
## it is still open to an order. See _close_through.
## The last turn this machine checksummed, on the same reasoning.
var _last_checksum_turn: int = NO_TURN
## The last turn whose orders were actually run, so a turn runs exactly once.
var _last_run_turn: int = NO_TURN
## Whether the world is being held still waiting for a turn, and which one.
var _stalling: bool = false
var _stalled_on: int = NO_TURN
## Physics frames spent in the current stall, for the repeating report.
var _stall_frames: int = 0
## Physics frames spent stalled across the whole match. The number that decides
## whether a stall count means anything: six stalls of one tick is invisible, six
## of a second each is a broken match, and a count alone cannot tell them apart.
var _stalled_total: int = 0
## Physics frames this machine has spent in the match, and the turn clock built
## on it.
##
## **Counted here rather than read from `MatchSession.tick()`, and that is not a
## duplication - it is the fix for a deadlock.** The match clock FREEZES
## whenever the world is held still, and the world is held still for things that
## are part of the game: the technology draft holds it at match start.
##
## Under lockstep a draft pick is a COMMAND, and a command needs a turn to
## travel on. Deriving the turn clock from the match clock means the draft
## freezes the turns, the turns cannot deliver the pick, and the pick is what
## would end the draft. Nothing errors; the match simply stops with the tree
## paused, which reads as "the game started and no input does anything".
##
## So the network clock keeps its own time. It stops for exactly one thing - a
## STALL, where by definition no peer may move - and for nothing else.
var _frames: int = 0

# --- server state ---------------------------------------------------------
## Checksums reported per turn, keyed by turn then by peer id.
var _turn_checksums: Dictionary = {}
## Peers already told their world diverged, so each is told once per match.
var _told: Dictionary = {}

## Relay only: the highest turn whose checksums have been forgotten.
##
## Kept so that a report arriving for a turn that is already gone can be REFUSED
## rather than quietly re-creating the entry. Without it a late report lands
## alone in a fresh dictionary, is compared against nothing, and reads exactly
## like agreement. See _compare_turn.
var _pruned_through: int = NO_TURN

## Relay only: how many late reports have been refused, so the log says it once
## rather than once per checksum turn for the rest of the match.
var _late_reports: int = 0

## The match all of the state above belongs to. See _reset_if_new_match.
var _match_id: String = ""

## The last few turns this machine closed, oldest first, as [turn, payload]
## pairs. Sent again in every echo. See _echo.

## Ticks since this machine last said it is alive.
##
## **Counted separately from `_frames`, and that separation is the whole fix.**
## `_frames` STOPS during a stall - which is exactly the moment a peer most needs
## to be able to say it is still here.
var _since_heartbeat: int = 0

## The rolling window of how much longer than a tick each tick actually took, in
## milliseconds. Written round-robin, so nothing is allocated per tick.
var _overruns: PackedFloat32Array = PackedFloat32Array()
var _overruns_filled: int = 0
var _last_tick_usec: int = 0
var _jitter_cache: int = -1
var _jitter_measured_at: int = -1000

## Relay only: the turn each peer last reported being on, for the log when one is
## given up on. Says who was actually behind rather than only who was dropped.
var _reported_turn: Dictionary = {}

## Relay only: the frame each peer was last heard from, so one that goes quiet
## while still connected can be given up on. See _drop_silent_peers.
var _last_heard: Dictionary = {}

## Relay only: peer id -> the last turn the relay has spoken for on its behalf.
## See _speak_for_the_departed.

## Relay only: what is waiting to go out to each peer this frame, reliable and
## unreliable kept apart. See _flush_batches.

## Relay only: peers the relay has given up on and now speaks for, even though
## the socket is still open. See _drop_silent_peers.
var _departed: Dictionary = {}

## The highest turn any peer has been heard closing. The relay's only sense of
## where the match has got to, since it keeps no clock of its own. See inject().
var _highest_seen: int = NO_TURN

## The furthest any player is from the server, one way, in milliseconds.
##
## Measured by the SERVER, which is the only machine with a connection to every
## peer, and announced to the rest. A client cannot work this out: its ENet host
## holds one link, to the server, so the other player's distance is a fact only
## the middle of the star can see. UNKNOWN_RTT until the first announcement.

## When THIS machine's player pressed, in wall-clock milliseconds, keyed by a
## CLIENT-LOCAL ORDER SEQUENCE rather than by a turn. Diagnostic only - see
## _report_latency.
##
## **Keyed by seq because the turn key is about to stop existing.** Once the
## relay seals the stream a client no longer names the turn its order lands in,
## so a stopwatch keyed by turn would have no key and `order.ran waited_ms` -
## the one number that says whether any of this worked - would be lost exactly
## when it is needed to judge the change. The seq is local and never goes on the
## wire yet; the cutover puts it there and resolves the turn from the seal
## instead of from `scheduled_turn()`.
## Monotonic, per match, per machine. Never leaves this process in phase 0.
var _order_seq: int = 0
## turn -> the order seqs booked into it, so a run turn can find its presses.

## Phase 0 instrumentation. Wall-clock milliseconds: when each turn became DUE
## on this machine's clock, and when each peer's word for it FIRST arrived.
##
## **Nothing in the simulation may read any of this.** Two machines do not share
## a clock, so a value derived from these would differ per peer and desync them -
## the same rule `_report_latency` already states.
var _due_at: Dictionary = {}
var _arrived_at: Dictionary = {}
## peer id -> a ring of how late that peer's words have been, in milliseconds,
## and how many samples have gone into it. Written round-robin, so nothing is
## allocated per turn once a peer has been seen.
var _leads: Dictionary = {}
var _leads_n: Dictionary = {}

## Phase 3 shadow. **None of this is played from; it exists to be compared.**
##
## Relay: orders that have arrived bare since the last seal, each as
## [slot, seq, stamped dict], plus the highest seq accepted per peer so a
## re-send cannot be counted twice.
var _pending_orders: Array = []
var _seq_seen: Dictionary = {}
## How many of those each slot has waiting, so the flood cap is a lookup rather
## than a scan of the pile on every order.
var _pending_count: Dictionary = {}

## Peer: the same orders reached this machine twice, by two different roads -
## once inside a turn word it waited for, once inside a seal the relay composed
## on arrival. Kept per SLOT rather than per peer id, because a slot is the same
## number on every machine and a peer id is not.
##
## They are compared as SUBSEQUENCES, never per turn: a peer books into
## `current_turn + delay_turns + 1` while the relay seals on arrival, so the two
## disagree about which turn holds an order by construction and no constant shift
## repairs it. What must hold is that each author's orders appear in the sealed
## stream exactly once, in the order they were pressed, none lost and none
## duplicated. A matched prefix is dropped from both, so neither grows.
## How many orders the shadow check has actually MATCHED.
##
## **The positive control, and without it this phase cannot be tested at all.**
## A clean run and a comparison that never executed look identical from the
## outside - no error either way - which is `CLAUDE.md`'s most repeated trap. A
## test passes only if this is greater than zero.

## --- the sealed stream ------------------------------------------------------

## Peer: turns the relay has sealed and this machine has not played yet, keyed
## by turn. **This replaces `_incoming` entirely when the flag is on**, and the
## difference is the whole point of the phase: `_incoming` is indexed by PEER
## and a turn is complete when every peer has filled its slot, so any one of
## them can hold the match. This is indexed by nothing - a turn is here or it is
## not, and only the relay can put it here.
var _sealed: Dictionary = {}

## Peer: when this machine's own presses happened, oldest first, in wall-clock
## milliseconds.
##
## **A queue rather than a turn key, because under the sealed stream this
## machine no longer knows which turn its order will land in** - that is the
## relay's decision and it is taken after the press. What survives is the ORDER:
## the reliable channel preserves it on the way up and the relay's (slot, seq)
## sort preserves it on the way down, so this peer's own orders come back in
## exactly the sequence they were pressed and can be paired off one for one.
## Diagnostic only, exactly as `_ordered_at` is - see `_report_latency`.
var _my_presses: Array[int] = []

## Peer: this machine has given up, so the buffer check says so once rather than
## once per seal for the rest of the match.
var _gave_up: bool = false

## Peer: told the relay its world is built. Once per match. See `submit_ready`.
var _announced_ready: bool = false

## Relay: peers whose world is built and which can therefore receive a seal.
## See `_seal_clock_may_start` - this is blocker B2.
var _ready_peers: Dictionary = {}

## Relay: the next turn to seal, whether the seal clock has started, and how
## long it has been waiting to.
var _seal_next: int = 0
var _sealing: bool = false
var _seal_wait_frames: int = 0

## Relay: its own monotonic press counter, for the orders it injects itself.
## Kept apart from `_seq_seen`, which is per PEER and dedupes what arrives; this
## one only has to make the sort key total.
var _server_seq: int = 0

## Peer: the engine rate this machine last asked for, so the pacing is logged
## when it changes rather than on every tick that wants the same number.
var _paced_at: int = 0


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

	_reset_if_new_match()
	_sample_tick_interval()

	# **A relay keeps no turn clock.** It has no world to advance, nothing to
	# say about a turn, and no checksum to take - all it does on a tick is
	# re-read the connections so it can tell everyone how far apart they are.
	# Relaying itself is event-driven and happens in submit_turn.
	#
	# This is also what makes `_measure_and_announce`'s gate on `_frames` safe:
	# the counter stops during a stall, and the relay is the one machine that
	# never stalls, so the measurement never stops on the machine that takes it.
	if MatchSession.is_relay():
		_frames += 1
		_drop_silent_peers()
		_seal_stream()
		_report_drift()
		return

	# **`_frames` counts ticks that have FINISHED, so the tick now beginning is
	# `_frames` itself and the turn it belongs to is `current_turn()`.**
	#
	# Counting it up first instead cost a whole tick of input lag for nothing:
	# turn X would only pass the `turn > clock_turn` gate on the tick AFTER the
	# one it belongs to, so every order in the game ran 50 ms later than the
	# schedule said it should. Measured at 126-134 ms on loopback where the
	# arithmetic says 50-100.
	_beat()
	_announce_ready()

	var turn: int = current_turn()

	# **Nothing is closed and nothing is emitted.** A peer under the sealed
	# stream has no word to say about a turn: it sent its orders bare when
	# they were pressed and the relay decided which turn they land in. All
	# that is left here is playing back what arrives.
	#
	# The clock is held back by the lead, which is this machine's jitter
	# buffer. `_advance_turn` runs one turn per tick at most and only ever
	# the next one, so a lead of L means a seal has L turns of slack to
	# arrive in before it is missed.
	_advance_turn(turn - _sealed_lead_turns())
	_pace_engine()

	# Held only by a stall. Everything else the world stops for - the draft
	# above all - must NOT stop the turns, or the very orders that would end it
	# can never arrive. A tick that stalled did not happen, so it is not counted.
	if !_stalling:
		_frames += 1


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
## `MatchSession.hold` is what does the holding, and it is exactly the
## right tool: it pauses the TREE, so every gameplay loop stops at once without
## any of them being asked, and it gives the match clock back what the hold took
## so no creep unlock silently serves its time during a stall.
## Turns are run IN ORDER and one at a time - the next one due, never the one
## the clock happens to be pointing at.
##
## The first version tested `_session_tick() == first_tick_of(turn)`, an exact
## match on a boundary. Anything that moved the clock off that boundary - a
## pause correcting it, a frame where more than one turn elapsed - meant the
## test was never true again and the match hung with no error. Asking "which
## turn have I not run yet" cannot miss.
func _advance_turn(clock_turn: int) -> void:
	var turn: int = _last_run_turn + 1
	if turn > clock_turn:
		return

	# **The first tick that gets past the guard above IS the instant this turn
	# became due on this machine's clock**, which is the reference every arrival
	# is measured against. Write-once, so the repeated stall passes below cost a
	# lookup rather than a write - and NO log call of any level here, this is the
	# per-tick path.
	if !_due_at.has(turn):
		_due_at[turn] = Time.get_ticks_msec()

	if !_is_complete(turn):
		if !_stalling:
			_stalling = true
			_stalled_on = turn
			_stall_frames = 0
			turn_stalled.emit(turn, _missing_for(turn))
			_set_held(true)

		# Repeated, with what IS present as well as what is missing. A stall
		# that never clears is the worst failure this system has - the world
		# stops and nothing says why - so it has to keep saying what it wants
		# rather than reporting once and going quiet.
		_stall_frames += 1
		_stalled_total += 1
		if _stall_frames % STALL_REPORT_FRAMES == 1:
			Log.warn("Waiting on a turn", {
				"turn": turn,
				"missing": _missing_for(turn),
				"have": [],
				"expected": PackedInt32Array([NetworkService.SERVER_PEER_ID]),
				"held": _sealed.size(),
				"seconds": snappedf(float(_stall_frames) * _engine_tick_seconds(), 0.1),
			})
		return

	if _stalling:
		# **Deliberately `debug` rather than `info`.** This fires on the tick that
		# CLEARS a stall, so under the failure this whole rework exists to remove
		# it is a per-tick path, not a per-player-action one - and `Log.info`
		# calls `get_stack()` and `print_rich()` before anything else. It and the
		# warning above it also sit INSIDE the interval `_sample_arrivals` is
		# measuring, so leaving them at `info` would have biased phase 0's own
		# numbers. See `CLAUDE.md` on Log.info in a per-tick path.
		Log.debug("Turn arrived, resuming", {
			"turn": turn, "waited_on": _stalled_on,
		})
		_stalling = false
		_stalled_on = NO_TURN
		_set_held(false)

	_last_run_turn = turn
	_sample_arrivals(turn)

	# **Checksummed BEFORE the orders are applied**, so the number describes a
	# point every machine can name without ambiguity: the boundary of this turn,
	# with everything up to it done and nothing of it started. Taking it after
	# would be equally valid and equally consistent; what would NOT be valid is
	# taking it at a moment the machines could reach differently.
	_maybe_report_checksum(turn)

	var orders: Array = commands_for(turn)
	# **No shadow comparison here, because there is nothing left to compare
	# to.** Phase 3 fed this from `commands_for` and the seal from
	# `receive_seal`, which under the flag are the SAME array arriving by the
	# same road - checking it against itself would pass unconditionally and
	# report a positive control that means nothing.
	_sealed.erase(turn)
	turn_ready.emit(turn, orders)
	if !orders.is_empty():
		Commands.apply_turn(orders)

	# **AFTER the orders, never before them.** The match clock is the turn stream
	# under lockstep rather than this machine's physics frames, and whether this
	# turn counts depends on whether anything but lockstep is holding the world -
	# which an order in this very turn is entitled to change. A technology pick
	# ends the draft from inside `apply_turn`, and the tick that ends it does
	# simulate. See MatchSession.advance_clock.
	var session: MatchSession = References.match_session
	if session != null:
		session.advance_clock(_ticks_per_turn())

	_report_latency(turn, orders)


## How long the player waited between giving an order and the world acting on
## it - the ONE number that says whether this game feels responsive.
##
## **Wall clock, and read by nothing but this line.** The simulation may never
## touch it: two machines do not share a clock, so a value derived from it would
## differ per peer and desync them. What a player feels is a wall-clock number
## though, and no count of ticks can stand in for it - the whole point is to
## catch the case where the tick arithmetic looks right and the game still feels
## slow.
##
## Fires once per turn that carried an order from this machine, which is once
## per player action, so `Log.info` is affordable here by the rule in
## `CLAUDE.md`. A turn nobody ordered on costs one Dictionary lookup.
func _report_latency(turn: int, orders: Array) -> void:
	_report_sealed_latency(turn, orders)


## The same number under the sealed stream, paired off BY ORDER rather than by
## turn.
##
## **This machine no longer knows which turn its own order will land in** - that
## is the relay's decision, taken after the press - so the turn-keyed stopwatch
## has no key. What survives is the sequence: the reliable channel preserves it
## on the way up, the relay's `(slot, seq)` sort preserves it on the way down,
## so this peer's orders come back in exactly the sequence they were pressed and
## pair off one for one against `_my_presses`.
##
## It reports `delay_turns` into the session log under the same key the old path
## uses, carrying the lead instead, so the two builds' logs still join on that
## field when the flag is flipped between paired runs.
##
## Wall clock, read by nothing but this line, and the simulation may never touch
## it - the same rule `_report_latency` states at length.
func _report_sealed_latency(turn: int, orders: Array) -> void:
	if _my_presses.is_empty() || orders.is_empty():
		return
	var session: MatchSession = References.match_session
	var setup: MatchSetup = null if session == null else session.setup()
	if setup == null || setup.local_slot == 0:
		return

	var mine: int = setup.local_slot
	var earliest: int = 0
	for entry: Variant in orders:
		var order: Dictionary = entry as Dictionary
		if order == null || int(order.get("slot", 0)) != mine:
			continue
		if _my_presses.is_empty():
			break
		var at: int = _my_presses.pop_front()
		if earliest == 0 || at < earliest:
			earliest = at
	if earliest == 0:
		return

	var waited: int = Time.get_ticks_msec() - earliest
	Log.info("Order ran", {
		"turn": turn,
		"waited_ms": waited,
		"ticks_per_turn": _ticks_per_turn(),
		"delay_turns": _sealed_lead_turns(),
	})
	SessionLog.note("order.ran", {"turn": turn, "waited_ms": waited,
		"delay_turns": _sealed_lead_turns()})








## Gives up on a player who is connected and has stopped talking.
##
## **The relay is the only machine that can do this**, because it is the only one
## that hears from everybody, and it is the only one not frozen while it happens -
## every player is stalled for exactly as long as this takes to decide.
##
## A peer sends a word every tick, so the first word sets its clock and silence
## past the timeout means it has stopped rather than slowed.
func _drop_silent_peers() -> void:
	var limit: float = _silent_timeout_seconds()
	if limit <= 0.0:
		return
	var frames: int = int(limit / maxf(0.001, _engine_tick_seconds()))

	# **The WORST offender only, one per pass**, and this is a backstop rather
	# than the fix - the heartbeat above is what makes silence mean something.
	# It is here because the failure this guards against loses a player their
	# match with no error and no desync to catch it, so it is worth making two
	# peers impossible to lose in the same instant whatever else goes wrong. A
	# genuine double failure simply resolves a tick later.
	var worst: int = 0
	var worst_silence: int = 0
	for peer: int in _match_peers():
		if !_last_heard.has(peer):
			# Never heard from at all yet. Its clock starts when the match does,
			# not at connection, or a slow loader would be dropped for loading.
			_last_heard[peer] = _frames
			continue
		var silence: int = _frames - int(_last_heard[peer])
		if silence >= frames && silence > worst_silence:
			worst = peer
			worst_silence = silence

	if worst == 0:
		return

	Log.warn("Player has gone silent, giving up on them", {
		"peer": worst,
		"seconds": snappedf(float(worst_silence) * _engine_tick_seconds(), 0.1),
		"their_turn": _reported_turn.get(worst, -1),
		"relay_turn": _highest_seen,
	})
	_last_heard[worst] = _frames
	# **Marked explicitly, because this peer's SOCKET IS STILL OPEN.** It is a
	# wedged game loop rather than a lost connection, so it stays in
	# `multiplayer.get_peers()` for ever - and without this the relay would never
	# start speaking for it and every other player would wait on it for the rest
	# of the match. Exactly the freeze this check exists to end.
	_departed[worst] = true
	MatchStart.drop_silent_peer(worst)






## How much this machine's own frame times are currently costing, in
## milliseconds, as an allowance added to the input delay.
##
## **This is the term a headless measurement cannot see**, and the one that
## actually bit in playtest 1: a peer whose ticks run late sends its word late,
## which is indistinguishable at the far end from a slow network and is not
## fixable by anything the network does.
##
## A high percentile rather than a mean, because a mean cannot see the spike that
## is the whole problem, and a maximum would let one unrelated hitch hold the
## delay up for the length of the window. Zero on a machine that is keeping up,
## which is the normal case and costs nothing.
func local_jitter_ms() -> int:
	if !_adaptive_local_jitter():
		return 0
	if _frames - _jitter_measured_at < JITTER_REFRESH_FRAMES && _jitter_cache >= 0:
		return _jitter_cache
	_jitter_measured_at = _frames
	_jitter_cache = _measure_local_jitter()
	return _jitter_cache


## The 90th percentile overrun across the sample window, capped.
func _measure_local_jitter() -> int:
	if mini(_overruns_filled, _overruns.size()) < JITTER_MIN_SAMPLES:
		return 0
	return clampi(int(_overrun_ms(0.9)), 0, _max_local_jitter_ms())


## One percentile of the tick-overrun window, RAW - not capped, and not gated on
## `adaptive_local_jitter`.
##
## The capped reading above is an input to the input delay and is deliberately
## bounded so one unrelated hitch cannot book delay for the length of the window.
## This one is a MEASUREMENT, and on the relay it is the achieved seal interval -
## the number that says whether a peer's complaint is the relay running late
## rather than its own buffer being short. Capping that would hide exactly the
## case worth finding.
func _overrun_ms(fraction: float) -> float:
	var filled: int = mini(_overruns_filled, _overruns.size())
	if filled <= 0:
		return 0.0
	var window: Array[float] = []
	for index: int in range(filled):
		window.append(_overruns[index])
	window.sort()
	return window[clampi(int(float(filled) * fraction), 0, filled - 1)]


## One tick interval, folded into the window.
##
## The interval is WALL CLOCK between two ticks, not the engine's fixed delta,
## which is a constant and would measure nothing. Godot may also run several
## physics ticks back to back to catch up after a long frame, which shows here as
## one large interval followed by tiny ones - the percentile is chosen so that
## shape reads as the one overrun it is rather than as a run of fast ticks.
func _sample_tick_interval() -> void:
	# Sized here rather than only in the reset, because the first match of a
	# process reaches this before anything has been reset and a zero-length
	# window would divide by zero.
	if _overruns.size() != JITTER_SAMPLES:
		_overruns.resize(JITTER_SAMPLES)
		_overruns.fill(0.0)
	var now: int = Time.get_ticks_usec()
	if _last_tick_usec > 0:
		var interval_ms: float = float(now - _last_tick_usec) * 0.001
		var ideal_ms: float = _engine_tick_seconds() * 1000.0
		var slot: int = _overruns_filled % _overruns.size()
		_overruns[slot] = maxf(0.0, interval_ms - ideal_ms)
		_overruns_filled += 1
	_last_tick_usec = now






## How many sealed turns are waiting to be played - this machine's lead over the
## relay, in turns, as it actually stands rather than as it was configured.
##
## Zero while the flag is off. It only ever GROWS while the flag is on, because
## without catch-up a peer runs exactly one turn per tick, so every gap it
## recovers from is added to its input delay permanently. That is amendment 10
## and this is the number that shows it happening.
func sealed_held() -> int:
	return _sealed.size()


## How far behind the relay this machine is playing, in seconds of real time.
##
## **The peer works this out entirely by itself, which is why phase 4c needs no
## message from the relay at all.** The plan assumed a `notify_lagging` rpc, and
## it is not needed: the backlog waiting to be played IS the lag, exactly, and
## it is sitting in this machine's own dictionary. A round trip could only tell
## it something it already knows, later and less accurately.
##
## Wall clock, for a human. Nothing in the simulation may read it.
func sealed_lag_seconds() -> float:
	return float(_sealed.size()) * _engine_tick_seconds() * float(_ticks_per_turn())


## Whether this machine has fallen so far behind that it has stopped playing.
##
## **A terminal state, and the panel says so rather than this leaving quietly.**
## Being yanked back to the main menu with no explanation is what a dropped
## player gets today, and it is the thing phase 4c exists to end.
func has_given_up() -> bool:
	return _gave_up


## How long this match has spent held, in seconds, across every stall.
##
## **Engine rate, not simulation rate.** A stalled tick is a tick of real time
## that elapsed, so this has to follow the clock the machine actually ran at. See
## `_engine_tick_seconds`.
func stalled_seconds() -> float:
	return float(_stalled_total) * _engine_tick_seconds()


## How late each peer's words have been arriving, per peer, in milliseconds.
##
## `{peer: {n, p50, p90, p99, max}}`, where the number is `arrived - due` and
## POSITIVE MEANS LATE - so it reads in the same direction as every other latency
## figure in this file, and p99 is the bad tail rather than the good one.
##
## **This is the measurement nothing in this codebase had**, and its absence is
## why the same problem was diagnosed wrongly twice: the system logged the
## ESTIMATED wire budget every hundred turns and never once recorded what a word
## actually cost. A negative or near-zero p99 here with stalls still happening
## falsifies the network story outright.
func arrival_leads() -> Dictionary:
	var out: Dictionary = {}
	for peer: Variant in _leads:
		var count: int = mini(int(_leads_n[peer]), LEAD_SAMPLES)
		if count <= 0:
			continue
		var ring: PackedFloat32Array = _leads[peer]
		var window: Array[float] = []
		for index: int in range(count):
			window.append(ring[index])
		window.sort()
		out[int(peer)] = {
			"n": count,
			"p50": int(window[clampi(int(float(count) * 0.5), 0, count - 1)]),
			"p90": int(window[clampi(int(float(count) * 0.9), 0, count - 1)]),
			"p99": int(window[clampi(int(float(count) * 0.99), 0, count - 1)]),
			"max": int(window[count - 1]),
		}
	return out


## Folds one finished turn's arrivals into the per-peer windows and frees them.
##
## Called from `_advance_turn` the moment a turn is accepted, which must be
## BEFORE `turn_ready.emit` - that signal is what drives the health line, so
## folding afterwards would make every line report a window one turn stale.
##
## The two dictionaries are erased here on the same turn `_incoming` is, because
## a match is thousands of turns long and they would otherwise grow for all of it.
func _sample_arrivals(turn: int) -> void:
	# Both erased before anything can return, or a turn that arrived without a
	# due stamp leaks its entry for the rest of the match.
	#
	# **Asked with `has` rather than against a zero**, because `Time.get_ticks_msec()`
	# CAN legitimately be zero and a sentinel that collides with a real value is
	# the same mistake `UNKNOWN_RTT` is negative to avoid. It cost nothing to get
	# right and the check that found it took one line.
	var known: bool = _due_at.has(turn)
	var due: int = int(_due_at.get(turn, 0))
	_due_at.erase(turn)
	var arrived: Dictionary = _arrived_at.get(turn, {})
	_arrived_at.erase(turn)
	if !known:
		return

	for peer: Variant in arrived:
		var id: int = int(peer)
		if !_leads.has(id):
			var fresh: PackedFloat32Array = PackedFloat32Array()
			fresh.resize(LEAD_SAMPLES)
			fresh.fill(0.0)
			_leads[id] = fresh
			_leads_n[id] = 0
		# Read out, write, put back: a packed array is copy-on-write, so writing
		# through the Dictionary lookup would edit a temporary.
		var ring: PackedFloat32Array = _leads[id]
		var count: int = int(_leads_n[id])
		ring[count % LEAD_SAMPLES] = float(int(arrived[peer]) - due)
		_leads[id] = ring
		_leads_n[id] = count + 1


## Relay only: how far behind each peer is, and how well the relay is keeping its
## own tick. Into the journal rather than a session log, because the relay writes
## no session log.
##
## **`Log.debug`, checked before `get_stack()` runs**, and gated to a few times a
## minute besides. It reports `current_turn()` rather than `_frames` because the
## two stop meaning the same thing the moment `ticks_per_turn` moves off one.
##
## What this CANNOT answer on its own is whether a peer is behind because its own
## clock runs slow or because it spent the time stalled - the peer knows both and
## the relay knows neither, so the peer's `lockstep.health` line carries
## `stalled_s` and the two are joined by turn afterwards.
func _report_drift() -> void:
	if _frames % DRIFT_EVERY_FRAMES != 0:
		return
	# **The relay's turn is the one it SEALED, not the one its frame counter is
	# on.** Under the sealed stream the seal clock starts later than `_frames`
	# does - it waits for every peer's world to be built (B2) - so reading the
	# frame counter here would report every peer as permanently behind by
	# however long the slowest one took to load.
	var mine: int = _highest_seen
	var behind: Dictionary = {}
	for peer: int in _match_peers():
		behind[peer] = mine - int(_reported_turn.get(peer, NO_TURN))
	Log.debug("Relay drift", {
		"relay_turn": mine,
		"behind_turns": behind,
		"seal_p90_ms": int(_overrun_ms(0.9)),
		"seal_max_ms": int(_overrun_ms(1.0)),
	})


## Seconds per ENGINE physics tick, for wall-clock arithmetic only.
##
## **Deliberately not `MatchSession.tick_seconds()`, and the split is the point.**
## That one is the SIMULATION rate: it converts authored seconds into ticks and
## ticks back into match time, and every peer must agree about it to the bit.
## This one is what the machine's clock is actually doing. They are the same
## number today and phase 6 makes them differ - a servo paces the engine while
## the simulation's second stays fixed - at which point every metric built on the
## wrong one silently stops meaning seconds. Since those metrics are exactly what
## phases 0 and 4 are judged by, the split is made here rather than there.
func _engine_tick_seconds() -> float:
	return 1.0 / maxf(1.0, float(Engine.physics_ticks_per_second))


## Whether the world is being held right now waiting for somebody's turn.
##
## Public because a STALL IS THE ONLY THING IN THIS GAME THAT STOPS THE WORLD
## WITHOUT TELLING THE PLAYER, and the panel that fixes that has to be able to
## ask. `turn_stalled` fires once at the start and nothing marks the end, so a
## screen driven by the signal alone could never work out when to hide itself.
func is_stalled() -> bool:
	return _stalling


## Whose word the match is waiting for, by peer id, or empty when it is not
## waiting. For the panel to turn into names.
func waiting_on() -> PackedInt32Array:
	if !_stalling || _stalled_on == NO_TURN:
		return PackedInt32Array()
	return _missing_for(_stalled_on)


## Whether every peer has said what it is doing on this turn.
func _is_complete(turn: int) -> bool:
	# **This one line is the whole cutover.** The question stops being "do I
	# hold a word from every peer" and becomes "do I hold the relay's word", so
	# NO OTHER PLAYER EVER APPEARS IN THIS MACHINE'S WAIT CONDITION AGAIN. A
	# machine that hitches now costs its own player input delay and costs
	# everybody else nothing at all.
	return _sealed.has(turn)


func _missing_for(turn: int) -> PackedInt32Array:
	# **Amendment 11: a local hold must never name an opponent.** Under the
	# sealed stream the only party that can be late IS the relay, and
	# `_expected_peers` deliberately excludes it - so left alone this would
	# report whichever innocent player happened to be missing from an
	# `_incoming` nothing writes to any more. The session log is the artefact a
	# tester sends back and section 11 of `netcode-rework.md` tells the next
	# investigator to trust this field, so it has to be true.
	#
	# `StallPanel` already renders this id as "the server", so the panel needs
	# no change to say the honest thing.
	return PackedInt32Array([NetworkService.SERVER_PEER_ID])


## Holds or releases the world. Routed through the session so the match clock is
## corrected, and so a stall and the technology draft cannot fight over the tree
## - whoever wants it held has it held.
##
## That last claim was a LIE until 2026-09-05: `set_paused` was a plain boolean,
## so a stall clearing released a draft's hold along with its own. It is true now
## because holds are named and counted. See MatchSession.hold.
func _set_held(held: bool) -> void:
	var session: MatchSession = References.match_session
	if session != null:
		session.hold(&"lockstep", held)


## Throws away everything belonging to the PREVIOUS match.
##
## **This is an autoload, so it outlives the match it was built for**, and a
## dedicated server hosts one match after another in the same process (D19).
## Without this, the second match on a given server inherits the first one's
## turn clock: `_frames` is thousands of ticks ahead, so it closes turns from
## the middle of a match nobody is playing, and every client sits on turn 0
## waiting for orders from a peer that has mentally moved on.
##
## The symptom is a permanent stall with `missing: [1]` and the world paused,
## which reads as "the game froze on start" and says nothing about why. It only
## ever bites the SECOND match on a server, which is why a fresh process always
## looked fine and testing never caught it.
##
## Keyed on the match id rather than on a signal, because every peer already
## holds it and it changes exactly when this needs to fire - no wiring to
## forget, and correct on the server and on a client alike.
func _reset_if_new_match() -> void:
	var session: MatchSession = References.match_session
	var id: String = "" if session == null || session.setup() == null \
		else session.setup().match_id
	if id == _match_id:
		return

	_match_id = id
	_order_seq = 0
	_pending_orders.clear()
	_pending_count.clear()
	_seq_seen.clear()
	# **Amendment 8, and its own docstring above says why this list matters.**
	# A relay hosts one match after another in the same process, so a `_seq_seen`
	# high-water mark left over from the last one would silently dedupe away
	# every order from a client that restarted its own counter - no error, no
	# stall, the player clicks and nothing happens.
	_sealed.clear()
	_my_presses.clear()
	_gave_up = false
	_announced_ready = false
	_ready_peers.clear()
	_seal_next = 0
	_sealing = false
	_seal_wait_frames = 0
	_server_seq = 0
	_restore_rate()
	_due_at.clear()
	_arrived_at.clear()
	_leads.clear()
	_leads_n.clear()
	_departed.clear()
	# A new match on a machine that struggled through the last one starts from
	# no opinion about it, rather than inheriting the delay it earned.
	_overruns.resize(JITTER_SAMPLES)
	_overruns.fill(0.0)
	_overruns_filled = 0
	_last_tick_usec = 0
	_jitter_cache = -1
	_jitter_measured_at = -1000
	_reported_turn.clear()
	_since_heartbeat = 0
	_last_heard.clear()
	_highest_seen = NO_TURN
	_turn_checksums.clear()
	_told.clear()
	_pruned_through = NO_TURN
	_late_reports = 0
	_last_checksum_turn = NO_TURN
	_last_run_turn = NO_TURN
	_stalled_on = NO_TURN
	_stall_frames = 0
	_stalled_total = 0
	_frames = 0

	# Never left holding the tree for a match that no longer exists.
	if _stalling:
		_stalling = false
		_set_held(false)

	Log.info("Lockstep reset for a new match", {"match": id})


# --- the turn clock -------------------------------------------------------

## The turn the match is in right now, on the network's own clock.
func current_turn() -> int:
	return turn_for_tick(_frames)


func turn_for_tick(tick: int) -> int:
	return tick / _ticks_per_turn()


## The first tick of a turn, which is when its orders would be applied.
func first_tick_of(turn: int) -> int:
	return turn * _ticks_per_turn()






# --- collecting orders ----------------------------------------------------

## Books a command for the turn it should run on, and answers which that is.
##
## Called ALONGSIDE the existing submit path rather than instead of it, so a
## command still travels and still applies exactly as it does today. What this
## adds is a record of which turn it would have belonged to.
func schedule(command: Command) -> int:
	if command == null || !_is_live():
		return NO_TURN

	# **The order goes bare, with no turn number on it, at press time.** The
	# relay decides which turn it lands in from when it arrives. Under the
	# sealed stream this is the only thing that happens here; under the old gate
	# it is phase 3's second road, checked against the first by _compare_shadow.
	_order_seq += 1
	submit_order.rpc_id(NetworkService.SERVER_PEER_ID, command.to_dict(), _order_seq)

	# **Nothing is booked locally, and booking it anyway would lose it.**
	# This machine closes no turns any more, so an entry in `_outgoing`
	# would sit there for the whole match and simply never happen - the same
	# silent failure the scheduling rewrite already cost a run to find.
	#
	# The stopwatch still starts where the player pressed. It is paired off
	# by order rather than by turn: see _report_sealed_latency.
	_my_presses.append(Time.get_ticks_msec())
	while _my_presses.size() > MAX_PRESSES_HELD:
		_my_presses.pop_front()
	return NO_TURN


## Every command known for a turn, in a deterministic order.
##
## **Sorted by the peer that sent it**, because a Dictionary's own order is not
## something two machines may be trusted to agree on - and if two peers applied
## the same turn's orders in different orders they would diverge, which is the
## exact failure this whole file exists to prevent.
func commands_for(turn: int) -> Array:
	# **Already ordered, and by the only machine entitled to order it.** The
	# relay sorted the seal by `(slot, seq)` before it sent it, which is a total
	# key and a pure function of the member set - so every peer receives the
	# identical array and the client-side merge sort below has nothing left to
	# decide.
	return _sealed.get(turn, [])


# --- exchanging them ------------------------------------------------------

## Tells the relay this machine is still running, whether or not it has anything
## to say about turns.
##
## **A STALLED PEER IS SILENT BY DESIGN, and treating that silence as failure cost
## an innocent player their match.** While `_stalling`, `_frames` does not advance,
## so `current_turn()` does not move, so `_close_through` has nothing new to close
## and this machine emits NOTHING. That is correct - it has genuinely nothing to
## say - but the relay used a turn word as its only evidence of life, so a healthy
## peer waiting for a departed one looked exactly like a peer that had itself
## stopped. Both crossed the timeout in the same pass and both were dropped, with
## every machine agreeing perfectly about a roster that was wrong. No checksum can
## catch that: it is not a divergence, it is consistent agreement on a bad
## decision.
##
## So liveness is now its own signal, and it discriminates correctly because of
## what it depends on. This service is `PROCESS_MODE_ALWAYS` - it has to be, or a
## stall could never clear - so a peer that is merely WAITING keeps ticking and
## keeps sending this. A peer whose game loop has actually stopped does not, and
## is still given up on.
##
## Unreliable on purpose: it is a heartbeat, not a fact about the world. A dozen
## of them fit inside the timeout, so losing several changes nothing, and it must
## never queue behind the reliable turn stream it exists to be independent of.
func _beat() -> void:
	_since_heartbeat += 1
	if _since_heartbeat < HEARTBEAT_FRAMES:
		return
	_since_heartbeat = 0
	submit_alive.rpc_id(NetworkService.SERVER_PEER_ID, current_turn())










## Puts a SERVER order into the turn stream - today only a drop (D14).
##
## **A relay cannot use `schedule()`, and finding that out is what this method
## is.** `schedule()` books an order into the next turn this machine has not
## closed, and a relay closes no turns at all: the order would sit in `_outgoing`
## for the rest of the match and simply never happen. That is the same silent
## failure the scheduling rewrite already cost a run to find, arrived at from the
## other direction.
##
## So the relay books off what it has HEARD instead. Every peer keeps reporting
## its own turns whatever else is going on, so `_highest_seen` tracks the match
## even when the relay is not in it.
##
## **`SYSTEM_LEAD_TURNS` is a margin, not a guarantee, and that is worth being
## honest about.** Nobody waits for the relay's word - that is the whole point of
## it being a relay - so a peer that ran the turn before this arrived would drop
## it (`_record` refuses a turn already run) while the others applied it, and the
## two would diverge. A peer closes turns only one or two ahead, so a second of
## lead on an already-in-flight reliable packet is a margin of roughly twenty
## times over. If it is ever missed the checksum says so on the next comparison
## turn, and a ranked match is cancelled rather than resolved (2026-09-05).
##
## The hard version of this needs peers to wait on the relay again, which costs
## every turn a second way to be late in order to make one event a match safe.
func inject(command: Command) -> void:
	if command == null || !_is_live() || !MatchSession.is_relay():
		return

	# **The whole `SYSTEM_LEAD_TURNS` hazard goes away here.** The relay owns
	# the clock now, so it books its own order into the very next turn it
	# seals rather than guessing a turn far enough ahead that nobody has
	# reached it. There is no margin to be missed and no divergence to catch
	# on the following checksum.
	#
	# Slot 0 is the relay's own, and it sorts before every player slot -
	# which is what the old path bought by filing under peer id 1. So a drop
	# still applies before anything a player did on the same turn.
	# **The sort key and the payload's slot are deliberately DIFFERENT
	# numbers here, and conflating them silently disabled every player
	# drop.** The tuple's own leading 0 is what sorts the relay's order
	# before every player's; the dictionary's `slot` is what the order is
	# ABOUT. For `PLAYER_LEFT` - the relay's only injected order - that is
	# the slot of the player who LEFT, and `_apply_player_left` returns on
	# its first line if it reads 0. Stamping it cost nothing visible: the
	# leaver's maze simply stayed, on every peer, with nothing logged
	# anywhere. If it happened during the draft it hung the match for good.
	_server_seq += 1
	_pending_orders.append([0, _server_seq, command.to_dict()])
	Log.info("Relay injecting a server order", {
		"seq": _server_seq, "into": _seal_next, "action": command.player_action,
	})












## A peer saying it is still running, and which turn it is on.
##
## The turn is carried because it costs nothing and it is what makes the log
## useful: when somebody is given up on, it can say who was actually behind rather
## than only who was dropped.
@rpc("any_peer", "unreliable")
func submit_alive(turn: int) -> void:
	if !multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_last_heard[sender] = _frames
	# **Clamped, because this arrives UNRELIABLY and can therefore go
	# BACKWARDS.** Two heartbeats can be reordered by the network, and a lost
	# one ages the reading at the seal rate - so the raw value wanders, and
	# 4b would build "how far behind is this peer, and should the match end for
	# them" on top of it. A peer's own turn count never decreases, so anything
	# that says it did is the transport talking, not the peer.
	_reported_turn[sender] = maxi(int(_reported_turn.get(sender, NO_TURN)), turn)


## **Phase 3a. One order, arriving bare, with no turn number on it.**
##
## This is the ingress the cutover keeps and the turn word is the one it
## replaces. Nothing plays from it yet: the relay files it, seals it into a turn
## of its own choosing, and broadcasts that seal for peers to CHECK against the
## turn they actually ran. See _compare_shadow.
##
## `seq` is the sender's own monotonic press counter, and dedupe is a high-water
## mark rather than a set because this arrives on the reliable ordered channel -
## a re-send can never overtake the original, so anything at or below the highest
## seq already accepted is a duplicate.
##
## The slot is stamped here from the roster, exactly as `submit_turn` does it,
## and for the same reason: it is the only defence against a forged slot, and a
## forged slot does not desync - every peer would apply the same forged order and
## agree perfectly about a maze somebody else paid for.
@rpc("any_peer", "reliable")
func submit_order(payload: Dictionary, seq: int) -> void:
	if !multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if seq <= int(_seq_seen.get(sender, 0)):
		return
	_seq_seen[sender] = seq

	# **Refused unless the sender is a PLAYER IN THIS MATCH.** `_slot_of_peer`
	# answers 0 for anyone else, and anyone else can reach here: pressing
	# Multiplayer connects a peer to this process long before it is in a match,
	# which is the shape of the bug D33 records. Filing their orders under slot 0
	# would put them in the seal.
	var slot: int = _slot_of_peer(sender)
	if slot == 0:
		return

	# **The only RELIABLE thing a peer sends the relay once the turn word is
	# gone.** `submit_alive` is unreliable by design, and after the cutover a
	# player who is doing nothing sends nothing else at all - so a run of lost
	# heartbeats is the only evidence `_drop_silent_peers` would have. Refreshing
	# here does not close that hole, it just means an ACTIVE player cannot be
	# dropped for a quiet UDP patch. Amendment 2 closes it properly, in 4b.
	_last_heard[sender] = _frames

	# A flood guard, not a gameplay limit. Orders are sent on the render frame,
	# so an honest client contributes a handful per seal even holding a
	# repeat-on-hold ability down; anything near the cap is a modified client.
	var held: int = int(_pending_count.get(slot, 0))
	if held >= _max_pending_orders():
		if held == _max_pending_orders():
			_pending_count[slot] = held + 1
			Log.warn("Refusing orders, a peer is flooding the seal", {
				"peer": sender, "slot": slot, "cap": _max_pending_orders(),
			})
		return
	_pending_count[slot] = held + 1

	var order: Dictionary = payload.duplicate()
	order["slot"] = slot
	_pending_orders.append([slot, seq, order])




## **The cutover's clock: one authoritative turn per tick, sealed from whatever
## has arrived, and the relay never waits for anybody.**
##
## **Every turn is sealed and sent, EMPTY OR NOT, and the empty ones are the
## point.** A seal is the only thing that moves a peer's world forward, so a
## turn nobody ordered on still has to be announced or every peer stops dead.
## That is the one behaviour phase 3's shadow deliberately did not exercise - it
## suppressed empty seals to halve its own upload - so this path is new here and
## is what the phase has to be tested for.
##
## Sorted by `(slot, seq)`, which is a total key and a pure function of the
## member set, so what a turn contains cannot depend on the order two packets
## happened to arrive in even at the relay. The slot is the one the relay
## stamped, never one a client claimed.
func _seal_stream() -> void:
	if !_sealing:
		if !_seal_clock_may_start():
			return
		_sealing = true
		Log.info("Sealed stream opened", {
			"peers": _match_peers(),
			"waited_frames": _seal_wait_frames,
		})

	var pending: Array = _pending_orders
	_pending_orders = []
	_pending_count.clear()
	pending.sort_custom(func(first: Array, second: Array) -> bool:
		if int(first[0]) != int(second[0]):
			return int(first[0]) < int(second[0])
		return int(first[1]) < int(second[1]))

	var orders: Array = []
	for entry: Array in pending:
		orders.append(entry[2])

	var turn: int = _seal_next
	_seal_next += 1
	_highest_seen = turn

	# **To the match roster, never a bare `rpc()`.** A broadcast reaches every
	# CONNECTED peer, and somebody sitting in the lobby browser is a connected
	# peer. Same rule as `_queue`, same reason, and D33 is what it cost.
	#
	# **And a peer in the roster is not a peer on the end of a socket.** The
	# roster is never pruned - who has left is the turn stream's answer, not the
	# transport's - so somebody who leaves stays in it for the whole match, and
	# `rpc_id` to them fails with "Attempt to call RPC with unknown peer ID"
	# plus a full GDScript backtrace. This runs EVERY TICK, so that is twenty a
	# second for the rest of the match, which is the exact flood `_flush_batches`
	# was changed to stop in a real match's journal on 2026-09-06. Asking the
	# transport here is not the mistake `CLAUDE.md` warns about: it decides
	# nothing about the world, only whether there is an address to send to.
	var live: PackedInt32Array = multiplayer.get_peers()
	for peer: int in _match_peers():
		if peer in live:
			receive_seal.rpc_id(peer, turn, orders)


## Whether every player is ready to be sent a turn - **blocker B2.**
##
## `MatchStartService._start_match` rpcs the go signal and opens the relay's own
## match scene in the same call, so the relay is live within a frame while a
## client still needs a round trip, a scene change and a whole world build.
## Under the sealed stream there is exactly ONE copy of each turn - no
## author-side record and no echo to recover it from - so every seal broadcast
## in that window would be gone for ever, and the peer would then be waiting for
## a turn nothing can ever send again. At match start. Every match.
##
## Today this cannot happen because each peer authors its own stream from turn
## zero whenever its own clock starts, which is exactly what the cutover removes.
##
## The timeout is a backstop against a client that reports loaded and then never
## arrives. Without it one wedged machine holds the match closed for everybody,
## which is the failure this whole rework exists to remove - reached through the
## fix for it.
func _seal_clock_may_start() -> bool:
	var peers: PackedInt32Array = _match_peers()
	if peers.is_empty():
		return false

	_seal_wait_frames += 1
	var waiting: PackedInt32Array = PackedInt32Array()
	for peer: int in peers:
		if !_ready_peers.has(peer):
			waiting.append(peer)
	if waiting.is_empty():
		return true

	var limit: int = int(maxf(
		1.0, _silent_timeout_seconds() / maxf(0.001, _engine_tick_seconds())
	))
	if _seal_wait_frames < limit:
		return false

	Log.warn("Opening the sealed stream without everybody, they never reported ready", {
		"waiting_on": waiting,
		"seconds": snappedf(float(_seal_wait_frames) * _engine_tick_seconds(), 0.1),
	})
	return true


## A peer saying its world is built and it can receive a seal. Once per match,
## and reliable because the relay's clock will not start without it.
@rpc("any_peer", "reliable")
func submit_ready() -> void:
	if !multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	# **Refused unless the sender is a player in this match.** Pressing
	# Multiplayer connects a peer to this process long before it is in a match -
	# the shape of the bug D33 records - and a lobby browser must not be able to
	# open a match's clock.
	if _slot_of_peer(sender) == 0 || _ready_peers.has(sender):
		return
	_ready_peers[sender] = true
	_last_heard[sender] = _frames
	Log.info("Peer is ready for the sealed stream", {"peer": sender})


## The other half of it, on the peer. Sent from the first tick this machine is
## live, which is after `Main` has built the world - a scene's `_ready` finishes
## before the next physics frame, and this service is an autoload that runs at
## the top of it.
func _announce_ready() -> void:
	if _announced_ready || MatchSession.is_relay():
		return
	_announced_ready = true
	submit_ready.rpc_id(NetworkService.SERVER_PEER_ID)


## **Phase 3b. The relay's answer, for checking only.** A peer files it and plays
## nothing from it - unless the sealed stream is on, in which case this IS the
## match and `_absorb_seal` has it.
@rpc("authority", "call_remote", "reliable")
func receive_seal(turn: int, orders: Array) -> void:
	if !_is_live() || multiplayer.get_remote_sender_id() != NetworkService.SERVER_PEER_ID:
		return
	_absorb_seal(turn, orders)


## Files one sealed turn, and works out whether this machine can still catch up.
##
## **The turn number is NOT checked for plausibility, and that is amendment 1.**
## `_plausible_turn` exists to stop a CLIENT lying about when; under the sealed
## stream no client names a turn, so the only sender is the authority - and a
## peer that refused a turn for looking too far ahead would be refusing the very
## turn it is starving for, stall permanently, and go on telling the relay it is
## alive so it would never be given up on either. That is this project's own
## hard-won lesson arriving from a third direction: THE THING THAT UNBLOCKS A
## QUEUE CANNOT BE REFUSED AT THE DOOR.
##
## What bounds memory instead is the BUFFER SIZE, and reaching it is an explicit
## end state rather than a silent stall - this machine cannot catch up, so it
## stops. **Amendment 9 decides how**: through `MatchStart.leave_match()`, the
## same road the in-game menu takes, so the relay is told at once and the other
## players see a clean departure rather than sitting out the disconnect grace.
func _absorb_seal(turn: int, orders: Array) -> void:
	# Nothing more is played on a machine that has given up, and nothing more is
	# kept either - the relay goes on sealing until this peer actually leaves.
	if _gave_up:
		return
	# A turn already played is finished with. It cannot arrive twice on a
	# reliable ordered channel from a single sender, and it costs one comparison
	# to be certain rather than to assume.
	if turn <= _last_run_turn:
		return
	_sealed[turn] = orders

	# The relay's lateness, filed under its own peer id, so `arrival_leads()`
	# reports it exactly as it reported every other peer's before the cutover -
	# which is what makes the paired measurement comparable across the flag.
	# Write-once per turn, on the same reasoning as `_record`'s stamp.
	var when: Dictionary = _arrived_at.get(turn, {})
	if !when.has(NetworkService.SERVER_PEER_ID):
		when[NetworkService.SERVER_PEER_ID] = Time.get_ticks_msec()
		_arrived_at[turn] = when

	if _gave_up || _sealed.size() <= _max_sealed_turns():
		return
	_gave_up = true
	Log.err("Hopelessly behind the sealed stream, leaving the match", {
		"held": _sealed.size(),
		"ceiling": _max_sealed_turns(),
		"playing": _last_run_turn,
		"sealed": turn,
	})
	SessionLog.note("lockstep.gave_up", {
		"held": _sealed.size(), "playing": _last_run_turn, "sealed": turn,
	})
	# **Stopped and EXPLAINED rather than quietly yanked to the menu.**
	#
	# Amendment 9 asked that a local end go through `MatchStart.leave_match()`
	# so the existing departure path runs, and it still does - but the player
	# presses the button, exactly as they do on `DesyncNotice`. The concern
	# behind the amendment was that a local end must not say nothing on the
	# wire; a deliberate leave says it. What is added is that the player finds
	# out why their match stopped, which no dropped player has ever been told.
	#
	# The backlog is dropped here and refused above, so a machine sitting on
	# this screen is not still eating memory. The world stays held: there is
	# nothing left to play, and the hold is what keeps `StallPanel` up.
	_sealed.clear()
	# Nothing left to catch up to.
	_restore_rate()
	if !_stalling:
		_stalling = true
		_stalled_on = _last_run_turn + 1
		_set_held(true)






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
















## Every peer id in THIS MATCH, from the roster rather than from the transport.
##
## **`multiplayer.get_peers()` answers "who is connected to this process", and
## every caller here wanted "who is in this match".** Those were the same number
## in every test ever run, because every headless run was one server and exactly
## two clients who were both playing - a topology that cannot falsify the
## assumption.
##
## They stop being the same the moment a THIRD person presses Multiplayer, which
## connects them (D20) and, because `SceneMultiplayer.server_relay` defaults to
## true, announces them to every other client. See _expected_peers for what that
## did.
func _match_peers() -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	var session: MatchSession = References.match_session
	var setup: MatchSetup = null if session == null else session.setup()
	if setup == null:
		return ids
	for player: MatchPlayer in setup.players:
		if player != null && player.network_id != NetworkService.SERVER_PEER_ID:
			ids.append(player.network_id)
	return ids




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
	# Beside the input hashes in the same file, so a reader can line the two up:
	# inputs agreeing while states diverge is a simulation bug, inputs diverging
	# is a network one. See SessionLog.
	SessionLog.note("turn.state", {"n": turn, "sum": sum})

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
	# **A report for a turn already forgotten is refused, not resurrected.**
	# Re-creating the entry would put this peer's answer in an empty dictionary
	# with nothing to measure it against, and a comparison that never happens is
	# indistinguishable from one that passed. That is the failure this whole
	# window exists to prevent, so it says so instead.
	if turn <= _pruned_through:
		_late_reports += 1
		if _late_reports <= 1:
			Log.warn("A checksum arrived for a turn already forgotten, so it was never compared", {
				"turn": turn,
				"peer": peer,
				"pruned_through": _pruned_through,
				"window_turns": _retention_turns(),
			})
		return

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
		# Everybody, not just the peer that disagreed - see
		# MatchStartService.announce_desync. Which peer is the "reference" here
		# is whichever one reported first, so singling out the other would end
		# an arbitrary player's match and award their opponent the win.
		MatchStart.announce_desync(
			first_tick_of(turn), int(by_peer[id]), reference
		)

	_forget_old_turns(turn)


## Keeps the last few turns and drops the rest. A match is thousands of turns
## long and every one of them would otherwise be held forever.
##
## **The window is how far apart two peers may be, NOT a multiple of how often
## the world is hashed.** It used to be the latter, which tied an unrelated
## number to the one that matters and came out around a second - so any peer
## further behind than that had its report refused by the guard above and was
## never checked against anybody. See NetworkConfig.max_peer_lag_turns.
##
## `now` is the turn just reported rather than the highest ever seen, which is
## deliberately conservative: a report from the peer that is BEHIND prunes less,
## never more.
func _forget_old_turns(now: int) -> void:
	var window: int = _retention_turns()
	for turn: Variant in _turn_checksums.keys():
		if now - int(turn) > window:
			_turn_checksums.erase(turn)
			_pruned_through = maxi(_pruned_through, int(turn))


## How many turns of checksums are kept: the furthest a peer may legitimately be
## behind, plus a checksum interval so that a peer exactly at the ceiling still
## has its last report compared rather than refused on the boundary.
func _retention_turns() -> int:
	# **The window has to cover the furthest a peer may LEGITIMATELY be behind,
	# and the sealed stream raised that number without moving this one.** A peer
	# is allowed to trail by `max_sealed_turns` before it gives up, which is
	# twice `max_peer_lag_turns` at the authored values - so a peer between the
	# two had every checksum refused by `_compare_turn`'s pruning guard and was
	# never measured against anybody again. It says so once and then goes quiet,
	# which is a divergence detector that has silently switched itself off on
	# exactly the machine most likely to be diverging.
	var furthest: int = _max_peer_lag_turns()
	furthest = maxi(furthest, _max_sealed_turns())
	return furthest + _checksum_every() * 2


# --- lookups --------------------------------------------------------------

## Off the network there are no turns to agree on, and a single player run must
## pay nothing at all for any of this.
##
## **Also gated on `lockstep_enabled`**, and that gate is not caution - it is a
## correctness fix. With the flag off the match is server-authoritative, so a
## client draws replicated snapshots and runs no gameplay loop of its own;
## comparing world checksums between machines is then meaningless, and left
## ungated it reported a desync as soon as a tower was built and ended a live
## match on 2026-09-04. See NetworkConfig.lockstep_enabled.
func _is_live() -> bool:
	if !Net.is_online() || References.match_session == null:
		return false
	var config: NetworkConfig = _config()
	return config != null && config.lockstep_enabled



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
	return 1 if config == null else maxi(1, config.ticks_per_turn)


func _jitter_margin_ms() -> int:
	var config: NetworkConfig = _config()
	return 20 if config == null else maxi(0, config.jitter_margin_ms)


func _adaptive_local_jitter() -> bool:
	var config: NetworkConfig = _config()
	return true if config == null else config.adaptive_local_jitter


func _max_local_jitter_ms() -> int:
	var config: NetworkConfig = _config()
	return 25 if config == null else maxi(0, config.max_local_jitter_ms)


func _silent_timeout_seconds() -> float:
	var config: NetworkConfig = _config()
	return 8.0 if config == null else maxf(0.0, config.silent_timeout_seconds)


func _flush_immediately() -> bool:
	var config: NetworkConfig = _config()
	return true if config == null else config.flush_immediately


func _max_peer_lag_turns() -> int:
	var config: NetworkConfig = _config()
	return 200 if config == null else maxi(1, config.max_peer_lag_turns)


func _checksum_every() -> int:
	var config: NetworkConfig = _config()
	return 5 if config == null else maxi(1, config.checksum_every_turns)




## **Runs this machine's engine a little fast while it has a backlog to repay.**
##
## The whole of catch-up, and it is four lines because of what came before it. A
## peer that hiccups banks the stall as permanent input delay - it plays one turn
## per tick for ever after, so the gap never closes. Running 24 ticks a second
## against the relay's 20 closes it at four turns a second and then stops.
##
## **The simulation is untouched.** Every turn is still exactly one step of
## `MatchSession.tick_seconds()`, which reads the AUTHORED rate rather than the
## live one - so a peer catching up computes the identical world and merely
## reaches it sooner. That is the delta refactor's entire purpose, and the bench
## proves it by running the same match at 20 Hz and 30 Hz and comparing the
## traces byte for byte.
##
## **Nothing in the simulation may branch on any of this** (I4). The only thing
## written here is an engine property; no gameplay code reads it, and two peers
## running at different rates is expected rather than a fault.
##
## **Not gated on the machine being CPU-healthy**, which is amendment 3: that
## disables catch-up exactly when it is needed. A peer that cannot sustain the
## rate falls further behind and ends its own match through `_absorb_seal`'s
## ceiling, which says so, rather than being quietly wedged.
##
## Drains only to the TARGET LEAD, never past it. The lead is this machine's
## jitter buffer, and a peer that drained it to zero would stall on the next
## packet that arrived a millisecond late.
func _pace_engine() -> void:
	var authored: int = _authored_rate()
	if authored <= 0:
		return

	var wanted: int = authored
	if _catch_up_enabled():
		var excess: int = _sealed.size() - _sealed_lead_turns()
		if excess > 0:
			var percent: int = mini(
				excess * _catch_up_percent_per_turn(), _catch_up_max_percent()
			)
			wanted = authored + int(float(authored) * float(percent) / 100.0)

	# Written only when it moves. Assigning every tick would be a property write
	# on the hot path for nothing, and it makes the log below say something.
	if wanted == Engine.physics_ticks_per_second:
		return
	if wanted != authored && _paced_at != wanted:
		SessionLog.note("lockstep.catchup", {
			"rate": wanted, "authored": authored, "held": _sealed.size(),
		})
	_paced_at = wanted
	Engine.physics_ticks_per_second = wanted


## Puts the engine back to the rate the project authored.
##
## **Called wherever a match stops mattering**, because this is a GLOBAL engine
## property and a match that left it raised would hand the next one - or the main
## menu - a machine running fast for no reason.
func _restore_rate() -> void:
	var authored: int = _authored_rate()
	if authored > 0 && Engine.physics_ticks_per_second != authored:
		Engine.physics_ticks_per_second = authored
	_paced_at = 0


func _authored_rate() -> int:
	return int(round(1.0 / maxf(0.0001, MatchSession.tick_seconds())))


func _catch_up_enabled() -> bool:
	var config: NetworkConfig = _config()
	return true if config == null else config.catch_up_enabled


func _catch_up_max_percent() -> int:
	var config: NetworkConfig = _config()
	return 20 if config == null else maxi(0, config.catch_up_max_percent)


func _catch_up_percent_per_turn() -> int:
	var config: NetworkConfig = _config()
	return 10 if config == null else maxi(1, config.catch_up_percent_per_turn)


func _sealed_lead_turns() -> int:
	var config: NetworkConfig = _config()
	return 2 if config == null else maxi(0, config.sealed_lead_turns)


func _max_sealed_turns() -> int:
	var config: NetworkConfig = _config()
	return 400 if config == null else maxi(1, config.max_sealed_turns)


func _max_pending_orders() -> int:
	var config: NetworkConfig = _config()
	return 128 if config == null else maxi(1, config.max_pending_orders)
