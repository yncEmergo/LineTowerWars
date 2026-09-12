class_name StartingTech
extends Node

## How a match HANDS OUT its opening technology, which is the whole of what
## MatchSettings.TechMode decides.
##
## Three answers, and only two of them do anything here:
##
##   PICK    the player spends their free technologies themselves, whenever
##           they like. Nothing happens - it is the game as it was.
##   RANDOM  one Ultimate is rolled for the whole match and handed to
##           everybody. **The world is held still while it is rolled**, and a
##           reel of Ultimates slows to a stop on the answer, so the match
##           opens on a moment everybody watches rather than on a line in a log.
##   DRAFT   three Ultimates are rolled for the whole match, every player is
##           shown the same three, and **the world is held still until they
##           have all chosen** - or until the clock runs out and one is chosen
##           for whoever has not.
##
## A node in the match scene next to TechManager, reached through References,
## and NOT an autoload: it receives no `@rpc` of its own. A draft pick is an
## ordinary player order and travels the road every other one takes - through
## `Commands`, checked for who sent it, applied here - exactly as a Research
## Center press does.
##
## **What it owns is which Ultimates, who has not chosen yet, and how long is
## left.** What a pick costs the record is TechManager's, in the same way a
## research press is: this calls grant_ultimate and holds none of the rules
## about prices or history.
##
## THE ROLL IS THE AUTHORITY'S, and it rides down to a replication client in the
## snapshot rather than being rolled again there (3.4). Both machines could
## derive the same answer from the seed, and that is exactly the kind of second
## simulation the rules forbid: it would agree until the day it did not, and the
## symptom would be a client drawing buttons the server refuses.
##
## **THE COUNTDOWN IS MEASURED IN SIMULATION TICKS AND ADVANCED BY THE TURN
## STREAM, never by a wall clock, and that is the load-bearing decision in this
## file.** Both phases HOLD THE WORLD, and a hold is only safe if every peer
## releases it on the same turn. `LockstepService` goes on applying turns
## through a hold - it must, or the very picks that end a draft could never
## arrive - so a peer that resumed five turns before its neighbour would
## simulate five turns the neighbour did not, and the two worlds would part with
## no error anywhere. Counting the turns makes the release an identity rather
## than a race. See MatchSession.hold and advance_clock.
##
## What is NOT deterministic and does not have to be is the ANIMATION: the reel
## of Ultimates on the reveal screen is presentation, runs on whatever clock the
## machine has, and lands on an answer that was decided here.

## Anything about the opening changed: which Ultimates are offered, who is still
## to choose, what was rolled, or how long is left. One signal rather than four,
## because the screens that listen redraw whole either way.
signal opening_changed()

## Given back by pick() when it went through. Same convention as TechManager,
## so a caller reads one kind of answer from both.
const ALLOWED: String = ""

## Which opening this match is in the middle of, if any.
##
## NONE covers both "this match deals no opening" and "it is finished", and the
## two never have to be told apart: what every caller asks is whether the world
## is being held, and a finished opening holds nothing.
enum Phase {
	NONE,
	DRAFT,
	REVEAL,
}

var _phase: Phase = Phase.NONE
var _options: Array[TechDefinition] = []
## Slots that still have to choose, during a DRAFT.
var _pending: PackedInt32Array = PackedInt32Array()
## What a RANDOM match rolled for everybody. Null in every other phase.
var _rolled: TechDefinition = null
## Simulation ticks left on the phase. See the note at the top about why this is
## ticks rather than seconds.
var _ticks_left: int = 0

var _session: MatchSession:
	get:
		return References.match_session

var _config: GameConfig:
	get:
		return References.game_config


func _ready() -> void:
	# Immune to the pause it causes itself, for the same reason LockstepService
	# is: the countdown that ENDS the hold could never run if it stopped with
	# everything else.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A player who leaves during the opening is not somebody to keep waiting
	# for. Without this, one crashed client holds every other player in a paused
	# world for the rest of the match.
	MatchStart.player_dropped.connect(_on_player_dropped)
	# The turn stream, which is the clock under lockstep. Fires on every peer for
	# the same turn, which is the whole point - see the note at the top.
	Lockstep.turn_ready.connect(_on_turn_ready)


