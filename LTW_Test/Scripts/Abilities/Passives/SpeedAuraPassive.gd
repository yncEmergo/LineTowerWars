class_name SpeedAuraPassive
extends CreepPassive

## Speeds up every creep around this one, itself included.
##
## Two speeds rather than one, because the source game's Endurance Aura raises
## both: how fast a creep WALKS and how fast it ATTACKS. Only the attacker
## creeps have an attack for the second half to act on, so for most of a pack
## this is a movement aura and nothing else - which is why both are one aura
## rather than two, exactly as the source states it.
##
## The radius is deliberately NOT a setting. EVERY creep aura in the game shares
## one radius, GameConfig.creep_aura_radius_cells, so a player learns the size
## of an aura once and it holds for all of them. See game_rules.md.
##
## Auras do not stack: the best one in range wins rather than their product.

@export_group("Settings")
## 0.10 is ten percent faster. One number drives both speeds where the source
## raises both by the same amount, and they are separate fields where it does
## not - the Tier 4 aura is +30% attack and +25% movement.
@export var move_speed_bonus: float = 0.1
@export var attack_speed_bonus: float = 0.1


func grants_aura() -> bool:
	return true


func aura_move_speed_ratio(_creep: Creep) -> float:
	return 1.0 + maxf(0.0, move_speed_bonus)


func aura_attack_speed_ratio(_creep: Creep) -> float:
	return 1.0 + maxf(0.0, attack_speed_bonus)


func effect_text() -> String:
	var radius: float = 0.0
	var config: GameConfig = References.game_config
	if config != null:
		radius = config.creep_aura_radius_cells

	var amount: String = "+%d%% movement and attack speed" \
		% roundi(move_speed_bonus * 100.0)
	if !is_equal_approx(move_speed_bonus, attack_speed_bonus):
		amount = "+%d%% attack speed and +%d%% movement speed" % [
			roundi(attack_speed_bonus * 100.0), roundi(move_speed_bonus * 100.0),
		]
	return "Grants %s to every creep within %s." \
		% [amount, StringUtil.trim_number(radius)]
