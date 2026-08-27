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
## Naive and linear, like creep separation. Both want the same spatial hash
## before the population cap of 100 is real.

## Score returned for a candidate that cannot be used at all.
const NO_SCORE: float = INF


## Every live creep of this area standing within radius of a world point.
static func creeps_in_radius(area: PlayerArea, center: Vector3, radius: float) -> Array[Creep]:
	var found: Array[Creep] = []
	if area == null || radius <= 0.0:
		return found

	var limit: float = radius * radius
	for child: Node in area.creeps_root().get_children():
		var creep: Creep = child as Creep
		if !_is_attackable(creep):
			continue
		if _flat_distance_squared(center, creep.global_position) <= limit:
			found.append(creep)

	return found


## The one creep a tower with these stats should be shooting from this point,
## or null when nothing is in range.
##
## Two rules narrow the search before the tower's own priority is ever asked,
## and both work the same way: run the ordinary search over a subset first and
## fall back to the rest, so each is a PRIORITY rather than a restriction.
##
##   prefer_air is the Prioritize toggle. Flyers first, then everything, so a
##   tower set to watch the sky still shoots ground rather than standing idle.
##
##   SKITTERING is the creep's own, and it is the outer loop: a skittering
##   creep is considered only once nothing else is left in range at all, which
##   is what "never draws attention, always targeted last" means. An attack
##   ORDER does not come through here, so one can still be aimed at it by hand.
static func best_target(area: PlayerArea, center: Vector3, stats: AttackStats,
		prefer_air: bool = false) -> Creep:
	if area == null || stats == null:
		return null

	for skittering: bool in [false, true]:
		if prefer_air && stats.can_hit_air():
			var flyer: Creep = _best_in(area, center, stats, true, skittering)
			if flyer != null:
				return flyer

		var found: Creep = _best_in(area, center, stats, false, skittering)
		if found != null:
			return found

	return null


## The one BUILDING an attacker creep should be attacking from this point, or
## null when none is in range.
##
## Always the NEAREST, whatever the attack's target_priority says. That field
## ranks creeps - first in line, strongest, weakest - and none of those
## questions means anything about a tower standing still, so an attacker
## reading it would be answering a question nobody asked.
##
## Only towers are ever found here, and that is structural rather than
## filtered: the builder is a MobileUnit and the send building is invulnerable,
## so neither is a Building this could return, and a technology disc will be
## invulnerable for the same reason. unit_data.md 1.5 is the rule.
static func best_building_target(area: PlayerArea, center: Vector3,
		stats: AttackStats) -> Building:
	if stats == null:
		return null
	return _nearest_building(area, center, stats.attack_range)


## The nearest building anywhere in the area, however far away it is.
##
## What an unordered attacker creep walks TOWARDS, which is a different
## question to what it can shoot right now: it has to pick something long
## before it is close enough to hit anything.
static func nearest_building(area: PlayerArea, center: Vector3) -> Building:
	return _nearest_building(area, center, INF)


## The best creep in range, restricted to flyers and to skittering creeps
## independently. Both restrictions are arguments rather than second loops, so
## no two passes can ever come to score the same creep differently.
static func _best_in(area: PlayerArea, center: Vector3, stats: AttackStats,
		flyers_only: bool, skittering: bool) -> Creep:
	var best: Creep = null
	var best_score: float = NO_SCORE
	var limit: float = stats.attack_range * stats.attack_range

	for child: Node in area.creeps_root().get_children():
		var creep: Creep = child as Creep
		if !_is_attackable(creep) || !can_be_hit_by(creep, stats):
			continue
		if flyers_only && !creep.is_flying():
			continue
		if creep.is_skittering() != skittering:
			continue

		var distance: float = _flat_distance_squared(center, creep.global_position)
		if distance > limit:
			continue

		var score: float = _score(creep, distance, stats.target_priority)
		if best == null || score < best_score:
			best = creep
			best_score = score

	return best


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
