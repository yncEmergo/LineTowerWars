class_name AiPlayer
extends Node

## One computer opponent: the brain behind one slot.
##
## **It is a LIST OF RULES run on a beat, not a state machine and not a
## planner**, and that is the shape Age of Empires II's AI has for a reason
## worth copying: every rule is a question about the world right now and an
## order if the answer is yes, so a new behaviour is a new rule rather than a
## new state somebody has to reach from everywhere else. The rules are tried in
## PRIORITY order and the pass stops at the first one that spends gold, which is
## the whole of its economy: it buys the most important thing it can afford and
## comes back on the next beat.
##
## The rules, hardest first:
##
##   1. OPENING. Spend the free research on an Ultimate, once.
##   2. MAZE. Put up the next tower in the plan.
##   3. UPGRADE. Raise a tower that is already standing.
##   4. SEND. Buy creeps for the player it is attacking.
##
## What decides how much goes to each is a FLOOR per rule rather than the order
## alone: every rule refuses to spend below its own, so gold filling up switches
## them on one at a time. Those three numbers are where an opponent's character
## actually lives - see AiProfile.
##
## **Everything it does goes down the road a player's click takes**, through
## `AiHand` into `Commands`. It has no privileged access to anything: not to
## gold, not to placement, not to the build timer. See AiHand.
##
## **It runs on the authority only**, like every other loop that advances the
## world - and the beat is counted in SIMULATION seconds rather than wall time,
## so an AI in a match that is held still for a draft does not get a free pass
## while everybody is waiting.

## How far the builder may be from a spot before the AI bothers to queue rather
## than replace - in other words, always. Kept as a named constant because the
## reason is worth stating: the builder walks, and an AI that replaced its order
## every beat would have a builder that never arrives anywhere.
const CHAIN_BUILDS: bool = true

var _slot: int = 0
var _profile: AiProfile = null
var _plan: AiMazePlan = null
## How far into the plan it has got. Entries the area refused are stepped over
## rather than retried for ever - see _consider_maze.
var _plan_index: int = 0
## Simulation seconds banked toward the next pass, and toward the next send.
var _think_clock: float = 0.0
var _send_clock: float = 0.0
## Whether the free research has been spent. A latch rather than a reading of
## what is owned, because the order takes a tick to land and a second press in
## the meantime would be refused with a line in the log every beat.
var _opening_taken: bool = false


## Hands this brain its slot and its difficulty. Called by AiDirector once the
## areas and the builders exist, because the plan is measured against the grid.
func begin(slot: int, profile: AiProfile) -> void:
	_slot = slot
	_profile = profile
	name = "AiPlayer%d" % slot

	var area: PlayerArea = _area()
	if area == null || profile == null:
		Log.err("An AI was started with no area or no profile", {"slot": slot})
		return

	_plan = AiMazePlan.for_profile(profile, area)
	# Spread the first pass across the AIs by slot, so four opponents in one
	# match do not all order their first tower on the same tick. Purely a
	# smoothing measure - nothing about the world depends on the order.
	_think_clock = float(slot) * 0.1
	Log.info("AI started", {
		"slot": slot,
		"difficulty": profile.display_name,
		"maze": _plan.size(),
	})


## The player this brain is playing for, for a name or a log line.
func slot() -> int:
	return _slot


func profile() -> AiProfile:
	return _profile


## Simulation, so it runs on the fixed tick like every other loop that advances
## the world.
func _physics_process(_engine_delta: float) -> void:
	# 3.4: only a machine that runs the world may order anything into it. Every
	# AI today plays offline, where this is always true - the guard is here
	# because it is the rule, and because the day an AI plays a networked match
	# this is the line that stops two machines ordering the same tower twice.
	if !MatchSession.is_authority() || _profile == null:
		return
	# **The SIMULATION's second, never the engine's.** The parameter is the real
	# time this frame took, which is what must not reach gameplay once a servo
	# can pace the engine - see MatchSession._sim_ticks_per_second.
	var delta: float = MatchSession.tick_seconds()

	_send_clock += delta
	_think_clock -= delta
	if _think_clock > 0.0:
		return
	_think_clock = maxf(0.05, _profile.decision_seconds)

	# A match that is decided is a match nothing more can be ordered in, and the
	# world refuses most of it anyway. Stopping here keeps the log quiet.
	var manager: PlayerManager = References.player_manager
	if manager != null && manager.is_match_over():
		return
	if _is_out(manager):
		return

	# Sloppiness, and it is the whole of it: a pass that did not happen. See
	# AiProfile.distraction_chance for why it is not a worse decision instead.
	if _profile.distraction_chance > 0.0 \
			&& MatchSession.match_rng().randf() < _profile.distraction_chance:
		return
	_think()


