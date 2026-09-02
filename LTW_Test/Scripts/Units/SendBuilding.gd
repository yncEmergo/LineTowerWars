class_name SendBuilding
extends Unit

## The thing creeps are bought from: one per creep TIER per player, and NOT a
## building standing anywhere.
##
## It used to stand on a strip above the player's area. It does not any more.
## Each is reached through its own button over the unit panel, which selects it
## and puts its card on screen - so the sender is always one press away instead
## of a camera pan away, and the strip of ground it stood on is gone with it.
## `is_in_world()` is how the rest of the game is told: nothing clicks one,
## boxes one, draws it on the minimap or centres the camera on it.
##
## What it still IS, and has to be, is an ordinary Unit. A player order names a
## unit by `unit_id` over the wire and the server checks that the card really
## carries the ability, so the sender has to be a registered unit with a card
## like everything else. Only its BODY went away.
##
## Extends Unit rather than Building on purpose. Building exists for things
## that claim grid cells and are constructed, sold and destroyed; this one does
## none of that, so inheriting a footprint, a build timer and a sell countdown
## would only be machinery that has to be switched off again.
##
## It cannot be destroyed because its stats give it the invulnerable armour
## type, which is the same mechanism that keeps the builder alive, so there is
## no special case here either.
##
## It also owns the send stock, one reserve per creep type on its card. Stock
## belongs to the building rather than to the ability, because abilities are
## shared stateless resources: one send_sheep_ability.tres is the same object for
## every player, so a count stored there would be everyone's count at once.

## Emitted when any reserve changes, so the command card can redraw its numbers.
signal stock_changed()

@export_group("Settings")
## Which creep TIER this one sends, counting from 1. The source game gives each
## tier a sender of its own because a tier is twelve creeps and twelve is
## exactly one command card, and the four buttons over the unit panel are laid
## out in this order. See unit_data.md 6.1.
##
## A tier with nothing implemented yet simply has no sender at all, and its
## button is drawn dead rather than the ones around it shuffling up.
@export var send_tier: int = 1
## Whether this sender is the SUDDEN DEATH one, which inverts the whole rule
## above it: its creeps carry no start delays of their own and none of them can
## be sent until the match clock reaches Sudden Death, at which point every
## OTHER sender stops working for the rest of the match.
##
## A flag rather than a number, so the rule is not "tier 4 is special" written
## as a 4 that somebody has to recognise. See GameConfig.sudden_death_seconds
## and unit_data.md 1.7.
@export var is_sudden_death_tier: bool = false

## One reserve per creep type, keyed by that type's stats resource.
var _stocks: Dictionary = {}
## The card this sender really shows, once the creeps this match left out have
## been taken off it. Built once - the settings cannot change mid match - and
## null until then. See current_abilities().
var _allowed_abilities: Array = []
var _card_filtered: bool = false


func _ready() -> void:
	super()
	_create_stocks()


## Hands this sender to its owner. Call after the node is in the tree.
##
## No placing any more: it stands nowhere, so where its node sits in the area
## is not a position anything reads. It rides along in the area prefab purely
## so that a player leaving the match takes their senders with them, exactly as
## they take their towers.
func attach_to(player_id: int, home_area: PlayerArea) -> void:
	setup(player_id, home_area)
	name = "SendBuildingT%d_P%d" % [send_tier, player_id]


## Whose maze this building's creeps walk: the owner's RIGHT NEIGHBOUR in the
## ring (game_rules.md), which PlayerManager resolves.
##
## Asked on every send rather than cached at placement, for two reasons. The
## areas do not exist yet when this building is placed, and the answer CHANGES
## - the ring closes over an eliminated player - so a cached one would go stale
## with nothing to invalidate it.
##
## Falls back to the owner's own area, which is what a one-player run gets.
func target_area() -> PlayerArea:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return area

	var destination: PlayerArea = manager.area_for(manager.sends_into(owner_player_id))
	if destination == null:
		return area
	return destination


## The card, minus every creep this match was set up without.
##
## THE ONLY PLACE the creep set is enforced, and that is on purpose: the card
## is what a player presses and it is also what the server checks an order
## against (CommandService._is_on_card), so a creep that is not on it can
## neither be clicked nor ordered by a client that tried anyway. There is no
## second refusal in send_creeps to keep in step with this one.
##
## The square a removed creep sat in is left EMPTY rather than closed up:
## every ability authors its own slot, so the rest of the card stays exactly
## where a player learned it.
##
## Built once and kept. The settings are fixed for the whole match, and this is
## asked several times a frame by the card that draws it.
func current_abilities() -> Array:
	var entries: Array = super()
	if _card_filtered:
		return _allowed_abilities

	var settings: MatchSettings = MatchSession.match_settings()
	_allowed_abilities = []
	for entry in entries:
		var send: SendCreepAbility = entry as SendCreepAbility
		if send != null && !settings.allows_creep(send.creep_stats):
			continue
		_allowed_abilities.append(entry)
	_card_filtered = true
	return _allowed_abilities


