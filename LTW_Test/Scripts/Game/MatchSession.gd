class_name MatchSession
extends Node

## What is true of THIS match: who is in it, which slot is ours, the shared
## random stream, and the id of every live unit.
##
## One object rather than four, because all of it has the same lifetime - it is
## born when a match starts and dies with it - and because the server will hand
## all of it over in one message. See multiplayer.md.
##
## Everything here used to be answered by reading game_config.tres, a file
## identical on every machine. That works for one player and cannot work for
## two, which is the whole reason this exists.

## Emitted once the setup is in place, before anything is built from it.
signal match_began(setup: MatchSetup)
## One unit became another and is the SAME unit as far as the player is
## concerned: a tower that finished an upgrade. Presentation listens so a
## selection and a control group follow the tower across the swap rather than
## quietly emptying.
##
## A signal rather than a call into the selection, because the two machines
## reach it from different directions - the authority from the upgrade itself,
## a client from the snapshot noticing the type changed - and neither should
## have to know what is listening.
signal unit_replaced(old_unit: Unit, new_unit: Unit)

## Ids count from 1 so 0 can mean "no unit" without ambiguity.
const NO_UNIT: int = 0

## How many times the phase 1 clock check may complain before it goes quiet. A
## clock that has drifted once drifts every tick afterwards.
const CLOCK_COMPLAINT_LIMIT: int = 5

## Stands in when there is no session at all, so a bare test scene still runs.
## Never used by a real match.
static var _fallback_rng: RandomNumberGenerator = null

var _setup: MatchSetup = null
var _rng: RandomNumberGenerator = null
var _start_frame: int = 0
## Every reason the world is currently being held still, by name. More than one
## thing is entitled to stop it and they overlap, so this is a SET of claims
## rather than a flag - see hold().
var _holds: Array[StringName] = []
## Whether the tree is actually paused, which is "are there any holds". Kept
## here rather than only on the tree because the match clock has to be corrected
## for it; see hold().
var _paused: bool = false
## Every reason the match CLOCK is being held while the world goes on moving -
## see hold_clock(). A set of claims for the same reason `_holds` is one.
var _clock_holds: Array[StringName] = []
## Whether the clock is standing still for ANY reason: the world held, or the
## clock held on its own. The two stop it the same way and must not refund each
## other twice, so there is one freeze and two ways into it.
var _frozen: bool = false
## The frame the freeze began on, so ending it can give the clock back what it
## took.
var _freeze_frame: int = 0
## The match clock UNDER LOCKSTEP: ticks accumulated from the turn stream rather
## than from this machine's physics frames. See tick().
var _turn_ticks: int = 0
## Phase 1 check. The legacy clock and the turn clock at the first tick they were
## compared on, so the two can be compared by DIFFERENCE - their absolute values
## cannot agree, because `_start_frame` is stamped in `Main._ready` while the
## turn stream starts counting on `LockstepService`'s first physics tick and
## nothing pins those two instants together.
var _clock_base: int = -1
var _clock_turn_base: int = 0
var _clock_complaints: int = 0
## Seconds the creep UNLOCK clock runs ahead of the match clock, and the latest
## time it may show. See unlock_elapsed_seconds().
var _unlock_lead: float = 0.0
var _unlock_ceiling: float = INF
var _abilities: AbilityRegistry = AbilityRegistry.new()
var _unit_types: UnitTypeRegistry = UnitTypeRegistry.new()
var _techs: TechRegistry = TechRegistry.new()
var _units: Dictionary = {}
var _next_unit_id: int = 1

## Whether THIS match is running deterministic lockstep, cached at `begin` and
## read by `is_authority` on every gameplay loop of every tick.
##
## STATIC because `is_authority` is, and it is static because a loop deep inside
## a passive has no session to hand it. Cached rather than read from the config
## each time for the same reason: 72 call sites ask this question, many of them
## per unit per tick, and a config lookup on that path is not free.
##
## Set at the START of a match and never mid-match: two peers that disagreed
## about which model they were running would not merely desync, they would
## disagree about what a desync IS.
static var _lockstep: bool = false


