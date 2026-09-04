class_name PlayerArea
extends Node3D

## One player's own area: the walkable space made of the spawn zone, the
## buildable middle and the end zone.
##
## The area's local origin is its top-left corner, so local coordinates are
## identical to the cell coordinates used in game_rules.md: local x runs
## across the width, local z runs from the creep spawn down to the end zone.
##
## One area is one prefab, Scenes/Game/player_area.tscn: the ground zones with
## their placeholder colours, the grid overlay drawn over the buildable part,
## the send building on the strip above and the parent its creeps walk under.
## So the whole thing can be opened and looked at rather than only existing
## once the game is running.
##
## Sizes and positions are still applied from GameConfig on setup. The scene
## owns which nodes exist and what they look like, the config owns how big they
## are, so widening the area stays one number in one file.

@export_group("References")
@export var _spawn_zone: MeshInstance3D
@export var _build_zone: MeshInstance3D
@export var _end_zone: MeshInstance3D
## Grid overlay over the buildable zone. Every area carries one, only the local
## player's is ever drawn.
@export var _build_grid: BuildGrid
## This area's own senders, one per creep tier that has creeps in it.
##
## They stand NOWHERE - see SendBuilding - and ride along in this prefab only
## so that a player leaving the match takes them with them. An array because
## each creep tier has a sender of its own and each says which tier it is, so
## a tier with nothing implemented yet is simply absent from this list and the
## ones around it notice nothing. See unit_data.md 6.1.
@export var _send_buildings: Array[SendBuilding] = []
## Parent for this area's creeps. Kept apart from the towers so crowding only
## ever iterates creeps, and so an area's creeps die with it.
@export var _creeps_root: Node3D

## What one byte of `_occupied` means. A cell is free, taken by a building that
## creeps have to walk AROUND, or taken by one they walk STRAIGHT OVER.
##
## The third state is the whole of the technology disc. A disc claims its cell
## against anything else being built there and reads on the grid exactly as a
## tower does, and it is not a wall: the flow field routes through it, a creep
## standing where one goes up is left alone, and a maze made of discs is no
## maze at all. See game_rules.md, Technology discs.
const CELL_FREE: int = 0
const CELL_BLOCKED: int = 1
const CELL_WALKABLE: int = 2

var player_id: int = 1

## One byte per internal cell, one of the CELL_ values above. Indexed
## iz * internal_width() + ix, so row major from the creep spawn downwards.
##
## This is the BUILDING question: whether anything at all stands on a cell.
var _occupied: PackedByteArray = PackedByteArray()
## The same grid reduced to the MOVEMENT question: 1 where a creep may not
## walk, 0 everywhere else, so a walkable building reads as open ground.
##
## Kept alongside rather than derived on demand, because every consumer of it -
## the flow field sweep, the route walk, the free-point test a creep runs on
## its own position every tick - wants a plain "is this blocked" array and
## would otherwise each have to build one. Written only by _set_footprint, so
## the two can never drift.
var _blocking: PackedByteArray = PackedByteArray()
## Every creep walking this area, kept in step with the creeps root rather than
## asked for it. See creeps().
var _creeps: Array[Creep] = []
## The grid that answers "which creeps are near here" over that list. Built on
## first use rather than in _ready, because the config it takes its cell size
## from is reached through References and an area is built before that is
## guaranteed to be wired.
var _creep_index: CreepIndex = null
## The grid's own shape and where it sits, held rather than recomputed.
##
## is_point_free() is the single hottest call in the simulation - a walking
## creep asks it about four times a tick, once for its next waypoint and twice
## more to slide along whatever is in the way. It used to answer by calling
## to_local(), which builds an INVERSE MATRIX, and by reaching References three
## more times for the grid's width, depth and cell size. None of those four
## answers can change while a match is running, and together they were most of
## what moving a creep cost. See Docs/Findings/2026-09-03-server-tick-overrun.md.
##
## Kept in step by _refresh_grid_cache: setup() calls it, and the transform
## notification below catches an area that is moved afterwards, so this cannot
## go stale silently.
var _grid_from_world: Transform3D = Transform3D.IDENTITY
var _grid_to_world: Transform3D = Transform3D.IDENTITY
var _internal_width: int = 0
var _internal_depth: int = 0
var _internal_cell: float = 0.5
var _grid_cache_ready: bool = false
## Route to the end zone, rebuilt whenever the occupancy grid changes.
var _flow: FlowField = FlowField.new()
## Scratch field for the point-to-point routes ordered units ask for, kept
## rather than allocated per call. One field is enough because every answer is
## read straight back out in route_between before anything else can ask: the
## sweep is not a state this area carries, only the buffer it runs in.
var _order_flow: FlowField = FlowField.new()
## Internal cells a destroyed tower left rubble on, as cell index -> seconds
## left. Sparse rather than one entry per cell, because rubble is rare and a
## dictionary of three entries costs nothing to tick where a full grid would be
## a thousand writes a frame for nothing.
var _rubble: Dictionary = {}