func is_structure() -> bool:
	return true


## It stands nowhere, so nothing on the map may find it. Everything that picks
## a unit out of the world reads this - see Unit.is_in_world().
func is_in_world() -> bool:
	return false


## Never with anything, its own kind included. There are four senders and each
## draws a different card, so a selection holding two of them would have to
## pick one card to draw and quietly drop the other.
func allows_multi_selection() -> bool:
	return false


## A class of its own, kept even though allows_multi_selection() already
## refuses every mixture: the two say different things, and a class named after
## what this is stays right if that rule is ever relaxed.
func selection_class() -> StringName:
	return SELECT_SEND_BUILDING


# --- Stock --------------------------------------------------------------

## Reserve for a creep type, or null if this building cannot send it. Read by
## the command card to draw the count and the regeneration sweep.
func stock_for(creep_stats: CreepStats) -> CreepStock:
	if creep_stats == null || !_stocks.has(creep_stats):
		return null
	return _stocks[creep_stats]


## Every reserve as [unit_type_id, count] pairs, for the snapshot. Keyed by
## the CREEP TYPE rather than by a slot on the card, so re-ordering the card
## cannot silently move somebody's stock to another creep.
func stock_entries() -> Array:
	var entries: Array = []
	for key in _stocks:
		var creep_stats: CreepStats = key as CreepStats
		if creep_stats != null:
			entries.append([creep_stats.unit_type_id, (_stocks[key] as CreepStock).count])
	return entries


## A reserve handed down by the server. The regeneration that normally moves
## this number is switched off on a client (3.4), so this is the only thing
## that moves it there - and the card redraws off the same signal it always
## did.
func set_replicated_stock(creep_stats: CreepStats, count: int) -> void:
	var stock: CreepStock = stock_for(creep_stats)
	if stock == null || stock.count == count:
		return
	stock.count = count
	stock_changed.emit()


## Fills every reserve on this card at once, for the developer cheat that
## waives the start delays. It hands over a FULL card rather than a starting
## one, since having everything to hand is the whole point of asking.
func fill_all_stocks() -> void:
	var changed: bool = false
	for key in _stocks:
		if (_stocks[key] as CreepStock).fill():
			changed = true
	if changed:
		stock_changed.emit()


## One reserve per creep the card offers, built from the abilities themselves
## so adding a creep to the card is all it takes to give it a reserve.
##
## The stats come straight off the ability now. This used to instantiate and
## free every creep prefab on the card just to read its stats resource back
## out, which is exactly the probe the send ability no longer needs.
func _create_stocks() -> void:
	_stocks.clear()
	for entry in current_abilities():
		var send: SendCreepAbility = entry as SendCreepAbility
		if send == null:
			continue

		var creep_stats: CreepStats = send.creep_stats
		if creep_stats == null || _stocks.has(creep_stats):
			continue

		var stock: CreepStock = CreepStock.new()
		stock.setup(creep_stats)
		_stocks[creep_stats] = stock
## Simulation, so it runs on the fixed tick rather than the render frame.
## See multiplayer.md: every machine must advance this the same way, and a
## render frame is whatever the player's GPU felt like doing.
func _physics_process(delta: float) -> void:
	# 3.4: a client runs no simulation of its own. What it draws is what the
	# server sent, so anything that would advance the world here has to stand
	# aside. See MatchSession.is_authority().
	if !MatchSession.is_authority():
		return

	var changed: bool = false
	for key in _stocks:
		# A reserve does not exist until its creep does. Woken here rather than
		# inside the stock, because whether the wait is over is a question
		# about the match clock and about this player's cheats, and a reserve
		# knows neither.
		if !is_unlocked(key as CreepStats):
			continue

		var stock: CreepStock = _stocks[key]
		# Never both in one tick: the reserve just handed over starts its next
		# one from zero rather than from whatever the wait had left over.
		if stock.unlock():
			changed = true
		elif stock.advance(delta):
			changed = true
	if changed:
		stock_changed.emit()


