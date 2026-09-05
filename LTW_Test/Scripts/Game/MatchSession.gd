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
## Every reason the world is currently being held still, by name. More than one
## thing is entitled to stop it and they overlap, so this is a SET of claims
## rather than a flag - see hold().
var _holds: Array[StringName] = []
## Whether the tree is actually paused, which is "are there any holds". Kept
## here rather than only on the tree because the match clock has to be corrected
## for it; see hold().
var _paused: bool = false
## The frame the hold began on, so resuming can give the clock back what the
## hold took.
var _pause_frame: int = 0
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
	# Read once, here, so it cannot change under a running match. A single
	# player run is its own authority either way, so the flag only means
	# anything when there is a network.
	var network: NetworkConfig = References.network_config
	# AND online: a single player run has no peers to agree with, and a turn
	# waiting on orders that will never arrive would hang the match on tick one.
	# One player is its own authority under either model.
	_lockstep = network != null && network.lockstep_enabled && Net.is_online()
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
	# Frozen while the world is held still. The engine goes on counting physics
	# frames whether or not anything is processing them, so without this the
	# clock would run through a pause and every creep unlock would come out of
	# it having silently served time. See hold().
	if _paused:
		return _pause_frame - _start_frame
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
	if wanted:
		_pause_frame = Engine.get_physics_frames()
	else:
		_start_frame += Engine.get_physics_frames() - _pause_frame
	Log.info("Match " + ("paused" if wanted else "resumed"), {
		"tick": tick(), "by": reason, "holders": holders(),
	})


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
		return true
	return !Net.is_online() || Net.is_server()


## Whether this match is running lockstep rather than replication. For the few
## places that genuinely have to know WHICH model is underneath - the
## replication layer switching itself off, and the command road choosing which
## way to send an order. Gameplay code must never ask: it asks `is_authority`.
static func is_lockstep() -> bool:
	return _lockstep


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
