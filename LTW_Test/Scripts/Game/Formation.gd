class_name Formation
extends RefCounted

## Turns ONE ordered point into one destination per unit.
##
## **A group order that names a single point is the whole of why a pack moved
## like a liquid.** Every unit wanted the same spot, so no unit that was not
## standing on it had a reason to stop; the only thing that ever ended the walk
## was bumping into somebody who stopped first, and a per-tick mutual push then
## had no arrangement to settle into and shoved the pack about for ever. One
## shared goal plus pairwise repulsion is Continuum Crowds, whose stated purpose
## is to make a crowd behave like a fluid. Give each unit a spot of its own and
## all of it goes away: arrival is per unit and definite rather than a
## negotiation over one contested tile.
##
## **It is a LAYOUT and never a movement mode.** Units leave the instant the
## order lands, at their own speed, by their own route. Nothing forms up first,
## nothing waits for a straggler, nothing walks backwards to hold a shape, and
## there is no state to carry once the spots are handed out. AoE2 DE shipped
## formation-FIRST movement and patched it back out after players asked for a
## switch to turn it off; this is the half they kept.
##
## **Everything here is INTEGER CELL ARITHMETIC, and that is a correction.** The
## first version laid an equilateral lattice out in world space at a pitch
## derived from the units' own personal space, and then legalised every spot
## onto a cell centre - which quantised the pitch to the grid and threw the
## derivation away. What shipped was a square block at the grid's own pitch, so
## the authored spacing was inert and, for the widest creep in the roster, the
## delivered pitch was INSIDE its own personal space: a parked block of them
## overlapped and shoved itself apart for ever. Laying out in cells from the
## start means the block that is computed is the block that is delivered,
## nothing is lost on the way to the screen, and a block lined up with the
## towers reads better in a maze than one at forty degrees to them.
##
## **Determinism.** Every peer runs this on the same Command and must get the
## same answer, so: the unit order comes from unit_id and never from the
## selection or the tree, the claim dictionary is probed by key and never
## iterated, every comparator ends on an integer, and there is no atan2 anywhere
## - facing is presentation in this project precisely because atan2 is not
## specified to the last bit. See MobileUnit.face_instantly.

## The four directions a block may face. Cardinal on purpose: an axis-aligned
## block is already legal on the grid, so there is nothing to quantise.
const HEADINGS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
]


## One destination per unit, parallel to `units` and always the same length.
##
## A unit that is invalid, stands in no area, or could not be given a legal spot
## gets the raw ordered point, which is what it would have got if this class did
## not exist. **Never a shorter array**: dropping an entry would hand every later
## spot to the wrong unit, identically on every peer, so the checksum would stay
## green while the whole group was wrong.
static func slots_for(units: Array, anchor: Vector3) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	slots.resize(units.size())
	slots.fill(anchor)

	var config: GameConfig = References.game_config
	if config == null || !config.formation_enabled || units.size() < 2:
		return slots

	# Bucketed by area because a selection can stand in two lanes at once - your
	# creeps in somebody else's maze while your builder is at home - and each
	# lane clamps the point into itself. Walked in FIRST APPEARANCE order over
	# the units rather than by iterating the dictionary, which has no order this
	# code may rely on.
	var order: Array[PlayerArea] = []
	var buckets: Dictionary = {}
	for index in range(units.size()):
		var unit: Unit = units[index] as Unit
		if unit == null || !is_instance_valid(unit) || unit.area == null:
			continue
		if !buckets.has(unit.area):
			buckets[unit.area] = PackedInt32Array()
			order.append(unit.area)
		buckets[unit.area].append(index)

	for area: PlayerArea in order:
		_lay_out(units, buckets[area], area, anchor, config, slots)

	return slots


