class_name RegenAuraPassive
extends CreepPassive

## Heals every creep around this one over time, itself included.
##
## The aura counterpart of HealthRegenPassive, which heals only the creep
## carrying it. A pack walking with one of these out-heals chip damage as a
## group, so a maze has to out-damage the aura rather than merely interrupt it.
##
## The radius is the shared creep aura radius like every other aura, and auras
## do not stack: two of these in range heal the better of the two rather than
## their sum. See game_rules.md.

@export_group("Settings")
@export var health_per_second: float = 2.0


func aura_health_regen(_creep: Creep) -> float:
	return maxf(0.0, health_per_second)


func effect_text() -> String:
	var radius: float = 0.0
	var config: GameConfig = References.game_config
	if config != null:
		radius = config.creep_aura_radius_cells
	return "Restores %s health per second to every creep within %s." % [
		StringUtil.trim_number(health_per_second), StringUtil.trim_number(radius),
	]
