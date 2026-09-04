class_name PlayerManager
extends Node

## Owns what there is exactly one of PER PLAYER: their state, and their area.
##
## The lookup exists so nothing has to reach for "the" player: a tower asks
## for its own owner's state, which stays correct once there are 12 of them.
##
## It also answers the two ring questions - who a player sends into, and where
## a creep goes after it leaks - because answering them needs both halves it
## already holds: the slot order, and who is still alive.
##
## Also drives the income tick. One shared clock rather than a timer per
## player, because income is paid to everyone on the same beat and a player
## joining or dying must never shift anyone else's schedule.

## Emitted after every player has been paid.
signal income_paid()
## A player ran out of lives and is out of the match, with their placement
## already set.
signal player_eliminated(slot: int)
## Only one player is left. The match is over: income stops and nothing more
## can be sent (game_rules.md - last player standing).
signal match_ended(winner_slot: int)

var _states: Dictionary = {}
## slot -> PlayerArea, filled by Main as it builds them. Separate from _states
## because the states exist before any area does: the economy is created first
## so nothing can be built before there is gold to build it with.
var _areas: Dictionary = {}
var _income_elapsed: float = 0.0
## Latched rather than recomputed, so match_ended fires exactly once.
var _over: bool = false
## Whether the one-off raise that Sudden Death brings has already been paid.
## A latch rather than a reading of the clock, because the raise happens ONCE
## at the moment the line is crossed - a player who spends their way back under
## the floor afterwards is not topped up again.
var _sudden_death_paid: bool = false
var _income_interval: float = 0.0


## Builds one state per player in the match. Called by Main once the setup is
## known. The setup says WHO is playing, the config says what they start with.
func _ready() -> void:
	# The match's own reaction to somebody leaving it. MatchStart says WHO is
	# gone; what that costs them is the match's business, and this is where the
	# match keeps everything per-player.
	MatchStart.player_dropped.connect(erase_player)


func create_states(setup: MatchSetup, config: GameConfig) -> void:
	_states.clear()
	if config == null:
		Log.err("PlayerManager cannot create states without a GameConfig")
		return
	if setup == null:
		Log.err("PlayerManager cannot create states without a MatchSetup")
		return

	# What a player STARTS with is the lobby's answer rather than the file's:
	# GameConfig is where the defaults live, and the settings are the copy of
	# them the host actually agreed to (multiplayer.md 8.2). Lives still fall
	# out of the player count unless the host typed a number over it, which is
	# what lives_for decides.
	var settings: MatchSettings = setup.settings
	if settings == null:
		Log.err("PlayerManager was given a setup with no settings, using the defaults")
		settings = MatchSettings.defaults(config)

	var starting_lives: int = settings.lives_for(setup.player_count(), config)
	for player in setup.players:
		if player == null:
			continue
		var state: PlayerState = PlayerState.new()
		state.setup(
			player.slot, settings.starting_gold, settings.starting_income, starting_lives
		)
		_states[player.slot] = state

	_income_interval = settings.income_interval
	_income_elapsed = 0.0
	_over = false


## Remembers one player's area. Called by Main as it places them, rather than
## found by walking the tree, so nothing has to know where areas are parented.
func register_area(area: PlayerArea) -> void:
	if area == null:
		Log.err("PlayerManager was asked to register a null area")
		return
	_areas[area.player_id] = area


func area_for(player_id: int) -> PlayerArea:
	if !_areas.has(player_id):
		return null
	var area: PlayerArea = _areas[player_id] as PlayerArea
	if !is_instance_valid(area):
		_areas.erase(player_id)
		return null
	return area


## Every area in the match, in slot order. For the things that act on all of
## them at once rather than on one player's - the build grid overlay is the
## first.
func areas() -> Array[PlayerArea]:
	var found: Array[PlayerArea] = []
	for slot in _sorted_slots():
		var area: PlayerArea = area_for(slot)
		if area != null:
			found.append(area)
	return found


# --- The ring -----------------------------------------------------------

