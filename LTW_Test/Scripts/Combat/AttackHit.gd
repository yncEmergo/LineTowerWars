class_name AttackHit
extends RefCounted

## One attack in flight, from the moment the tower fires until it lands.
##
## Carries copies of everything the hit needs rather than a handle on the tower
## that fired it. A projectile can be halfway to its target when its tower is
## sold, and that shot still has to land: holding the tower would either crash
## or quietly swallow the damage.
##
## Created fresh per attack, so unlike the resources it copies from, this one is
## allowed to hold state.

## Rolled once when the tower fires, so every creep caught by the same shot
## takes the same roll rather than each rolling its own.
var damage: int = 0
var damage_type: DamageTable.DamageType = DamageTable.DamageType.NORMAL
## Whether this counts as area damage, which some creeps resist. Copied off the
## attack when it fires rather than asked of it later, for the same reason the
## damage roll is: the tower may be gone by the time the shot lands.
var is_aoe: bool = false
## Applied in order once the hit lands. Shared resources, never modified.
var effects: Array[AttackEffect] = []
## Area the attack happened in, which is what splash and chain search.
var area: PlayerArea
## Who fired. Not used for damage, since a tower shoots every creep in its own
## area whoever sent it, but kill credit and future effects want it.
var attacker_player_id: int = 1


## Lands the hit: the primary target takes the damage, then every effect gets
## its turn at the impact point.
##
## target may be null when the creep died mid flight. The effects still run,
## because a cannon orb that arrives a moment late should still splash the
## crowd standing where its target was.
func resolve(target: Unit, impact_point: Vector3) -> void:
	if target != null && is_instance_valid(target) && target.is_alive():
		target.take_damage(damage, damage_type, is_aoe)

	for effect: AttackEffect in effects:
		if effect != null:
			effect.apply(self, target, impact_point)