## Deals the opening. Called by Main once the world is built and the technology
## registry exists, on every machine - a replication client reaches the holding
## branches and nothing else, because everything that grants anything is the
## authority's.
func apply(setup: MatchSetup) -> void:
	if setup == null || setup.settings == null:
		return

	match setup.settings.tech_mode:
		MatchSettings.TechMode.RANDOM:
			_begin_reveal(setup)
		MatchSettings.TechMode.DRAFT:
			_begin_draft(setup)
		_:
			return


# --- what the screens ask --------------------------------------------------

## Whether the world is being held still for the opening, in either phase.
##
## The question `CommandService` asks before it lets anything at all through: a
## paused world must not be moved by an order pressed on a screen that should
## have been frozen.
func is_holding() -> bool:
	return _phase != Phase.NONE


## Whether the match is waiting on somebody's CHOICE, which is the one thing a
## held match still accepts an order for.
func is_drafting() -> bool:
	return _phase == Phase.DRAFT


## Whether the match is showing everybody the Ultimate it rolled for them.
func is_revealing() -> bool:
	return _phase == Phase.REVEAL


## The Ultimates on offer, in the order they are drawn. Empty unless a draft is
## running, and briefly empty on a replication client that is held and has not
## had its first snapshot yet.
func options() -> Array[TechDefinition]:
	return _options


## What a RANDOM match rolled for the whole match, or null when it has not
## rolled one. What the reel lands on.
func rolled_tech() -> TechDefinition:
	return _rolled


## Whether the player at this client is one of the ones still to choose.
func needs_local_pick() -> bool:
	var session: MatchSession = _session
	if session == null:
		return false
	return _pending.has(session.local_slot())


## How many players the match is still waiting on, for the line the draft screen
## shows once you have chosen and somebody else has not.
func pending_count() -> int:
	return _pending.size()


## Seconds left on the phase, for the countdown a screen draws. Simulation
## seconds, so a match held by a stall does not spend them.
func seconds_left() -> float:
	return maxf(0.0, float(_ticks_left) * MatchSession.tick_seconds())


# --- the countdown ---------------------------------------------------------

## The turn stream, which is what drives the countdown under LOCKSTEP.
##
## One turn is `ticks_per_turn` simulation ticks, read off the same NetworkConfig
## LockstepService reads it from, so the two cannot disagree about how long a
## turn is.
##
## Fires BEFORE the turn's orders are applied, which is the right way round: a
## deadline and a pick landing on the same turn resolve the same way on every
## peer, and the pick that arrives a moment too late is refused identically
## everywhere with "you have already chosen".
func _on_turn_ready(_turn: int, _orders: Array) -> void:
	if !MatchSession.is_lockstep():
		return
	var network: NetworkConfig = References.network_config
	_advance(1 if network == null else maxi(1, network.ticks_per_turn))


## The countdown for everything that has no turn stream: a single player run,
## the replication path, and both benches. Under lockstep this stands aside
## entirely and the turns above do the counting.
func _physics_process(_delta: float) -> void:
	if MatchSession.is_lockstep():
		return
	_advance(1)


## One step of the countdown, however it was reached.
##
## AUTHORITY ONLY. A replication client is TOLD how long is left in the
## snapshot, exactly as it is told which Ultimates are on offer - it must not
## run a second countdown of its own that could finish first. Under lockstep
## every peer is an authority and every peer counts, which is what makes them
## release together.
##
## Gated on the shader warm-up, because the opening is a thing to WATCH and the
## warm-up is a black screen over the top of it. Under lockstep this is already
## true by construction - no turn is played until the renderer is warm - so the
## gate only really answers for the offline path, and having both paths agree is
## worth the line.
func _advance(ticks: int) -> void:
	if _phase == Phase.NONE || ticks <= 0:
		return
	if !MatchSession.is_authority() || !ShaderWarmup.is_done():
		return

	var before: int = _ticks_left
	_ticks_left = maxi(0, _ticks_left - ticks)
	if _ticks_left > 0:
		# Only when the whole second the screen draws actually changes. The
		# alternative is a signal twenty times a second for a number that moves
		# once, and every listener redraws whole.
		if _whole_seconds(before) != _whole_seconds(_ticks_left):
			opening_changed.emit()
		return

	if _phase == Phase.DRAFT:
		_force_remaining_picks()
	else:
		_finish_reveal()