## Starts a match. Called by Main before anything is created, since areas,
## builders and player states all read from here.
func begin(match_setup: MatchSetup) -> void:
	_setup = match_setup
	_paused = false
	_frozen = false
	_clock_holds.clear()
	# Read once, here, so it cannot change under a running match. A single
	# player run is its own authority either way, so the flag only means
	# anything when there is a network.
	_lockstep = _lockstep_for(References.network_config)
	_units.clear()
	_next_unit_id = 1
	_start_frame = Engine.get_physics_frames()
	_turn_ticks = 0
	_clock_base = -1
	_clock_turn_base = 0
	_clock_complaints = 0
	# **Cleared here as well as in hold(), because `_paused` is and `_holds` was
	# not.** A second match in the same process inheriting a holder from the last
	# one would freeze a clock that nothing would ever release.
	_holds.clear()

	_rng = RandomNumberGenerator.new()
	if _setup != null:
		_rng.seed = _setup.rng_seed
	else:
		Log.err("MatchSession began with no MatchSetup, the match has no players")

	match_began.emit(_setup)


func setup() -> MatchSetup:
	return _setup


## The rules this match is played under, chosen in the lobby. Never null: a
## match with no settings has no starting gold and no income interval, so a
## stand-in from GameConfig is better than a crash and far better than silence.
func settings() -> MatchSettings:
	if _setup != null && _setup.settings != null:
		return _setup.settings
	Log.warn("MatchSession was asked for settings it has none of, standing in the defaults")
	return MatchSettings.defaults(References.game_config)


## The same answer, reachable without already holding the session - the shape
## match_rng() uses, and for the same reason: the things that ask are scattered
## and most of them hold nothing.
static func match_settings() -> MatchSettings:
	var session: MatchSession = References.match_session
	if session != null:
		return session.settings()
	return MatchSettings.defaults(References.game_config)


## The match RNG, reachable without already holding the session.
##
## Simulation code calls this and passes the result down, rather than calling
## the global randf()/randi(): those are not shared between machines, so two
## clients would roll different damage for the same shot. Matches the shape
## RNGUtil already uses, where the generator is always an explicit argument.
static func match_rng() -> RandomNumberGenerator:
	var session: MatchSession = References.match_session
	if session != null:
		return session.rng()

	if _fallback_rng == null:
		_fallback_rng = RandomNumberGenerator.new()
		Log.warn("No MatchSession, rolling on a throwaway RNG that nothing else shares")
	return _fallback_rng


## The one random stream the whole match rolls from. Seeded from the setup, so
## every machine running this match produces the same numbers in the same
## order. Never use the global randf()/randi() in simulation code.
func rng() -> RandomNumberGenerator:
	if _rng == null:
		Log.err("MatchSession was asked for its RNG before the match began")
		_rng = RandomNumberGenerator.new()
	return _rng


## Which slot this client plays, or 0 on a server that plays none.
func local_slot() -> int:
	if _setup == null:
		return 1
	return _setup.local_slot


func is_local_player(slot: int) -> bool:
	return slot != 0 && slot == local_slot()


func player_count() -> int:
	if _setup == null:
		return 1
	return _setup.player_count()


## What this player is CALLED on screen, which is not always who they are.
##
## The ANONYMOUS modifier answers with the slot's colour instead - "Red",
## "Blue" - and it is answered here rather than at the panel that draws it, so
## that a second reader cannot forget the rule. The lobby is deliberately not
## routed through this: the anonymity is a rule of the match, and hiding who
## you are about to play would only stop people finding each other.
func display_name_for(slot: int) -> String:
	if _setup != null && _setup.settings != null:
		if _setup.settings.modifier == MatchSettings.Modifier.ANONYMOUS:
			return _color_name_for(slot)
	if _setup == null:
		return "Player %d" % slot
	var player: MatchPlayer = _setup.player_for(slot)
	if player == null:
		return "Player %d" % slot
	return player.display_name


## Which colour in the palette a slot owns: what that player CHOSE in the
## lobby, and the slot's own place in the palette when nobody chose anything.
##
## The one place slot and colour are joined, which is what keeps them separate
## everywhere else. A colour is per-match identity carried on MatchPlayer, and
## the lane shuffle moves a slot without moving it - so a reader that indexed
## the palette by slot would draw one player in another player's colour the
## moment the lanes were dealt.
##
## The fallback is what a SINGLE PLAYER run and a bare test scene get: no lobby
## ever handed out a colour there, and slot order is the same deal a lobby
## would have made anyway.
func color_index_for(slot: int) -> int:
	if _setup != null:
		var player: MatchPlayer = _setup.player_for(slot)
		if player != null && player.color_index != MatchPlayer.NO_COLOR:
			return player.color_index
	return maxi(0, slot - 1)


