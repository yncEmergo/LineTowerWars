class_name Building
extends Unit

## A unit that occupies grid cells instead of moving: towers, and later the
## creep sending building.
##
## The footprint is claimed the moment the order completes, so a building
## still under construction blocks pathing exactly like a finished one. That
## matches WC3 and, more importantly, means the no-full-block rule cannot be
## dodged by placing a tower and mazing around it before it finishes.
##
## While building, health climbs from 1 to full over the build time, which
## doubles as the construction progress bar. Damage taken meanwhile lowers the
## result without slowing the timer, so an attacked tower finishes on schedule
## but arrives hurt.

signal construction_finished()
signal sell_started()
signal sell_cancelled()

## Height the building's visuals start at while they rise into place.
const CONSTRUCTION_START_HEIGHT: float = 0.15

@export_group("References")
## Meshes that rise during construction. Separate from the root so the health
## bar does not get squashed along with them.
@export var _visual_root: Node3D

## Top-left internal cell of this building's footprint, or -1 when unplaced.
var cell: Vector2i = Vector2i(-1, -1)
## Gold sunk into this building, which the sell refund is a share of. Upgrades
## will add to this rather than being tracked separately.
var invested_gold: int = 0

var _under_construction: bool = false
var _construction_elapsed: float = 0.0
var _selling: bool = false
var _sell_elapsed: float = 0.0
## Damage suffered while still building, kept apart from the construction ramp
## so attacks never slow the timer.
var _construction_damage: int = 0

var _building_stats: BuildingStats:
	get:
		return stats as BuildingStats


func _ready() -> void:
	super()
	if stats != null && _building_stats == null:
		Log.err("Building needs BuildingStats but got plain UnitStats", name)


## Footprint in internal cells, which is what the grid works in.
func footprint() -> Vector2i:
	if _building_stats == null || area == null:
		return Vector2i(2, 2)
	return area.cells_to_internal(_building_stats.footprint_cells)


## Anchors the building to a grid cell and starts construction.
## Call after the node is in the tree.
func place(player_id: int, home_area: PlayerArea, grid_cell: Vector2i, spent_gold: int) -> void:
	setup(player_id, home_area)
	cell = grid_cell
	invested_gold = spent_gold

	# Named after its grid cell, so the scene tree stays readable once a maze
	# has thirty towers in it rather than a wall of @Node3D@7.
	if _building_stats != null:
		name = "%s_%d_%d" % [
			_building_stats.display_name.replace(" ", ""), grid_cell.x, grid_cell.y
		]

	var size: Vector2i = footprint()
	home_area.occupy(grid_cell, size)
	global_position = home_area.footprint_world_center(grid_cell, size)
	reset_physics_interpolation()
	_begin_construction()


## A replicated tower has to claim its grid cells too, or this client would let
## the player place another one on top of it and draw a green ghost while doing
## it - the build preview reads the local grid, not the server's.
##
## The cell is DERIVED from the position rather than sent. place() puts a
## building at its footprint's world centre, so snapping that centre back gives
## the cell it came from, and the message stays one position shorter.
##
## invested_gold is a stand-in: the sell refund is quoted from it, and the real
## figure lives on the server. It is only ever read to draw a number here.
func adopt(id: int, player_id: int, home_area: PlayerArea, world_pos: Vector3) -> void:
	var session: MatchSession = References.match_session
	if session != null && session.claim_unit_id(self, id):
		unit_id = id

	global_position = world_pos
	var size: Vector2i = _adopted_footprint(home_area)
	var spent: int = 0 if _building_stats == null else _building_stats.gold_cost
	place(player_id, home_area, home_area.snap_footprint(world_pos, size), spent)


func _adopted_footprint(home_area: PlayerArea) -> Vector2i:
	if _building_stats == null:
		return Vector2i(2, 2)
	return home_area.cells_to_internal(_building_stats.footprint_cells)


## What the server says this building is doing, which on a client is the only
## thing that says so: the timers that would normally flip these are switched
## off (3.4).
func set_replicated_phase(under_construction: bool, selling: bool) -> void:
	if _under_construction && !under_construction:
		_finish_construction()
	_under_construction = under_construction
	_selling = selling


func is_under_construction() -> bool:
	return _under_construction


## A tower still going up has nothing to shoot with. A tower being sold does:
## it is standing, it still blocks the maze, and the sale can still be called
## off, so it goes on defending until it is actually gone.
func can_attack() -> bool:
	return super() && !_under_construction


func is_structure() -> bool:
	return true


## A building in the middle of something offers only that job's card, which is
## what makes construction and selling interruptible and stops anything else
## being ordered meanwhile.
func current_abilities() -> Array:
	if _building_stats != null:
		if _under_construction:
			return _building_stats.construction_abilities
		if _selling:
			return _building_stats.selling_abilities
	return super()


# --- Selling ------------------------------------------------------------

## Gold returned for selling right now.
func sell_refund() -> int:
	var ratio: float = 0.7
	var config: GameConfig = References.game_config
	if config != null:
		ratio = config.sell_refund_ratio
	return int(floor(float(invested_gold) * ratio))


