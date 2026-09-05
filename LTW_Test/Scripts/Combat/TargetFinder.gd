class_name TargetFinder
extends RefCounted

## Finds creeps for towers to shoot and for splashes to catch.
##
## Deliberately not physics. Creeps carry no collider at all - they move on the
## grid and test their next position against it - so range detection walks the
## area's own creep list instead of putting an Area3D on every tower. That list
## is already parented per area, which is also the ownership rule: a tower
## shoots every creep walking its area, whoever sent it. Creeps belong to the
## sender, so a hostility test would have a player's towers ignore the creeps
## they are defending against the moment sending across areas exists.
##
## Naive and linear, and now the last scan of this shape that a full lane pays
## every tick - creep separation used to be the other one and is no longer run
## for the ordinary roster. It wants a spatial hash before the population cap
## of 100 is real.
##
## What it does NOT do any more is walk that list more than once per search.
## See _scan.

## Score returned for a candidate that cannot be used at all.
const NO_SCORE: float = INF

## The four candidates one pass sorts the lane into, listed in the order
## best_target reads them back out. Both flyer slots are only ever read when
## the tower's Prioritize toggle is on and the attack can reach air at all.
##
## Four rather than two because the two preferences are independent: air-first
## is the player's setting and skittering-last is the creep's own rule, and a
## tower with Prioritize on still wants an ordinary ground creep before a
## skittering flyer.
const SLOT_FLYER: int = 0
const SLOT_ANY: int = 1
const SLOT_SKITTERING_FLYER: int = 2
const SLOT_SKITTERING_ANY: int = 3
const SLOT_COUNT: int = 4


## Every live creep of this area standing within radius of a world point.
static func creeps_in_radius(area: PlayerArea, center: Vector3, radius: float) -> Array[Creep]:
	var found: Array[Creep] = []
	if area == null || radius <= 0.0:
		return found

	var limit: float = radius * radius
	# DISTANCE FIRST, then the predicate. Three float operations reject most
	# candidates; _is_attackable is five calls, and paying those for a creep
	# standing at the other end of the lane was most of what this cost.
	for creep: Creep in area.creeps_near(center, radius):
		if _flat_distance_squared(center, creep.global_position) > limit:
			continue
		if _is_attackable(creep):
			found.append(creep)

	return found


## Every building of this area standing within radius of a world point.
##
## The mirror of creeps_in_radius above, and the same list best_building_target
## narrows down to one - what differs is only which question the caller is
## asking. The Siege Engine's Bombardment picks a RANDOM tower in range rather
## than the nearest, so it wants them all and chooses for itself.
##
## Only towers are ever found, and structurally rather than by filtering: the
## builder is a MobileUnit, a sender is not in the world at all, and a
## technology disc is invulnerable, so none of them is a Building this could
## return. unit_data.md 1.5 is the rule.
##
## Which also means a disc's OWN aura cannot find another disc through here,
## and that is the answer the disc auras want: every one of them is stated as
## reaching friendly TOWERS.
static func buildings_in_radius(area: PlayerArea, center: Vector3,
		radius: float) -> Array[Building]:
	var found: Array[Building] = []
	if area == null || radius <= 0.0:
		return found

	var limit: float = radius * radius
	for child: Node in area.get_children():
		var building: Building = child as Building
		if !_is_attackable(building):
			continue
		if _flat_distance_squared(center, building.global_position) <= limit:
			found.append(building)

	return found


## The one creep a tower with these stats should be shooting from this point,
## or null when nothing is in range.
##
## Two rules narrow the search before the tower's own priority is ever asked,
## and both are PRIORITIES rather than restrictions: each says what to prefer,
## never what to refuse.
##
##   prefer_air is the Prioritize toggle. Flyers first, then everything, so a
##   tower set to watch the sky still shoots ground rather than standing idle.
##
##   SKITTERING is the creep's own, and it outranks the toggle: a skittering
##   creep is considered only once nothing else is left in range at all, which
##   is what "never draws attention, always targeted last" means. An attack
##   ORDER does not come through here, so one can still be aimed at it by hand.
##
## Both used to be a pass of their own over the whole lane. They are now four
## slots filled by a single pass and read back here in that same order, which
## is the same answer for a quarter of the work - see _scan.
static func best_target(area: PlayerArea, center: Vector3, stats: AttackStats,
		prefer_air: bool = false, range_bonus: float = 0.0) -> Creep:
	if area == null || stats == null:
		return null

	var found: Array[Creep] = _scan(area, center, stats, range_bonus)
	var air_first: bool = prefer_air && stats.can_hit_air()

	if air_first && found[SLOT_FLYER] != null:
		return found[SLOT_FLYER]
	if found[SLOT_ANY] != null:
		return found[SLOT_ANY]
	if air_first && found[SLOT_SKITTERING_FLYER] != null:
		return found[SLOT_SKITTERING_FLYER]
	return found[SLOT_SKITTERING_ANY]