# --- Sending ------------------------------------------------------------

## Buys and spawns one pack. Charges the reserve and the gold before anything
## spawns, and only spawns if both went through, so a failed send can never
## hand out free creeps or silently eat a stock.
##
## Called by SendCreepAbility, which supplies the creep's STATS. The prefab is
## loaded off those stats at the moment of the first spawn, never before.
func send_creeps(creep_stats: CreepStats) -> void:
	if creep_stats == null:
		Log.err("SendBuilding was asked to send nothing", name)
		return

	var destination: PlayerArea = target_area()
	if destination == null:
		Log.err("SendBuilding has no area to send into", name)
		return

	# Checked here as well as on the button, because the last opponent can run
	# out of lives between pressing it and the order arriving on the server.
	if !can_send(creep_stats):
		Log.info("Send refused", {"type": creep_stats.display_name})
		return

	var creep_scene: PackedScene = creep_stats.scene()
	if creep_scene == null:
		Log.err("Creep stats name no loadable prefab, send refused",
			creep_stats.display_name)
		return

	var stock: CreepStock = stock_for(creep_stats)
	if stock != null && !stock.has_stock():
		Log.info("Out of stock", {"type": creep_stats.display_name})
		return

	var state: PlayerState = _owner_state()
	if state != null && !state.spend(creep_stats.gold_cost):
		Log.warn("Not enough gold to send", {
			"cost": creep_stats.gold_cost,
			"gold": state.gold,
		})
		return

	# Taken after the gold, so a send refused for being too expensive does not
	# also cost a stock.
	if stock != null:
		stock.consume()
		stock_changed.emit()

	# The pack rather than a count, because a Sheep send is two Sheep and one
	# Timber Wolf. Everything else in the roster has a pack of one kind, and
	# reads as [[itself, 3]]. See CreepStats.pack_contents().
	for entry: Array in creep_stats.pack_contents():
		_spawn_pack_entry(entry[0] as CreepStats, int(entry[1]), creep_scene,
			creep_stats, destination)

	# Income rises per send, not per creep, so a pack and a boss are priced on
	# the same scale. See game_rules.md.
	if state != null:
		state.add_income(_income_for(creep_stats, state))

	Log.info("Creeps sent", {
		"type": creep_stats.display_name,
		"count": creep_stats.pack_creep_count(),
		"cost": creep_stats.gold_cost,
		"stock": stock.count if stock != null else -1,
	})
## Whether a send would go through right now, for greying out the slot. Asked
## by the ability, which has no state of its own to answer it with.
func can_send(creep_stats: CreepStats) -> bool:
	if creep_stats == null:
		return false

	var manager: PlayerManager = References.player_manager
	if manager != null && manager.is_match_over():
		return false
	if !is_unlocked(creep_stats):
		return false
	if is_at_population_cap():
		return false
	if _refused_for_income(creep_stats):
		return false

	var stock: CreepStock = stock_for(creep_stats)
	if stock != null && !stock.has_stock():
		return false

	var state: PlayerState = _owner_state()
	return state == null || state.can_afford(creep_stats.gold_cost)


## Whether this creep is refused outright for the sender being too rich.
##
## One creep in the roster answers yes, and only above the income cap: a
## Treasure Goblin is nothing but income, so a player already at the ceiling
## has nothing to buy with it. Refused HERE rather than refunded, which is the
## same answer the source game gives by another route - nothing is spent, so
## there is nothing to give back. See CreepStats.refused_above_income_cap.
func _refused_for_income(creep_stats: CreepStats) -> bool:
	if !creep_stats.refused_above_income_cap:
		return false

	var config: GameConfig = References.game_config
	var state: PlayerState = _owner_state()
	if config == null || state == null || config.income_cap <= 0:
		return false
	return state.income >= config.income_cap


## What one send of this creep really raises income by.
##
## Full price for everything, except a SUDDEN DEATH creep bought by a player
## already over the income cap - which pays a quarter (unit_data.md 1.7). The
## rule is here rather than on the creep because both halves of it are about
## the sender: which tier this is, and how much income that player already has.
##
## The creep's own figure is what a tooltip quotes, and the two differ only
## once a player is over the cap - which is the moment the rule is meant to
## become visible.
func _income_for(creep_stats: CreepStats, state: PlayerState) -> int:
	var config: GameConfig = References.game_config
	if config == null || !is_sudden_death_tier || config.income_cap <= 0:
		return creep_stats.income_gain
	if state.income < config.income_cap:
		return creep_stats.income_gain
	return int(round(float(creep_stats.income_gain) * config.income_share_above_cap))