## The name of the colour a slot is drawn in. Presentation, so it comes off
## PresentationConfig - and anything that wires none falls back to the slot
## number rather than refusing to answer.
func _color_name_for(slot: int) -> String:
	var presentation: PresentationConfig = References.presentation_config
	if presentation == null:
		return "Player %d" % slot
	return presentation.player_color_name(color_index_for(slot))


## Simulation ticks since this match began, counting from 0.
##
## The physics frame IS the simulation tick: the engine runs it at the rate in
## project.godot (20 Hz), every gameplay loop lives in _physics_process, and
## nothing gameplay-relevant happens on a render frame. So there is no second
## clock to keep in step with this one.
##
## This is what a command will be stamped with, and what the server and a
## client compare when they disagree. See multiplayer.md.
func tick() -> int:
	# **Under lockstep the clock is the TURN STREAM, not this machine's physics
	# frames**, and that is the whole of invariant I4 in `netcode-rework.md`.
	#
	# It holds today by construction rather than by enforcement: every peer
	# pauses for exactly the same turns, so every peer's physics-frame count
	# minus its own paused frames comes out the same. The cutover is what stops
	# that being true - a peer will hold for a word nobody else is waiting on -
	# and this number is hashed into every checksum through `elapsed_seconds()`,
	# so two peers whose clocks disagreed by one would desync with no other
	# symptom. Deriving it from the turns makes the invariant an identity.
	if _lockstep:
		return _turn_ticks

	# **The physics-frame clock survives for everything that has no turn stream**,
	# and it has to: `_lockstep` needs a network, so a single player run, the
	# replication path and both benches never apply a turn at all. A purely
	# turn-derived clock would sit at zero for ever there - no income, no creep
	# unlock, no Sudden Death - and `ReplicationService` dedupes its snapshots on
	# this number, so a client would apply exactly one and freeze.
	return _legacy_tick()


## Seconds this match has been running, which is what a creep unlock is timed
## against (unit_data.md 6.1).
##
## Derived from the tick rather than kept as a second clock of its own, so
## there is nothing that could ever drift from it. On a client it is this
## machine's own count and so is approximate by however long the match took to
## start here - fine for greying out a button, and the server refuses a send
## that arrives too early whatever the button showed.
func elapsed_seconds() -> float:
	return float(tick()) * tick_seconds()


## Moves the match clock on by one turn's worth of ticks. Lockstep only.
##
## **Called from `LockstepService._advance_turn` AFTER the turn's orders have
## been applied, and the ordering is load-bearing.** The technology draft
## releases its own hold from inside `Commands.apply_turn` - a pick is an order
## like any other - and `hold()`'s own measurement says a pause change made from
## an earlier node's `_physics_process` takes effect in that same physics frame.
## So the tick that ends the draft DOES simulate, and asking before the orders
## ran would refuse to count it.
##
## **Skipped while anything OTHER than lockstep holds the world.** The draft is
## the case that exists today: `LockstepService` is `PROCESS_MODE_ALWAYS` and
## goes on applying turns through it - which it must, or the very picks that end
## the draft could never arrive - while nothing else in the world moves. Counting
## those turns would be the exact bug the refund in `hold()` exists to prevent: a
## ten second draft would be ten seconds every creep unlock had silently already
## served.
##
## A lockstep stall needs no such test and must not get one. A stalled peer
## applies no turn at all, so it never reaches here.
func advance_clock(ticks: int) -> void:
	if !_lockstep:
		return
	if _held_by_other_than(&"lockstep") || is_clock_held():
		return
	_turn_ticks += ticks
	_check_clock()


## Whether anything except `reason` is holding the world still.
##
## Cheap on purpose: this is asked once per applied turn. `holders()` duplicates
## and sorts the array, which is fine for a log line and not for here.
func _held_by_other_than(reason: StringName) -> bool:
	for holder: StringName in _holds:
		if holder != reason:
			return true
	return false


## The match clock as it was computed before the turn stream drove it.
##
## Kept alive because everything without a turn stream still uses it, and because
## it is what `_check_clock` compares against.
func _legacy_tick() -> int:
	# Frozen while the world is held still. The engine goes on counting physics
	# frames whether or not anything is processing them, so without this the
	# clock would run through a pause and every creep unlock would come out of
	# it having silently served time. See hold(), and hold_clock() for the
	# other way in.
	if _frozen:
		return _freeze_frame - _start_frame
	return Engine.get_physics_frames() - _start_frame


