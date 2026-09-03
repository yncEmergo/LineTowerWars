class_name FlowField
extends RefCounted

## Distance field over one player area's internal grid, used to walk creeps to
## the end zone.
##
## A single breadth-first sweep outwards from the end zone gives every free
## cell its step count to the exit. A creep then only ever asks "which of my
## neighbours has a lower number", which is O(1) per creep per waypoint, so a
## hundred creeps cost about as much as one. Per-creep A* would instead cost a
## full search each, times again every time a tower lands in someone's path.
##
## The sweep is four-connected on purpose, matching PlayerArea's block test:
## creeps need a whole free internal cell to pass, so two towers touching at a
## corner are a wall, not a gap.
##
## Movement reads it eight-connected, because walking the field exactly as it
## was built would produce visible stair-steps. Diagonal steps are only offered
## when both neighbouring orthogonal cells are free, so a creep still never
## squeezes through a corner it could not fit through.

## Distance value for a cell no route reaches, including blocked cells.
const UNREACHABLE: int = -1

var _width: int = 0
var _depth: int = 0
## Steps from each cell to the nearest exit cell, row major like the occupancy
## grid it was built from.
var _distance: PackedInt32Array = PackedInt32Array()


## Sweeps the field. exit_first_row and everything below it is the goal, which
## is the end zone strip at the bottom of the area.
func build(occupied: PackedByteArray, width: int, depth: int, exit_first_row: int) -> void:
	var goals: Array[Vector2i] = []
	for iz in range(maxi(0, exit_first_row), depth):
		for ix in range(width):
			if occupied[iz * width + ix] == 0:
				goals.append(Vector2i(ix, iz))
	_sweep(occupied, width, depth, goals)


## Sweeps the field towards ONE cell rather than towards the end zone, which is
## what a COMMANDED walk reads: the goal is wherever a player pointed instead of
## the strip at the bottom, and every other thing about following the field -
## the diagonal smoothing, the corner test, committing to a route - is
## identical, which is why it is this class rather than an A* of its own.
##
## Affordable per order because the grid is small - an area is a thousand-odd
## internal cells - and because a creep COMMITS to what comes out of it. A
## chase re-aims itself every tick and re-plans only when its quarry crosses
## into another cell. See Creep._plan_order_route.
##
## A goal that is off the grid or inside a wall leaves the field unreachable
## everywhere, so path_from hands back nothing and the caller is free to fall
## back on walking straight at the point. PlayerArea.route_between resolves a
## blocked one before it ever gets here.
func build_to(occupied: PackedByteArray, width: int, depth: int, goal: Vector2i) -> void:
	var goals: Array[Vector2i] = []
	if _in_bounds_of(goal, width, depth) && occupied[goal.y * width + goal.x] == 0:
		goals.append(goal)
	_sweep(occupied, width, depth, goals)


## The breadth-first sweep itself, outwards from every goal cell at once. Both
## builds above are the same walk over the grid and differ only in what they
## call the goal.
func _sweep(occupied: PackedByteArray, width: int, depth: int,
		goals: Array[Vector2i]) -> void:
	_width = width
	_depth = depth
	_distance = PackedInt32Array()
	if width <= 0 || depth <= 0:
		return

	_distance.resize(width * depth)
	_distance.fill(UNREACHABLE)

	# Cells rather than flat indices, so the sweep never has to divide an index
	# back into coordinates.
	var queue: Array[Vector2i] = []
	for cell: Vector2i in goals:
		_distance[cell.y * width + cell.x] = 0
		queue.append(cell)

	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var next_distance: int = _distance[cell.y * width + cell.x] + 1

		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if next.x < 0 || next.y < 0 || next.x >= width || next.y >= depth:
				continue
			var neighbour: int = next.y * width + next.x
			if occupied[neighbour] != 0 || _distance[neighbour] != UNREACHABLE:
				continue
			_distance[neighbour] = next_distance
			queue.append(next)


func is_built() -> bool:
	return !_distance.is_empty()


func distance_at(cell: Vector2i) -> int:
	if !_in_bounds(cell):
		return UNREACHABLE
	return _distance[cell.y * _width + cell.x]


func is_reachable(cell: Vector2i) -> bool:
	return distance_at(cell) != UNREACHABLE


## True once a creep standing here has arrived, i.e. it is in the end zone.
func is_exit(cell: Vector2i) -> bool:
	return distance_at(cell) == 0


## The neighbouring cell a creep at this cell should walk to, or the cell
## itself when there is nowhere better to go.
##
## Only cells strictly closer to the exit are considered, so a creep can never
## be handed a step that leaves it no better off than standing still.
##
## Among those, diagonals cost slightly more than straight steps, so a creep
## cuts a corner only where that genuinely shortens the route: in open ground
## it walks straight down, and it goes diagonal to round a tower. Scores are in
## tenths to stay integer, 10 per orthogonal step and 14 per diagonal, the
## usual approximation of the square root of two.
func next_cell(cell: Vector2i, occupied: PackedByteArray) -> Vector2i:
	var here: int = distance_at(cell)
	if here <= 0 || here == UNREACHABLE:
		return cell

	var best: Vector2i = cell
	var best_score: int = 0

	for step in _steps():
		var candidate: Vector2i = cell + step
		var neighbour: int = distance_at(candidate)
		if neighbour == UNREACHABLE || neighbour >= here:
			continue

		var diagonal: bool = step.x != 0 && step.y != 0
		if diagonal && !_corner_open(cell, step, occupied):
			continue

		var score: int = neighbour * 10 + (14 if diagonal else 10)
		if best == cell || score < best_score:
			best_score = score
			best = candidate

	return best


## The whole route from a cell to the exit, as the cells to walk in order.
##
## Handed out as a list rather than read one step at a time because creeps
## commit to a route: a tower built behind or beside a creep must not silently
## redirect it, and one built in front only takes effect when the creep
## actually arrives at it. That needs the route it set out on to still exist
## somewhere, which a step-at-a-time lookup cannot provide.
func path_from(cell: Vector2i, occupied: PackedByteArray) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current: Vector2i = cell

	# Distance strictly decreases every step, so this cannot loop. The cell
	# count is a cheap guard in case a malformed field ever says otherwise.
	var limit: int = _width * _depth
	while path.size() < limit:
		var here: int = distance_at(current)
		if here <= 0 || here == UNREACHABLE:
			break
		var next: Vector2i = next_cell(current, occupied)
		if next == current:
			break
		path.append(next)
		current = next

	return path


## Whether a diagonal step is physically possible, i.e. both cells it cuts
## between are free. Without this a creep would slip through the join between
## two towers that only touch at a corner.
func _corner_open(cell: Vector2i, step: Vector2i, occupied: PackedByteArray) -> bool:
	return _cell_free(Vector2i(cell.x + step.x, cell.y), occupied) \
		&& _cell_free(Vector2i(cell.x, cell.y + step.y), occupied)


func _cell_free(cell: Vector2i, occupied: PackedByteArray) -> bool:
	if !_in_bounds(cell):
		return false
	return occupied[cell.y * _width + cell.x] == 0


func _in_bounds(cell: Vector2i) -> bool:
	return _in_bounds_of(cell, _width, _depth)


## Bounds test against dimensions handed in rather than against the field's
## own, so a build may ask it before the field has any.
func _in_bounds_of(cell: Vector2i, width: int, depth: int) -> bool:
	return cell.x >= 0 && cell.y >= 0 && cell.x < width && cell.y < depth


func _steps() -> Array:
	return [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