## One spot each on the ring of ground within reach of a NAMED target.
##
## **An attack order used to get no layout at all**, because the seam that
## computes one bailed out whenever a command named a unit - so the single most
## common order in the game aimed every creep in the selection at the tower's
## own centre and left them to shove each other around it. This is that gap.
##
## The ring is PlayerArea.reach_cells, the same function that gives an attack
## order's route its goal set, so a spot offered here is a spot the swing lands
## from and there is no second notion of reach to drift from this one. Which
## spot goes to which creep is PlayerArea.assign_reach_cells - one sweep, by
## route - so a pack coming at the north face claims the north face.
##
## A creep that does not fit is given a spot on a WAITING ring further out. It
## walks there and stands, rather than joining a scrum it cannot reach into.
## What it does NOT do is pick another tower: the player named this one, and
## "my units ignored my click" is a worse complaint than "my units waited".
## An attack-MOVE and the autonomous march are the orders that choose their own
## fights - see AttackAbility.
static func attack_slots_for(units: Array, target: Unit) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	slots.resize(units.size())
	if target == null || !is_instance_valid(target):
		return slots
	slots.fill(target.global_position)

	var config: GameConfig = References.game_config
	var area: PlayerArea = target.area
	if config == null || !config.formation_enabled || area == null || units.size() < 2:
		return slots

	# Only the creeps that are actually going to walk to this tower, in the
	# tower's own area. Anything else keeps the plain aim and is unaffected.
	var taking: Array[int] = []
	for index in range(units.size()):
		var creep: Creep = units[index] as Creep
		if creep == null || !is_instance_valid(creep) || creep.area != area:
			continue
		if !creep.is_attacker() || creep.attack_component == null:
			continue
		taking.append(index)
	if taking.size() < 2:
		return slots
	taking.sort_custom(func(a: int, b: int) -> bool:
		return (units[a] as Creep).unit_id < (units[b] as Creep).unit_id)

	# **The SMALLEST reach in the group sets the ring.** A mixed pack spaced by
	# the longest-reaching creep's ring would put the short-reaching ones on
	# ground they cannot swing from, which reads as a creep standing next to a
	# tower doing nothing.
	var within: float = INF
	for index: int in taking:
		var creep: Creep = units[index] as Creep
		within = minf(within, creep.attack_component.order_reach())
	if within == INF || within <= 0.0:
		return slots
	within *= clampf(config.attacker_order_reach_ratio, 0.0, 1.0)

	var held: Dictionary = _ground_held_by_others(area, units, taking)
	var ring: Array[Vector2i] = _offer(area.reach_cells(target.global_position, within), held)

	var froms: Array[Vector3] = []
	for index: int in taking:
		froms.append((units[index] as Creep).global_position)

	var assigned: Array[Vector2i] = area.assign_reach_cells(froms, ring)

	# Whoever got nothing goes on a waiting ring further out - the same
	# machinery, a wider radius, and the cells of the inner ring taken out so a
	# waiter is never handed a spot somebody is already fighting from.
	var waiting: Array[int] = []
	var waiting_from: Array[Vector3] = []
	for rank in range(taking.size()):
		if assigned[rank] == PlayerArea.OFF_GRID:
			waiting.append(rank)
			waiting_from.append(froms[rank])

	if !waiting.is_empty():
		var margin: float = float(maxi(1, config.attacker_wait_ring_cells)) \
			* area.internal_cell_size()
		for cell: Vector2i in ring:
			held[cell] = true
		var outer: Array[Vector2i] = _offer(
			area.reach_cells(target.global_position, within + margin), held)
		var extra: Array[Vector2i] = area.assign_reach_cells(waiting_from, outer)
		for entry in range(waiting.size()):
			assigned[waiting[entry]] = extra[entry]

	for rank in range(taking.size()):
		if assigned[rank] == PlayerArea.OFF_GRID:
			continue
		slots[taking[rank]] = area.internal_cell_center(assigned[rank])

	return slots


## The ring, less anything already spoken for.
static func _offer(cells: Array[Vector2i], held: Dictionary) -> Array[Vector2i]:
	var free: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if !held.has(cell):
			free.append(cell)
	return free


