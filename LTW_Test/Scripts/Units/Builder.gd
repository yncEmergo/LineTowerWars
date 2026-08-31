class_name Builder
extends MobileUnit

## The player-controlled builder unit.
##
## Per game_rules.md the builder is invulnerable, has no collision and cannot
## leave its owner's area. Because it passes through towers and creeps it
## needs no pathfinding - MobileUnit's straight line movement is enough.
##
## Invulnerability needs no code: a unit only takes damage through a health
## component, and the builder's prefab has none.
##
## Building follows the WC3 undead pattern: the builder only has to be in
## range to start a tower, then walks away immediately. An order aimed further
## off walks there first and starts the tower on arrival.

## The tower this order will place, held as its STATS rather than as a prefab.
## The stats answer the footprint and the price for free, where reading them
## off a prefab meant instantiating a probe - which must not happen every
## physics frame while the builder walks to the spot.
var _pending_stats: BuildingStats = null
var _pending_cell: Vector2i = Vector2i(-1, -1)
var _pending_footprint: Vector2i = Vector2i.ZERO

var _builder_stats: BuilderStats:
	get:
		return stats as BuilderStats


## Places the builder in the middle of its own buildable zone.
func setup(player_id: int, home_area: PlayerArea) -> void:
	super(player_id, home_area)
	name = "Builder%d" % player_id
	global_position = home_area.build_zone_center()
	reset_physics_interpolation()
	stop()


# --- Building -----------------------------------------------------------

## Orders a tower at a world point. Snapped and validated up front, so an
## illegal spot is refused immediately rather than after a walk across the
## maze. Revalidated again on arrival, since the grid can change in between.
##
## Takes the tower's stats, not its prefab. The prefab is only loaded at the
## moment the tower is actually placed, see BuildingStats.scene().
func order_build(tower_stats: BuildingStats, world_target: Vector3) -> void:
	if area == null || tower_stats == null:
		Log.err("Builder cannot take a build order without an area and tower stats")
		return

	var footprint: Vector2i = area.cells_to_internal(tower_stats.footprint_cells)
	var cell: Vector2i = area.snap_footprint(world_target, footprint)
	if !area.can_place(cell, footprint, tower_stats.blocks_movement):
		Log.warn("Tower cannot be placed there", {"cell": cell})
		return

	# Gold is deliberately NOT checked here. It is taken when the tower
	# actually starts, so a CHAIN of them can be queued on one tower's worth of
	# gold and each is paid for as the builder reaches it - income accrues
	# during the walk, and one that still cannot be paid for is dropped there.
	# A plain order is refused before it ever gets here anyway, by the same
	# can_execute that greys the button.
	_pending_stats = tower_stats
	_pending_cell = cell
	_pending_footprint = footprint

	if _in_build_range(cell, footprint):
		_start_pending_build()
	else:
		move_to(area.footprint_world_center(cell, footprint))


## Stop cancels a queued build the same way it cancels movement.
func stop() -> void:
	super()
	_clear_pending()


func has_pending_build() -> bool:
	return _pending_stats != null


func _physics_process(delta: float) -> void:
	# 3.4: a client runs no simulation of its own. What it draws is what the
	# server sent, so anything that would advance the world here has to stand
	# aside. See MatchSession.is_authority().
	if !MatchSession.is_authority():
		return

	super(delta)
	if _pending_stats == null:
		return
	if _in_build_range(_pending_cell, _pending_footprint):
		_start_pending_build()


func _in_build_range(cell: Vector2i, footprint: Vector2i) -> bool:
	if area == null:
		return false

	var range_limit: float = 3.0
	if _builder_stats != null:
		range_limit = _builder_stats.build_range

	var center: Vector3 = area.footprint_world_center(cell, footprint)
	var to_center: Vector3 = center - global_position
	to_center.y = 0.0
	return to_center.length() <= range_limit


func _start_pending_build() -> void:
	var tower_stats: BuildingStats = _pending_stats
	var cell: Vector2i = _pending_cell
	var footprint: Vector2i = _pending_footprint
	_clear_pending()

	if area == null || tower_stats == null:
		return

	# Another tower may have landed here while the builder walked over.
	if !area.can_place(cell, footprint, tower_stats.blocks_movement):
		Log.warn("Build spot was taken on the way, order dropped", {"cell": cell})
		return

	# Loaded here rather than when the order was given, so a walk that ends in
	# a refused spot never pulls a prefab into memory. After the placement
	# tests, so a failed load cannot leave the spot marked as taken.
	var scene: PackedScene = tower_stats.scene()
	if scene == null:
		Log.err("Tower stats name no loadable prefab, order dropped",
			tower_stats.display_name)
		return

	# Gold is taken here rather than when the order was given, so a walk that
	# ends in a refused spot never costs anything.
	var cost: int = tower_stats.gold_cost
	var state: PlayerState = _owner_state()
	if state != null && !state.spend(cost):
		Log.warn("Not enough gold on arrival, order dropped", {"cost": cost})
		return

	var building: Building = scene.instantiate() as Building
	if building == null:
		Log.err("Tower scene root does not have a Building script")
		if state != null:
			state.gain(cost)
		return

	# Parented to the area so a player's towers live and die with it.
	area.add_child(building)
	building.place(owner_player_id, area, cell, cost)

	# Gold is on the field from this moment, so the technology choice behind it
	# is committed too and can no longer be taken back (unit_data.md 2.2's undo
	# window). Here rather than when the order was given, because a walk that
	# ended in a refused spot cost nothing and settled nothing.
	if References.tech_manager != null:
		References.tech_manager.notify_construction_started(owner_player_id)

	# The builder is free the instant the tower starts, it does not construct,
	# but it turns to face what it just started.
	_is_moving = false
	face_instantly(building.global_position)
	Log.info("Tower placed", {"cell": cell, "tower": building.name, "cost": cost})


func _owner_state() -> PlayerState:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return null
	return manager.state_for(owner_player_id)


func _clear_pending() -> void:
	_pending_stats = null
	_pending_cell = Vector2i(-1, -1)
	_pending_footprint = Vector2i.ZERO
