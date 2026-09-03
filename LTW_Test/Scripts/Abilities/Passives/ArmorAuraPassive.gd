class_name ArmorAuraPassive
extends CreepPassive

## Grants armour points to every creep around this one, itself included.
##
## The radius is deliberately NOT a setting here. EVERY creep aura in the game
## shares one radius, GameConfig.creep_aura_radius_cells, so a player learns
## the size of an aura once and it holds for all of them. See game_rules.md.
##
## Auras do not stack: two of these in range grant the better of the two rather
## than their sum, which is the WC3 convention and keeps a stacked pack from
## walking through a maze untouched.
##
## Armour points, not a damage share, so what the aura is worth depends on how
## much armour the creep already has - see DamageTable.armor_multiplier.

@export_group("Settings")
@export var armor_bonus: int = 3


func aura_armor_bonus(_creep: Creep) -> int:
	return armor_bonus


func effect_text() -> String:
	var radius: float = 0.0
	var config: GameConfig = References.game_config
	if config != null:
		radius = config.creep_aura_radius_cells
	return "Grants +%d armor to every creep within %s." \
		% [armor_bonus, StringUtil.trim_number(radius)]
