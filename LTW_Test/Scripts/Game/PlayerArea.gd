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
## Strip above the walkable space that the send building stands on.
@export var _send_zone: MeshInstance3D
@export var _spawn_zone: MeshInstance3D
@export var _build_zone: MeshInstance3D
@export var _end_zone: MeshInstance3D
## Grid overlay over the buildable zone. Every area carries one, only the local
## player's is ever drawn.
@export var _build_grid: BuildGrid
## This area's own send building, standing on the send strip.
@export var _send_building: SendBuilding
## Parent for this area's creeps. Kept apart from the towers so crowding only
## ever iterates creeps, and so an area's creeps die with it.
@export var _creeps_root: Node3D

var player_id: int = 1

## One byte per internal cell, 1 when a building occupies it. Indexed
## iz * internal_width() + ix, so row major from the creep spawn downwards.
var _occupied: PackedByteArray = PackedByteArray()
## Route to the end zone, rebuilt whenever the occupancy grid changes.
var _flow: FlowField = FlowField.new()

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
	_occupied = PackedByteArray()
	_occupied.resize(internal_width() * internal_depth())
	_apply_layout()
	_rebuild_flow_field()
	_setup_send_building()
	_setup_build_grid()


## Sizes the prefab's ground quads and stands them in the right places.
func _apply_layout() -> void:
	var spawn_depth: float = float(_config.spawn_depth_cells) * _config.cell_size
	var build_depth: float = float(_config.build_depth_cells) * _config.cell_size
	var end_depth: float = float(_config.end_depth_cells) * _config.cell_size

	# Above the walkable space and deliberately outside the grid, so the send
	# building can never be pathed through or built on.
	_place_zone(_send_zone, _config.send_zone_start_z(), _config.send_zone_depth())
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


## The send building rides along in the prefab and only has to be told whose
## area it is standing on.
func _setup_send_building() -> void:
	if _send_building == null:
		Log.err("PlayerArea has no send building in its prefab", player_id)
		return
	_send_building.place_above(player_id, self)


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
	if _config == null:
		return 0
	return _config.area_width_cells * _config.internal_cells_per_cell


func internal_depth() -> int:
	if _config == null:
		return 0
	return _config.area_depth_cells() * _config.internal_cells_per_cell


func internal_cell_size() -> float:
	if _config == null:
		return 0.5
	return _config.internal_cell_size()


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


## Whether a footprint may be built at a cell. Checks the buildable zone, then
## occupancy, then that creeps would still have a route. Order matters: the
## path flood fill is the expensive one, so it runs last.
func can_place(cell: Vector2i, footprint: Vector2i) -> bool:
	if !_fits_build_zone(cell, footprint):
		return false
	if !_footprint_free(cell, footprint):
		return false
	return _path_exists(cell, footprint)


func occupy(cell: Vector2i, footprint: Vector2i) -> void:
	_set_footprint(cell, footprint, 1)
	_rebuild_flow_field()
	# Creeps never block placement, so anything standing where the building
	# just went up is moved aside instead. See game_rules.md.
	_displace_creeps_in(cell, footprint)


func release(cell: Vector2i, footprint: Vector2i) -> void:
	_set_footprint(cell, footprint, 0)
	_rebuild_flow_field()


func _set_footprint(cell: Vector2i, footprint: Vector2i, value: int) -> void:
	var width: int = internal_width()
	for dz in range(footprint.y):
		for dx in range(footprint.x):
			var index: int = (cell.y + dz) * width + cell.x + dx
			if index >= 0 && index < _occupied.size():
				_occupied[index] = value


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

	var blocked: PackedByteArray = _occupied.duplicate()
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
	_flow.build(_occupied, internal_width(), internal_depth(), build_zone_row_end())


## Internal cell containing a world point, unclamped, so a caller can tell an
## off-grid point from an edge one.
func world_to_internal_cell(world_pos: Vector3) -> Vector2i:
	var local: Vector3 = to_local(world_pos)
	var size: float = internal_cell_size()
	return Vector2i(int(floor(local.x / size)), int(floor(local.z / size)))


func internal_cell_center(cell: Vector2i) -> Vector3:
	var size: float = internal_cell_size()
	return to_global(Vector3(
		(float(cell.x) + 0.5) * size,
		0.0,
		(float(cell.y) + 0.5) * size
	))


## The whole route from a world point to the end zone, as internal cells in
## walking order. Empty when the point is already there or has no route.
##
## Creeps take the route once and keep it, so this is asked for a full path
## rather than a next step. See Creep for why they commit to it.
func route_to_exit(world_pos: Vector3) -> Array[Vector2i]:
	if !_flow.is_built():
		var empty: Array[Vector2i] = []
		return empty
	return _flow.path_from(world_to_internal_cell(world_pos), _occupied)


## Whether something standing here has reached the end zone.
func is_at_exit(world_pos: Vector3) -> bool:
	return _flow.is_exit(world_to_internal_cell(world_pos))


## Whether a world point is inside the area and not inside a building. Creeps
## test their next position with this rather than carrying a collider.
func is_point_free(world_pos: Vector3) -> bool:
	var cell: Vector2i = world_to_internal_cell(world_pos)
	if cell.x < 0 || cell.y < 0 || cell.x >= internal_width() || cell.y >= internal_depth():
		return false
	return _occupied[cell.y * internal_width() + cell.x] == 0


## Parent for this area's creeps, taken from the prefab. Rebuilt on the spot if
## it is missing, so a hand-assembled area still spawns creeps somewhere valid.
func creeps_root() -> Node3D:
	if _creeps_root == null || !is_instance_valid(_creeps_root):
		_creeps_root = Node3D.new()
		_creeps_root.name = "Creeps"
		add_child(_creeps_root)
	return _creeps_root


## Pushes any creep standing inside a footprint out to the nearest free spot.
func _displace_creeps_in(cell: Vector2i, footprint: Vector2i) -> void:
	if _creeps_root == null || !is_instance_valid(_creeps_root):
		return

	for child in _creeps_root.get_children():
		var creep: Creep = child as Creep
		if creep == null:
			continue

		var at: Vector2i = world_to_internal_cell(creep.global_position)
		if at.x < cell.x || at.x >= cell.x + footprint.x:
			continue
		if at.y < cell.y || at.y >= cell.y + footprint.y:
			continue

		Log.info("Creep displaced by a building", {"creep": creep.name})
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


## Nearest point not inside a building, searched outwards ring by ring from the
## cell the point falls in. Used when a tower lands on top of a creep.
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
				if _occupied[cell.y * width + cell.x] == 0:
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


## Null once it has been freed, not a dangling reference. A player who is out
## of the match has everything of theirs removed, this included, and callers
## ask "is there one" rather than "was there one".
func send_building() -> SendBuilding:
	if _send_building == null || !is_instance_valid(_send_building):
		return null
	return _send_building


## Centre of the send strip above the area, where the send building stands.
func send_zone_center() -> Vector3:
	if _config == null:
		return global_position
	return to_global(Vector3(
		_config.area_width() * 0.5,
		0.0,
		_config.send_zone_start_z() + _config.send_zone_depth() * 0.5
	))


## Centre of the buildable zone in world space. Used as the builder's start.
func build_zone_center() -> Vector3:
	if _config == null:
		return global_position
	return to_global(Vector3(
		_config.area_width() * 0.5,
		0.0,
		(_config.build_zone_start_z() + _config.build_zone_end_z()) * 0.5
	))