## **Phase 1's falsification test, and the only moment it is cheap.**
##
## Under the CURRENT gate every peer holds for exactly the same turns, so the
## turn-derived clock and the physics-frame clock must agree - and if they do
## not, the reasoning about the draft hold or about the refund is wrong and
## nothing built on top of this is safe. After the cutover they are entitled to
## disagree and this check stops meaning anything, which is why it is worth
## spending now rather than later.
##
## Compared by DIFFERENCE from the first tick both were seen on. The absolutes
## cannot match: `_start_frame` is stamped in `Main._ready` and the turn stream
## starts on `LockstepService`'s first physics tick, with nothing pinning the two
## together, and the opening stall while peers find each other sits between them.
##
## `Log.err` because `CLAUDE.md` records that it reaches the editor log with a
## full stack from a running game, which is the channel for a rare correctness
## assertion. Capped, because a clock that has drifted once drifts every tick
## afterwards and an uncapped per-tick `push_error` is a flood.
func _check_clock() -> void:
	if _clock_complaints >= CLOCK_COMPLAINT_LIMIT:
		return
	if _clock_base < 0:
		_clock_base = _legacy_tick()
		_clock_turn_base = _turn_ticks
		return
	var legacy_delta: int = _legacy_tick() - _clock_base
	var turn_delta: int = _turn_ticks - _clock_turn_base
	if legacy_delta == turn_delta:
		return
	_clock_complaints += 1
	Log.err("Match clock disagrees with the physics-frame clock", {
		"turn_ticks": _turn_ticks,
		"legacy_tick": _legacy_tick(),
		"turn_delta": turn_delta,
		"legacy_delta": legacy_delta,
		"drift": turn_delta - legacy_delta,
		"holders": holders(),
		"complaint": _clock_complaints,
	})


## Whether the world is being held still, by anybody. See hold().
func is_paused() -> bool:
	return _paused


## Who is currently holding the world still, for a message or a log line.
func holders() -> Array:
	var names: Array = _holds.duplicate()
	names.sort()
	return names


## Holds the whole match still, or releases ONE holder's claim on it.
##
## **Named holders rather than a boolean, because there is more than one thing
## entitled to stop the world and they overlap.** The technology draft holds it
## at match start; a lockstep stall holds it whenever a peer's turn has not
## arrived. As a plain bool the second one released the first:
##
##   1. the draft opens, and pauses
##   2. a stall arrives, asks for a pause, and finds one already set
##   3. the stall clears, clears the pause - and the match is now RUNNING
##      while it is still drafting
##
## That peer then advances ticks nobody else runs: income accrues, the clock
## moves, creep unlocks serve their time. Gold is in the checksum, so it is a
## desync as well as a visibly wrong screen. **And a stall at match start is
## close to guaranteed**, because peers finish loading at different moments and
## whichever is ready first waits for the last. It is latent today only because
## the shipped `tech_mode` is PICK; the day a lobby turns DRAFT on, it fires.
##
## The world moves again when the LAST holder lets go, which is what
## `LockstepService._set_held` already claimed in a comment: whoever wants it
## held has it held.
##
## **The tree is what is paused**, not a flag every loop has to check: every
## gameplay loop in the project lives in `_physics_process`, so Godot's own
## pause switches all of them off at once and nothing new has to remember to
## ask. What must keep running says so for itself - the network autoloads, and
## whatever screen the player is being held FOR. Measured 2026-09-05: a pause
## set from an earlier node's `_physics_process` takes effect within that SAME
## physics frame, in both directions, so a held peer advances exactly zero
## world ticks and resumes on the tick the hold clears.
##
## The match CLOCK is given back what the hold took, because the tick counter
## is the physics frame and the engine goes on counting those while nothing is
## processing them. Without this, a ten second draft would be ten seconds every
## creep unlock in the match had silently already served.
## **A match that has left the tree may not still be holding it still.**
##
## `hold` pauses the WHOLE TREE, and the only thing that ever un-pauses it is
## another `hold(..., false)`. So any road out of a match taken while something
## was holding - a lockstep peer giving up, a desync notice, a crash out of the
## draft - freed the match scene and left `tree.paused` true, which freezes the
## main menu for the rest of the process with nothing on screen to say why.
##
## Nothing reached this before the sealed stream, because every existing exit
## happened to run through a release first. That is not a property worth relying
## on: the cost of being wrong is the whole application, and the fix is four
## lines in the one place that always runs.
func _exit_tree() -> void:
	_holds.clear()
	_clock_holds.clear()
	_frozen = false
	if _paused:
		_paused = false
		var tree: SceneTree = get_tree()
		if tree != null:
			tree.paused = false


