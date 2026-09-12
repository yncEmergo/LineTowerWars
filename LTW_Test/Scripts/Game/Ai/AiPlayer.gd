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
## Plan entries this builder can never place at all - a target nothing on its
## card leads to. Struck off so a content fault does not cost a pass every beat.
##
## **Nothing is struck off for having been ORDERED**, and that is the fix to the
## worst bug this AI had: an order is not a tower. A build is paid for when the
## builder REACHES the spot, so a chain longer than the gold in hand has its tail
## dropped there - by design, and exactly as it is for a player. An AI that
## crossed a cell off when it ordered one therefore lost every cell it could not
## afford on arrival, silently, for the rest of the match.
##
## It scaled with builds_per_pass, which is why the profile that chained THREE
## orders a beat finished a thirty minute match with twelve towers while the one
## that ordered a single tower finished with twenty-seven. What is standing is
## the only honest record, so the plan asks the AREA instead - see
## _order_cheapest_affordable, which skips a cell something is already on.
var _done: Dictionary = {}
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
	# **Every rule gets its turn, rather than the pass stopping at the first that
	# spent.** Stopping was the first design and it looked right: one decision a
	# beat, priority order, no rule ever starving another. What it actually did
	# was starve UPGRADES for a whole match.
	#
	# The reason is that building is limited by the BUILDER'S WALK rather than by
	# gold - it crosses the lane between towers, exactly as a player's does - so
	# an AI on a million gold still orders one or two towers a beat and the maze
	# rule was answering yes to every pass for twenty-five minutes. Measured: two
	# difficulties that should have been a tier apart both ended a full match with
	# eighty-odd Basic towers, a million in the bank and nothing upgraded.
	#
	# The floors are what keep this honest: each rule refuses to spend below its
	# own, so they work from different parts of the purse rather than racing for
	# the whole of it. See AiProfile.
	_consider_send()
	_consider_maze()
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
	if manager == null:
		_opening_taken = true
		return false

	# A NAMED Ultimate where the profile has one, because which one it opens on
	# is most of a hard opponent's character - a rolled one is a rolled plan, and
	# half of them will not answer what the player is sending.
	var wanted: TechDefinition = _wanted_ultimate()
	if wanted != null:
		_opening_taken = true
		AiHand.order_ultimate(_slot, wanted.tech_id)
		return true

	if !manager.can_roll_random_ultimate(_slot):
		# Not YET is the usual answer here, not never: the technology registry
		# is built before this runs, but a match with no free research at all
		# never offers one. Latched either way, so it is asked once.
		_opening_taken = true
		return false

	_opening_taken = true
	AiHand.order_random_ultimate(_slot)
	return true


## The Ultimate this profile means to open on, or null for one that rolls.
##
## Refused rather than forced if the rules would not allow it, so an AI whose
## profile names something this match cannot give it falls through to the roll
## instead of pressing a dead button every beat.
func _wanted_ultimate() -> TechDefinition:
	var manager: TechManager = References.tech_manager
	var session: MatchSession = References.match_session
	if manager == null || session == null || _profile.ultimate_tech_id == 0:
		return null

	var path: TechDefinition = session.techs().tech_for(_profile.ultimate_tech_id)
	if path == null:
		return null
	if manager.refusal_for_ultimate(_slot, path) != TechManager.ALLOWED:
		return null
	return path


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
		if !_order_cheapest_affordable(builder, state, ordered > 0):
			break
		ordered += 1
	return ordered > 0


## Puts up the FIRST ENTRY IN THE PLAN THIS PLAYER CAN AFFORD, which is not
## always the next one.
##
## **Skipping past what it cannot pay for and coming back is the difference
## between a maze and a wall with a hole in it.** The first design walked the
## plan with a single cursor and stopped at the entry it could not afford, which
## is fine while every tower costs ten gold and fatal the moment one does not: an
## AI whose plan turns elemental part way along saves for a 200g Elemental Core
## while thirty cheap cells behind it stay empty, and the creeps walk through the
## gap. Measured twice, in opposite directions - once with the send rule draining
## the gold it was saving, and once with sending switched off so hard it earned
## nothing to save.
##
## So the plan is a SET of cells rather than a queue, and the order it is walked
## in is only a preference. Front to back still, because a lane is lost at the
## top - it simply no longer blocks.
func _order_cheapest_affordable(builder: Builder, state: PlayerState,
		chained: bool) -> bool:
	for index in range(_plan.size()):
		if _done.has(index):
			continue
		var entry: AiMazePlan.Entry = _plan.entry_at(index)
		if entry == null:
			continue

		var stats: BuildingStats = _placeable_for(entry, builder)
		if stats == null:
			# Nothing on this builder's card can ever become what the plan wants
			# here. Struck off rather than retried: the plan is content, and a
			# content fault must not cost the maze a cell every pass for ever.
			Log.warn("AI cannot place a tower its maze asks for, skipping it", {
				"slot": _slot, "target": entry.target_type_id,
			})
			_done[index] = true
			continue

		# Floor two of three: new towers are bought with what is above it, so a
		# send is never spent out from under. A cell that cannot be paid for is
		# left for later rather than waited on. See AiProfile.
		if state.gold - stats.gold_cost < _floor(_profile.build_floor_gold):
			continue
		if !_order_entry(builder, entry, stats, chained):
			continue
		return true
	return false


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
		# Something is standing there - usually a tower this plan put up - or the
		# cell is under rubble. Not ordered, not struck off: rubble clears, and a
		# tower that is destroyed leaves a cell the plan wants again.
		return false

	var ability: BuildTowerAbility = AiHand.build_ability(builder, stats)
	if ability == null:
		return false
	# **Asked before the order goes out, and the plan does NOT move on if it is
	# refused.** An Elemental Core on the beat before its technology lands is the
	# case: the order road refuses it silently, exactly as it refuses a player's,
	# and an AI that advanced anyway would lose that cell out of its maze for the
	# rest of the match.
	if !ability.can_execute(builder):
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


