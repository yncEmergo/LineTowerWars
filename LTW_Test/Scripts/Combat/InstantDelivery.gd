class_name InstantDelivery
extends AttackDelivery

## The damage lands the same moment the tower attacks, with no travel time.
##
## This is the delivery for anything that touches its target directly: a
## spinning blade, a stomp, a beam. Leaving impact_scene empty gives a tower
## that has no attack visual at all, which is exactly right for a grinder whose
## own model is already the attack.


func deliver(hit: AttackHit, from: Vector3, target: Unit) -> void:
	# A dead target still has a position worth splashing, so the impact point
	# falls back to the muzzle only when the target is gone entirely.
	var point: Vector3 = from
	if target != null && is_instance_valid(target):
		point = target.global_position

	hit.resolve(target, point)
	spawn_impact(point)
