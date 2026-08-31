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

## Stands in when there is no session at all, so a bare test scene still runs.
## Never used by a real match.
static var _fallback_rng: RandomNumberGenerator = null

var _setup: MatchSetup = null
var _rng: RandomNumberGenerator = null
var _start_frame: int = 0
var _abilities: AbilityRegistry = AbilityRegistry.new()
var _unit_types: UnitTypeRegistry = UnitTypeRegistry.new()
var _techs: TechRegistry = TechRegistry.new()
var _units: Dictionary = {}
var _next_unit_id: int = 1


## Starts a match. Called by Main before anything is created, since areas,
## builders and player states all read from here.
func begin(match_setup: MatchSetup) -> void:
	_setup = match_setup
	_units.clear()
	_next_unit_id = 1
	_start_frame = Engine.get_physics_frames()

	_rng = RandomNumberGenerator.new()
	if _setup != null:
		_rng.seed = _setup.rng_seed
	else:
		Log.err("MatchSession began with no MatchSetup, the match has no players")

	match_began.emit(_setup)


func setup() -> MatchSetup:
	return _setup


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


func display_name_for(slot: int) -> String:
	if _setup == null:
		return "Player %d" % slot
	var player: MatchPlayer = _setup.player_for(slot)
	if player == null:
		return "Player %d" % slot
	return player.display_name


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
	return Engine.get_physics_frames() - _start_frame


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
func is_sudden_death() -> bool:
	var config: GameConfig = References.game_config
	if config == null || config.sudden_death_seconds <= 0.0:
		return false
	return elapsed_seconds() >= config.sudden_death_seconds


## Seconds until Sudden Death, or 0 once it has arrived. What a dead send
## square draws so a player waiting on tier 4 reads how long rather than only
## that it is not ready.
func sudden_death_remaining() -> float:
	var config: GameConfig = References.game_config
	if config == null || config.sudden_death_seconds <= 0.0:
		return -1.0
	return maxf(0.0, config.sudden_death_seconds - elapsed_seconds())


## Seconds per simulation tick, read from the engine rather than duplicated, so
## there is exactly one place the rate is set.
static func tick_seconds() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


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
static func is_authority() -> bool:
	return !Net.is_online() || Net.is_server()


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


## Every live unit id, ascending. Ascending because the one caller compares the
## result between two machines (WorldChecksum), and a dictionary's own order is
## an implementation detail that has no business deciding whether two worlds
## match.
func unit_ids() -> Array:
	var ids: Array = _units.keys()
	ids.sort()
	return ids