## Ground a creep OUTSIDE this order is already standing on.
##
## **Read off the world rather than booked in a ledger**, deliberately. A ledger
## of claims has exactly one catastrophic failure - an entry left behind by a
## creep that died, leaked or was moved - and it presents as the bug being
## fixed, silently and permanently. Asking the world cannot go stale: a creep
## that is gone is not standing anywhere. The cost is one walk over the area's
## attackers per ORDER, which is a player click rather than a tick.
##
## Only creeps that are STANDING STILL take up room. One on its way somewhere
## owns nothing and is walked through, which is what every shipping RTS does and
## is the correction that replaced the per-tick pushing.
static func _ground_held_by_others(area: PlayerArea, units: Array,
		taking: Array[int]) -> Dictionary:
	var mine: Dictionary = {}
	for index: int in taking:
		mine[(units[index] as Creep).get_instance_id()] = true

	var held: Dictionary = {}
	for other: Creep in area.creeps():
		if other == null || !is_instance_valid(other) || other.is_down():
			continue
		if !other.is_attacker() || other.is_moving():
			continue
		if mine.has(other.get_instance_id()):
			continue
		# Every cell its own body covers, so a big creep is not stepped onto by
		# a small one whose cell centre happens to miss it.
		for cell: Vector2i in area.reach_cells(
				other.global_position, other.crowd_radius() * 2.0):
			held[cell] = true
	return held


## One lane's share of the order, written into `slots` at the caller's indices.
static func _lay_out(units: Array, indices: PackedInt32Array, area: PlayerArea,
		anchor: Vector3, config: GameConfig, slots: Array[Vector3]) -> void:
	if indices.size() < 2:
		return

	# **Sorted by unit id, not by selection order.** unit_ids arrives in the
	# order the ordering machine happened to hold them, which agrees across
	# peers but changes between two presses of the same order - so without this
	# the same group told to go the same place twice would reshuffle itself. The
	# offline path hands over a tree-ordered array, which is a third order
	# again. Sorting makes the layout a pure function of WHICH units were named.
	var sorted: Array[int] = []
	for index: int in indices:
		sorted.append(index)
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return (units[a] as Unit).unit_id < (units[b] as Unit).unit_id)

	var count: int = sorted.size()
	var target: Vector3 = area.clamp_point(anchor)
	var anchor_cell: Vector2i = area.world_to_internal_cell(target)

	var centroid: Vector3 = Vector3.ZERO
	for index: int in sorted:
		centroid += (units[index] as Unit).global_position
	centroid /= float(count)

	var forward: Vector2i = _heading(area, target - centroid, config)
	var right: Vector2i = Vector2i(forward.y, -forward.x)
	var pitch: int = _pitch(units, sorted, area, config)
	var columns: int = _columns(count, anchor_cell, right, area, pitch, config)

	var cells: Array[Vector2i] = _block(count, columns, anchor_cell, forward, right, pitch)
	_legalise(cells, area, config)
	_assign(units, sorted, cells, forward, right, area, slots)


## Which of the four cardinal directions the block faces.
##
## Along the way the group is travelling, so the front row is the edge that
## arrives first and nobody has to walk through anybody to reach their spot.
##
## **A short travel vector is thrown away rather than reduced.** A click just
## outside a spread-out group gives a vector whose length is a fraction of the
## group's own width, and whose direction therefore flips between two clicks a
## pixel apart - which would snap the whole block ninety degrees for no reason a
## player can see. Below the threshold the lane's own down-lane axis is used,
## which is fixed and shared by every peer.
##
## Reduced to a cardinal by comparing the two components, with the ties broken
## in a fixed order, so no angle is ever computed and no float decides anything
## beyond one comparison.
static func _heading(area: PlayerArea, travel: Vector3, config: GameConfig) -> Vector2i:
	var flat: Vector3 = Vector3(travel.x, 0.0, travel.z)
	var floor_length: float = config.formation_min_travel_cells * config.cell_size
	if flat.length() < floor_length:
		return Vector2i(0, 1)

	# The area's grid may be rotated relative to the world, so the travel vector
	# is read in the grid's own axes rather than in the world's.
	var origin: Vector2i = area.world_to_internal_cell(area.clamp_point(Vector3.ZERO))
	var along_x: Vector3 = area.internal_cell_center(origin + Vector2i(1, 0)) \
		- area.internal_cell_center(origin)
	var along_z: Vector3 = area.internal_cell_center(origin + Vector2i(0, 1)) \
		- area.internal_cell_center(origin)
	along_x.y = 0.0
	along_z.y = 0.0

	var dx: float = flat.dot(along_x)
	var dz: float = flat.dot(along_z)
	if absf(dz) >= absf(dx):
		return Vector2i(0, 1) if dz >= 0.0 else Vector2i(0, -1)
	return Vector2i(1, 0) if dx >= 0.0 else Vector2i(-1, 0)