## Whose maze this player's creeps walk: their RIGHT NEIGHBOUR in slot order
## (game_rules.md). Eliminated players are skipped, which is the ring closing.
##
## Resolved on every send rather than cached, so the ring closing needs nothing
## invalidated anywhere.
func sends_into(player_id: int) -> int:
	return _next_living(player_id, player_id)


## Where a creep goes after it leaks: the next maze in ring order after the one
## it just leaked, skipping its own sender, since a creep never walks the lane
## of the player who bought it. In a 1v1 that resolves back to the same maze,
## which game_rules.md states explicitly.
func next_maze_after(defender_id: int, sender_id: int) -> int:
	return _next_living(defender_id, sender_id)


## Walks the ring from `from` and returns the next living player who is not
## `excluded`.
##
## Falls back to `from` when the ring holds nobody else - a 1v1 whose other
## player is out. That means sending into your own lane, which is odd but
## harmless, and it cannot last: with the win condition deliberately NOT BUILT
## (game_rules.md) a match with one player left simply carries on.
func _next_living(from: int, excluded: int) -> int:
	var count: int = _player_count()
	for step in range(1, count + 1):
		var slot: int = ((from - 1 + step) % count) + 1
		if slot == excluded:
			continue
		var state: PlayerState = state_for(slot)
		if state != null && !state.is_eliminated():
			return slot
	return from


## Who currently sends INTO this player: the previous living player round the
## ring, which is the mirror of sends_into() above.
##
## Falls back to `defender_id` when the ring holds nobody else, exactly as
## _next_living does, so a caller reading their own slot back is being told
## "there is no other player" rather than being handed a wrong one.
func attacker_of(defender_id: int) -> int:
	var count: int = _player_count()
	for step in range(1, count + 1):
		var slot: int = ((defender_id - 1 - step + count) % count) + 1
		if slot == defender_id:
			continue
		var state: PlayerState = state_for(slot)
		if state != null && !state.is_eliminated():
			return slot
	return defender_id


func _player_count() -> int:
	return maxi(1, _states.size())


## Takes EVERYTHING a player owns off the field: their maze, their builder,
## their send building, and the creeps they have sent - wherever those happen
## to be walking. Used both when a player is eliminated and when one drops out
## (D14).
##
## Walked over the unit registry rather than over the player's own area,
## because the creeps they sent are standing in somebody ELSE's lane and are
## still theirs. Ownership is the only thing that answers "is this mine".
##
## **Nothing here dies, it is simply removed.** Freeing the node deliberately
## skips `_die()`, so no death passive fires: a Skeleton does not get back up,
## an Acolyte heals nobody on the way out, and no bounty is paid to the player
## whose lane it happened to be standing in. Somebody leaving the match is not
## a kill and must not pay like one.
##
## The grid cells still come back, because that happens in `_exit_tree` rather
## than in death - so the lane is really open rather than merely empty-looking.
##
## Server side by nature - a client sees it all vanish through replication like
## any other change - but guarded rather than assumed, because a client freeing
## its own copy would only have it handed straight back.
func erase_player(player_id: int) -> void:
	if !MatchSession.is_authority():
		return

	var session: MatchSession = References.match_session
	if session == null:
		return

	var removed: int = 0
	for id in session.unit_ids():
		var unit: Unit = session.unit_for(int(id))
		if unit == null || unit.owner_player_id != player_id:
			continue
		# Out of the registry at once: queue_free is deferred, and the next
		# tick would otherwise still find it and treat it as alive.
		session.unregister_unit(int(id))
		unit.queue_free()
		removed += 1

	Log.info("Player erased from the field", {"player": player_id, "units": removed})


func state_for(player_id: int) -> PlayerState:
	if !_states.has(player_id):
		return null
	return _states[player_id]


