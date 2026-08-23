class_name SendBuilding
extends Unit

## The building creeps are bought from, one per player, standing on the strip
## above that player's own area.
##
## Extends Unit rather than Building on purpose. Building exists for things
## that claim grid cells and are constructed, sold and destroyed; this one does
## none of that. It is placed by Main at match start, never blocks a path and
## never leaves, so inheriting a footprint, a build timer and a sell countdown
## would only be machinery that has to be switched off again.
##
## It cannot be destroyed because its stats give it the invulnerable armour
## type, which is the same mechanism that keeps the builder alive, so there is
## no special case here either.
##
## It also owns the send stock, one reserve per creep type on its card. Stock
## belongs to the building rather than to the ability, because abilities are
## shared stateless resources: one send_basic_creep.tres is the same object for
## every player, so a count stored there would be everyone's count at once.

## Emitted when any reserve changes, so the command card can redraw its numbers.
signal stock_changed()

## Height above the strip the building's origin sits at, so its base rests on
## the ground. Visual only.
const GROUND_OFFSET: float = 0.0

## One reserve per creep type, keyed by that type's stats resource.
var _stocks: Dictionary = {}


func _ready() -> void:
	super()
	_create_stocks()


## Stands the building on the strip above its owner's area.
## Call after the node is in the tree.
func place_above(player_id: int, home_area: PlayerArea) -> void:
	setup(player_id, home_area)
	name = "SendBuilding%d" % player_id
	global_position = home_area.send_zone_center() + Vector3(0.0, GROUND_OFFSET, 0.0)
	reset_physics_interpolation()


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


func is_structure() -> bool:
	return true


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
		var stock: CreepStock = _stocks[key]
		if stock.advance(delta):
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

	for index in range(maxi(1, creep_stats.pack_size)):
		_spawn_one(creep_scene, creep_stats, destination)

	# Income rises per send, not per creep, so a pack and a boss are priced on
	# the same scale. See game_rules.md.
	if state != null:
		state.add_income(creep_stats.income_gain)

	Log.info("Creeps sent", {
		"type": creep_stats.display_name,
		"count": creep_stats.pack_size,
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

	var stock: CreepStock = stock_for(creep_stats)
	if stock != null && !stock.has_stock():
		return false

	var state: PlayerState = _owner_state()
	return state == null || state.can_afford(creep_stats.gold_cost)


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
