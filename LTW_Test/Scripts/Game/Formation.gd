class_name Formation
extends RefCounted

## Turns ONE ordered point into one destination per unit.
##
## **A group order that names a single point is the whole of why a pack moves
## like a liquid.** Every unit wants the same spot, so no unit that is not
## standing on it has a reason to stop; the only thing that ever ends the walk
## is bumping into somebody who stopped first, and a per-tick separation push
## then has no arrangement to settle into and shoves the pack about for ever.
## One shared goal plus pairwise repulsion is Continuum Crowds, whose stated
## purpose is to make a crowd behave like a fluid - so no amount of tuning the
## push can fix it, because the push is doing its job. See
## Findings/2026-09-16-attacker-pathing-and-group-movement.md.
##
## Give each unit a spot of its own and all of that goes away at once: arrival
## is per unit and definite rather than a negotiation over one contested tile,
## and a parked block is at rest because every neighbour is already far enough
## away to be left alone.
##
## **It is a LAYOUT and never a movement mode.** Units leave the instant the
## order lands, at their own speed, by their own route. Nothing forms up first,
## nothing waits for a straggler, nothing walks backwards to hold a shape, and
## there is no state to carry once the slots are handed out. AoE2 DE shipped
## formation-FIRST movement and patched it back out after players asked for a
## switch to turn it off; this is the half of it that they kept.
##
## **Determinism.** Every peer runs this on the same Command and must get the
## same answer, so: the unit order is taken from unit_id and never from the
## selection or the tree, both dictionaries are probed by key and never
## iterated, no dictionary decides an order, every comparator ends on an
## integer, and there is no atan2 anywhere - facing is presentation in this
## project precisely because atan2 is not specified to the last bit. See
## MobileUnit.face_instantly.

## Rows are pitched by this share of the column spacing, which is what makes a
## staggered lattice equilateral: an odd row offset half a column across sits at
## exactly one spacing from its two neighbours in the row above.
const ROW_PITCH: float = 0.866025


## One destination per unit, parallel to `units` and always the same length.
##
## A unit that is invalid, stands in no area, or could not be given a legal spot
## gets the raw ordered point, which is exactly what it would have got if this
## class did not exist. **Never a shorter array**: dropping an entry would hand
## every later slot to the wrong unit, and would do it identically on every
## peer, so the checksum would stay green while the whole group was wrong.
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


## One lane's share of the order, written into `slots` at the callers' indices.
static func _lay_out(units: Array, indices: PackedInt32Array, area: PlayerArea,
		anchor: Vector3, config: GameConfig, slots: Array[Vector3]) -> void:
	if indices.size() < 2:
		return

	# **Sorted by unit id, not by selection order.** unit_ids arrives in the
	# order the ordering machine happened to have them in, which agrees across
	# peers but changes between two presses of the same order - so without this
	# the same group told to go the same place twice would reshuffle itself.
	# The offline path hands over a tree-ordered array, which is a third order
	# again. Sorting makes the layout a pure function of WHICH units were named.
	var sorted: Array[int] = []
	for index: int in indices:
		sorted.append(index)
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return (units[a] as Unit).unit_id < (units[b] as Unit).unit_id)

	var count: int = sorted.size()
	var target: Vector3 = area.clamp_point(anchor)
	target.y = 0.0

	var centroid: Vector3 = Vector3.ZERO
	for index: int in sorted:
		centroid += (units[index] as Unit).global_position
	centroid /= float(count)
	centroid.y = 0.0

	var forward: Vector3 = _heading(target - centroid, area, config)
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	var spacing: float = _spacing(units, sorted, config)

	var columns: int = _columns(count, target, right, area, spacing, config)
	var nominal: Array[Vector3] = _block(count, columns, target, forward, right, spacing)
	_legalise(nominal, area, config)
	_assign(units, sorted, nominal, target, forward, right, slots)


## Which way the block faces.
##
## Along the way the group is travelling, so the front row is the edge that
## arrives first and nobody has to walk through anybody to reach their spot.
##
## **A short travel vector is thrown away rather than normalised.** A click just
## outside a spread-out group gives a vector whose length is a fraction of the
## group's own width, and whose DIRECTION therefore flips between two clicks a
## pixel apart - which snaps the whole block ninety degrees for no reason a
## player can see. Below the threshold the lane's own down-lane axis is used,
## which is fixed, shared by every peer, and the direction a lane is about
## anyway.
static func _heading(travel: Vector3, area: PlayerArea, config: GameConfig) -> Vector3:
	var flat: Vector3 = Vector3(travel.x, 0.0, travel.z)
	if flat.length() >= config.formation_min_travel_cells * config.cell_size:
		return flat.normalized()

	var down_lane: Vector3 = area.internal_cell_center(Vector2i(0, 1)) \
		- area.internal_cell_center(Vector2i(0, 0))
	down_lane.y = 0.0
	if down_lane.length_squared() <= 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return down_lane.normalized()