## The one BUILDING an attacker creep should be attacking from this point, or
## null when none is in range.
##
## Always the NEAREST, whatever the attack's target_priority says. That field
## ranks creeps - first in line, strongest, weakest - and none of those
## questions means anything about a tower standing still, so an attacker
## reading it would be answering a question nobody asked.
##
## Only towers are ever found here, and that is structural rather than
## filtered: the builder is a MobileUnit, and the send building and the
## technology discs are invulnerable, so none of the three is a Building this
## could return. unit_data.md 1.5 is the rule, and it is why a wall of discs is
## a wall an attacker creep cannot open.
static func best_building_target(area: PlayerArea, center: Vector3,
		stats: AttackStats, range_bonus: float = 0.0) -> Building:
	if stats == null:
		return null
	return _nearest_building(area, center, stats.attack_range + range_bonus)


## The nearest building anywhere in the area, however far away it is.
##
## What an unordered attacker creep walks TOWARDS, which is a different
## question to what it can shoot right now: it has to pick something long
## before it is close enough to hit anything.
static func nearest_building(area: PlayerArea, center: Vector3) -> Building:
	return _nearest_building(area, center, INF)


## The best creep in range for each of the four slots, in ONE walk of the lane.
##
## One walk rather than the two to four this used to take. The old shape ran a
## filtered pass per preference and threw away every creep that did not match
## the flag it had been handed, so a lane holding only skittering creeps - a
## Forest Troll wave is exactly that - paid for a complete pass that could not
## match anything before the pass that could. A tower with an empty range
## circle, which is most of a maze at any moment, paid for both and got
## nothing either time. It was the largest single cost in a loaded tick.
##
## A creep is SCORED once and offered to the slots it qualifies for, so no two
## slots can disagree about one. The old shape had to state that as a rule it
## was careful about; here it is the only thing that can happen.
##
## Ties still go to the creep found first, because the offer is a strict
## improvement and the lane is walked in the one order both machines agree on.
##
## **That order is LOAD-BEARING and nothing enforces it.** It comes from
## `PlayerArea._creeps`, an Array in spawn-and-reparent order, read through
## `CreepIndex.near`, which walks its buckets over an ascending integer range.
## Both machines replay the same spawns, so both build the same Array and reach
## the same creep first. Sort that Array, pool it, or fill the index from a
## Dictionary, and two machines pick different targets on an exact score tie -
## which is a desync with no visible cause. **The tie-break on `unit_id` is now
## in `_offer`**, so this is no longer load-bearing for correctness - only for
## the order candidates are OFFERED in, which the tie-break makes irrelevant.
static func _scan(area: PlayerArea, center: Vector3, stats: AttackStats,
		range_bonus: float = 0.0) -> Array[Creep]:
	var best: Array[Creep] = []
	var scores: Array[float] = []
	best.resize(SLOT_COUNT)
	scores.resize(SLOT_COUNT)
	scores.fill(NO_SCORE)

	# The reach the SHOOTER has right now rather than the one its stats file
	# records: a Primal disc standing beside a tower lends it cells, and a
	# search that read only the stats would have the tower refuse to shoot at
	# something its own attack would happily reach. See Unit.attack_range_bonus.
	var reach: float = stats.attack_range + range_bonus
	var limit: float = reach * reach
	# Only the creeps near enough to be worth asking about, and the DISTANCE
	# asked before anything else: it is three float operations and it rejects
	# most of what arrives, where _is_attackable and can_be_hit_by are six
	# calls between them. The old order paid those for every creep in the lane.
	for creep: Creep in area.creeps_near(center, reach):
		var distance: float = _flat_distance_squared(center, creep.global_position)
		if distance > limit:
			continue

		if !_is_attackable(creep) || !can_be_hit_by(creep, stats):
			continue

		var score: float = _score(creep, distance, stats.target_priority)
		var skittering: bool = creep.is_skittering()
		_offer(best, scores, SLOT_SKITTERING_ANY if skittering else SLOT_ANY, creep, score)
		if creep.is_flying():
			_offer(best, scores, SLOT_SKITTERING_FLYER if skittering else SLOT_FLYER,
				creep, score)

	return best