## Read all over this class, so it comes through a getter onto References
## rather than being fetched and passed around by hand.
var _config: GameConfig:
	get:
		return References.game_config


## Builds the area for the given player. Call after the node is in the tree.
func setup(id: int) -> void:
	if _config == null:
		Log.err("PlayerArea.setup failed, no GameConfig on References")
		return

	player_id = id
	name = "PlayerArea%d" % id
	position = _config.area_origin(id)
	# After the position is set, since the cache holds the area's transform, and
	# before anything below sizes itself off internal_width/internal_depth.
	set_notify_transform(true)
	_refresh_grid_cache()
	_occupied = PackedByteArray()
	_occupied.resize(internal_width() * internal_depth())
	_blocking = PackedByteArray()
	_blocking.resize(_occupied.size())
	_apply_layout()
	_rebuild_flow_field()
	_watch_creeps()
	_setup_send_buildings()
	_setup_build_grid()


## Sizes the prefab's ground quads and stands them in the right places.
func _apply_layout() -> void:
	var spawn_depth: float = float(_config.spawn_depth_cells) * _config.cell_size
	var build_depth: float = float(_config.build_depth_cells) * _config.cell_size
	var end_depth: float = float(_config.end_depth_cells) * _config.cell_size

	_place_zone(_spawn_zone, 0.0, spawn_depth)
	_place_zone(_build_zone, _config.build_zone_start_z(), build_depth)
	_place_zone(_end_zone, _config.build_zone_end_z(), end_depth)


## One flat quad spanning the full area width, starting at start_z.
func _place_zone(zone: MeshInstance3D, start_z: float, depth: float) -> void:
	if zone == null:
		Log.err("PlayerArea is missing one of its ground zones", player_id)
		return

	var plane: PlaneMesh = zone.mesh as PlaneMesh
	if plane == null:
		Log.err("PlayerArea ground zone carries no PlaneMesh", zone.name)
		return

	plane.size = Vector2(_config.area_width(), depth)
	# PlaneMesh is centred on its origin, so offset to the zone's midpoint.
	zone.position = Vector3(_config.area_width() * 0.5, 0.0, start_z + depth * 0.5)


## The senders ride along in the prefab and only have to be told whose they
## are. Nothing is placed: they have no body to put anywhere.
func _setup_send_buildings() -> void:
	if _send_buildings.is_empty():
		Log.err("PlayerArea has no sender in its prefab", player_id)
		return
	for building in _send_buildings:
		if building != null:
			building.attach_to(player_id, self)


## Only the player building here has any use for a grid, so every other area's
## is switched off rather than drawn over someone else's maze.
func _setup_build_grid() -> void:
	if _build_grid == null:
		Log.err("PlayerArea has no build grid in its prefab", player_id)
		return

	# Every area's grid, not just the local player's. The overlay answers
	# "where can a tower go", and that is worth reading in an opponent's maze
	# as well as your own - so the toggle shows all of them together.
	_build_grid.cover_build_zone(self)


func _is_local_players() -> bool:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return true
	return player_id == manager.local_player_id()


# --- Queries ------------------------------------------------------------

## Walkable bounds in local space, as an xz rectangle.
func local_bounds() -> Rect2:
	if _config == null:
		return Rect2()
	return Rect2(0.0, 0.0, _config.area_width(), _config.area_depth())