## One pass of the rules, in priority order, stopping at the first one that
## spent anything.
##
## **SENDING COMES BEFORE BUILDING, and that is not the obvious order.** It is
## there because of what the two rules cost: a send fires on a beat and a build
## fires whenever there is ten gold, so a build rule asked first wins every race
## and the AI never sends at all. Income compounds and a tower does not
## (game_rules.md, Economy), so the beat wins the tie.
##
## What stops that being suicidal is the floors: building refuses to spend below
## one and sending below a lower one, so the two are working from different
## parts of the same purse rather than racing for the whole of it. Nothing is
## sent at all until there is a maze standing - see
## AiProfile.min_towers_before_sending.
func _think() -> void:
	if _consider_opening():
		return
	if _consider_send():
		return
	if _consider_maze():
		return
	_consider_upgrade()


## RULE 1. The opening: the free research spent on one Ultimate.
##
## Once, and only while the allowance still covers a whole one - which is what
## TechManager refuses it on afterwards anyway, so the latch here is about not
## pressing a dead button every beat rather than about the rule.
func _consider_opening() -> bool:
	if _opening_taken || !_profile.takes_opening_ultimate:
		return false

	var manager: TechManager = References.tech_manager
	if manager == null || !manager.can_roll_random_ultimate(_slot):
		# Not YET is the usual answer here, not never: the technology registry
		# is built before this runs, but a match with no free research at all
		# never offers one. Latched either way, so it is asked once.
		_opening_taken = true
		return false

	_opening_taken = true
	AiHand.order_random_ultimate(_slot)
	return true


## RULE 2. The maze: the next tower in the plan.
##
## The builder is asked for whether it is already carrying an order, and the
## answer is deliberately allowed to be yes: a build is CHAINED behind whatever
## it is doing, exactly as holding shift does for a player, so a rich AI can
## order several walks at once instead of standing between them. What limits it
## is `builds_per_pass` and the gold, not the builder's patience.
func _consider_maze() -> bool:
	var builder: Builder = _builder()
	var state: PlayerState = _state()
	if builder == null || state == null || _plan == null:
		return false

	var ordered: int = 0
	while ordered < maxi(1, _profile.builds_per_pass):
		var entry: AiMazePlan.Entry = _plan.entry_at(_plan_index)
		if entry == null:
			return ordered > 0

		var stats: BuildingStats = _placeable_for(entry, builder)
		if stats == null:
			# Nothing on this builder's card can ever become what the plan wants
			# here. Stepped over rather than retried: the plan is content and a
			# content fault must not stall the whole maze behind it.
			Log.warn("AI cannot place a tower its maze asks for, skipping it", {
				"slot": _slot, "target": entry.target_type_id,
			})
			_plan_index += 1
			continue

		# Floor two of three: new towers are bought with what is above it, so a
		# send is never spent out from under. See AiProfile.
		if state.gold - stats.gold_cost < _floor(_profile.build_floor_gold):
			return ordered > 0
		if !_order_entry(builder, entry, stats, ordered > 0):
			return ordered > 0
		_plan_index += 1
		ordered += 1
	return ordered > 0


## One plan entry ordered, or false when the area will not take it.
##
## The cell is checked HERE as well as by the area, and that is not a second
## copy of the rule - it is what lets the plan step past an entry that can never
## work. A build order refused by the area is silent by design (a player simply
## sees no tower go up), so an AI that only submitted would sit on a blocked
## cell for the rest of the match.
func _order_entry(builder: Builder, entry: AiMazePlan.Entry, stats: BuildingStats,
		chained: bool) -> bool:
	var area: PlayerArea = _area()
	if area == null:
		return false

	var footprint: Vector2i = area.cells_to_internal(stats.footprint_cells)
	if !area.can_place(entry.cell, footprint, stats.blocks_movement):
		# Usually because something is already standing there, which after a
		# restored blueprint or a tower the plan placed earlier is normal rather
		# than wrong. Stepped over on the caller's next turn round the loop.
		_plan_index += 1
		return true

	var ability: BuildTowerAbility = AiHand.build_ability(builder, stats)
	if ability == null:
		return false

	AiHand.order_build(
		_slot, builder, ability,
		area.footprint_world_center(entry.cell, footprint),
		CHAIN_BUILDS && chained
	)
	return true