## Keeps a candidate if it beats whatever is already in that slot. Lower is
## better, which is the order _score hands its answers back in.
static func _offer(best: Array[Creep], scores: Array[float], slot: int, creep: Creep,
		score: float) -> void:
	if best[slot] == null:
		best[slot] = creep
		scores[slot] = score
		return
	if score < scores[slot]:
		best[slot] = creep
		scores[slot] = score
		return
	# **The tie-break, and it is here BEFORE anything needs it.** On an exact
	# score tie the winner would otherwise be whichever creep this loop happened
	# to reach first, which is `PlayerArea._creeps` order - and the docstring
	# above says plainly that this holds only while that order is identical on
	# every machine. The spatial hash listed under known weaknesses in CLAUDE.md
	# is exactly the change that breaks it, and a desync from it would have no
	# visible cause at all.
	#
	# `unit_id` is authored, unique and identical everywhere, so it settles a tie
	# the same way on every machine whatever order the candidates arrive in.
	if score == scores[slot] && creep.unit_id < best[slot].unit_id:
		best[slot] = creep


## Buildings are parented straight under the area, unlike creeps which have a
## root of their own, so this walks the area itself. An unlimited reach is what
## the "walk towards one" question wants and is why the range comes in.
static func _nearest_building(area: PlayerArea, center: Vector3,
		reach: float) -> Building:
	if area == null:
		return null

	var best: Building = null
	var best_distance: float = NO_SCORE
	var limit: float = INF if is_inf(reach) else reach * reach

	# `distance >= best_distance` keeps the FIRST of two equally close towers,
	# and what decides which that is, is child order under the area - which is
	# the order the build commands arrived in, identical on every machine that
	# replayed them. Deterministic by construction rather than by a tie-break;
	# anything that reorders an area's children breaks it silently.
	for child: Node in area.get_children():
		var building: Building = child as Building
		if !_is_attackable(building):
			continue

		var distance: float = _flat_distance_squared(center, building.global_position)
		if distance > limit || distance >= best_distance:
			continue
		best = building
		best_distance = distance

	return best


## Whether an attack may hit this creep at all, which for now is only the
## ground versus air question. Range is not part of it, since a splash catches
## creeps the tower itself could never have reached.
static func can_be_hit_by(creep: Creep, stats: AttackStats) -> bool:
	if creep == null || stats == null:
		return false
	if creep.is_flying():
		# A PARALYZED flyer has been pulled out of the sky and stands there
		# like anything else, so a ground tower may shoot it. That is the whole
		# value of Water 1's paralyze and it is the one place air-versus-ground
		# is not decided by what the creep is. See unit_data.md 4.10.
		if creep.is_pinned():
			return stats.can_hit_ground() || stats.can_hit_air()
		return stats.can_hit_air()
	return stats.can_hit_ground()


## Whether an attacker at this point still has this target in range, used to
## drop one that has walked away rather than re-scanning for one every frame.
##
## Takes a Unit rather than a Creep: an attacker creep asks it about the tower
## it is chewing on and a tower asks it about a creep, and it is the same
## question both ways round.
static func is_in_range(center: Vector3, unit: Unit, attack_range: float) -> bool:
	if !_is_attackable(unit):
		return false
	return _flat_distance_squared(center, unit.global_position) <= attack_range * attack_range


## Lower is better, so every priority can be compared the same way.
static func _score(creep: Creep, distance_squared: float, priority: int) -> float:
	match priority:
		AttackStats.TargetPriority.CLOSEST:
			return distance_squared
		AttackStats.TargetPriority.STRONGEST:
			return float(-creep.current_health)
		AttackStats.TargetPriority.WEAKEST:
			return float(creep.current_health)

	# FIRST, and the fallback for anything unrecognised: furthest along its
	# route, which is the creep closest to leaking.
	return float(creep.steps_to_exit())


## Whether a unit can be attacked at all: it exists, it is not on its way out,
## it has health left and it is not invulnerable. Invulnerability is the whole
## of the builder-and-disc rule in unit_data.md 1.5, so nothing has to be named
## by type here.
## The public form of the test below, for callers that select creeps by
## something other than a radius and must not quietly disagree about which of
## them count. PlayerArea.aura_sources is the one that does.
static func is_attackable(unit: Unit) -> bool:
	return _is_attackable(unit)


static func _is_attackable(unit: Unit) -> bool:
	if unit == null || !is_instance_valid(unit) || unit.is_queued_for_deletion():
		return false
	return unit.is_alive() && !unit.is_invulnerable()


## Distances are compared flat, because the game is played on the xz plane and
## a creep's height is only ever visual.
static func _flat_distance_squared(from: Vector3, to: Vector3) -> float:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	return dx * dx + dz * dz