## Spacing between neighbouring spots, in whole internal cells.
##
## Taken from the LARGEST personal space in the group, because a lattice is only
## as loose as its biggest member: spaced for the smallest, the big one overlaps
## its neighbours the moment it parks. Rounded UP to a whole cell, which is what
## makes the delivered pitch equal to the computed one - the widest creep in the
## roster needs more than one cell and used to be given one.
static func _pitch(units: Array, sorted: Array[int], area: PlayerArea,
		config: GameConfig) -> int:
	var contact: float = 0.0
	for index: int in sorted:
		var unit: Unit = units[index] as Unit
		contact = maxf(contact, 2.0 * _personal_space(unit))

	var cell: float = area.internal_cell_size()
	if cell <= 0.0:
		return 1
	return maxi(1, int(ceil(contact / cell))) + maxi(0, config.formation_extra_pitch_cells)


## The room one unit claims, by the same reckoning the crowding rule used.
##
## A cast rather than has_method, because crowd_radius is genuinely a creep's
## question: the builder is the only other unit that can be sent anywhere, there
## is one of it, and its own selection circle is the honest answer for it.
static func _personal_space(unit: Unit) -> float:
	if unit == null:
		return 0.0
	var creep: Creep = unit as Creep
	if creep != null:
		return creep.crowd_radius()
	return unit.select_radius


## How wide the block may be, in columns.
##
## The shape wanted is a little wider than deep - a group walking into open
## ground looks like a line abreast, not a column - but **the ground has the
## last word.** A block wider than the corridor it is being sent into puts half
## of itself inside towers, which is the detour bug reproduced at group scale.
## So the free width across the anchor is probed outwards a cell at a time and
## the block is capped to it.
static func _columns(count: int, anchor_cell: Vector2i, right: Vector2i,
		area: PlayerArea, pitch: int, config: GameConfig) -> int:
	var wanted: int = int(ceil(sqrt(float(count) * config.formation_aspect)))
	wanted = clampi(wanted, 1, count)

	var free_cells: int = 1
	for side: int in [1, -1]:
		var reach: int = 0
		while reach < pitch * wanted:
			reach += 1
			var cell: Vector2i = anchor_cell + right * side * reach
			if !_cell_open(area, cell):
				break
		free_cells += reach

	return clampi(free_cells / pitch, 1, wanted)