## Walkable bounds in world space, as an xz rectangle.
func world_bounds() -> Rect2:
	var local: Rect2 = local_bounds()
	return Rect2(
		global_position.x + local.position.x,
		global_position.z + local.position.y,
		local.size.x,
		local.size.y
	)


## True if a world point lies inside this area's walkable space.
## Only x and z are considered, y is ignored.
func contains_point(world_pos: Vector3) -> bool:
	var bounds: Rect2 = world_bounds()
	# Rect2.has_point excludes the max edge, so test inclusively instead.
	return world_pos.x >= bounds.position.x && world_pos.x <= bounds.end.x \
		&& world_pos.z >= bounds.position.y && world_pos.z <= bounds.end.y


## Nearest walkable world point, clamped into this area.
func clamp_point(world_pos: Vector3) -> Vector3:
	var bounds: Rect2 = world_bounds()
	return Vector3(
		clampf(world_pos.x, bounds.position.x, bounds.end.x),
		0.0,
		clampf(world_pos.z, bounds.position.y, bounds.end.y)
	)


# --- Internal build grid ------------------------------------------------
#
# Every player cell is 2 x 2 internal cells, which is what lets towers sit on
# half cell positions while still snapping to whole numbers. Occupancy and
# path checks work entirely in internal cells; only placement snapping ever
# converts back to world space.

func internal_width() -> int:
	if !_grid_cache_ready:
		_refresh_grid_cache()
	return _internal_width


func internal_depth() -> int:
	if !_grid_cache_ready:
		_refresh_grid_cache()
	return _internal_depth


func internal_cell_size() -> float:
	if !_grid_cache_ready:
		_refresh_grid_cache()
	return _internal_cell


## Reads the grid's shape and the area's placement off the config and the node,
## once, so the hot paths above are three field reads instead of a matrix
## inverse and three trips through References.
func _refresh_grid_cache() -> void:
	var config: GameConfig = _config
	if config == null:
		return
	_internal_width = config.area_width_cells * config.internal_cells_per_cell
	_internal_depth = config.area_depth_cells() * config.internal_cells_per_cell
	_internal_cell = config.internal_cell_size()
	_grid_to_world = global_transform
	_grid_from_world = _grid_to_world.affine_inverse()
	_grid_cache_ready = true


## An area is placed once and never moves, but "never" is a claim about today's
## Main rather than a property of this class - so the cache is invalidated if it
## ever does, instead of quietly reporting cells from where the area used to be.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_grid_cache_ready = false


## First internal row of the buildable zone. Everything above is spawn.
func build_zone_first_row() -> int:
	if _config == null:
		return 0
	return _config.spawn_depth_cells * _config.internal_cells_per_cell


## One past the last internal row of the buildable zone.
func build_zone_row_end() -> int:
	if _config == null:
		return 0
	return build_zone_first_row() + _config.build_depth_cells * _config.internal_cells_per_cell


## Footprint of one player cell in internal cells.
func cells_to_internal(cells: Vector2i) -> Vector2i:
	if _config == null:
		return cells
	return cells * _config.internal_cells_per_cell


## Top-left internal cell a footprint would occupy if dropped at a world
## point. Clamped so dragging the cursor off the area still yields a legal
## cell rather than nothing to preview.
func snap_footprint(world_pos: Vector3, footprint: Vector2i) -> Vector2i:
	var local: Vector3 = to_local(world_pos)
	var size: float = internal_cell_size()
	var ix: int = int(round(local.x / size - float(footprint.x) * 0.5))
	var iz: int = int(round(local.z / size - float(footprint.y) * 0.5))
	ix = clampi(ix, 0, maxi(0, internal_width() - footprint.x))
	iz = clampi(iz, build_zone_first_row(), maxi(0, build_zone_row_end() - footprint.y))
	return Vector2i(ix, iz)


## World centre of a footprint anchored at an internal cell.
func footprint_world_center(cell: Vector2i, footprint: Vector2i) -> Vector3:
	var size: float = internal_cell_size()
	return to_global(Vector3(
		(float(cell.x) + float(footprint.x) * 0.5) * size,
		0.0,
		(float(cell.y) + float(footprint.y) * 0.5) * size
	))