## Whether the match clock has reached this creep's start delay yet.
##
## Every creep unlocks on its own, one at a time in ascending cost order, so
## this is per creep and never per tier - unit_data.md 6.1. A creep is refused
## here as well as greyed out on the card, because a client's clock is its own
## count and may be a fraction ahead of the server's.
func is_unlocked(creep_stats: CreepStats) -> bool:
	if creep_stats == null:
		return false
	return is_open() && unlock_remaining(creep_stats) <= 0.0


## Whether this sender may be used at all right now, before any single creep's
## own start delay is asked about.
##
## The Sudden Death rule and nothing else. Every sender but one is open from
## the first second and closes for good at Sudden Death; the last is closed
## until then and is the only one open afterwards. game_rules.md calls this the
## single exception to "a lower tier is never retired by a higher one".
##
## The cheat that waives start delays opens everything, which is the whole
## point of it: tier 4 is otherwise twenty-five minutes away from being
## testable at all.
func is_open() -> bool:
	var state: PlayerState = _owner_state()
	if state != null && state.creeps_unlocked:
		return true

	var session: MatchSession = References.match_session
	if session == null:
		return !is_sudden_death_tier
	return session.is_sudden_death() == is_sudden_death_tier


## Seconds still to wait before this creep can be sent, or 0 once it can.
##
## The command card draws this in the middle of the slot, so a player waiting
## on a creep reads HOW LONG rather than only that it is not ready yet. One
## question with two callers on purpose: the greying and the number can never
## disagree about when the wait ends.
##
## Answered here rather than on the ability because the ability is shared by
## every player and this is not: the cheat that waives the wait is granted to
## whoever pressed it, and only the building knows whose card this is.
func unlock_remaining(creep_stats: CreepStats) -> float:
	if creep_stats == null:
		return 0.0

	var state: PlayerState = _owner_state()
	if state != null && state.creeps_unlocked:
		return 0.0

	var session: MatchSession = References.match_session
	if session == null:
		return 0.0
	# The Sudden Death sender's creeps carry no start delays of their own: the
	# whole tier arrives at once, so what a slot counts down to is the clock
	# rather than anything on the creep.
	if is_sudden_death_tier:
		return maxf(0.0, session.sudden_death_remaining())
	return maxf(0.0, creep_stats.unlock_seconds - session.elapsed_seconds())


## Whether this player is at their population ceiling.
##
## AT it, not over it: a send is refused from the cap upwards, and a player at
## 98 of 100 may still send a pack of three and end up at 101. Population is
## charged per creep, so what a send costs is not a whole number of slots and
## refusing a partial one would make the last few unusable. See game_rules.md.
func is_at_population_cap() -> bool:
	var config: GameConfig = References.game_config
	var manager: PlayerManager = References.player_manager
	if config == null || manager == null || config.population_cap <= 0:
		return false
	return manager.population_for(owner_player_id) >= config.population_cap


## One kind of creep out of a pack, however many of it the pack holds.
##
## The prefab of the creep that was BOUGHT is already loaded and comes in
## rather than being looked up again; a companion loads its own. A companion
## whose prefab is missing is skipped with a message rather than taking the
## whole send down - the pack that could be sent still is.
func _spawn_pack_entry(entry_stats: CreepStats, count: int, bought_scene: PackedScene,
		bought_stats: CreepStats, destination: PlayerArea) -> void:
	if entry_stats == null || count <= 0:
		return

	var scene: PackedScene = bought_scene if entry_stats == bought_stats else entry_stats.scene()
	if scene == null:
		Log.err("Creep in a pack names no loadable prefab, it was left out",
			entry_stats.display_name)
		return

	for index in range(count):
		_spawn_one(scene, entry_stats, destination)


## One creep, at its own random spot in the spawn zone. Each rolls separately,
## so a pack arrives spread across the width rather than in a line.
func _spawn_one(creep_scene: PackedScene, creep_stats: CreepStats, destination: PlayerArea) -> void:
	var creep: Creep = creep_scene.instantiate() as Creep
	if creep == null:
		Log.err("Creep scene root does not have a Creep script")
		return

	destination.creeps_root().add_child(creep)
	var spawn_point: Vector3 = destination.random_spawn_point(
		creep_stats.body_radius, MatchSession.match_rng()
	)
	creep.spawn(owner_player_id, destination, spawn_point)


func _owner_state() -> PlayerState:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return null
	return manager.state_for(owner_player_id)