func hold(reason: StringName, held: bool) -> void:
	var had: bool = reason in _holds
	if held == had:
		return
	if held:
		_holds.append(reason)
	else:
		_holds.erase(reason)

	var wanted: bool = !_holds.is_empty()
	if wanted == _paused:
		return
	_paused = wanted

	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = wanted
	_refresh_freeze()
	# **A lockstep stall is not a player action, and under the sealed stream it is
	# frequent** - every stall starts and ends here, and a peer on a jittery link
	# can take dozens a minute. `Log.info` runs `get_stack()` and `print_rich()`,
	# measured at ~10 ms a call on Windows (see CLAUDE.md), and the RESUME call
	# lands on the very frame the world starts moving again. The stall is already
	# reported by LockstepService and the session log, so it goes to debug here;
	# every other holder - the draft - stays at info.
	var detail: Dictionary = {"tick": tick(), "by": reason, "holders": holders()}
	if reason == &"lockstep":
		Log.debug("Match " + ("paused" if wanted else "resumed"), detail)
	else:
		Log.info("Match " + ("paused" if wanted else "resumed"), detail)


## Holds the match CLOCK still while the world goes on moving, or releases ONE
## holder's claim on it.
##
## **The other half of hold(), and the difference is the whole point of it.**
## hold() stops everything: units, projectiles, the HUD. This stops only what
## the CLOCK drives - income payouts, creep unlocks, a reserve refilling,
## Sudden Death - so a builder still walks, a tower still goes up and a creep
## still dies while nothing that is timed can move on. What a player does is
## theirs to take as long over as they like; what the match does to them waits.
##
## The tutorial is the one holder, and it is why this exists: a lesson asking a
## player to build a row has them build it on their own time, and the income
## beat they have not been taught about yet does not tick past while they do.
## A reserve reads is_clock_held() for itself - see SendBuilding - because its
## refill runs on the tick rather than on the clock.
##
## **Offline only, by use rather than by guard.** Under lockstep the clock is
## the turn stream and advance_clock() respects this as it respects hold(); but
## nothing online holds it, and a peer holding a clock nobody else held would be
## a desync with no other symptom.
func hold_clock(reason: StringName, held: bool) -> void:
	var had: bool = reason in _clock_holds
	if held == had:
		return
	if held:
		_clock_holds.append(reason)
	else:
		_clock_holds.erase(reason)
	_refresh_freeze()
	Log.info("Match clock " + ("held" if held else "released"), {
		"tick": tick(), "by": reason,
	})


## Whether the match clock is being held while the world moves. See hold_clock.
func is_clock_held() -> bool:
	return !_clock_holds.is_empty()


## Moves the match clock on without anything happening in between, for a match
## that skips its opening. Offline only, and refused under lockstep, where the
## clock is the turn stream every peer has to agree on.
##
## Whatever the clock times is answered against it afterwards exactly as if the
## seconds had been played: a creep whose start delay has passed is open, and
## an income payout that fell inside them is paid on the next tick - nothing,
## on a match that started on no income.
func fast_forward(seconds: float) -> void:
	if _lockstep:
		Log.err("The match clock cannot be moved on under lockstep", seconds)
		return
	var ticks: int = int(round(maxf(0.0, seconds) / tick_seconds()))
	# Backwards, because the clock is "frames since the start": an earlier start
	# is a later clock, frozen or not.
	_start_frame -= ticks


## Stops the clock or starts it again, from whichever of the two holds changed.
##
## One freeze with two ways into it rather than two refunds, because they
## overlap: a lesson holding the clock while a draft pauses the world must give
## the clock back ONE gap when both let go, not the same gap twice.
func _refresh_freeze() -> void:
	var wanted: bool = _paused || !_clock_holds.is_empty()
	if wanted == _frozen:
		return
	_frozen = wanted
	if wanted:
		_freeze_frame = Engine.get_physics_frames()
	else:
		_start_frame += Engine.get_physics_frames() - _freeze_frame


