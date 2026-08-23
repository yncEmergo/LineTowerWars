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
		if !_is_shootable(creep):
			continue
		if _flat_distance_squared(center, creep.global_position) <= limit:
			found.append(creep)

	return found


## The one creep a tower with these stats should be shooting from this point,
## or null when nothing is in range.
static func best_target(area: PlayerArea, center: Vector3, stats: AttackStats) -> Creep:
	if area == null || stats == null:
		return null

	var best: Creep = null
	var best_score: float = NO_SCORE
	var limit: float = stats.attack_range * stats.attack_range

	for child: Node in area.creeps_root().get_children():
		var creep: Creep = child as Creep
		if !_is_shootable(creep) || !can_be_hit_by(creep, stats):
			continue

		var distance: float = _flat_distance_squared(center, creep.global_position)
		if distance > limit:
			continue

		var score: float = _score(creep, distance, stats.target_priority)
		if best == null || score < best_score:
			best = creep
			best_score = score

	return best


## Whether an attack may hit this creep at all, which for now is only the
## ground versus air question. Range is not part of it, since a splash catches
## creeps the tower itself could never have reached.
static func can_be_hit_by(creep: Creep, stats: AttackStats) -> bool:
	if creep == null || stats == null:
		return false
	if creep.is_flying():
		return stats.can_hit_air()
	return stats.can_hit_ground()


## Whether a tower at this point still has this creep in range, used to drop a
## target that has walked away rather than re-scanning for one every frame.
static func is_in_range(center: Vector3, creep: Creep, attack_range: float) -> bool:
	if !_is_shootable(creep):
		return false
	return _flat_distance_squared(center, creep.global_position) <= attack_range * attack_range


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


static func _is_shootable(creep: Creep) -> bool:
	if creep == null || !is_instance_valid(creep) || creep.is_queued_for_deletion():
		return false
	return creep.is_alive() && !creep.is_invulnerable()


## Distances are compared flat, because the game is played on the xz plane and
## a creep's height is only ever visual.
static func _flat_distance_squared(from: Vector3, to: Vector3) -> float:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	return dx * dx + dz * dz