## How far apart neighbouring slots stand.
##
## Taken from the LARGEST personal space in the group, because a lattice is only
## as loose as its biggest member: spaced for the smallest, the big one is
## overlapping its neighbours the moment it parks and the push starts up again.
##
## **The floor is above one, and that is what makes a parked block hold still.**
## Creep._hold_apart leaves a pair alone once they are the sum of their two
## radii apart, so slots at exactly that distance are on the boundary - and a
## unit stops within its own arrive_threshold of its slot, so two neighbours can
## each be that much nearer than the lattice says. Clamped up by twice that
## slack, so the block is at rest by construction rather than by a value
## somebody chose.
static func _spacing(units: Array, sorted: Array[int], config: GameConfig) -> float:
	var space: float = 0.0
	var slack: float = 0.0
	for index: int in sorted:
		var unit: Unit = units[index] as Unit
		space = maxf(space, _personal_space(unit))
		slack = maxf(slack, _arrive_threshold(unit))

	var contact: float = 2.0 * space
	if contact <= 0.0:
		return 0.0

	var floor_ratio: float = 1.0 + 2.0 * slack / contact
	return contact * maxf(config.formation_spacing_ratio, floor_ratio)


## The room one unit claims, by the same reckoning the crowding rule uses.
##
## A cast rather than has_method, because crowd_radius is genuinely a creep's
## question and not a thing every unit answers differently - the builder is the
## only other unit that can be sent anywhere, there is one of it, and its own
## selection circle is the honest answer for it.
static func _personal_space(unit: Unit) -> float:
	if unit == null:
		return 0.0
	var creep: Creep = unit as Creep
	if creep != null:
		return creep.crowd_radius()
	return unit.select_radius


static func _arrive_threshold(unit: Unit) -> float:
	if unit == null:
		return 0.0
	var stats: MobileUnitStats = unit.stats as MobileUnitStats
	if stats == null:
		return 0.0
	return stats.arrive_threshold


## How wide the block may be, in columns.
##
## The shape wanted is a little wider than deep - a group walking into open
## ground looks like a line abreast, not a column - but **the ground has the
## last word.** A block wider than the corridor it is being sent into puts half
## of itself inside towers, which is this whole finding's own bug reproduced at
## group scale. So the free width across the anchor is probed outwards in
## internal-cell steps and the block is capped to it.
static func _columns(count: int, target: Vector3, right: Vector3, area: PlayerArea,
		spacing: float, config: GameConfig) -> int:
	var wanted: int = int(ceil(sqrt(float(count) * config.formation_aspect)))
	wanted = clampi(wanted, 1, count)
	if spacing <= 0.0:
		return wanted

	var step: float = area.internal_cell_size()
	if step <= 0.0:
		return wanted

	var free: float = 0.0
	for side: float in [1.0, -1.0]:
		var reach: float = 0.0
		while reach < spacing * float(wanted):
			reach += step
			if !area.is_point_free(target + right * side * reach):
				break
		free += reach

	return clampi(int(floor(free / spacing)), 1, wanted)


## The lattice itself: a staggered block whose FRONT ROW sits on the clicked
## point and whose later rows recede back along the travel vector.
##
## Receding backwards rather than centring on the click is what stops the group
## overshooting where it was sent, and means the unit that was already in front
## stays in front.
##
## Odd rows are offset half a column and rows are pitched by ROW_PITCH, so every
## nearest neighbour in the lattice sits at exactly one spacing - a square grid
## would put the diagonal neighbours closer than the orthogonal ones and give
## the push something to do in a block that was meant to be at rest.
static func _block(count: int, columns: int, target: Vector3, forward: Vector3,
		right: Vector3, spacing: float) -> Array[Vector3]:
	var cells: Array[Vector3] = []
	for index in range(count):
		var row: int = index / columns
		var column: int = index % columns
		var width: int = mini(columns, count - row * columns)

		# **A short last row is nudged in by WHOLE columns, never by half of
		# one.** Centring it on its own width instead puts it half a spacing
		# across from where the lattice wants it, which lands it right on top of
		# the staggered row above: the nearest pair then sits at the ROW PITCH
		# rather than at the spacing, the push has something to correct in a
		# block that was meant to be at rest, and the whole point of deriving
		# the spacing from the crowding rule is lost. Measured at 0.866 of the
		# spacing before this line existed.
		var indent: int = (columns - width) / 2
		var across: float = (float(column + indent) - float(columns - 1) * 0.5) * spacing
		if row % 2 == 1:
			across += spacing * 0.5

		var back: float = float(row) * spacing * ROW_PITCH
		cells.append(target + right * across - forward * back)
	return cells


