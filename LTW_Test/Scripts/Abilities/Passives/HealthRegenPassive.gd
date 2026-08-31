class_name HealthRegenPassive
extends CreepPassive

## Restores health over time while the creep is alive.
##
## Runs all the time rather than only out of combat, so a maze has to
## out-damage it rather than merely interrupt it. A maze that cannot is one the
## creep walks through whole.
##
## Fractions are carried between frames rather than rounded away, so a rate
## below one point a second still heals instead of doing nothing at all.

@export_group("Settings")
@export var health_per_second: float = 5.0


func health_regen(_creep: Creep) -> float:
	return maxf(0.0, health_per_second)


func effect_text() -> String:
	return "Regenerates %s health per second." % StringUtil.trim_number(health_per_second)
