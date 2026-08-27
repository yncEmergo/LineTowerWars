class_name HitPattern
extends RefCounted

## The shapes an elemental tower's damage comes in, beyond "the creep it shot".
##
## Three of them recur across the roster and none is a splash, which is why
## they are not AttackEffects: a splash is a radius around a point and these
## are all a WALK over creeps, picking each one in turn.
##
##   CHAIN   hop from creep to creep, each hop starting where the last one
##           ended. The Arcane Orb line, and Ultimate Annihilation Glyph
##   LINE    everything standing between the tower and its target, out to the
##           tower's own reach. Ice 2's Ice Lance, and the Beastmaster's beast
##   NEAREST the N closest creeps to a point, however they are arranged
##
## All three are pure SEARCHES. They pick creeps and hand them back; what is
## then done to them is the caller's, because a chain that damages and a chain
## that only slows want the same walk.
##
## Naive and linear, like TargetFinder and creep separation next to it. All
## three want the same spatial hash, and none of them is the reason to build it.

## How far a creep may sit off the line and still count as standing in it, in
## player cells. Half a cell each side, so a lance passes through a creep the
## player can see it passing through and misses one it can see it missing.
const LINE_HALF_WIDTH: float = 0.5


## Creeps struck by hopping outwards from `start`, never the same creep twice.
##
## Each hop searches from where the LAST one landed rather than from the tower,
## which is what makes a chain follow a line of creeps around a corner instead
## of only reaching the ones near its first target.
static func chain(area: PlayerArea, start: Unit, hops: int, hop_range: float,
		attack: AttackStats) -> Array[Creep]:
	var found: Array[Creep] = []
	if area == null || start == null || hops <= 0:
		return found

	var struck: Dictionary = {start: true}
	var from: Vector3 = start.global_position
	for _hop in range(hops):
		var next: Creep = _nearest_unstruck(area, from, hop_range, struck, attack)
		if next == null:
			break
		struck[next] = true
		found.append(next)
		from = next.global_position
	return found


## Every creep standing on the line from `from` towards `towards`, out to
## `reach` cells, nearest first and never more than `limit` of them.
##
## Nearest first because the damage usually grows per creep passed - a lance
## that hit the far one first would be ramping backwards along its own path.
static func line(area: PlayerArea, from: Vector3, towards: Vector3, reach: float,
		limit: int, attack: AttackStats) -> Array[Creep]:
	var found: Array[Creep] = []
	if area == null || limit <= 0 || reach <= 0.0:
		return found

	var direction: Vector3 = _flat(towards - from)
	if direction.length_squared() < 0.0001:
		return found
	direction = direction.normalized()

	var scored: Array = []
	for creep: Creep in TargetFinder.creeps_in_radius(area, from, reach):
		if !TargetFinder.can_be_hit_by(creep, attack):
			continue
		var offset: Vector3 = _flat(creep.global_position - from)
		var along: float = offset.dot(direction)
		if along < 0.0:
			continue
		var sideways: float = (offset - direction * along).length()
		if sideways > LINE_HALF_WIDTH + creep.body_radius():
			continue
		scored.append([along, creep])

	scored.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for entry in scored:
		if found.size() >= limit:
			break
		found.append(entry[1] as Creep)
	return found


## The `count` creeps nearest a point, nearest first, skipping anything in
## `skip`. The plainest of the three, and what a multi-target burst wants.
static func nearest(area: PlayerArea, at: Vector3, radius: float, count: int,
		attack: AttackStats, skip: Dictionary = {}) -> Array[Creep]:
	var found: Array[Creep] = []
	if area == null || count <= 0:
		return found

	var scored: Array = []
	for creep: Creep in TargetFinder.creeps_in_radius(area, at, radius):
		if skip.has(creep) || !TargetFinder.can_be_hit_by(creep, attack):
			continue
		scored.append([at.distance_squared_to(creep.global_position), creep])

	scored.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for entry in scored:
		if found.size() >= count:
			break
		found.append(entry[1] as Creep)
	return found


## One creep at random from those in range, or null. What every "marks a RANDOM
## creep within N" in unit_data.md picks with.
##
## Rolled on the shared match RNG rather than the global one, because the
## server rolls and every machine has to be able to arrive at the same world
## from the same seed. See MatchSession.match_rng().
static func random_in_radius(area: PlayerArea, at: Vector3, radius: float,
		attack: AttackStats) -> Creep:
	var candidates: Array[Creep] = []
	for creep: Creep in TargetFinder.creeps_in_radius(area, at, radius):
		if TargetFinder.can_be_hit_by(creep, attack):
			candidates.append(creep)
	if candidates.is_empty():
		return null
	return candidates[MatchSession.match_rng().randi_range(0, candidates.size() - 1)]


static func _nearest_unstruck(area: PlayerArea, from: Vector3, reach: float,
		struck: Dictionary, attack: AttackStats) -> Creep:
	var best: Creep = null
	var best_distance: float = INF
	for creep: Creep in TargetFinder.creeps_in_radius(area, from, reach):
		if struck.has(creep) || !TargetFinder.can_be_hit_by(creep, attack):
			continue
		var distance: float = from.distance_squared_to(creep.global_position)
		if distance < best_distance:
			best = creep
			best_distance = distance
	return best


## Flattened onto the xz plane, because the game is played there and a flyer's
## height is only ever visual.
static func _flat(offset: Vector3) -> Vector3:
	return Vector3(offset.x, 0.0, offset.z)
