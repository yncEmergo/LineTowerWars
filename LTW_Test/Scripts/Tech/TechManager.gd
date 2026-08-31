class_name TechManager
extends Node

## Every rule of the technology system, in one place: what a technology costs,
## what has to be owned before it, what buying one does, and how long it can be
## taken back.
##
## A node in the match scene, next to PlayerManager, and reached through
## References. Not an autoload, because it is not an `@rpc` endpoint - a
## research order travels down the road every other player order takes, which
## is `Commands`, and arrives here already checked for who sent it.
##
## **The rules live HERE and nowhere else.** CommandService validates the
## SENDER and then hands the order over exactly as it hands a unit order to the
## ability that runs it, so there is no second copy of the price or the
## prerequisite on the server side. A single player run reaches the same
## methods through the same road.
##
## What it does NOT hold is per-player state: what a player owns is on their
## PlayerState, the same place their gold is. This is the rules, they are the
## record.
##
## Nothing here knows about towers, which is deliberate and is why it can be
## finished before they exist: a technology unlocks nothing by pointing at
## anything. A tower will ask `owns()` for the id it needs, from its own side.

## Reason strings a refused order comes back with, so the caller does not have
## to guess why. Empty means it went through.
const ALLOWED: String = ""

var _config: GameConfig:
	get:
		return References.game_config

var _players: PlayerManager:
	get:
		return References.player_manager

var _session: MatchSession:
	get:
		return References.match_session


## Closes undo windows that have run out. Simulation, so it runs on the fixed
## tick: the deadline is a tick number and a render frame is whatever the
## player's GPU felt like doing.
func _physics_process(_delta: float) -> void:
	# 3.4: a client runs no simulation of its own, and an undo window is the
	# server's clock. What is left of it arrives in the snapshot.
	if !MatchSession.is_authority():
		return

	var session: MatchSession = _session
	var players: PlayerManager = _players
	if session == null || players == null:
		return

	var tick: int = session.tick()
	for slot in range(1, session.player_count() + 1):
		var state: PlayerState = players.state_for(slot)
		if state != null:
			state.tech.expire_history(tick)


# --- questions ------------------------------------------------------------

## Whether a player has researched something, by id. The one question a tower
## will ask, which is why it takes an id rather than a resource.
func owns(player_id: int, tech_id: int) -> bool:
	var tech: PlayerTech = _tech_of(player_id)
	return tech != null && tech.has(tech_id)


## What the NEXT technology costs this player, whichever one it is.
##
## The price is a property of how many they have already bought rather than of
## the technology itself (unit_data.md 2.2): the first four are free and each
## one after that costs a step more than the last. So every square in the
## Research Center quotes the same number, and that number climbs as the grid
## fills.
func cost_of_next(player_id: int) -> int:
	var tech: PlayerTech = _tech_of(player_id)
	if tech == null:
		return 0
	return _cost_at(tech.owned_count())


## How many free technologies this player has left, for the tooltip that says
## so. Never negative.
func free_left(player_id: int) -> int:
	var tech: PlayerTech = _tech_of(player_id)
	if tech == null:
		return 0
	return maxi(0, _free_count() - tech.owned_count())


## Why this player cannot research this right now, or ALLOWED when they can.
##
## One method rather than a bool and a separate explanation, because the two
## can never be allowed to disagree: the tooltip says what the button would
## refuse, and the server refuses with the very same call.
func refusal_for(player_id: int, tech: TechDefinition) -> String:
	if tech == null:
		return "no such technology in this build"

	var state: PlayerState = _state_of(player_id)
	if state == null:
		return "no such player"
	if state.tech.has(tech.tech_id):
		return "already researched"

	var missing: TechDefinition = _missing_prerequisite(state.tech, tech)
	if missing != null:
		return "requires %s" % missing.display_name

	var cost: int = _cost_at(state.tech.owned_count())
	if !state.can_afford(cost):
		return "costs %s gold" % StringUtil.compact_number(cost)
	return ALLOWED


func can_research(player_id: int, tech: TechDefinition) -> bool:
	return refusal_for(player_id, tech) == ALLOWED


## Ticks left on this player's undo window, or 0 when there is nothing to take
## back. Drives the Undo button, which is why it is a number rather than a
## bool: the button says how long is left.
func undo_ticks_left(player_id: int) -> int:
	var tech: PlayerTech = _tech_of(player_id)
	return 0 if tech == null else tech.undo_ticks_left()


## Whether there is any Ultimate this player could complete right now, which is
## the whole of what the random button needs to know before it is pressed.
func can_roll_random_ultimate(player_id: int) -> bool:
	var state: PlayerState = _state_of(player_id)
	return state != null && !_affordable_ultimates(state).is_empty()


