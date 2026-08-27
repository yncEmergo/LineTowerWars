class_name CrashLightningPassive
extends TowerPassive

## Lightning 2, the whole Orb Keeper line: fills up over four attacks and
## spends the lot on a stun.
##
## unit_data.md 4.6: every attack gains mana and deals extra damage equal to a
## share of the target's CURRENT health; at full mana the tower spends all of
## it to stun the target briefly and deal a large flat Spell Damage.
##
## The Ultimate adds the strangest rule in the element: each cast lowers the
## tower's own MAXIMUM mana, and when that ceiling falls too far it snaps back
## to full and drags the ceiling of the other Ultimate Orb Keepers standing
## near it DOWN with it. Two of them packed together are worth less than two of
## them spread out, which is the only anti-clustering rule outside Primal.

@export_group("Crash Lightning")
## Mana gained per attack.
@export var mana_per_attack: float = 10.0
## Extra damage as a share of the target's CURRENT health.
@export var current_health_share: float = 0.012
## Seconds the target is stunned when the tower spends its mana.
@export var stun_seconds: float = 0.67
## Flat Spell Damage the cast deals on top of the stun.
@export var burst_damage: int = 300

@export_group("Ultimate")
## Maximum mana lost per cast, or 0 on the tiers that keep their ceiling.
@export var max_mana_cost: int = 0
## The ceiling below which it resets to full and pulls its neighbours down.
@export var max_mana_floor: int = 20
## What a reset takes off the ceiling of every other Ultimate Orb Keeper in
## range.
@export var neighbour_penalty: int = 20
## How far that reaches, in player cells.
@export var neighbour_cells: float = 1.17


## Mana is gained per ATTACK rather than per creep hit, which matters because
## the Orb Keeper line is single target and would otherwise be identical.
func on_attack(tower: Building, _target: Unit) -> void:
	tower.gain_mana(mana_per_attack)


func bonus_damage(_tower: Building, target: Unit, _rolled: int) -> int:
	if target == null:
		return 0
	return int(round(float(target.current_health) * current_health_share))


func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	if !is_primary || target == null || !tower.has_full_mana():
		return

	tower.drain_mana()
	var status: StatusEffects = status_of(target)
	if status != null:
		status.stun(stun_seconds)
	target.take_damage(burst_damage, DamageTable.DamageType.SPELL)
	_spend_ceiling(tower)


## The Ultimate's own half. Nothing happens on the tiers that author no cost,
## which is what leaves them paying nothing for the question.
func _spend_ceiling(tower: Building) -> void:
	if max_mana_cost <= 0:
		return

	if tower.set_max_mana(tower.max_mana - max_mana_cost) >= max_mana_floor:
		return

	# Bottomed out: back to a full ceiling, and every neighbour of the same
	# kind loses part of theirs. Only towers carrying THIS passive are touched,
	# which is what keeps the rule to one tower type without naming it.
	tower.set_max_mana(_authored_max(tower))
	for other: Building in _neighbours(tower):
		other.set_max_mana(other.max_mana - neighbour_penalty)


func _authored_max(tower: Building) -> int:
	var stats: BuildingStats = tower.stats as BuildingStats
	return tower.max_mana if stats == null else stats.max_mana


## Every other tower in range carrying this very passive resource. Identity
## rather than a type check: two different tiers of Orb Keeper carry different
## .tres files and do not drag each other's ceilings about.
func _neighbours(tower: Building) -> Array[Building]:
	var found: Array[Building] = []
	if tower.area == null:
		return found

	for child: Node in tower.area.get_children():
		var other: Building = child as Building
		if other == null || other == tower || !(self in other.tower_passives()):
			continue
		var offset: Vector3 = other.global_position - tower.global_position
		if Vector2(offset.x, offset.z).length() <= neighbour_cells:
			found.append(other)
	return found


func effect_text() -> String:
	var text: String = ("Gains %s mana per attack and deals extra damage equal"
		+ " to %s%% of the target's current health. At full mana it spends"
		+ " everything to stun for %ss and deal %s bonus Spell Damage.") % [
		StringUtil.trim_number(mana_per_attack),
		StringUtil.trim_number(current_health_share * 100.0),
		StringUtil.trim_number(stun_seconds),
		StringUtil.compact_number(burst_damage),
	]
	if max_mana_cost > 0:
		text += (" Each cast lowers its own maximum mana by %d; below %d it"
			+ " resets and lowers nearby Orb Keepers by %d.") % [
			max_mana_cost, max_mana_floor, neighbour_penalty]
	return text
