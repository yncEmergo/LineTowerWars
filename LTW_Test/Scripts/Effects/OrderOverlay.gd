class_name OrderOverlay
extends Node3D

## Everything a player's own order chains put on the ground: a waypoint for
## each point still to be walked to, and a grey ghost for each tower ordered
## and not started yet.
##
## PRESENTATION, and local from end to end. Nothing here is an order and
## nothing here leaves the machine - it is the same kind of thing as the
## selection rings, the build preview and the range overlay. What it DRAWS is
## simulation, and that arrives the ordinary way: on the authority it reads the
## real queue, and on a client it reads the mirror the server sent (3.4). One
## code path either way, because OrderQueue.orders() answers that question -
## see ActiveAbilityState, which does the same thing for a cooldown.
##
## **Pushed rather than polled.** A queue tells this when it changes rather
## than this walking the world looking for changes, so a maze of towers costs
## nothing at all and the markers appear on the tick the order does. That is
## also why OrderQueue reaches References for it: a headless server has no
## overlay, and a null there is the whole of the answer.
##
## Two different visibility rules, deliberately:
##   ghosts     always, whether or not the builder is selected. A queued tower
##              is a decision the player made about a piece of ground, and it
##              also RESERVES that ground - see is_reserved, which is what
##              stops the next placement being aimed on top of it
##   waypoints  only while the unit is selected, as in WC3. There is one
##              builder and a handful of attacker creeps, and a lane wearing
##              every dot any of them is walking to would be unreadable

## Cells a queued tower has spoken for, as one Rect2i of cell + footprint.
var _reserved: Dictionary = {}
## unit -> Array[OrderWaypointMarker], the points it still has to walk to.
var _waypoints: Dictionary = {}
## unit -> Array[BuildPreview], the towers it has been told to place.
var _ghosts: Dictionary = {}
## The units currently selected, so a waypoint knows whether to draw.
var _selected: Dictionary = {}


func _ready() -> void:
	var selection: SelectionController = References.selection_controller
	if selection != null:
		selection.selection_changed.connect(_on_selection_changed)


## Rebuilds one unit's markers from its queue. Called by OrderQueue whenever
## the chain changes, on both machines and for the same reason.
##
## Rebuilt whole rather than patched, because a queue change is nearly always
## the head being dropped and the rest shifting up - working out which markers
## survived that would be more code than making three of them again.
func refresh_unit(unit: Unit) -> void:
	if unit == null || !is_instance_valid(unit):
		return

	_forget(unit)
	# Somebody else's chain is none of this player's business, and on a client
	# it is not even in the snapshot.
	if !unit.is_owned_by_local_player() || unit.order_queue == null:
		return

	var drawn: Array[QueuedOrder] = unit.order_queue.drawn_orders()
	if drawn.is_empty():
		return

	_waypoints[unit] = []
	_ghosts[unit] = []
	_reserved[unit] = []
	for order: QueuedOrder in drawn:
		_add_visual(unit, order)

	# Freed by _forget when the unit goes, so the markers can never outlive
	# what they belong to. The bound callable is built once and compared, not
	# `_forget` itself: a Callable carries its bound arguments, so the unbound
	# one is never the thing that got connected and the guard would pass every
	# time - one more connection per rebuild, forever.
	var on_exit: Callable = _forget.bind(unit)
	if !unit.tree_exiting.is_connected(on_exit):
		unit.tree_exiting.connect(on_exit)
	_apply_visibility(unit)


## Whether a tower this player has already ordered is standing on any of these
## cells, which makes the ground as good as taken for the next placement.
##
## Local only, and it has to be: a queued tower exists on no grid anywhere -
## not here, not on the server - until the builder actually starts it. This is
## the one thing that knows about it.
func is_reserved(area: PlayerArea, cell: Vector2i, footprint: Vector2i) -> bool:
	if area == null:
		return false

	var wanted: Rect2i = Rect2i(cell, footprint)
	for unit: Unit in _reserved:
		if !is_instance_valid(unit) || unit.area != area:
			continue
		for taken: Rect2i in _reserved[unit]:
			if taken.intersects(wanted):
				return true
	return false


# --- building the markers -------------------------------------------------

## One task's worth of ground marking. A tower gets its own shape as a ghost;
## everything else that names a point is somewhere the unit is walking to.
func _add_visual(unit: Unit, order: QueuedOrder) -> void:
	var build: BuildTowerAbility = order.ability as BuildTowerAbility
	if build != null:
		_add_ghost(unit, build, order.target_position)
		return
	_add_waypoint(unit, order.target_position)


func _add_ghost(unit: Unit, build: BuildTowerAbility, at: Vector3) -> void:
	var area: PlayerArea = unit.area
	if area == null:
		return

	# Snapped HERE as well as by the builder, with the same two calls, so the
	# ghost stands exactly where the tower will. Both are pure functions of the
	# same point, so there is no second answer to keep in step.
	var footprint: Vector2i = area.cells_to_internal(build.footprint_cells())
	var cell: Vector2i = area.snap_footprint(at, footprint)

	var ghost: BuildPreview = BuildPreview.new()
	ghost.name = "OrderGhost"
	add_child(ghost)
	ghost.setup(build.model_scene())
	ghost.show_at(area.footprint_world_center(cell, footprint), UnitModel.Tint.PENDING)

	_ghosts[unit].append(ghost)
	_reserved[unit].append(Rect2i(cell, footprint))


func _add_waypoint(unit: Unit, at: Vector3) -> void:
	# Clamped for the same reason MobileUnit.has_arrived_at clamps: an order
	# aimed past the edge of the area walks the unit as close as it can get,
	# so that is where the marker belongs. A dot outside the fence would be
	# pointing at somewhere nobody is going.
	var point: Vector3 = at
	if unit.area != null:
		point = unit.area.clamp_point(at)

	var marker: OrderWaypointMarker = OrderWaypointMarker.new()
	marker.name = "OrderWaypoint"
	add_child(marker)
	marker.place_at(point)
	_waypoints[unit].append(marker)


# --- visibility and cleanup -----------------------------------------------

func _on_selection_changed(units: Array) -> void:
	_selected.clear()
	for unit in units:
		if is_instance_valid(unit):
			_selected[unit] = true
	for unit: Unit in _waypoints:
		_apply_visibility(unit)


func _apply_visibility(unit: Unit) -> void:
	var shown: bool = _selected.has(unit)
	for marker: OrderWaypointMarker in _waypoints.get(unit, []):
		if is_instance_valid(marker):
			marker.visible = shown


## Drops everything drawn for one unit. Bound to its tree_exiting as well as
## called on every rebuild, so a builder that is somehow removed mid-chain
## takes its ghosts with it rather than leaving them standing in the maze.
func _forget(unit: Unit) -> void:
	_free_all(_waypoints.get(unit, []))
	_free_all(_ghosts.get(unit, []))
	_waypoints.erase(unit)
	_ghosts.erase(unit)
	_reserved.erase(unit)


func _free_all(nodes: Array) -> void:
	for node: Node in nodes:
		if is_instance_valid(node):
			node.queue_free()
