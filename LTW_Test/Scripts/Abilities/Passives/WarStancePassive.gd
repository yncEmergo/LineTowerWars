class_name WarStancePassive
extends CreepPassive

## Becomes a different creep once it is nearly dead.
##
## The Kodo Beast trait. unit_data.md 6.6: "at 30% health, gains Hero armour
## type, +7 armour, and an aura giving creeps within 2,000 AoE +20% attack
## damage."
##
## THE ARMOUR TYPE IS THE LOUD HALF. A Kodo at a third of its health stops
## being the thing the maze was killing and starts counting as Hero armour,
## which every damage type in the matrix is worse against - so the last third
## of its health takes far longer to remove than the first two, and a maze that
## was comfortably ahead of a pack of them is suddenly not.
##
## It is a THRESHOLD rather than a one-shot trigger, which matters: heal a Kodo
## back over the line and it loses all three, and this is one of the very few
## things in the roster a Regen Aura therefore turns off. That is deliberate,
## and it is why nothing is spent on the creep to record it - the answer is
## read off the health every time it is asked.
##
## `?` THE AURA RADIUS IS THIS PROJECT. The source states 2,000, which is 15.6
## cells and would cover most of a lane - and every creep aura in this game
## shares ONE radius so a player learns it once (game_rules.md). It uses the
## shared radius like every other aura, and the source figure is recorded here
## rather than in the code.

@export_group("Settings")
## Health share at or below which all three switch on.
@export_range(0.0, 1.0, 0.05) var at_health: float = 0.3
## Armour points gained.
@export var armor_bonus: int = 7
## Armour type it counts as instead of its own.
@export var armor_type: UnitStats.ArmorType = UnitStats.ArmorType.HERO
## Extra share of attack damage granted to every creep in the shared aura
## radius, which only the attacker creeps have anything for.
@export_range(0.0, 2.0, 0.05) var damage_bonus: float = 0.20


func armor_delta(creep: Creep) -> int:
	return armor_bonus if _roused(creep) else 0


func armor_type_override(creep: Creep) -> int:
	return int(armor_type) if _roused(creep) else -1


func grants_aura() -> bool:
	return true


func aura_attack_damage_ratio(creep: Creep) -> float:
	return 1.0 + damage_bonus if _roused(creep) else 1.0


## Whether the creep is under the line right now. Read every time rather than
## recorded, which is what makes healing it back over the line switch all three
## off again.
func _roused(creep: Creep) -> bool:
	if creep == null || creep.max_health() <= 0:
		return false
	return creep.current_health <= float(creep.max_health()) * at_health


func effect_text() -> String:
	return ("Below %d%% health it counts as %s armor, gains +%d armor, and"
		+ " grants every creep within %s +%d%% attack damage.") % [
		roundi(at_health * 100.0), UnitStats.armor_type_name(armor_type),
		armor_bonus, StringUtil.trim_number(CreepPassive.aura_radius()),
		roundi(damage_bonus * 100.0),
	]