## The tower the builder can actually PLACE for one plan entry.
##
## A plan names where the maze is GOING, and most of a real maze is towers
## nothing can build directly - the builder places a 10g Basic or an Elemental
## Core and everything above them is reached by upgrading. So the entry's target
## is resolved back down to whichever buildable tower can still climb to it, and
## RULE 3 does the climbing afterwards.
##
## Falls back to the first tower on the build menu for a plan that names no
## target at all, which is what a generated zigzag from a profile with no
## opening tower produces.
func _placeable_for(entry: AiMazePlan.Entry, builder: Builder) -> BuildingStats:
	var offered: Array[BuildingStats] = AiHand.buildable_towers(builder)
	if offered.is_empty():
		return null
	if entry.target_type_id == UnitTypeRegistry.NO_TYPE:
		return offered[0]

	for stats in offered:
		if stats.unit_type_id == entry.target_type_id:
			return stats
		if AiHand.branch_reaches(stats, entry.target_type_id, {}):
			return stats
	# A target this builder cannot reach at all - a disc on a card that has
	# none, a tower from content this build does not have. The maze is built
	# with what there is rather than stalled.
	return offered[0]


## One of the profile's floors, or nothing at all while there is no maze worth
## defending yet.
##
## Counted over what is STANDING rather than over how far into the plan it has
## got, so an AI whose towers were destroyed goes back to building flat out -
## which is what a player does when a wall comes down.
func _floor(gold: int) -> int:
	if _towers_standing() < maxi(0, _profile.min_towers_before_sending):
		return 0
	return maxi(0, gold)


func _towers_standing() -> int:
	var area: PlayerArea = _area()
	if area == null:
		return 0
	var count: int = 0
	for child in area.get_children():
		var building: Building = child as Building
		if building != null && building.cell.y >= 0:
			count += 1
	return count


## RULE 3. One tower raised a rung.
##
## The one nearest the creep spawn first, which is the whole of its targeting
## policy and is the right one for a lane: a creep walks the maze from the top,
## so gold spent at the top is gold spent on every creep that enters, and gold
## spent at the bottom is only spent on the ones that got that far.
##
## Which rung it takes is the plan's business where the plan has an opinion - a
## saved maze names a target tower per cell - and the cheapest available one
## where it has not, which is what a generated maze gets. See AiHand.
func _consider_upgrade() -> bool:
	var state: PlayerState = _state()
	if !_profile.upgrades_towers || state == null:
		return false
	for tower in _towers_front_to_back():
		var ability: UpgradeTowerAbility = _upgrade_for(tower)
		if ability == null:
			continue
		# Floor three of three, and the highest: a maze that is still growing
		# needs the gold more than one tower does, so upgrading is what a RICH AI
		# does rather than what every AI does constantly.
		if state.gold - ability.gold_cost() < maxi(0, _profile.upgrade_floor_gold):
			continue
		AiHand.order_upgrade(_slot, tower, ability)
		return true
	return false


## Which upgrade this tower should take, if any.
func _upgrade_for(tower: Building) -> UpgradeTowerAbility:
	var target: int = _plan_target_at(tower.cell)
	if target != UnitTypeRegistry.NO_TYPE:
		var aimed: UpgradeTowerAbility = AiHand.upgrade_toward(tower, target)
		if aimed != null:
			return aimed
	return AiHand.cheapest_upgrade(tower)


## What the plan wanted on one cell, or nothing when the plan never named it -
## a tower the AI put somewhere the plan does not cover, or a plan with no
## opinion at all.
func _plan_target_at(cell: Vector2i) -> int:
	if _plan == null:
		return UnitTypeRegistry.NO_TYPE
	for entry in _plan.entries():
		if entry.cell == cell:
			return entry.target_type_id
	return UnitTypeRegistry.NO_TYPE