## The lattice itself: an axis-aligned block whose FRONT ROW sits on the clicked
## cell and whose later rows recede back along the travel direction.
##
## Receding backwards rather than centring on the click stops the group
## overshooting where it was sent, and means the unit that was already in front
## stays in front.
##
## A short last row is indented by whole PITCHES, so every spot of it still
## lands on the lattice. Centring it on its own width instead would put it half
## a pitch across from where the lattice wants it, which is how the first
## version landed a row on top of the one above it.
static func _block(count: int, columns: int, anchor_cell: Vector2i, forward: Vector2i,
		right: Vector2i, pitch: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for index in range(count):
		var row: int = index / columns
		var column: int = index % columns
		var width: int = mini(columns, count - row * columns)
		var indent: int = (columns - width) / 2
		# Twice the offset, so a block with an even number of columns still
		# lands on whole cells: the halving is done once, on the integer.
		var across: int = ((2 * (column + indent)) - (columns - 1)) * pitch / 2
		var back: int = row * pitch
		cells.append(anchor_cell + right * across - forward * back)
	return cells


## Moves any spot that landed on ground nothing can stand on, and makes sure no
## two spots are the same ground.
##
## **Non-destructive, which is the correction.** The first version rewrote EVERY
## spot to a cell centre unconditionally, which is what quantised the pitch away.
## This one leaves a legal spot exactly where the lattice put it and only moves
## one that is blocked or already taken.
##
## **Claimed by key and never by iteration**, which is worth saying because the
## dictionary makes this look like a determinism violation and it is not: it is
## only ever asked "is this cell taken" and told "it is now".
##
## A spot with nothing free inside the search bound is left where it is and its
## unit falls back on the raw ordered point - what every unit got before there
## were spots at all, so the worst case is the old behaviour for one unit.
static func _legalise(cells: Array[Vector2i], area: PlayerArea, config: GameConfig) -> void:
	var claimed: Dictionary = {}
	var limit: int = config.formation_slot_search_cells

	for index in range(cells.size()):
		var wanted: Vector2i = cells[index]
		if !claimed.has(wanted) && _cell_open(area, wanted):
			claimed[wanted] = true
			continue

		var best: Vector2i = Vector2i(-1, -1)
		var best_score: int = 0
		for dz in range(-limit, limit + 1):
			for dx in range(-limit, limit + 1):
				var cell: Vector2i = Vector2i(wanted.x + dx, wanted.y + dz)
				if claimed.has(cell) || !_cell_open(area, cell):
					continue
				# Integer distance with an integer tie-break, so nothing here is
				# decided by a float - and biased towards the spot this unit was
				# actually given rather than towards a compass direction, which
				# is the mistake nearest_free_point makes.
				var score: int = dx * dx + dz * dz
				if best.x < 0 || score < best_score:
					best_score = score
					best = cell

		if best.x < 0:
			continue
		claimed[best] = true
		cells[index] = best


## Whether a cell is on the grid and not inside a wall.
static func _cell_open(area: PlayerArea, cell: Vector2i) -> bool:
	if cell.x < 0 || cell.y < 0 \
			|| cell.x >= area.internal_width() || cell.y >= area.internal_depth():
		return false
	return area.is_point_free(area.internal_cell_center(cell))


## Pairs units to spots so that nobody walks through anybody.
##
## Both lists are sorted along the travel axis and paired off in order, so
## whoever is already nearest the front gets the frontmost spot and the group
## keeps the shape it had. That is the property a player actually feels, and it
## costs a sort rather than the assignment solve that would buy the last few
## percent of it - Zero-K ships that solve, caps it, and lowers the cap when it
## runs long.
##
## **Every comparator is integer**, because the heading is cardinal and both
## sides are cells. The first version projected world positions onto a float
## axis and broke ties on bitwise float equality, which sort_custom - an
## unstable introsort - is entitled to resolve however it likes.
static func _assign(units: Array, sorted: Array[int], cells: Array[Vector2i],
		forward: Vector2i, right: Vector2i, area: PlayerArea,
		slots: Array[Vector3]) -> void:
	var unit_cells: Dictionary = {}
	for index: int in sorted:
		unit_cells[index] = area.world_to_internal_cell(
			(units[index] as Unit).global_position)

	var by_unit: Array[int] = sorted.duplicate()
	by_unit.sort_custom(func(a: int, b: int) -> bool:
		var ca: Vector2i = unit_cells[a]
		var cb: Vector2i = unit_cells[b]
		var fa: int = forward.x * ca.x + forward.y * ca.y
		var fb: int = forward.x * cb.x + forward.y * cb.y
		if fa != fb:
			return fa > fb
		var ra: int = right.x * ca.x + right.y * ca.y
		var rb: int = right.x * cb.x + right.y * cb.y
		if ra != rb:
			return ra < rb
		return (units[a] as Unit).unit_id < (units[b] as Unit).unit_id)

	var by_cell: Array[int] = []
	for index in range(cells.size()):
		by_cell.append(index)
	by_cell.sort_custom(func(a: int, b: int) -> bool:
		var fa: int = forward.x * cells[a].x + forward.y * cells[a].y
		var fb: int = forward.x * cells[b].x + forward.y * cells[b].y
		if fa != fb:
			return fa > fb
		var ra: int = right.x * cells[a].x + right.y * cells[a].y
		var rb: int = right.x * cells[b].x + right.y * cells[b].y
		if ra != rb:
			return ra < rb
		return a < b)

	for rank in range(by_unit.size()):
		slots[by_unit[rank]] = area.internal_cell_center(cells[by_cell[rank]])