func _whole_seconds(ticks: int) -> int:
	return int(ceil(float(ticks) * MatchSession.tick_seconds()))


## An authored duration in seconds as a whole number of simulation ticks, which
## is the only unit the countdown may be kept in.
func _ticks_for(seconds: float) -> int:
	if seconds <= 0.0:
		return 0
	return maxi(1, ceili(seconds / MatchSession.tick_seconds()))


# --- RANDOM: one Ultimate for the whole match ------------------------------

## Rolls the match's Ultimate and holds the world while it is shown.
##
## Rolled once and given to everybody rather than rolled per player, which is
## the rule - the point of the mode is that everyone opens on the same tower and
## the match is about playing it rather than about who drew better.
##
## A CLIENT under replication reaches this too and does exactly one thing with
## it: it stops. It rolls nothing and knows nothing yet - what was drawn and how
## long is left arrive in the next snapshot - but it must not run a single tick
## ahead of a server that is already holding.
func _begin_reveal(_setup: MatchSetup) -> void:
	_phase = Phase.REVEAL
	_ticks_left = _ticks_for(_reveal_seconds())

	if !MatchSession.is_authority():
		_settle()
		return

	var paths: Array[TechDefinition] = _path_techs()
	if paths.is_empty():
		Log.err("Random technology mode has no Ultimates to roll, nobody is given one")
		_phase = Phase.NONE
		_settle()
		return

	_rolled = paths[_rng().randi_range(0, paths.size() - 1)]
	Log.info("Random Ultimate rolled for the whole match", {
		"ultimate": _rolled.ultimate_name,
		"seconds": snappedf(_reveal_seconds(), 0.1),
	})

	# A build that has switched the reel off gets the old behaviour: the roll is
	# handed out on the spot and nothing is ever held.
	if _ticks_left <= 0:
		_finish_reveal()
		return
	_settle()


## The end of the reel: everybody is handed what was rolled, and the world moves.
func _finish_reveal() -> void:
	_phase = Phase.NONE
	if MatchSession.is_authority():
		_grant_to_everybody(_rolled)
	_settle()


func _grant_to_everybody(path: TechDefinition) -> void:
	if path == null:
		return
	var manager: TechManager = References.tech_manager
	if manager == null:
		Log.err("Random technology mode found no TechManager, nobody is given one")
		return

	for slot in _slots():
		var reason: String = manager.grant_ultimate(slot, path)
		if reason != TechManager.ALLOWED:
			Log.err("Could not hand a player the match Ultimate", {
				"player": slot, "why": reason,
			})


func _reveal_seconds() -> float:
	var config: GameConfig = _config
	return 0.0 if config == null else maxf(0.0, config.tech_reveal_seconds)


func _draft_seconds() -> float:
	var config: GameConfig = _config
	return 0.0 if config == null else maxf(0.0, config.draft_seconds)


# --- DRAFT: three Ultimates, everybody picks one ---------------------------

## Opens the draft and holds the world until everybody has chosen.
##
## A CLIENT under replication reaches this and stops, for the same reason it
## stops on a reveal: the three on offer and who is left arrive in the next
## snapshot, but it must not run a tick ahead of a server that is waiting.
func _begin_draft(setup: MatchSetup) -> void:
	_phase = Phase.DRAFT
	_ticks_left = _ticks_for(_draft_seconds())
	_pending = PackedInt32Array()
	for player in setup.players:
		if player != null:
			_pending.append(player.slot)
	# Ascending, so the auto-pick below consumes the match RNG in an order every
	# peer agrees on. The roster arrives in the same order everywhere today, but
	# that is a property of how a lobby happens to build it rather than a rule,
	# and the cost of not relying on it is one sort.
	_pending.sort()

	if !MatchSession.is_authority():
		_settle()
		return

	_options = _roll_options()
	if _options.is_empty():
		Log.err("Draft technology mode has no Ultimates to offer, it is skipped")
		_phase = Phase.NONE
		_pending = PackedInt32Array()
		_settle()
		return

	var names: Array[String] = []
	for tech in _options:
		names.append(tech.ultimate_name)
	Log.info("Draft opened", {
		"options": names,
		"players": _pending.size(),
		"seconds": snappedf(_draft_seconds(), 0.1),
	})
	_settle()


