class_name MatchPause
extends Node

## The PAUSE a networked match can be put into: the world held completely still
## for everybody until somebody asks for it back, and then a countdown before it
## moves again.
##
## A node in the match scene next to StartingTech, reached through References,
## and NOT an autoload: it receives no `@rpc` of its own. A press on the pause
## button is an ordinary player order and travels the road every other one takes
## - through `Commands`, stamped with who sent it, applied here - exactly as a
## Research Center press does.
##
## **THE PAUSE HAS TO RIDE THE TURN STREAM, and that is the load-bearing
## decision in this file.** A hold stops the match clock as well as the world -
## `MatchSession.advance_clock` refuses a turn while anything but lockstep is
## holding - so two peers that began holding on different turns would have two
## different clocks, which is hashed into every checksum and is therefore a
## desync with no other symptom. An order lands on ONE agreed turn on every
## machine; a broadcast rpc lands whenever the packet does. So there is no
## shortcut here, and "immediately" honestly means "on the next sealed turn",
## which is the same delay every other order in the game pays.
##
## **The countdown back is measured in SIMULATION TICKS and advanced by the turn
## stream**, for the same reason StartingTech's is: `LockstepService` goes on
## applying turns through a hold - it must, or the very order that ends this one
## could never arrive - so a peer that resumed five turns before its neighbour
## would simulate five turns the neighbour did not. Counting turns makes the
## release an identity rather than a race.
##
## **Offline there is no pause here at all.** A single player match is paused by
## opening the menu, which holds the world directly - there is nobody to agree
## with, so there is nothing to send. See GameMenu.
##
## **And the replication path deliberately cannot pause.** A client there
## simulates nothing and is told what happened in the snapshot, so a pause would
## have to ride that wire the way the opening does - and that path is kept only
## to compare load against lockstep. `can_pause` says no, so no button is
## offered.
##
## Anybody may pause and anybody may resume, as often as they like. There is no
## allowance and no cooldown: the user's call while the game is in testing, and
## the first thing to revisit when it is not.

## The pause changed in any way - held, released, or one second nearer to
## resuming. One signal rather than three, because everything that listens
## redraws whole.
signal pause_changed()

## Given back by pause() and resume() when the order went through. Same
## convention as TechManager and StartingTech, so a caller reads one kind of
## answer from all three.
const ALLOWED: String = ""

## The name this holds the world under. Its own, so it can neither release nor
## be released by the opening's hold or a lockstep stall - see MatchSession.hold.
const HOLD_REASON: StringName = &"pause"

## Whether the world is being held still by a pause. Stays true through the
## resume countdown: the world does not move again until the count reaches zero.
var _holding: bool = false
## Which slot pressed Pause, for the line the panel shows. Kept through the
## countdown so the message does not change under the player mid-read.
var _by_slot: int = 0
## Simulation ticks left before the world moves again, or 0 when the pause is
## not counting down. See the note at the top about why this is ticks.
var _ticks_left: int = 0

var _session: MatchSession:
	get:
		return References.match_session

var _config: GameConfig:
	get:
		return References.game_config


func _ready() -> void:
	# Immune to the pause it causes itself, for the same reason LockstepService
	# and StartingTech are: the countdown that ENDS the hold could never run if
	# it stopped with everything else.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The turn stream, which is the clock under lockstep. Fires on every peer for
	# the same turn, which is the whole point - see the note at the top.
	Lockstep.turn_ready.connect(_on_turn_ready)

	var players: PlayerManager = References.player_manager
	if players != null:
		players.match_ended.connect(_on_match_ended)


## **A match that has left the tree may not still be holding it still.** Belt
## and braces next to MatchSession's own clearing of it: a road out of a paused
## match frees this node, and a hold nothing releases freezes the menu for the
## rest of the process.
func _exit_tree() -> void:
	_holding = false
	_ticks_left = 0


# --- what the screens ask --------------------------------------------------

## Whether the world is being held still by a pause, counting down or not. The
## question `CommandService` asks before it lets anything through.
func is_holding() -> bool:
	return _holding


## Whether somebody has asked for the world back and it is counting down to it.
func is_counting_down() -> bool:
	return _holding && _ticks_left > 0


## Seconds left on the countdown. Simulation seconds, so a match also held by a
## lockstep stall does not spend them.
func seconds_left() -> float:
	return maxf(0.0, float(_ticks_left) * MatchSession.tick_seconds())


## Which slot pressed Pause, or 0 when the match is not paused.
func paused_by() -> int:
	return _by_slot if _holding else 0


## Whether THIS match can be paused at all, which is what decides whether the
## button exists. Lockstep only: see the note at the top about the other two.
func can_pause() -> bool:
	return MatchSession.is_lockstep()


# --- the press -------------------------------------------------------------