## The four technologies one Ultimate tower needs (unit_data.md 2.3): its own
## element's Basic and path, and the Basic and path of the one other element
## that path names.
##
## Empty for a Basic technology, which leads to no Ultimate of its own.
func ultimate_requirement(tech: TechDefinition) -> Array[TechDefinition]:
	var needed: Array[TechDefinition] = []
	if tech == null || !tech.is_path():
		return needed

	var registry: TechRegistry = _registry()
	if registry == null:
		return needed

	var cross: TechDefinition = registry.tech_for(tech.ultimate_cross_tech_id)
	_append_tech(needed, registry.basic_for(tech.element))
	_append_tech(needed, tech)
	if cross != null:
		_append_tech(needed, registry.basic_for(cross.element))
		_append_tech(needed, cross)
	return needed


# --- orders ---------------------------------------------------------------

## The far end of the road a Research Center press takes. Called by
## CommandService once it knows WHO is asking, and never called directly by
## anything a player touches.
##
## Returns the reason it was refused, or ALLOWED. CommandService turns a reason
## into the rejection it logs, so the refusal is written once, here, where the
## rule is.
func apply_order(player_id: int, action: Command.PlayerAction, tech_id: int) -> String:
	match action:
		Command.PlayerAction.RESEARCH:
			var registry: TechRegistry = _registry()
			if registry == null:
				return "this build contains no technologies"
			return research(player_id, registry.tech_for(tech_id))
		Command.PlayerAction.UNDO_RESEARCH:
			return undo(player_id)
		Command.PlayerAction.RANDOM_ULTIMATE:
			return roll_random_ultimate(player_id)
		_:
			return "not a player order"


## Buys one technology. Every rule it can break is checked here first, so the
## gold and the grant can never come apart.
func research(player_id: int, tech: TechDefinition) -> String:
	var reason: String = refusal_for(player_id, tech)
	if reason != ALLOWED:
		return reason

	var state: PlayerState = _state_of(player_id)
	var cost: int = _cost_at(state.tech.owned_count())
	if !state.spend(cost):
		# refusal_for already asked, so this is a rule changing under the order.
		return "costs %s gold" % StringUtil.compact_number(cost)

	state.tech.grant(tech.tech_id)
	state.tech.push_purchase(TechPurchase.create(
		PackedInt32Array([tech.tech_id]), cost, _undo_deadline()
	))
	Log.info("Technology researched", {
		"player": player_id, "tech": tech.display_name, "cost": cost,
	})
	return ALLOWED


## Takes back the most recent press, giving the gold and the technologies back.
##
## Only ever the MOST RECENT one, and only inside its own window. That keeps
## the refund exact: the price depends on how many were owned at the time, so
## anything but last-in-first-out would give back a number that was never
## charged. Two presses inside one window can both be taken back, newest first.
func undo(player_id: int) -> String:
	var state: PlayerState = _state_of(player_id)
	if state == null:
		return "no such player"

	var session: MatchSession = _session
	var tick: int = 0 if session == null else session.tick()
	var record: TechPurchase = state.tech.pop_purchase(tick)
	if record == null:
		return "nothing left to undo"

	for tech_id in record.tech_ids:
		state.tech.revoke(tech_id)
	state.gain(record.gold_paid)
	state.tech.expire_history(tick)

	Log.info("Technology undone", {
		"player": player_id, "count": record.tech_ids.size(), "refund": record.gold_paid,
	})
	return ALLOWED


## Picks one Ultimate tower at random and buys everything still missing from
## its four-technology requirement, as ONE press that can be undone whole.
##
## Rolled over the Ultimates this player could actually complete, so the button
## never spends a click on an answer it cannot pay for. At the start of a match
## the free technologies cover one Ultimate exactly, so that is all twenty of
## them - which is the standard opening the design is built around
## (unit_data.md 2.3).
func roll_random_ultimate(player_id: int) -> String:
	var state: PlayerState = _state_of(player_id)
	if state == null:
		return "no such player"

	var affordable: Array = _affordable_ultimates(state)
	if affordable.is_empty():
		return "no Ultimate can be afforded"

	# The shared match RNG, never the global one: the server rolls and every
	# machine has to be able to arrive at the same world from the same seed.
	var index: int = MatchSession.match_rng().randi_range(0, affordable.size() - 1)
	return _buy_batch(player_id, state, affordable[index] as Array)


## Developer cheat: hands one player every technology in the build, free.
##
## Here rather than beside the gold cheat in CommandService, because what a
## grant costs the record is a technology rule - the undo history has to go
## with it, and this is the file that knows that. CommandService still owns
## the question of whether cheats are on at all.
##
## Nothing is charged and nothing is refusable, so the only reason it comes
## back with is a machine that has nobody in that slot or no technologies.
func grant_all(player_id: int) -> String:
	var state: PlayerState = _state_of(player_id)
	if state == null:
		return "no such player"

	var registry: TechRegistry = _registry()
	if registry == null:
		return "this build contains no technologies"

	for tech in registry.all():
		state.tech.grant(tech.tech_id)

	# No press is left to take back. An undo after this would refund gold that
	# was never charged and revoke a technology the cheat has just handed over,
	# so the window closes exactly as it does when a build commits gold.
	state.tech.forget_history()

	Log.info("Cheat: technologies unlocked", {"player": player_id})
	return ALLOWED