## Every player's state, ascending by slot.
##
## Ascending because the one caller compares the result BETWEEN TWO MACHINES
## (`WorldChecksum`), and a Dictionary's own order is an implementation detail
## with no business deciding whether two worlds are called identical. Exactly
## the shape and exactly the reasoning of `MatchSession.unit_ids()`.
##
## Anything that merely draws a player's gold should keep using `state_for` and
## not pay for this.
func states_in_slot_order() -> Array[PlayerState]:
	var slots: Array = _states.keys()
	slots.sort()
	var ordered: Array[PlayerState] = []
	for slot: Variant in slots:
		var state: PlayerState = _states[slot] as PlayerState
		if state != null:
			ordered.append(state)
	return ordered


## Which player this client controls. The single place that answers "is this
## mine".
##
## Now comes off the MatchSession rather than the config, because a config file
## is identical on every machine and so cannot say which player YOU are.
func local_player_id() -> int:
	var session: MatchSession = References.match_session
	if session == null:
		return 1
	return session.local_slot()


## State of the player at this client, which is who the HUD describes.
func local_state() -> PlayerState:
	return state_for(local_player_id())


# --- Income -------------------------------------------------------------

## Seconds until the next payout, for the HUD readout.
func seconds_until_income() -> float:
	if _income_interval <= 0.0:
		return 0.0
	return maxf(0.0, _income_interval - _income_elapsed)


# --- Elimination and the end of the match -------------------------------

## How many players are still in it.
func living_count() -> int:
	var alive: int = 0
	for state in _states.values():
		if (state as PlayerState).placement == 0:
			alive += 1
	return alive


## Whether the match has been decided. A one player run is never "over": there
## is nobody to beat, and it is how the prototype is still mostly tested.
func is_match_over() -> bool:
	return _states.size() > 1 && living_count() <= 1


## A player's living creeps, counted as the sum of what each one costs in
## population - which is per SENDER rather than per lane, because it is a limit
## on what you have put into the world, not on what is walking through yours.
##
## Walked over the unit registry rather than tracked, for the same reason value
## is: a running total needs correcting on every spawn, death, leak and recycle,
## and one missed hook makes it wrong for the rest of the match.
func population_for(player_id: int) -> int:
	var session: MatchSession = References.match_session
	if session == null:
		return 0

	var total: int = 0
	for id in session.unit_ids():
		var creep: Creep = session.unit_for(int(id)) as Creep
		if creep != null && creep.owner_player_id == player_id && creep.stats != null:
			total += (creep.stats as CreepStats).population
	return total


## Gold standing on the field for a player: everything they have built, at what
## it cost them. Walked rather than accumulated, because a running total has to
## be corrected by every sale, every refund and every destroyed tower, and one
## missed hook makes it wrong for the rest of the match.
func value_for(player_id: int) -> int:
	var area: PlayerArea = area_for(player_id)
	if area == null:
		return 0

	var total: int = 0
	for child in area.get_children():
		var building: Building = child as Building
		if building != null:
			total += building.invested_gold
	return total


## Gives everybody who has just run out of lives their placement, erases their
## maze, and closes the match when only one is left.
##
## Placement counts DOWN from the number still playing: the first player out of
## five takes 5th, and the survivor takes 1st. So it is read off how many are
## left at the moment somebody goes, and never stored anywhere else.
func _settle_standings() -> void:
	for slot in _sorted_slots():
		var state: PlayerState = _states[slot]
		state.set_standing(value_for(slot), state.placement)
		if state.placement != 0 || !state.is_eliminated():
			continue

		state.set_standing(value_for(slot), living_count())
		Log.info("Player eliminated", {"slot": slot, "placement": state.placement})
		erase_player(slot)
		player_eliminated.emit(slot)
		_pay_catch_up_gold(slot)

	if _over || !is_match_over():
		return
	_over = true
	for slot in _sorted_slots():
		var state: PlayerState = _states[slot]
		if state.placement == 0:
			state.set_standing(value_for(slot), 1)
			Log.info("Match over", {"winner": slot})
			match_ended.emit(slot)