## The three on offer, drawn without replacement so nobody is shown the same
## Ultimate twice. Fewer than three when the build contains fewer.
func _roll_options() -> Array[TechDefinition]:
	var pool: Array[TechDefinition] = _path_techs()
	var chosen: Array[TechDefinition] = []
	var rng: RandomNumberGenerator = _rng()
	while !pool.is_empty() && chosen.size() < MatchSettings.DRAFT_OPTIONS:
		var index: int = rng.randi_range(0, pool.size() - 1)
		chosen.append(pool[index])
		pool.remove_at(index)
	return chosen


## One player choosing their Ultimate. The far end of the road their button
## press took, called by CommandService once it knows who is asking - never
## called by anything a player touches.
##
## Returns the reason it was refused, or ALLOWED, exactly as TechManager's
## orders do.
func pick(player_id: int, tech_id: int) -> String:
	if !is_drafting():
		return "there is no draft running"
	if !_pending.has(player_id):
		return "you have already chosen"

	var chosen: TechDefinition = _option_for(tech_id)
	if chosen == null:
		return "that Ultimate is not one of the three on offer"

	var manager: TechManager = References.tech_manager
	if manager == null:
		return "this scene has no TechManager"

	var reason: String = manager.grant_ultimate(player_id, chosen)
	if reason != TechManager.ALLOWED:
		return reason

	_pending = _without(player_id)
	Log.info("Draft pick", {
		"player": player_id,
		"ultimate": chosen.ultimate_name,
		"waiting_on": _pending.size(),
	})
	_close_if_done()
	return ALLOWED


## Chooses for everybody who has not, once the clock runs out.
##
## **A match may not wait on somebody who walked away from the keyboard**, and
## with no deadline that is exactly what it does - one player who never presses
## anything holds every other player in a frozen world for the rest of the
## match. So the clock picks, and it picks at RANDOM from the same three: there
## is no defensible "best" one to hand out, and any fixed answer - the first
## square, the cheapest - would make the deadline a strategy.
##
## Applied directly rather than sent through `Commands`, and that is deliberate:
## every peer reaches this on the SAME turn with the SAME match RNG, so every
## peer makes the same choices for the same players. An order would multiply the
## decision by the number of peers that issued it.
func _force_remaining_picks() -> void:
	if !MatchSession.is_authority():
		return

	# A copy, because pick() rewrites _pending as it goes.
	var waiting: PackedInt32Array = _pending.duplicate()
	for slot: int in waiting:
		var choice: TechDefinition = _random_option()
		if choice == null:
			break
		var reason: String = pick(slot, choice.tech_id)
		Log.info("Draft chose for a player who ran out of time", {
			"player": slot,
			"ultimate": choice.ultimate_name,
			"refused": reason,
		})

	# Belt and braces: anything the loop above could not settle must not leave
	# the world held for the rest of the match.
	_pending = PackedInt32Array()
	_close_if_done()


func _random_option() -> TechDefinition:
	if _options.is_empty():
		return null
	return _options[_rng().randi_range(0, _options.size() - 1)]


## Ends the draft once nobody is left to wait for.
func _close_if_done() -> void:
	if _phase == Phase.DRAFT && _pending.is_empty():
		_phase = Phase.NONE
	_settle()


# --- holding the world still ----------------------------------------------

## Puts the pause where the opening is, and tells whatever draws it.
##
## One place every machine ends up in, whichever direction it came from - the
## authority from a pick or a countdown it just ran, a replication client from
## the snapshot that told it about one - so there is exactly one line that
## decides whether the world is moving.
func _settle() -> void:
	var session: MatchSession = _session
	if session != null:
		session.hold(&"opening", is_holding())
	opening_changed.emit()


## A player who left is not one to keep waiting for (D13). Their slot simply
## stops being outstanding, and if they were the last one the match starts.
func _on_player_dropped(slot: int) -> void:
	if !_pending.has(slot):
		return
	_pending = _without(slot)
	Log.info("Draft no longer waiting on a player who left", slot)
	_close_if_done()