## Aborts an unfinished building and returns the full price. Cancelling is not
## selling: nothing was gained, so nothing is kept.
func cancel_construction() -> void:
	if !_under_construction:
		return

	var manager: PlayerManager = References.player_manager
	if manager != null:
		var state: PlayerState = manager.state_for(owner_player_id)
		if state != null:
			state.gain(invested_gold)

	Log.info("Construction cancelled", {"building": name, "refund": invested_gold})
	queue_free()


func is_selling() -> bool:
	return _selling


## Begins a sale. The building stays standing and keeps blocking pathing for
## the whole countdown, so cancelling costs nothing and changes nothing.
func sell() -> void:
	if _selling || _under_construction:
		return

	var duration: float = 0.0
	if _building_stats != null:
		duration = _building_stats.sell_time

	if duration <= 0.0:
		_complete_sell()
		return

	_selling = true
	_sell_elapsed = 0.0
	sell_started.emit()
	# Swaps the card down to just cancel while the sale runs.
	abilities_changed.emit()


## Calls off a sale in progress and restores the normal command card.
func cancel_sell() -> void:
	if !_selling:
		return
	_selling = false
	_sell_elapsed = 0.0
	Log.info("Sale cancelled", {"building": name})
	sell_cancelled.emit()
	abilities_changed.emit()


## Removes the building and refunds its owner. The grid frees itself in
## _exit_tree, so selling and being destroyed take the same path.
func _complete_sell() -> void:
	var refund: int = sell_refund()
	var manager: PlayerManager = References.player_manager
	if manager != null:
		var state: PlayerState = manager.state_for(owner_player_id)
		if state != null:
			state.gain(refund)

	Log.info("Building sold", {"building": name, "refund": refund})
	queue_free()


# --- Construction -------------------------------------------------------

func take_damage(amount: int, damage_type: DamageTable.DamageType,
		is_aoe: bool = false) -> void:
	if amount <= 0 || is_invulnerable():
		return

	# While building, health is driven by the ramp, so damage is banked and
	# subtracted from it rather than applied directly. The matrix still applies:
	# what is banked is what the hit actually cost.
	if _under_construction:
		_construction_damage += resolve_damage(amount, damage_type, is_aoe)
		_apply_construction_health()
		return

	super(amount, damage_type, is_aoe)


func _begin_construction() -> void:
	var total: float = 0.0
	if _building_stats != null:
		total = _building_stats.build_time

	_construction_damage = 0
	_construction_elapsed = 0.0

	if total <= 0.0:
		_under_construction = false
		_apply_visual_height(1.0)
		return

	_under_construction = true
	_apply_visual_height(0.0)
	_apply_construction_health()


func _construction_progress() -> float:
	if _building_stats == null || _building_stats.build_time <= 0.0:
		return 1.0
	return clampf(_construction_elapsed / _building_stats.build_time, 0.0, 1.0)


## Health climbs from 1 to full across the build, minus anything taken on the
## way, so the bar reads as a construction progress bar.
func _apply_construction_health() -> void:
	var target: int = int(round(lerpf(1.0, float(max_health()), _construction_progress())))
	_set_health(target - _construction_damage)


func _apply_visual_height(progress: float) -> void:
	var root: Node3D = _visual_root if _visual_root != null else self
	root.scale = Vector3(1.0, lerpf(CONSTRUCTION_START_HEIGHT, 1.0, progress), 1.0)


## Simulation, so it runs on the fixed tick rather than the render frame.
## See multiplayer.md: every machine must advance this the same way, and a
## render frame is whatever the player's GPU felt like doing.
func _physics_process(delta: float) -> void:
	# 3.4: a client runs no simulation of its own. What it draws is what the
	# server sent, so anything that would advance the world here has to stand
	# aside. See MatchSession.is_authority().
	if !MatchSession.is_authority():
		return

	if _building_stats == null:
		return

	if _under_construction:
		_advance_construction(delta)
	elif _selling:
		_advance_sell(delta)


func _advance_construction(delta: float) -> void:
	_construction_elapsed += delta
	var progress: float = _construction_progress()
	_apply_visual_height(progress)
	_apply_construction_health()

	if progress >= 1.0:
		_finish_construction()


func _advance_sell(delta: float) -> void:
	_sell_elapsed += delta
	if _sell_elapsed >= _building_stats.sell_time:
		_complete_sell()


func _finish_construction() -> void:
	_under_construction = false
	_apply_visual_height(1.0)
	_set_health(max_health() - _construction_damage)
	construction_finished.emit()
	# Swaps the cancel button for the finished building's real card.
	abilities_changed.emit()


## Frees the grid again, so a sold or destroyed tower never leaves a permanent
## hole that would silently narrow the maze.
##
## super() FIRST and unconditionally, because Unit._exit_tree gives the unit id
## back and this used to return before ever reaching it - so every tower ever
## sold left its id in the registry. Harmless while nothing walked the registry;
## replication does (3.2).
func _exit_tree() -> void:
	super()
	if cell.x < 0 || !is_instance_valid(area):
		return
	area.release(cell, footprint())
	cell = Vector2i(-1, -1)