## Closes this player's undo window for good. Called the moment they commit
## gold to the field, because a tower bought under a technology must not be
## left standing by a technology that is given back.
func notify_construction_started(player_id: int) -> void:
	if !MatchSession.is_authority():
		return
	var tech: PlayerTech = _tech_of(player_id)
	if tech != null:
		tech.forget_history()


# --- the price ------------------------------------------------------------

## What the technology after `owned` of them costs. The first few are free and
## each paid one costs a step more than the one before (unit_data.md 2.2).
func _cost_at(owned: int) -> int:
	var paid_index: int = owned - _free_count()
	if paid_index < 0:
		return 0
	return _cost_step() * (paid_index + 1)


## What it costs to buy `count` more in one press, which is not `count` times
## anything: every one of them raises the price of the next.
func _batch_cost(owned: int, count: int) -> int:
	var total: int = 0
	for step in range(count):
		total += _cost_at(owned + step)
	return total


func _free_count() -> int:
	var config: GameConfig = _config
	return 0 if config == null else maxi(0, config.free_technologies)


func _cost_step() -> int:
	var config: GameConfig = _config
	return 0 if config == null else maxi(0, config.technology_cost_step)


## The tick this player's undo window would close on, were a press made now.
func _undo_deadline() -> int:
	var session: MatchSession = _session
	var seconds: float = 0.0
	if _config != null:
		seconds = maxf(0.0, _config.technology_undo_seconds)

	var ticks: int = ceili(seconds / MatchSession.tick_seconds())
	return (0 if session == null else session.tick()) + ticks


# --- the random roll ------------------------------------------------------

## Every Ultimate this player could complete right now, as the list of
## technologies each one still needs. In path id order, so the roll is over the
## same list on every machine.
func _affordable_ultimates(state: PlayerState) -> Array:
	var registry: TechRegistry = _registry()
	if registry == null:
		return []

	var owned: int = state.tech.owned_count()
	var affordable: Array = []
	for path in registry.path_techs():
		var missing: Array[TechDefinition] = _missing_of(state.tech, path)
		if missing.is_empty():
			continue
		if state.can_afford(_batch_cost(owned, missing.size())):
			affordable.append(missing)
	return affordable


## What one Ultimate still needs, in the order it would be bought: an element's
## Basic always before the path that rests on it.
func _missing_of(tech: PlayerTech, path: TechDefinition) -> Array[TechDefinition]:
	var missing: Array[TechDefinition] = []
	for needed in ultimate_requirement(path):
		if !tech.has(needed.tech_id):
			missing.append(needed)
	return missing


## Buys a whole set as one press. Charged once and recorded once, so undoing it
## gives back the set rather than picking it apart.
func _buy_batch(player_id: int, state: PlayerState, batch: Array) -> String:
	var cost: int = _batch_cost(state.tech.owned_count(), batch.size())
	if !state.spend(cost):
		return "costs %s gold" % StringUtil.compact_number(cost)

	var ids: PackedInt32Array = PackedInt32Array()
	for entry in batch:
		var tech: TechDefinition = entry as TechDefinition
		state.tech.grant(tech.tech_id)
		ids.append(tech.tech_id)

	state.tech.push_purchase(TechPurchase.create(ids, cost, _undo_deadline()))
	Log.info("Random Ultimate researched", {
		"player": player_id, "count": ids.size(), "cost": cost,
	})
	return ALLOWED


# --- lookups --------------------------------------------------------------

## The element Basic a path technology rests on, when it is not owned yet.
## Null when nothing is missing, which includes every Basic technology - those
## rest on nothing.
func _missing_prerequisite(tech: PlayerTech, wanted: TechDefinition) -> TechDefinition:
	if !wanted.is_path():
		return null

	var registry: TechRegistry = _registry()
	if registry == null:
		return null

	var basic: TechDefinition = registry.basic_for(wanted.element)
	if basic == null || tech.has(basic.tech_id):
		return null
	return basic


func _registry() -> TechRegistry:
	var session: MatchSession = _session
	return null if session == null else session.techs()


func _state_of(player_id: int) -> PlayerState:
	var players: PlayerManager = _players
	return null if players == null else players.state_for(player_id)


func _tech_of(player_id: int) -> PlayerTech:
	var state: PlayerState = _state_of(player_id)
	return null if state == null else state.tech


func _append_tech(into: Array[TechDefinition], tech: TechDefinition) -> void:
	if tech != null && !(tech in into):
		into.append(tech)