## The clock a creep's start delay is measured against: the match clock, moved
## ahead by any lead and stopped at any ceiling. Everything else the clock times
## - income, Sudden Death - reads elapsed_seconds() and is untouched by either.
##
## The tutorial's, and it is why this is separate from fast_forward(): a lesson
## opening the creep roster two minutes early must not pay two minutes of income
## on the next tick, and a lesson holding tier 2 back must not stop the income
## beat it is teaching. Offline only by use, like hold_clock().
func unlock_elapsed_seconds() -> float:
	return minf(elapsed_seconds() + _unlock_lead, _unlock_ceiling)


## Moves the unlock clock further ahead of the match clock. See
## unlock_elapsed_seconds().
func lead_unlocks(seconds: float) -> void:
	if _lockstep:
		Log.err("The unlock clock cannot be moved on under lockstep", seconds)
		return
	_unlock_lead += maxf(0.0, seconds)


## Stops the unlock clock at a match clock time, or lets it run again with INF.
## The time is where it STOPS, so a creep unlocking exactly then is open.
func cap_unlocks(at_seconds: float) -> void:
	if _lockstep:
		Log.err("The unlock clock cannot be capped under lockstep", at_seconds)
		return
	_unlock_ceiling = at_seconds


## Whether the match has reached Sudden Death.
##
## Derived from the clock rather than kept as a flag, so there is no state that
## could disagree with the time and nothing to replicate: a client works the
## same answer out of its own clock, and the server refuses a send that arrives
## on the wrong side of the line whatever the button showed. The same shape a
## creep unlock already has - see SendBuilding.unlock_remaining.
##
## What it means is in game_rules.md and unit_data.md 1.7: the whole of tier 4
## unlocks at once and tiers 1 to 3 stop being sendable.
##
## Through unlock_clock() rather than against sudden_death_seconds directly,
## so the opening phase moves this with everything else the match clock times.
## See GameConfig.start_delay_seconds.
func is_sudden_death() -> bool:
	var config: GameConfig = References.game_config
	if config == null || config.sudden_death_seconds <= 0.0:
		return false
	return elapsed_seconds() >= config.unlock_clock(config.sudden_death_seconds)


## Seconds until Sudden Death, or 0 once it has arrived. What a dead send
## square draws so a player waiting on tier 4 reads how long rather than only
## that it is not ready.
func sudden_death_remaining() -> float:
	var config: GameConfig = References.game_config
	if config == null || config.sudden_death_seconds <= 0.0:
		return -1.0
	var at: float = config.unlock_clock(config.sudden_death_seconds)
	return maxf(0.0, at - elapsed_seconds())


## Seconds per SIMULATION tick, read from the engine rather than duplicated, so
## there is exactly one place the rate is set.
##
## **This is the simulation's second and every peer must agree about it to the
## bit.** It converts an authored duration into ticks and the tick count back
## into match time, so anything derived from it is hashed into the checksum
## through `elapsed_seconds()`.
##
## **It is therefore NOT the number to use for wall-clock arithmetic** - how long
## a stall lasted, how many frames a timeout is, how many milliseconds of wire
## time a turn buys. Those follow the rate the machine is actually running at,
## and the two stop being the same number as soon as anything paces the engine.
## `LockstepService._engine_tick_seconds` is that reading, and it says why.
static func tick_seconds() -> float:
	return 1.0 / _sim_ticks_per_second()


## The AUTHORED simulation rate, read from the project setting and cached.
##
## **Deliberately not `Engine.physics_ticks_per_second`, and that is the whole
## delta refactor in one line.** The two are the same number today, and they stop
## being the same the moment anything paces the engine - a catch-up servo runs a
## peer that has fallen behind at 21 or 24 Hz so it can consume more game time
## than real time. Reading the live value there would change the LENGTH OF A
## SIMULATION SECOND on that peer alone, so its creeps would move further per
## turn than everybody else's and the worlds would part with no error anywhere.
##
## The project setting is what the authored rate IS, and assigning
## `Engine.physics_ticks_per_second` at runtime does not write back to it - so
## this stays fixed however the engine is paced. Cached because it is read on
## every gameplay loop of every unit, every tick.
static var _sim_rate: float = 0.0


static func _sim_ticks_per_second() -> float:
	if _sim_rate <= 0.0:
		_sim_rate = maxf(1.0, float(ProjectSettings.get_setting(
			"physics/common/physics_ticks_per_second", 20
		)))
	return _sim_rate


## Every ability a command can name, by id. Built by Main from the same content
## roots it validates, so it always matches what this build contains.
func abilities() -> AbilityRegistry:
	return _abilities


## Every unit type a spawn can name, by id. Built by Main at the same moment,
## from the same ContentConfig.
func unit_types() -> UnitTypeRegistry:
	return _unit_types


