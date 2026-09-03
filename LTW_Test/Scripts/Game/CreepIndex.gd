class_name CreepIndex
extends RefCounted

## A grid of an area's creeps, so a search reads the creeps NEAR a point rather
## than every creep in the lane.
##
## The scans this exists for are the two CLAUDE.md lists together - a tower's
## target search and a creep's look around for an aura - and both had the same
## shape: walk the whole lane, throw away the ninety per cent that were never
## in reach. Measured on the server at ~200 creeps, the aura sweep alone was
## about a third of the tick. See Docs/Findings/2026-09-03-server-tick-overrun.md.
##
## REBUILT WHOLE, once per tick, rather than kept in step as creeps move. A
## creep changes cell constantly, so incremental bookkeeping would mean a hook
## on every step and a bug the day one is missed - and rebuilding is one pass
## over a list that is already in memory, against the many searches that pass
## then serves. Cheap to build once, read many times.
##
## Rebuilt LAZILY, on the first query of a tick, deliberately: it must not
## depend on this node running before the towers that ask it, and Godot's tick
## order is plain tree order unless every node in the chain sets
## process_physics_priority - which is exactly the trap CLAUDE.md records
## ReplicationService falling into. Asking "is this the frame I was built for"
## costs one integer compare and cannot be ordered wrongly.
##
## NOT authority-gated, and must not be: AttackComponent runs its search on
## clients too (it points the barrels), so a client with an empty index would
## draw towers staring at nothing.
##
## The answer is a SUPERSET. Cells are square and a range is round, so a query
## returns candidates that may be out of reach, and every caller still tests
## the exact distance against the live position. That is what keeps this a pure
## accelerator: delete it and every answer stays the same, only slower.

## How far a creep may travel between the index being built and being read,
## plus the slack that makes the query's square cover the round range it stands
## for. The fastest creep in the game crosses well under a tenth of a cell in
## one tick, so this is generous by an order of magnitude - and generous is the
## right side to err on, because the cost of too much padding is a few extra
## candidates while the cost of too little is a tower that cannot see a creep
## standing in front of it.
const QUERY_PADDING: float = 1.0

var _cells: Dictionary = {}
var _cell_size: float = 2.0
## The physics frame `_cells` describes, or -1 when it has never been built.
## Compared rather than trusted, so a stale index rebuilds itself on the next
## question instead of answering from the last tick.
var _frame_built: int = -1


func _init(cell_size: float) -> void:
	_cell_size = maxf(0.5, cell_size)


## Every creep of this area that MIGHT stand within radius of a point.
##
## A superset, and never a subset - see the class docstring. `creeps` is the
## area's own live list, handed in rather than reached for, so this class knows
## nothing about PlayerArea and can be tested with a plain array.
func near(creeps: Array[Creep], center: Vector3, radius: float) -> Array[Creep]:
	if radius <= 0.0 || creeps.is_empty():
		return []

	_rebuild_if_stale(creeps)

	var reach: float = radius + QUERY_PADDING
	var min_x: int = _axis(center.x - reach)
	var max_x: int = _axis(center.x + reach)
	var min_z: int = _axis(center.z - reach)
	var max_z: int = _axis(center.z + reach)

	# The whole lane is only a handful of cells wide, so a long ranged tower
	# asks for most of them and gets most of the lane back. That is the honest
	# ceiling of this structure on a maze this narrow, and it still beats
	# reading every creep in it.
	var found: Array[Creep] = []
	for cx: int in range(min_x, max_x + 1):
		for cz: int in range(min_z, max_z + 1):
			var bucket: Variant = _cells.get(Vector2i(cx, cz))
			if bucket != null:
				found.append_array(bucket as Array[Creep])

	return found


## Throws the grid away, so the next query builds it again. Called when the
## area's creep list changes shape in a way a position sweep would not catch -
## a creep recycled into another lane, an area torn down.
func invalidate() -> void:
	_frame_built = -1


func _rebuild_if_stale(creeps: Array[Creep]) -> void:
	var frame: int = Engine.get_physics_frames()
	if frame == _frame_built:
		return

	_frame_built = frame
	_cells.clear()
	for creep: Creep in creeps:
		# is_instance_valid rather than a null check alone: the list holds a
		# creep until the frame ends, so one already on its way out is still in
		# it. Callers filter those too, but an invalid instance must not be
		# asked for a position here.
		if creep == null || !is_instance_valid(creep):
			continue
		var key: Vector2i = Vector2i(
			_axis(creep.global_position.x), _axis(creep.global_position.z)
		)
		var bucket: Variant = _cells.get(key)
		if bucket == null:
			var made: Array[Creep] = [creep]
			_cells[key] = made
		else:
			(bucket as Array[Creep]).append(creep)


func _axis(value: float) -> int:
	return floori(value / _cell_size)
