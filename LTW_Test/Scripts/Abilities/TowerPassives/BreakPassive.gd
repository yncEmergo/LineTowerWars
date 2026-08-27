class_name BreakPassive
extends TowerPassive

## Primal base towers: four attacks and a stun, forever.
##
## unit_data.md 4.7: a point of mana per attack, and at its (very small)
## maximum the tower spends the lot to stun what it hit. Nothing scales, which
## makes the Quarry and the Coreway the only base towers in the game whose
## ability is worth exactly as much in the last minute as in the first - and
## the reason Primal's economy sits entirely behind its path 1 upgrade.

@export_group("Break")
## Mana gained per attack. Its maximum is 4, so this is the whole cadence.
@export var mana_per_attack: float = 1.0
## How long the stun holds.
@export var stun_seconds: float = 0.8


func on_attack(tower: Building, _target: Unit) -> void:
	tower.gain_mana(mana_per_attack)


func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	if !is_primary || target == null || !tower.has_full_mana():
		return

	tower.drain_mana()
	var status: StatusEffects = status_of(target)
	if status != null:
		status.stun(stun_seconds)


func effect_text() -> String:
	return ("Gains %s mana per attack. At full mana it spends everything to"
		+ " stun the target for %ss.") % [
		StringUtil.trim_number(mana_per_attack),
		StringUtil.trim_number(stun_seconds),
	]