## Every technology a Research Center press can name, by id. Built by Main
## alongside the other two registries, from the folder ContentConfig names.
func techs() -> TechRegistry:
	return _techs


## Whether THIS machine decides what happens, as opposed to being told.
##
## True for a single player run and for the dedicated server; false on a
## client, which runs no simulation of its own and draws what the server sends
## (3.2, 3.4). There is deliberately no third answer: with no prediction yet
## (D17) a client never half-owns anything, so every simulation loop in the
## project can ask this one question and stop.
##
## Reads the peer rather than the setup, because it is a fact about this
## PROCESS rather than about the match: a match run from the editor with no
## network is its own authority.
## Whether a developer cheat may fire right now.
##
## ONE definition, asked by the machine the key was pressed on and by the
## server that grants the order, so the two cannot disagree about it. Two ways
## in, and they answer different needs:
##
##   GameConfig.cheats_allowed - the master switch, plus the separate flag that
##   lets a NETWORKED match have them at all. Invisible to players and edited on
##   the server, which is what makes it right for a scripted headless run and
##   wrong for anything anybody is playing.
##
##   MatchSettings.cheats_enabled - a row in the lobby, off by default, and
##   incompatible with ranked. Visible to everybody before they agree to play,
##   which is the property the config flag has not got.
##
## A single player run never reaches the second: there is no lobby, so the
## master switch is the whole answer.
static func cheats_permitted() -> bool:
	var config: GameConfig = References.game_config
	if config == null:
		return false

	var networked: bool = Net.is_online()
	if config.cheats_allowed(networked):
		return true
	if !networked:
		return false

	var settings: MatchSettings = match_settings()
	return settings != null && settings.cheats_enabled


## Whether THIS machine may advance the world.
##
## **Under lockstep the answer is always yes, and that is the whole cutover.**
## Every peer runs the same simulation over the same inputs, so every peer is an
## authority and none of them is THE authority. That one word changes what all
## 72 call sites mean without any of them being touched - which is what the
## discipline of routing every gameplay loop through this function bought.
##
## What replaces the server's veto is not a check here but the TURN: a peer may
## only simulate a turn once every peer's orders for it have arrived, so the
## inputs are identical before the simulation is allowed to run at all. See
## `LockstepService`.
##
## Under D2 (replication) it means what it always did: the server decides, a
## client draws what it is told, and a single player run is its own authority
## because there is nobody to ask.
static func is_authority() -> bool:
	if _lockstep:
		# **Except on the relay, which simulates nothing at all.** Under lockstep
		# every machine that HAS a world computes it, and the dedicated server
		# deliberately does not have one - see is_relay().
		return !Net.is_server()
	return !Net.is_online() || Net.is_server()


## Whether this process is the lockstep RELAY: the dedicated server, forwarding
## orders between peers and simulating nothing.
##
## **This is what the cutover was FOR and it did not happen at first.** D2 was
## changed on the reasoning that "a lockstep server is a relay that runs no game
## loop", and then `is_authority()` was left answering true everywhere, the
## server went on loading a full match scene, and every client waited on its word
## for every turn. So the server carried the same per-creep cost it always had,
## and it was now on the critical path of every client's tick - which is strictly
## worse than before: an overloaded server used to send late snapshots, and under
## lockstep it produces a hard freeze on every client instead.
##
## A relay keeps only what forwarding needs: the setup, so it can stamp which
## slot an order came from, and the membership, so it knows who is still here. It
## builds no areas, spawns no units, runs no economy and computes no checksum of
## its own. The peers check each other.
##
## The cost, accepted deliberately on 2026-09-05: with no third world there is
## nothing to arbitrate between two peers that disagree, so a ranked match is
## simply CANCELLED on a desync rather than resolved. Working out who was right
## needs the input log replayed offline, which the turn stream already contains
## and nothing yet does.
static func is_relay() -> bool:
	return _lockstep && Net.is_server()


## Whether this match is running lockstep rather than replication. For the few
## places that genuinely have to know WHICH model is underneath - the
## replication layer switching itself off, and the command road choosing which
## way to send an order. Gameplay code must never ask: it asks `is_authority`.
static func is_lockstep() -> bool:
	return _lockstep