## Counts rubble down. Only ever has anything to do just after a tower was
## destroyed, which is why it returns on the common case before touching
## anything.
##
## Simulation, so it runs on the fixed tick like everything else. It is only
## ever MARKED on the authority - a client is told a tower is gone but never
## why - so a client's grid simply has none, and its build ghost can read green
## over a cell the server will refuse for a few seconds. See multiplayer.md.
func _physics_process(delta: float) -> void:
	if _rubble.is_empty():
		return

	# keys() hands back a copy, so erasing while walking it is safe.
	for index: int in _rubble.keys():
		var left: float = float(_rubble[index]) - delta
		if left <= 0.0:
			_rubble.erase(index)
		else:
			_rubble[index] = left


## Leaves rubble over a footprint, blocking a rebuild there for a while.
##
## The cells are NOT re-occupied: a destroyed tower stops being a wall
## immediately and creeps walk straight over the spot. Only building there
## waits, which is what stops an attacker creep's work being undone the instant
## it finishes. unit_data.md 1.5.
func mark_rubble(cell: Vector2i, footprint: Vector2i) -> void:
	var seconds: float = 0.0 if _config == null else _config.rubble_seconds
	if seconds <= 0.0:
		return

	var width: int = internal_width()
	for dz in range(footprint.y):
		for dx in range(footprint.x):
			var index: int = (cell.y + dz) * width + cell.x + dx
			if index >= 0 && index < _occupied.size():
				_rubble[index] = seconds


## Whether a footprint may be built at a cell. Checks the buildable zone, then
## occupancy, then rubble, then that creeps would still have a route. Order
## matters: the path flood fill is the expensive one, so it runs last.
##
## `blocks` is what the building about to stand here does to the maze, and a
## walkable one skips the route test entirely rather than passing it: a disc is
## not a wall, so there is no arrangement of them that could ever seal an area
## and no reason to sweep the grid to find that out again per placement.
func can_place(cell: Vector2i, footprint: Vector2i, blocks: bool = true) -> bool:
	if !_fits_build_zone(cell, footprint):
		return false
	if !_footprint_free(cell, footprint):
		return false
	if _rubble_in(cell, footprint):
		return false
	if !blocks:
		return true
	return _path_exists(cell, footprint)


## Whether any cell of a footprint is still under rubble.
func _rubble_in(cell: Vector2i, footprint: Vector2i) -> bool:
	if _rubble.is_empty():
		return false

	var width: int = internal_width()
	for dz in range(footprint.y):
		for dx in range(footprint.x):
			if _rubble.has((cell.y + dz) * width + cell.x + dx):
				return true
	return false


## Claims a footprint for a building that has just gone up.
##
## `blocks` says which kind it is. A walkable one changes nothing about how
## creeps move, so neither the flow field nor the creeps standing on the cell
## have anything to be told - a disc going up under a creep leaves it exactly
## where it was, which is the whole point of one.
func occupy(cell: Vector2i, footprint: Vector2i, blocks: bool = true) -> void:
	_set_footprint(cell, footprint, CELL_BLOCKED if blocks else CELL_WALKABLE)
	if !blocks:
		return
	_rebuild_flow_field()
	# Creeps never block placement, so anything standing where the building
	# just went up is moved aside instead. See game_rules.md.
	_displace_creeps_in(cell, footprint)


## Gives a footprint back. Unconditional about the flow field, unlike occupy():
## what is being released is not always known to have blocked, and a sweep that
## changes nothing is cheaper than a wrong one.
func release(cell: Vector2i, footprint: Vector2i) -> void:
	_set_footprint(cell, footprint, CELL_FREE)
	_rebuild_flow_field()


func _set_footprint(cell: Vector2i, footprint: Vector2i, value: int) -> void:
	var width: int = internal_width()
	var walled: int = 1 if value == CELL_BLOCKED else 0
	for dz in range(footprint.y):
		for dx in range(footprint.x):
			var index: int = (cell.y + dz) * width + cell.x + dx
			if index >= 0 && index < _occupied.size():
				_occupied[index] = value
				_blocking[index] = walled