## Moves any slot that landed somewhere nothing can stand onto the nearest free
## ground, and makes sure no two slots are the same ground.
##
## **Claimed by key and never by iteration**, which is worth saying because the
## dictionary makes this look like a determinism violation and it is not: it is
## only ever asked "is this cell taken" and told "it is now".
##
## A slot with nothing free within the search bound is left where it is and the
## unit falls back on the raw ordered point, which is what every unit got before
## there were slots at all - so the worst case here is the old behaviour for one
## unit rather than a unit sent somewhere absurd.
static func _legalise(cells: Array[Vector3], area: PlayerArea, config: GameConfig) -> void:
	var claimed: Dictionary = {}
	var width: int = area.internal_width()
	var depth: int = area.internal_depth()
	var limit: int = config.formation_slot_search_cells

	for index in range(cells.size()):
		var point: Vector3 = area.clamp_point(cells[index])
		var wanted: Vector2i = area.world_to_internal_cell(point)
		var best: Vector2i = Vector2i(-1, -1)
		var best_score: int = 0

		for dz in range(-limit, limit + 1):
			for dx in range(-limit, limit + 1):
				var cell: Vector2i = Vector2i(wanted.x + dx, wanted.y + dz)
				if cell.x < 0 || cell.y < 0 || cell.x >= width || cell.y >= depth:
					continue
				if claimed.has(cell) || !area.is_point_free(area.internal_cell_center(cell)):
					continue
				# Integer distance with an integer tie-break, so nothing here is
				# decided by a float comparison - and biased towards the slot
				# this unit was actually given rather than towards a compass
				# direction, which is the mistake nearest_free_point makes.
				var score: int = dx * dx + dz * dz
				if best.x < 0 || score < best_score:
					best_score = score
					best = cell

		if best.x < 0:
			continue
		claimed[best] = true
		cells[index] = area.internal_cell_center(best)


## Pairs units to slots so that nobody walks through anybody.
##
## Both lists are sorted along the travel axis and then paired off in order, so
## whoever is already nearest the front gets the frontmost spot and the group
## keeps the shape it had. That is the property a player actually feels, and it
## costs a sort rather than the assignment solve that would buy the last few
## percent of it - Zero-K ships that solve and caps it, and lowers the cap when
## it runs long.
##
## Both comparators end on an INTEGER and use exact float compares. sort_custom
## is an unstable introsort, so a comparator that could call two entries equal
## would leave its own result undefined; and is_equal_approx is not transitive,
## which would do the same thing more quietly.
static func _assign(units: Array, sorted: Array[int], cells: Array[Vector3],
		target: Vector3, forward: Vector3, right: Vector3,
		slots: Array[Vector3]) -> void:
	var by_unit: Array[int] = sorted.duplicate()
	by_unit.sort_custom(func(a: int, b: int) -> bool:
		var pa: Vector3 = (units[a] as Unit).global_position
		var pb: Vector3 = (units[b] as Unit).global_position
		var fa: float = forward.dot(pa)
		var fb: float = forward.dot(pb)
		if fa != fb:
			return fa > fb
		var ra: float = right.dot(pa)
		var rb: float = right.dot(pb)
		if ra != rb:
			return ra < rb
		return (units[a] as Unit).unit_id < (units[b] as Unit).unit_id)

	var by_cell: Array[int] = []
	for index in range(cells.size()):
		by_cell.append(index)
	by_cell.sort_custom(func(a: int, b: int) -> bool:
		var fa: float = forward.dot(cells[a])
		var fb: float = forward.dot(cells[b])
		if fa != fb:
			return fa > fb
		var ra: float = right.dot(cells[a])
		var rb: float = right.dot(cells[b])
		if ra != rb:
			return ra < rb
		return a < b)

	for rank in range(by_unit.size()):
		slots[by_unit[rank]] = cells[by_cell[rank]]
