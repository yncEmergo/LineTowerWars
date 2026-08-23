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

@export_group("Splash")
## Radius around the impact, in player cells.
@export var radius: float = 1.0
## Share of the attack's damage dealt at the very edge of the radius. 1.0 is a
## flat splash that hits everything equally, 0.0 fades to nothing.
@export_range(0.0, 1.0, 0.05) var edge_damage_ratio: float = 1.0


func apply(hit: AttackHit, target: Unit, impact_point: Vector3) -> void:
	if hit == null || hit.area == null || radius <= 0.0:
		return

	for creep: Creep in TargetFinder.creeps_in_radius(hit.area, impact_point, radius):
		if creep == target:
			continue

		var damage: int = _damage_at(hit.damage, impact_point, creep.global_position)
		if damage > 0:
			# Always area damage, whatever hit.is_aoe says. That flag labels
			# the attack as a whole, and a splash is the definition of covering
			# ground however the tower that threw it is set up.
			creep.take_damage(damage, hit.damage_type, true)


func effect_name() -> String:
	return "Splash"


## Phrased as "a 1 cell radius" rather than "within 1 cells", so a whole number
## radius does not read as broken English.
func description_text() -> String:
	var text: String = "Damages everything in a %s cell radius around the impact." \
		% StringUtil.trim_number(radius)
	if edge_damage_ratio < 1.0:
		text += " Falls off to %d%% of the damage at the edge." \
			% roundi(edge_damage_ratio * 100.0)
	return text


## Damage falls off linearly from the centre of the splash to its edge. Rounded
## up rather than down, so a creep inside the radius is never splashed for
## nothing at all.
func _damage_at(full_damage: int, center: Vector3, at: Vector3) -> int:
	if edge_damage_ratio >= 1.0:
		return full_damage

	var offset: Vector2 = Vector2(at.x - center.x, at.z - center.z)
	var falloff: float = clampf(offset.length() / radius, 0.0, 1.0)
	var ratio: float = lerpf(1.0, edge_damage_ratio, falloff)
	return maxi(1, ceili(float(full_damage) * ratio))