func _fits_build_zone(cell: Vector2i, footprint: Vector2i) -> bool:
	if cell.x < 0 || cell.y < 0:
		return false
	if cell.x + footprint.x > internal_width():
		return false
	# Towers may only stand in the buildable zone, never in the spawn or end
	# strips, so those always stay walkable.
	return cell.y >= build_zone_first_row() && cell.y + footprint.y <= build_zone_row_end()


func _footprint_free(cell: Vector2i, footprint: Vector2i) -> bool:
	var width: int = internal_width()
	for dz in range(footprint.y):
		for dx in range(footprint.x):
			if _occupied[(cell.y + dz) * width + cell.x + dx] != 0:
				return false
	return true


## Flood fills from the spawn strip to the end strip over free internal cells,
## treating the candidate footprint as already built.
##
## Four-connected on purpose: creeps need a full internal cell to pass, so
## diagonal gaps between two corner-touching towers are not a route.
## Pass a negative cell to test the grid as it stands.
func _path_exists(cell: Vector2i, footprint: Vector2i) -> bool:
	var width: int = internal_width()
	var depth: int = internal_depth()
	if width <= 0 || depth <= 0:
		return false

	var blocked: PackedByteArray = _blocking.duplicate()
	if cell.x >= 0 && cell.y >= 0:
		for dz in range(footprint.y):
			for dx in range(footprint.x):
				var index: int = (cell.y + dz) * width + cell.x + dx
				if index >= 0 && index < blocked.size():
					blocked[index] = 1

	var visited: PackedByteArray = PackedByteArray()
	visited.resize(width * depth)

	var queue: Array[Vector2i] = []
	var spawn_rows: int = build_zone_first_row()
	for iz in range(spawn_rows):
		for ix in range(width):
			var index: int = iz * width + ix
			if blocked[index] == 0 && visited[index] == 0:
				visited[index] = 1
				queue.append(Vector2i(ix, iz))

	var exit_row: int = build_zone_row_end()
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current.y >= exit_row:
			return true

		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + step
			if next.x < 0 || next.y < 0 || next.x >= width || next.y >= depth:
				continue
			var index: int = next.y * width + next.x
			if blocked[index] != 0 || visited[index] != 0:
				continue
			visited[index] = 1
			queue.append(next)

	return false


# --- Creep routing ------------------------------------------------------
#
# Creeps never path individually. One distance field is swept over the whole
# grid whenever it changes, and every creep just reads it, so a tower dropped
# into a busy maze reroutes a hundred creeps for the cost of one sweep.

func _rebuild_flow_field() -> void:
	_flow.build(_blocking, internal_width(), internal_depth(), build_zone_row_end())


## Internal cell containing a world point, unclamped, so a caller can tell an
## off-grid point from an edge one.
func world_to_internal_cell(world_pos: Vector3) -> Vector2i:
	if !_grid_cache_ready:
		_refresh_grid_cache()
	var local: Vector3 = _grid_from_world * world_pos
	return Vector2i(
		int(floor(local.x / _internal_cell)), int(floor(local.z / _internal_cell))
	)


func internal_cell_center(cell: Vector2i) -> Vector3:
	if !_grid_cache_ready:
		_refresh_grid_cache()
	return _grid_to_world * Vector3(
		(float(cell.x) + 0.5) * _internal_cell,
		0.0,
		(float(cell.y) + 0.5) * _internal_cell
	)


## The whole route from a world point to the end zone, as internal cells in
## walking order. Empty when the point is already there or has no route.
##
## Creeps take the route once and keep it, so this is asked for a full path
## rather than a next step. See Creep for why they commit to it.
func route_to_exit(world_pos: Vector3) -> Array[Vector2i]:
	if !_flow.is_built():
		var empty: Array[Vector2i] = []
		return empty
	return _flow.path_from(world_to_internal_cell(world_pos), _blocking)


