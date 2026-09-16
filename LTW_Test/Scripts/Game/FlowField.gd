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
##
## And a creep does not walk that route cell by cell either: aims_along turns
## it into straight lines between the corners it actually has to go round.

## Distance value for a cell no route reaches, including blocked cells.
const UNREACHABLE: int = -1

## The four steps the SWEEP takes, and the eight a walker reads.
##
## Constants rather than literals because both used to be built inside the
## loops that read them: the four-element one was allocated once per DEQUEUED
## CELL - so once per free cell of the area, on every sweep, and a sweep runs on
## every tower placed or sold in every lane - and _steps() returned a fresh
## eight-element array on every next_cell call, which is once per step of every
## route ever walked. The order of both is preserved exactly, so every route
## that came out of them before comes out of them now.
const SWEEP_STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const WALK_STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

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
	build_to_any(occupied, width, depth, [goal])


## The same sweep towards a SET of cells rather than one, which is what an
## ATTACK order asks for.
##
## **An attack order's destination was never a point.** It is every cell the
## target can be hit from, and which of those is nearest is a question only the
## search can answer. Handing the search one cell picked in advance is choosing
## before the information exists - and the cell that looks nearest by straight
## line is routinely the far face of a tower, which in a maze is round the
## outside of a wall. Straight-line distance is not walking distance, and a
## maze is built out of U-shapes on purpose.
##
## Seeded together, every cell of the ring starts at zero and the field hands
## the walker whichever is nearest BY ROUTE: the cell on its own side of the
## wall is one step away and wins, the one three metres off through the maze is
## forty steps away and does not. The near face falls out of the search for
## free and is correct by construction rather than by a rule that could be
## tuned wrong.
##
## **The seed order provably cannot matter.** Every seed enters at distance
## zero, and a breadth-first sweep from a zero-distance set gives every cell the
## same minimum whatever order the seeds were queued in; next_cell and path_from
## then read only the distance field and a fixed step order. So this is safe
## under lockstep by construction rather than by the caller happening to build
## its list in a fixed order.
##
## Goals off the grid or inside a wall are DROPPED rather than refused, so a
## ring half buried in a maze still sweeps to the half that is not. An empty set
## leaves the field unreachable everywhere, which is the same answer build_to
## always gave for a blocked goal.
func build_to_any(occupied: PackedByteArray, width: int, depth: int,
		goals: Array[Vector2i]) -> void:
	var kept: Array[Vector2i] = []
	for cell: Vector2i in goals:
		if _in_bounds_of(cell, width, depth) && occupied[cell.y * width + cell.x] == 0:
			kept.append(cell)
	_sweep(occupied, width, depth, kept)


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

		for step: Vector2i in SWEEP_STEPS:
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

	for step: Vector2i in WALK_STEPS:
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


## Where the straight lines of a route go: for every cell of a path_from route,
## the index of the corner a creep walking towards that cell may head for
## instead, in one straight line.
##
## The cell route is what the field says and stays the authority on WHICH way
## round the maze a creep goes. Walked cell by cell it is a staircase, and every
## creep on it is funnelled onto the same few cells long before it has to be:
## two creeps spawning a lane apart would run along the top edge together and
## only then turn down. Walking corner to corner instead is the shortest line
## through the same corridor, from wherever each creep actually started.
##
## Greedy from the start cell: the furthest cell still in plain sight becomes a
## corner, and the search starts again from there. Found by galloping and then
## halving rather than by testing every cell in turn, so a long open stretch
## costs a handful of line tests rather than one per cell. Every corner handed
## out is one whose line was actually tested clear, whatever the search skipped.
##
## Worked out against cell CENTRES. A creep standing elsewhere in its cell tests
## its own line again before it trusts one - see PlayerArea.can_walk_straight.
func aims_along(start: Vector2i, path: Array[Vector2i], occupied: PackedByteArray,
		clearance: float) -> PackedInt32Array:
	var aims: PackedInt32Array = PackedInt32Array()
	var size: int = path.size()
	aims.resize(size)

	var anchor: Vector2 = _center_of(start)
	var first: int = 0
	while first < size:
		# The next cell along is always a legal step from the anchor, so the
		# search only ever has to decide how much further than that to go.
		var good: int = first
		var bad: int = size
		var stride: int = 1
		while good + stride < size:
			var probe: int = good + stride
			if !is_line_clear(anchor, _center_of(path[probe]), occupied, clearance):
				bad = probe
				break
			good = probe
			stride *= 2
		if bad == size && good < size - 1:
			if is_line_clear(anchor, _center_of(path[size - 1]), occupied, clearance):
				good = size - 1
			else:
				bad = size - 1
		while bad - good > 1:
			var middle: int = (good + bad) >> 1
			if is_line_clear(anchor, _center_of(path[middle]), occupied, clearance):
				good = middle
			else:
				bad = middle

		for index in range(first, good + 1):
			aims[index] = good
		anchor = _center_of(path[good])
		first = good + 1

	return aims


## Whether a straight walk between two points, in internal cell units, stays at
## least `clearance` cells away from every blocked cell and every edge.
##
## Tested one row at a time: the stretch of line that can reach a row is worked
## out, widened by the clearance, and every cell it covers must be free. The
## clearance is applied as a square around the line rather than a circle, which
## is conservative only at a tower's corners.
##
## The clearance must be above zero. At zero a line could run exactly through
## the point where two towers touch at a corner, which is a wall.
func is_line_clear(from: Vector2, to: Vector2, occupied: PackedByteArray,
		clearance: float) -> bool:
	var from_x: float = from.x
	var from_y: float = from.y
	var dx: float = to.x - from_x
	var dy: float = to.y - from_y
	var min_y: float = minf(from_y, to.y)
	var max_y: float = maxf(from_y, to.y)

	var first_row: int = int(floor(min_y - clearance))
	var last_row: int = int(ceil(max_y + clearance)) - 1
	for row in range(first_row, last_row + 1):
		var low: float = maxf(min_y, float(row) - clearance)
		var high: float = minf(max_y, float(row + 1) + clearance)
		if low > high:
			continue

		var x_low: float = minf(from_x, to.x)
		var x_high: float = maxf(from_x, to.x)
		if dy != 0.0:
			var x_at_low: float = from_x + (low - from_y) * dx / dy
			var x_at_high: float = from_x + (high - from_y) * dx / dy
			x_low = minf(x_at_low, x_at_high)
			x_high = maxf(x_at_low, x_at_high)

		var first_column: int = int(floor(x_low - clearance))
		var last_column: int = int(ceil(x_high + clearance)) - 1
		for column in range(first_column, last_column + 1):
			if !_cell_free(Vector2i(column, row), occupied):
				return false

	return true


func _center_of(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)


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