## What the CHEAPEST cell the maze still wants costs, plus the floor the build
## rule keeps behind it - so the send rule can leave exactly that much alone.
##
## The cheapest rather than the next, because the plan is walked for what can be
## afforded rather than in order: what the build rule will actually buy on its
## next pass is the cheapest thing left, and saving for something dearer would
## hold back gold nothing is waiting on.
##
## Zero once the plan is finished, which is when there is nothing left to save
## for and every coin should be going into sends and upgrades.
func _saving_for() -> int:
	var builder: Builder = _builder()
	if builder == null || _plan == null:
		return 0

	var cheapest: int = -1
	for index in range(_plan.size()):
		if _done.has(index):
			continue
		var stats: BuildingStats = _placeable_for(_plan.entry_at(index), builder)
		if stats == null:
			continue
		if cheapest < 0 || stats.gold_cost < cheapest:
			cheapest = stats.gold_cost
	if cheapest < 0:
		return 0
	return cheapest + _floor(_profile.build_floor_gold)


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
## **What it buys is the creep with the best INCOME FOR THE GOLD, not the most
## expensive one it can afford**, and that swap is worth a tier of difficulty on
## its own. Every creep has an implicit ratio of cost to income granted and the
## ratio gets WORSE as creeps get stronger (game_rules.md, Economy) - so an AI
## that always bought the biggest thing on the card was paying a premium for
## creeps the other player's maze killed anyway, while an AI buying cheap
## efficient ones out-earned it. Measured: the difficulty that bought big lost
## to the one below it, twice.
##
## What it does NOT do is choose a creep for what the other player has BUILT,
## which is where a harder AI has to go next; see Docs/singleplayer.md.
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
	#
	# **Except that it may never be lower than what the MAZE is saving for**, and
	# that exception is the whole of a bug worth knowing about. The next entry in
	# the plan can cost far more than this floor - a 200g Elemental Core against a
	# floor of ninety - and the send rule runs first, so it drained the purse below
	# what the build rule needed on every single pass and the maze stopped dead at
	# that cell for the rest of the match. It is not specific to Cores: any plan
	# entry dearer than the send floor starves behind it.
	#
	# Measured as a difficulty stalling twenty-nine towers into a forty-two tower
	# plan and losing to the one below it, which built its whole maze.
	var spendable: int = state.gold - maxi(
		_floor(_profile.send_floor_gold), _saving_for()
	)
	if spendable <= 0:
		return false

	var offers: Array = _affordable_sends(spendable)
	if offers.is_empty():
		return false

	var chosen: Array = _pick_send(offers)
	AiHand.order_send(_slot, chosen[0] as SendBuilding, chosen[1] as SendCreepAbility)
	_send_clock = 0.0
	return true


## Every send this player could press right now, as [sender, ability, cost,
## income-per-gold] rows.
##
## `can_execute` is the SAME question the button greys itself on - the stock, the
## start delay, the population cap and the gold - so asking it is what keeps the
## AI from submitting orders that bounce.
func _affordable_sends(spendable: int) -> Array:
	var offers: Array = []
	for sender in _senders():
		# **The cap does not apply to the SUDDEN DEATH sender**, or it silently
		# stops the AI sending anything at all once tiers 1 to 3 are retired. See
		# AiProfile.max_send_tier.
		if !sender.is_sudden_death_tier && sender.send_tier > _profile.max_send_tier:
			continue
		for send in AiHand.sends_on(sender):
			var cost: int = send.creep_stats.gold_cost
			if cost <= 0 || cost > spendable || !send.can_execute(sender):
				continue
			offers.append([
				sender, send, cost,
				float(send.creep_stats.income_gain) / float(cost),
			])
	return offers


## Which of them to buy: the BIGGEST among those that are efficient enough.
##
## See AiProfile.send_efficiency for why it is neither the biggest nor the most
## efficient outright - both were measured and both were wrong in opposite
## directions.
func _pick_send(offers: Array) -> Array:
	var best_value: float = 0.0
	for offer: Array in offers:
		best_value = maxf(best_value, float(offer[3]))

	var floor_value: float = best_value * clampf(_profile.send_efficiency, 0.0, 1.0)
	var chosen: Array = offers[0]
	var chosen_cost: int = -1
	for offer: Array in offers:
		if float(offer[3]) < floor_value || int(offer[2]) <= chosen_cost:
			continue
		chosen = offer
		chosen_cost = int(offer[2])
	return [chosen[0], chosen[1]]


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
