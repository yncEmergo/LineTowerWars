class_name SplashEffect
extends AttackEffect

## Damages everything standing around the point the attack landed.
##
## The creep that was actually hit is skipped, because it already took the
## attack's own damage. Otherwise a splash tower would quietly deal its primary
## target double.
##
## Splash reaches creeps the tower itself could not have shot: the radius is
## measured from the impact, not from the tower, so an orb landing at the edge
## of a tower's range still catches what is standing just beyond it. That is
## deliberate and is what makes a big splash worth its short range.
##
## FLAT: everything inside the radius takes the attack's full damage, and
## nothing outside it takes any. There is deliberately no falloff - the source
## game has none, and a ring that pays less for being at its edge would make
## the radius a number a player cannot read off the ground.

@export_group("Splash")
## Radius around the impact, in player cells.
@export var radius: float = 1.0


func apply(hit: AttackHit, target: Unit, impact_point: Vector3) -> void:
	if hit == null || hit.area == null || radius <= 0.0:
		return

	for creep: Creep in TargetFinder.creeps_in_radius(hit.area, impact_point, radius):
		if creep == target:
			continue
		# Always area damage, whatever hit.is_aoe says. That flag labels the
		# attack as a whole, and a splash is the definition of covering ground
		# however the tower that threw it is set up.
		creep.take_damage(hit.damage, hit.damage_type, true)


func effect_name() -> String:
	return "Splash"


## Phrased as "a 1 cell radius" rather than "within 1 cells", so a whole number
## radius does not read as broken English.
func description_text() -> String:
	return "Deals full damage to everything in a %s cell radius around the impact." \
		% StringUtil.trim_number(radius)
