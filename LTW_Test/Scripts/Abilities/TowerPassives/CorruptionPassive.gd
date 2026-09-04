class_name CorruptionPassive
extends TowerPassive

## Unholy base towers: what a corrupted creep does when it dies.
##
## unit_data.md 4.8: a hit corrupts the creep for a few seconds, and a
## corrupted creep that dies inside that window explodes, damaging everything
## around where it fell. It is the cheapest area damage in the game and it only
## pays out when something else finishes the job, which is what makes the
## Unholy base towers a support rather than a killer.
##
## The corruption is a plain immunity-style flag on the creep rather than a new
## kind of status: this passive is what knows the tower's numbers, so it needs
## no more from the creep than "was I corrupted, and by how much".
##
## The explosion is dealt by the TOWER, at the point the creep fell, so a
## corrupted creep killed by somebody else's tower still pays out.

@export_group("Corruption")
## Seconds the corruption lasts.
@export var duration_seconds: float = 4.0
## Spell Damage the explosion deals.
@export var explosion_damage: int = 28
## Radius it covers, in player cells.
@export var explosion_cells: float = 1.25


func apply_debuffs(_tower: Building, target: Unit) -> void:
	var status: StatusEffects = status_of(target)
	if status != null:
		# Written as an immunity because that is exactly the shape: a key with
		# a countdown, asked before something is allowed to happen.
		status.set_immune(resource_path, duration_seconds)


## The creep died while corrupted, so it goes off. on_kill only fires for a
## creep this very tower struck, which already covers "was corrupted by me" -
## the immunity check covers "recently enough".
func on_kill(tower: Building, target: Unit) -> void:
	if target == null || tower.area == null:
		return
	var status: StatusEffects = status_of(target)
	if status == null || !status.is_immune(resource_path):
		return
	spell_burst(tower.area, target.global_position, explosion_cells, explosion_damage)


func effect_text() -> String:
	return ("Corrupts creeps hit for %ss. A corrupted creep that dies explodes"
		+ " for %s Spell Damage within %s.") % [
		StringUtil.trim_number(duration_seconds),
		StringUtil.compact_number(explosion_damage),
		StringUtil.trim_number(explosion_cells),
	]