## The whole route from one world point to another, as internal cells in
## walking order. Empty when the two share a cell, and empty when no route
## joins them at all - which leaves the caller free to walk straight at the
## point instead.
##
## The same shape as route_to_exit above and read exactly the same way, and it
## exists for the same reason one cell further along: a COMMANDED walk has to
## go round the maze rather than press into it, and where it is going is a spot
## the player pointed at rather than the end zone. See Creep._walk_to_order.
##
## A destination inside a wall resolves to the nearest cell that is not, so an
## order aimed at a tower routes to its face rather than to nowhere. It is the
## same rule CommandController._reachable_point_in applies to a ground click,
## asked here as well because an attack order never passes through that.
func route_between(from: Vector3, to: Vector3) -> Array[Vector2i]:
	var goal: Vector3 = clamp_point(to)
	if !is_point_free(goal):
		goal = nearest_free_point(goal)

	_order_flow.build_to(_blocking, internal_width(), internal_depth(),
		world_to_internal_cell(goal))
	return _order_flow.path_from(world_to_internal_cell(from), _blocking)


## Whether something standing here has reached the end zone.
func is_at_exit(world_pos: Vector3) -> bool:
	return _flow.is_exit(world_to_internal_cell(world_pos))


## Whether a world point is inside the area and not inside a WALL. Creeps test
## their next position with this rather than carrying a collider.
##
## A walkable building is free ground to this: it reads the movement grid, so a
## creep steps onto a technology disc exactly as it steps onto bare floor.
func is_point_free(world_pos: Vector3) -> bool:
	var cell: Vector2i = world_to_internal_cell(world_pos)
	if cell.x < 0 || cell.y < 0 || cell.x >= internal_width() || cell.y >= internal_depth():
		return false
	return _blocking[cell.y * internal_width() + cell.x] == 0


## Parent for this area's creeps, taken from the prefab. Rebuilt on the spot if
## it is missing, so a hand-assembled area still spawns creeps somewhere valid.
##
## SPAWNING is what this is for. Anything that wants to LOOK at the creeps
## wants creeps() below instead, which is the same list without the allocation.
func creeps_root() -> Node3D:
	if _creeps_root == null || !is_instance_valid(_creeps_root):
		_creeps_root = Node3D.new()
		_creeps_root.name = "Creeps"
		add_child(_creeps_root)
		_watch_creeps()
	return _creeps_root


## Every creep walking this area, in the order they arrived.
##
## THE LIST ITSELF, not a copy. Callers may only iterate it; anything that has
## to hold on to the result or sort it takes its own copy. That is the whole
## point of it existing: this is read by every tower's target search on every
## tick, and get_children() builds a fresh hundred-element array each time it
## is asked, which made those allocations the largest single cost in a loaded
## tick after the search itself.
##
## A creep that is on its way out is still in here until the frame ends,
## exactly as it was still a child before - TargetFinder._is_attackable is what
## filters those out, and that has not moved.
func creeps() -> Array[Creep]:
	return _creeps


## The creeps that MIGHT be within radius of a world point - a superset, which
## the caller narrows by testing the exact distance itself.
##
## The accelerated form of creeps() above, and the one every range question
## should ask: a tower's target search and a creep's aura sweep both used to
## read the whole lane and discard most of it. See CreepIndex, which is where
## the reasoning lives.
func creeps_near(center: Vector3, radius: float) -> Array[Creep]:
	if _creep_index == null:
		var config: GameConfig = References.game_config
		var size: float = 2.0 if config == null else config.creep_index_cell_size
		_creep_index = CreepIndex.new(size)
	return _creep_index.near(_creeps, center, radius)


## Starts keeping that list in step with the creeps root.
##
## Signals rather than a register/unregister pair the spawner has to remember
## to call, because a creep is not only added and freed: a leak RECYCLES it
## into the next player's maze with reparent(), so it leaves one area's list
## and joins another's mid match. Both signals fire on a reparent, where a call
## made at spawn time would miss it and leave the creep on two lists at once.
## See Creep._recycle.
func _watch_creeps() -> void:
	var root: Node3D = _creeps_root
	if root == null || !is_instance_valid(root):
		return

	if !root.child_entered_tree.is_connected(_on_creep_entered):
		root.child_entered_tree.connect(_on_creep_entered)
	if !root.child_exiting_tree.is_connected(_on_creep_exiting):
		root.child_exiting_tree.connect(_on_creep_exiting)

	# Whatever is already parented, so this is correct whether it is called
	# before any creep exists or after a prefab arrived with some in it.
	_creeps.clear()
	for child: Node in root.get_children():
		_on_creep_entered(child)