## Hands the player who was being attacked by `dead_slot` a one time lump for
## the attacker they have just been given instead.
##
## CATCH-UP GOLD. Losing an attacker is not a reprieve: the ring closes and the
## next player round it takes over, and that player has been fighting somebody
## else all match and may be several tiers of income ahead. The lump is a
## multiple of what the NEW attacker earns per income tick, so it scales with
## how big a step up they are, and it is paid once at the hand-over.
##
## Called after the elimination has been settled, which is what makes both
## lookups answer with the ring as it now stands: the dead player is already
## out of it, so sends_into() names the defender they were attacking and
## attacker_of() names whoever inherited them.
##
## It pays nothing in a 1v1. The ring holds one player, both walks fall back to
## that same slot, and a player cannot be handed a share of their own income -
## which is right, because a 1v1 whose second player is gone is over.
func _pay_catch_up_gold(dead_slot: int) -> void:
	var config: GameConfig = References.game_config
	if config == null || config.catch_up_gold_share <= 0.0 || living_count() < 2:
		return

	var defender_slot: int = sends_into(dead_slot)
	var attacker_slot: int = attacker_of(defender_slot)
	if defender_slot == dead_slot || attacker_slot == defender_slot:
		return

	var defender: PlayerState = state_for(defender_slot)
	var attacker: PlayerState = state_for(attacker_slot)
	if defender == null || attacker == null || defender.is_eliminated():
		return

	var bonus: int = int(round(float(attacker.income) * config.catch_up_gold_share))
	if bonus <= 0:
		return

	defender.gain(bonus)
	Log.info("Catch-up gold paid", {
		"defender": defender_slot,
		"new_attacker": attacker_slot,
		"gold": bonus,
	})


## Ascending, so two machines settle eliminations in the same order when two
## players run out on the same tick. game_rules.md says resolution is by
## execution order and is deterministic; this is that order.
func _sorted_slots() -> Array:
	var slots: Array = _states.keys()
	slots.sort()
	return slots


## Simulation, so it runs on the fixed tick rather than the render frame.
## See multiplayer.md: every machine must advance this the same way, and a
## render frame is whatever the player's GPU felt like doing.
func _physics_process(delta: float) -> void:
	# 3.4: a client runs no simulation of its own. What it draws is what the
	# server sent, so anything that would advance the world here has to stand
	# aside. See MatchSession.is_authority().
	if !MatchSession.is_authority():
		return

	if _income_interval <= 0.0 || _states.is_empty():
		return

	# Standings first: a player who ran out of lives this tick must not be paid
	# for it, and must be out before anything else reads the ring.
	_settle_standings()

	# The match is decided, so nothing accrues any more (game_rules.md). The
	# clock is left where it stopped rather than reset, since nobody is waiting
	# on it.
	if is_match_over():
		return

	_check_sudden_death()

	_income_elapsed += delta
	# A while loop rather than an if, so a long stall pays every interval it
	# covered instead of silently dropping the extras.
	while _income_elapsed >= _income_interval:
		_income_elapsed -= _income_interval
		_pay_all()


## Raises anybody under the floor to it, once, the moment Sudden Death starts.
##
## unit_data.md 1.7. What it is for is the shape of the tier it opens: tier 4
## creeps cost hundreds of thousands each, so a player who has been losing
## slowly for twenty-five minutes would reach the one tier that can end the
## match and be unable to afford any of it. The floor makes Sudden Death a
## fight rather than a formality.
##
## Income rather than gold, deliberately: it does not hand anybody a send, it
## hands them the rate at which they can start affording one.
func _check_sudden_death() -> void:
	if _sudden_death_paid:
		return

	var session: MatchSession = References.match_session
	var config: GameConfig = References.game_config
	if session == null || config == null || !session.is_sudden_death():
		return

	_sudden_death_paid = true
	if config.sudden_death_income_floor <= 0:
		return

	for player_id in _states:
		var state: PlayerState = _states[player_id]
		if state.income < config.sudden_death_income_floor:
			state.add_income(config.sudden_death_income_floor - state.income)
	Log.info("Sudden Death", {"income_floor": config.sudden_death_income_floor})


func _pay_all() -> void:
	for player_id in _states:
		var state: PlayerState = _states[player_id]
		state.pay_income()
	income_paid.emit()