## Every tower this AI owns, nearest the creep spawn first.
##
## Walked over the area's children rather than kept as a list, for the reason
## PlayerManager.value_for walks them: a running list needs correcting by every
## sale, every destroyed tower and every upgrade that replaces a node, and one
## missed hook makes it wrong for the rest of the match.
func _towers_front_to_back() -> Array[Building]:
	var area: PlayerArea = _area()
	var found: Array[Building] = []
	if area == null:
		return found

	for child in area.get_children():
		var building: Building = child as Building
		if building == null || building.cell.y < 0:
			continue
		if building.is_under_construction() || building.is_selling() \
				|| building.is_upgrading():
			continue
		found.append(building)

	found.sort_custom(func(a: Building, b: Building) -> bool:
		if a.cell.y != b.cell.y:
			return a.cell.y < b.cell.y
		return a.cell.x < b.cell.x
	)
	return found


## RULE 4. Creeps bought for whoever it is attacking.
##
## On a beat of its own rather than every pass, because sending is the one thing
## an AI would otherwise do continuously: gold arrives on the income tick and a
## rule that fires the moment it can afford anything would spend every coin on
## the cheapest creep in the game for the whole match.
##
## What it buys is the MOST EXPENSIVE creep it can afford and still keep its
## defence reserve, which is the closest one line gets to the real rule -
## income compounds, so the biggest send you can pay for is nearly always the
## right one (game_rules.md, Economy). What it does NOT do yet is choose a creep
## for what the other player has built, which is where a harder AI has to go
## next; see Docs/singleplayer.md.
func _consider_send() -> bool:
	var state: PlayerState = _state()
	if state == null || _send_clock < maxf(1.0, _profile.send_seconds):
		return false
	# Nothing worth sending into somebody else's lane until this one can survive
	# the answer.
	if _towers_standing() < maxi(0, _profile.min_towers_before_sending):
		return false

	# **The beat is NOT reset here.** A beat that came due while the purse was
	# empty is a beat still owed: the AI sends the moment it can pay, which turns
	# an income tick into a send rather than into a wasted fifteen seconds. Only a
	# send that actually went out starts the next beat.
	# Floor one of three, and the lowest: income compounds and a tower does not.
	var spendable: int = state.gold - _floor(_profile.send_floor_gold)
	if spendable <= 0:
		return false

	var best: SendCreepAbility = null
	var best_sender: SendBuilding = null
	var best_cost: int = 0
	for sender in _senders():
		if sender.send_tier > _profile.max_send_tier:
			continue
		for send in AiHand.sends_on(sender):
			var cost: int = send.creep_stats.gold_cost
			if cost > spendable || cost <= best_cost:
				continue
			# can_execute is the SAME question the button greys itself on: the
			# stock, the start delay, the population cap and the gold. Asking it
			# is what keeps the AI from submitting orders that bounce.
			if !send.can_execute(sender):
				continue
			best = send
			best_sender = sender
			best_cost = cost

	if best == null:
		return false
	AiHand.order_send(_slot, best_sender, best)
	_send_clock = 0.0
	return true


# --- lookups --------------------------------------------------------------

func _state() -> PlayerState:
	var manager: PlayerManager = References.player_manager
	return null if manager == null else manager.state_for(_slot)


func _area() -> PlayerArea:
	var manager: PlayerManager = References.player_manager
	return null if manager == null else manager.area_for(_slot)


func _senders() -> Array[SendBuilding]:
	var area: PlayerArea = _area()
	if area == null:
		var empty: Array[SendBuilding] = []
		return empty
	return area.send_buildings()


## Whether this AI is out of the match, in which case it has no units left to
## order and nothing to order them with.
func _is_out(manager: PlayerManager) -> bool:
	if manager == null:
		return true
	var state: PlayerState = manager.state_for(_slot)
	return state == null || state.is_eliminated()


## The builder this AI commands.
##
## Found through the unit registry rather than held, because a builder is a unit
## like any other and a held reference to one would be a dangling pointer the
## moment the player it belongs to is erased from the field. Walked rather than
## indexed because it is asked once per pass, which is at most twice a second.
func _builder() -> Builder:
	var session: MatchSession = References.match_session
	if session == null:
		return null
	for unit: Unit in session.live_units():
		var builder: Builder = unit as Builder
		if builder != null && builder.owner_player_id == _slot:
			return builder
	return null