## Starts a match on the lockstep RELAY, which has no session and no world.
##
## **The relay opens no match scene, and it used to open one for this flag
## alone.** Its match scene built nothing - `Main` returned before the first
## area - but loading it took a second on the relay's one main thread, and every
## player of that match sat at turn 0 waiting for the relay's first seal while it
## did. It also swapped the lobby's own scene out, taking the configs the lobby
## reads with it. `is_relay()` and `is_lockstep()` still have to answer on the
## relay, so the one thing a session would have set is set here, by the same
## rule `begin` uses and at the same moment: when the match starts.
static func begin_relay() -> void:
	_lockstep = _lockstep_for(References.network_config)


## Whether a match started now would run lockstep, from the network config.
##
## AND online: a single player run has no peers to agree with, and a turn
## waiting on orders that will never arrive would hang the match on tick one.
## One player is its own authority under either model.
static func _lockstep_for(network: NetworkConfig) -> bool:
	return network != null && network.lockstep_enabled && Net.is_online()


# --- Unit registry ------------------------------------------------------

## Gives a unit the id both machines will call it by, and remembers it.
##
## Ids are handed out in spawn order, so as long as both machines spawn the
## same units in the same order they agree without having to be told. Once the
## server is authoritative it assigns them instead and clients adopt what they
## are given - which is what claim_id is for.
func register_unit(unit: Unit) -> int:
	if unit == null:
		Log.err("MatchSession was asked to register a null unit")
		return NO_UNIT

	var id: int = _next_unit_id
	_next_unit_id += 1
	_units[id] = unit
	return id


## Registers a unit under an id chosen elsewhere - by the server, later. Keeps
## the local counter ahead of it so a locally spawned unit can never collide
## with one that was handed down.
func claim_unit_id(unit: Unit, id: int) -> bool:
	if unit == null || id == NO_UNIT:
		Log.err("MatchSession was given a null unit or a zero id to claim", id)
		return false
	if _units.has(id):
		Log.err("MatchSession already has a unit under that id", id)
		return false

	_units[id] = unit
	_next_unit_id = maxi(_next_unit_id, id + 1)
	return true


func unregister_unit(id: int) -> void:
	if id != NO_UNIT:
		_units.erase(id)


## The unit an id names, or null once it has died. Callers must expect null:
## a command can name a tower that was sold while the message was in flight.
func unit_for(id: int) -> Unit:
	if !_units.has(id):
		return null
	var unit: Unit = _units[id] as Unit
	if !is_instance_valid(unit):
		_units.erase(id)
		return null
	return unit


## Hands an id from one node to another and tells the world they are the same
## unit. Called on the authority the moment an upgrade completes, and on a
## client the moment replication notices the id changed type.
##
## The OLD unit must already be out of the tree, so its _exit_tree has given
## the id back - claiming it again is what makes the new node answer to the
## name both machines already use, and is why an upgrade costs no wire format
## change at all.
func replace_unit(old_unit: Unit, new_unit: Unit) -> void:
	if old_unit == null || new_unit == null:
		Log.err("MatchSession was asked to replace a unit with nothing")
		return
	unit_replaced.emit(old_unit, new_unit)


func unit_count() -> int:
	return _units.size()


## Every live unit, in no particular order. For anything that has to look at
## all of them at once rather than at one id - the minimap does.
##
## Unordered on purpose: sorting is unit_ids()'s job, and it only sorts because
## its caller compares the result between two machines. Nothing that just draws
## the world needs to pay for that.
func live_units() -> Array:
	var units: Array = []
	for unit: Unit in _units.values():
		if is_instance_valid(unit):
			units.append(unit)
	return units


## Every live unit id, ascending. Ascending because the caller that wants THIS
## one compares the result between two machines (WorldChecksum), and a
## dictionary's own order is an implementation detail that has no business
## deciding whether two worlds match.
##
## **If order does not matter to you, call `unit_ids_unsorted()` instead.** The
## sort here is over every unit in the world, and a caller on a per-frame path
## pays it for nothing - which `ReplicationService._apply_units` did, on every
## client, twenty times a second, for a sweep that only asks which ids are
## absent.
func unit_ids() -> Array:
	var ids: Array = _units.keys()
	ids.sort()
	return ids


## Every live unit id, in whatever order the dictionary holds them.
##
## A COPY, like `keys()` itself, so erasing a unit while walking the result is
## safe - which the removal sweep in `ReplicationService` relies on.
##
## Never use this where two machines compare the answer. That is what
## `unit_ids()` is for, and the difference between them is the difference
## between a checksum that means something and one that does not.
func unit_ids_unsorted() -> Array:
	return _units.keys()