# --- the wire (replication only) -------------------------------------------

## The opening as it goes on the wire: the phase, how long is left, what was
## rolled, how many Ultimates are on offer, those ids, then the slots still to
## choose. Empty when no opening is running, which is every tick of nearly every
## match.
##
## Self-describing rather than a block of fixed fields, for the reason the
## technology block already is: two of its halves are a different length every
## time and they are read back together or not at all.
##
## **Nothing sends this under lockstep**, where there is no snapshot at all and
## every peer works the whole opening out for itself from the shared seed and
## the shared turn stream. It exists for the replication path, which is kept
## switchable for load comparisons.
func opening_record() -> PackedInt32Array:
	if !is_holding():
		return PackedInt32Array()

	var rolled_id: int = TechRegistry.NO_TECH if _rolled == null else _rolled.tech_id
	var record: PackedInt32Array = PackedInt32Array([
		int(_phase), _ticks_left, rolled_id, _options.size(),
	])
	for tech in _options:
		record.append(tech.tech_id)
	record.append_array(_pending)
	return record


## The same record, arriving on a client. Set rather than worked out: the roll,
## the clock and the count of who is left are all the server's, and a client
## that derived any of them would be running a second simulation of the opening.
func set_replicated_opening(record: PackedInt32Array) -> void:
	var phase: Phase = Phase.NONE
	var ticks: int = 0
	var rolled: TechDefinition = null
	var options: Array[TechDefinition] = []
	var pending: PackedInt32Array = PackedInt32Array()
	var registry: TechRegistry = _registry()

	if record.size() >= 4:
		phase = clampi(record[0], 0, int(Phase.REVEAL)) as Phase
		ticks = maxi(0, record[1])
		if registry != null:
			rolled = registry.tech_for(record[2])
		var count: int = clampi(record[3], 0, record.size() - 4)
		for index in range(4, 4 + count):
			var tech: TechDefinition = null if registry == null \
				else registry.tech_for(record[index])
			if tech != null:
				options.append(tech)
		for index in range(4 + count, record.size()):
			pending.append(record[index])

	# The clock moves every tick, and rebuilding the screen off it twenty times
	# a second would be the only work this class ever did. It is compared to the
	# whole SECOND instead, which is all a screen ever draws of it.
	var clock_moved: bool = _whole_seconds(ticks) != _whole_seconds(_ticks_left)
	_ticks_left = ticks
	if !clock_moved && phase == _phase && rolled == _rolled && _same_as(options, pending):
		return

	_phase = phase
	_rolled = rolled
	_options = options
	_pending = pending
	_settle()


# --- lookups --------------------------------------------------------------

## The one shared match RNG, so a server rolling the opening rolls from the
## same stream everything else in the match does and the seed in the log is
## the whole story.
func _rng() -> RandomNumberGenerator:
	return MatchSession.match_rng()


func _registry() -> TechRegistry:
	var session: MatchSession = _session
	return null if session == null else session.techs()


## Every technology that leads to an Ultimate, ascending by id - the registry's
## own order, which is stable across machines by construction.
func _path_techs() -> Array[TechDefinition]:
	var registry: TechRegistry = _registry()
	if registry == null:
		return []
	return registry.path_techs()


func _slots() -> Array:
	var session: MatchSession = _session
	if session == null:
		return []
	var slots: Array = []
	for slot in range(1, session.player_count() + 1):
		slots.append(slot)
	return slots


func _option_for(tech_id: int) -> TechDefinition:
	for tech in _options:
		if tech.tech_id == tech_id:
			return tech
	return null


func _without(slot: int) -> PackedInt32Array:
	var left: PackedInt32Array = PackedInt32Array()
	for entry in _pending:
		if entry != slot:
			left.append(entry)
	return left


## Whether an arriving record says anything about the offer this one does not
## already know.
func _same_as(options: Array[TechDefinition], pending: PackedInt32Array) -> bool:
	if options.size() != _options.size() || pending.size() != _pending.size():
		return false
	for index in range(options.size()):
		if options[index] != _options[index]:
			return false
	for index in range(pending.size()):
		if pending[index] != _pending[index]:
			return false
	return true