func _on_creep_entered(child: Node) -> void:
	var creep: Creep = child as Creep
	if creep != null && !_creeps.has(creep):
		_creeps.append(creep)


func _on_creep_exiting(child: Node) -> void:
	var creep: Creep = child as Creep
	if creep != null:
		_creeps.erase(creep)


## Pushes any creep standing inside a footprint out to the nearest free spot.
func _displace_creeps_in(cell: Vector2i, footprint: Vector2i) -> void:
	if _creeps_root == null || !is_instance_valid(_creeps_root):
		return

	for creep: Creep in _creeps:
		# A flyer reads none of this grid and neither does an ethereal creep,
		# so a tower going up under one is nothing that happened to it.
		if creep.ignores_maze():
			continue

		var at: Vector2i = world_to_internal_cell(creep.global_position)
		if at.x < cell.x || at.x >= cell.x + footprint.x:
			continue
		if at.y < cell.y || at.y >= cell.y + footprint.y:
			continue

		Log.debug("Creep displaced by a building", {"creep": creep.name})
		creep.set_back_along_path()


## Whether a creep standing here still has a way out. Always true in practice,
## because placement that would seal the area is refused, but a creep that ends
## up walled in by a teleport should not stand still forever unnoticed.
func has_route_from(world_pos: Vector3) -> bool:
	return _flow.is_reachable(world_to_internal_cell(world_pos))


## A random point for a creep to appear at: anywhere across the width, near the
## very top of the spawn zone. See game_rules.md.
func random_spawn_point(margin: float, rng: RandomNumberGenerator) -> Vector3:
	if _config == null:
		return global_position

	var inset: float = clampf(margin, 0.0, _config.area_width() * 0.5)
	var depth: float = maxf(internal_cell_size(), _config.creep_spawn_margin_cells * _config.cell_size)
	return to_global(Vector3(
		rng.randf_range(inset, _config.area_width() - inset),
		0.0,
		rng.randf_range(internal_cell_size() * 0.5, depth)
	))


## Nearest point not inside a WALL, searched outwards ring by ring from the
## cell the point falls in. Used when a tower lands on top of a creep.
##
## The movement grid, like is_point_free above: a creep pushed aside by a new
## tower may perfectly well end up standing on a technology disc, and refusing
## that would send it further than it had to go for no reason at all.
func nearest_free_point(world_pos: Vector3) -> Vector3:
	var origin: Vector2i = world_to_internal_cell(world_pos)
	var width: int = internal_width()
	var depth: int = internal_depth()

	# Zero radius first, so a point that is already clear never moves.
	for radius in range(0, maxi(width, depth)):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				# Only the ring itself, the inside was covered by earlier passes.
				if radius > 0 && absi(dx) != radius && absi(dz) != radius:
					continue
				var cell: Vector2i = Vector2i(origin.x + dx, origin.y + dz)
				if cell.x < 0 || cell.y < 0 || cell.x >= width || cell.y >= depth:
					continue
				if _blocking[cell.y * width + cell.x] == 0:
					return internal_cell_center(cell)

	Log.warn("No free cell anywhere in the area", {"player": player_id})
	return world_pos


## The building this area's owner buys creeps from. It stands on the strip
## above the walkable space, so it belongs to the area without being on its
## grid. Wanted by the boot content check now, and by the send ring later.
## The grid overlay drawn over this area's buildable zone, or null when the
## prefab has none. Exposed so the builder's toggle ability can reach it - it
## is presentation, and the ability only ever flips its visibility.
func build_grid() -> BuildGrid:
	return _build_grid


## Every sender this area still has.
##
## Freed ones are left out rather than handed back as dangling references: a
## player who is out of the match has everything of theirs removed, these
## included, and callers ask "which are there" rather than "which were there".
func send_buildings() -> Array[SendBuilding]:
	var standing: Array[SendBuilding] = []
	for building in _send_buildings:
		if building != null && is_instance_valid(building):
			standing.append(building)
	return standing



## Centre of the buildable zone in world space. Used as the builder's start.
func build_zone_center() -> Vector3:
	if _config == null:
		return global_position
	return to_global(Vector3(
		_config.area_width() * 0.5,
		0.0,
		(_config.build_zone_start_z() + _config.build_zone_end_z()) * 0.5
	))
