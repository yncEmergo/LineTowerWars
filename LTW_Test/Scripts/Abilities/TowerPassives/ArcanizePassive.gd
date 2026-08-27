class_name ArcanizePassive
extends TowerPassive

## Arcane base towers: fills itself up by shooting, and hits far harder once
## it is full.
##
## unit_data.md 4.1: the Apprentice gains a point of mana per attack and deals
## double damage at maximum; the Sorcerer deals two and a half times. It is the
## simplest ramp in the game and the one that most rewards a tower being left
## alone with a long lane in front of it.
##
## Mana is NOT reduced when the tower is upgraded, which Building already does
## for every tower - see inherit_ability_state.

@export_group("Arcanize")
## Mana gained per attack.
@export var mana_per_attack: float = 1.0
## Extra damage at FULL mana, as a share of the roll. 1.0 is the +100% of the
## Apprentice; it is all or nothing rather than scaled, which is what the
## source states.
@export var full_mana_bonus: float = 1.0


func on_attack(tower: Building, _target: Unit) -> void:
	tower.gain_mana(mana_per_attack)


func bonus_damage(tower: Building, _target: Unit, rolled: int) -> int:
	if !tower.has_full_mana():
		return 0
	return int(round(float(rolled) * full_mana_bonus))


func effect_text() -> String:
	return ("Attacks increase mana by %s. At maximum mana, damage dealt is"
		+ " increased by %d%%.") % [
		StringUtil.trim_number(mana_per_attack),
		int(round(full_mana_bonus * 100.0)),
	]
