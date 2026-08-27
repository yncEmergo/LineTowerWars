class_name OverchargePassive
extends TowerPassive

## Lightning base towers: hits harder the healthier the target is.
##
## unit_data.md 4.6: "+2 damage for every 10% of the target's CURRENT health".
## The exact inverse of an execute - a Shock Particle is at its best against a
## fresh creep and worth almost nothing against one about to die, which is what
## makes the base Lightning towers a softener rather than a finisher.

@export_group("Overcharge")
## Damage added per 10% of the target's current health.
@export var damage_per_tenth: float = 2.0


func bonus_damage(_tower: Building, target: Unit, _rolled: int) -> int:
	if target == null || target.max_health() <= 0:
		return 0
	var tenths: float = (float(target.current_health) / float(target.max_health())) * 10.0
	return int(round(damage_per_tenth * tenths))


func effect_text() -> String:
	return "Attacks deal +%s damage for every 10%% of the target's current health." \
		% StringUtil.trim_number(damage_per_tenth)