## The local player asking for whichever of the two this press means. Called by
## the menu button and by nothing else.
##
## **It decides nothing and claims nothing.** What it sends is an order, and the
## answer comes back on the turn every peer runs it on - so the button does not
## flip here, it flips when the world does. D17: feedback, never prediction.
func request_toggle() -> void:
	if !can_pause():
		return
	if _holding && !is_counting_down():
		Commands.submit_player_action(Command.PlayerAction.RESUME_MATCH)
		return
	Commands.submit_player_action(Command.PlayerAction.PAUSE_MATCH)


# --- the orders, applied on the turn every peer runs them on ---------------

## One player pausing the match. The far end of the road their button press
## took, called by CommandService once it knows who is asking - never called by
## anything a player touches.
##
## Pausing an already-paused match is not refused, it CANCELS a countdown that
## is running: that is the only sensible reading of pressing Pause while the
## world is about to move. Whoever pressed it becomes the holder named on screen.
func pause(slot: int) -> String:
	if !can_pause():
		return "this match cannot be paused"
	if _holding && !is_counting_down():
		return "the match is already paused"

	_holding = true
	_by_slot = slot
	_ticks_left = 0
	Log.info("Match paused by a player", {"player": slot, "tick": _tick()})
	_settle()
	return ALLOWED


## One player asking for the world back, which starts the countdown rather than
## ending the pause. Anybody in the match may send it, including somebody who
## did not press Pause.
func resume(slot: int) -> String:
	if !_holding:
		return "the match is not paused"
	if is_counting_down():
		return "the match is already resuming"

	_ticks_left = _ticks_for(_countdown_seconds())
	Log.info("Match resuming", {
		"player": slot,
		"seconds": snappedf(_countdown_seconds(), 0.1),
		"tick": _tick(),
	})
	# A build that has switched the countdown off gets the world back on this
	# turn, which is still one turn every peer agrees on.
	if _ticks_left <= 0:
		_release()
		return ALLOWED
	_settle()
	return ALLOWED


# --- the countdown ---------------------------------------------------------

## The turn stream, which is what drives the countdown under LOCKSTEP.
##
## One turn is `ticks_per_turn` simulation ticks, read off the same NetworkConfig
## LockstepService reads it from, so the two cannot disagree about how long a
## turn is. Fires BEFORE the turn's orders are applied, exactly as StartingTech's
## does, so a Pause landing on the turn a countdown would have ended on resolves
## the same way on every peer.
func _on_turn_ready(_turn: int, _orders: Array) -> void:
	if !MatchSession.is_lockstep():
		return
	var network: NetworkConfig = References.network_config
	_advance(1 if network == null else maxi(1, network.ticks_per_turn))


## The countdown for everything that has no turn stream. Nothing offline can
## reach a pause today - `can_pause` refuses it - so this is here to keep the
## two clocks the same shape rather than because anything runs it.
func _physics_process(_delta: float) -> void:
	if MatchSession.is_lockstep():
		return
	_advance(1)


## One step of the countdown, however it was reached.
##
## AUTHORITY ONLY, like StartingTech's: under lockstep every peer is an
## authority and every peer counts, which is what makes them release together.
func _advance(ticks: int) -> void:
	if !is_counting_down() || ticks <= 0:
		return
	if !MatchSession.is_authority():
		return

	var before: int = _ticks_left
	_ticks_left = maxi(0, _ticks_left - ticks)
	if _ticks_left > 0:
		# Only when the whole second the screen draws actually changes -
		# StartingTech's reasoning word for word, since the alternative is a
		# signal twenty times a second for a number that moves once.
		if _whole_seconds(before) != _whole_seconds(_ticks_left):
			pause_changed.emit()
		return
	_release()


## The end of it: the world moves again, on this turn, on every peer at once.
func _release() -> void:
	_holding = false
	_ticks_left = 0
	_by_slot = 0
	Log.info("Match resumed", {"tick": _tick()})
	_settle()


## A finished match is not one to hold still. There is nothing on the end screen
## a pause protects, and a hold left over one would sit on the summary with no
## button left to lift it.
func _on_match_ended(_winner_slot: int) -> void:
	if !_holding:
		return
	_release()


# --- holding the world still ----------------------------------------------

## Puts the hold where the pause is, and tells whatever draws it. One place
## every road ends in, so there is exactly one line that decides whether the
## world is moving.
func _settle() -> void:
	var session: MatchSession = _session
	if session != null:
		session.hold(HOLD_REASON, _holding)
	pause_changed.emit()


func _countdown_seconds() -> float:
	var config: GameConfig = _config
	return 0.0 if config == null else maxf(0.0, config.resume_countdown_seconds)


## An authored duration in seconds as a whole number of simulation ticks, which
## is the only unit the countdown may be kept in.
func _ticks_for(seconds: float) -> int:
	if seconds <= 0.0:
		return 0
	return maxi(1, ceili(seconds / MatchSession.tick_seconds()))


func _whole_seconds(ticks: int) -> int:
	return int(ceil(float(ticks) * MatchSession.tick_seconds()))


func _tick() -> int:
	var session: MatchSession = _session
	return 0 if session == null else session.tick()
