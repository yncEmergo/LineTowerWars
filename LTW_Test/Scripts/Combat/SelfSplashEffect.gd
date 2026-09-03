class_name SelfSplashEffect
extends AttackEffect

## Damages everything standing around the ATTACKER, not around the impact.
##
## The Crusher is what this exists for: its reach is barely more than a cell
## while its blast is more than twice that, so what it really does is flatten
## the ground it stands on. Measuring that from whichever creep it happened to
## swing at would mean a tower whose damage lands somewhere slightly different
## every time, for no reason a player could see or use.
##
## **A deliberate exception to the splash rule in game_rules.md**, which is
## otherwise measured from the impact. That rule is what lets a cannon shell
## reach past a tower's own range; this one does the opposite, and the two are
## different enough to be different effects rather than a flag on one.
##
## Consequences worth knowing, because they follow from the centre moving and
## not from anything else:
##   - the creep that was hit takes the attack's damage as usual, then this
##     skips it, exactly as SplashEffect does
##   - a creep BEHIND the tower is caught, though nothing could be targeted
##     there. That is the point of a tower that swings at its own feet
##   - a creep at the far edge of the tower's reach can fall OUTSIDE the blast
##     if the radius is ever authored smaller than the range, which would be an
##     odd tower. validate() says so once at boot rather than every swing
##
## The attacker's position rides in the AttackHit rather than being read off a
## node, for the same reason everything else there does: the tower can be sold
## while the swing is still in the air.

@export_group("Splash")
## Radius around the attacker, in player cells.
@export var radius: float = 1.0


func apply(hit: AttackHit, target: Unit, _impact_point: Vector3) -> void:
	if hit == null || hit.area == null || radius <= 0.0:
		return

	for creep: Creep in TargetFinder.creeps_in_radius(
			hit.area, hit.attacker_position, radius):
		if creep == target:
			continue
		# Always area damage, whatever hit.is_aoe says - covering ground is
		# what this is, however the tower that threw it is set up. Through the
		# hit, so a kill by the blast counts as this tower's; see
		# AttackHit.splash_onto.
		hit.splash_onto(creep, hit.damage, hit.damage_type)


func effect_name() -> String:
	return "Shockwave"


## Says "around itself" rather than "around the impact", because that is the
## whole difference between this and an ordinary splash and a player reading
## the card has no other way to find it out.
func description_text() -> String:
	return "Deals full damage to everything within %s of the tower itself." \
		% StringUtil.trim_number(radius)
