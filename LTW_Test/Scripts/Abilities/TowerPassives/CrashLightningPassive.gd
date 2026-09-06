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
##
## **THE RESET IS A CONDITION ON THE CEILING, NOT ON THE CAST**, and the
## difference is the whole of what used to be wrong here. The source reads
## "when below 20 maximum mana, it resets back to 100": a state the tower is
## IN, however it got there. Checking it only at the end of the tower's own
## cast meant a tower pushed under the floor by its NEIGHBOURS was never asked,
## and it could never ask itself either - a ceiling of zero can never be full,
## so it can never cast, so it could never reach the check that would have
## restored it. Two Ultimates stood side by side ground each other down to a
## dead ability with the mana bar gone. See on_tick, which is where the
## condition is answered now.

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
@export var neighbour_cells: float = 1.25


## Mana is gained per ATTACK rather than per creep hit, which matters because
## the Orb Keeper line is single target and would otherwise be identical.
func on_attack(tower: Building, _target: Unit) -> void:
	tower.gain_mana(mana_per_attack)


func bonus_damage(_tower: Building, target: Unit, _rolled: int) -> int:
	if target == null:
		return 0
	return int(round(float(target.current_health) * current_health_share))


## Watches the CEILING, which is the other half of the Ultimate's rule and the
## half that has to be asked every tick rather than after a cast.
##
## A tower under the floor may have been put there by its own casts or by a
## neighbour's reset, and the source does not distinguish - so neither does
## this. Nothing happens on the tiers that author no cost, and they pay one
## integer compare a tick for the question.
##
## It does NOT recurse into the neighbours it just pushed under the floor.
## Each of them answers this on its own next tick, which keeps a cluster's
## cascade spread over ticks instead of unbounded inside one - and every
## machine walks the same towers in the same order on the same tick, so the
## outcome is identical on all of them.
func on_tick(tower: Building, _delta: float) -> void:
	if max_mana_cost <= 0 || tower.max_mana >= max_mana_floor:
		return
	_reset_ceiling(tower)


func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	if !is_primary || target == null || !tower.has_full_mana():
		return

	tower.drain_mana()
	var status: StatusEffects = status_of(target)
	if status != null:
		status.stun(self, stun_seconds)
	target.take_damage(burst_damage, DamageTable.DamageType.SPELL)
	_spend_ceiling(tower)


## What one cast costs the tower's own ceiling. Nothing happens on the tiers
## that author no cost, which is what leaves them paying nothing for it.
##
## The reset is deliberately NOT done here even though this is where the
## ceiling usually crosses the floor: one place answers the condition, and it
## is the one that also catches a tower pushed under by somebody else. The
## caster simply waits a tick for it, which it would have spent refilling
## anyway - it has just emptied itself.
func _spend_ceiling(tower: Building) -> void:
	if max_mana_cost <= 0:
		return
	tower.set_max_mana(tower.max_mana - max_mana_cost)


## Back to a full ceiling, and every neighbour of the same kind loses part of
## theirs. Only towers carrying THIS passive are touched, which is what keeps
## the rule to one tower type without naming it.
##
## A neighbour this pushes under the floor - or to zero, which the penalty can
## do to one already low - is left there for its OWN next tick to pick up. So a
## ceiling of zero is reachable and lasts exactly one tick, which is the rule
## working rather than the bug that used to live here: what was wrong was a
## zero nothing ever came back from. Verified over a long match with two of
## them side by side, neither spending more than a tick under the floor.
func _reset_ceiling(tower: Building) -> void:
	tower.set_max_mana(_authored_max(tower))
	for other: Building in _neighbours(tower):
		other.set_max_mana(other.max_mana - neighbour_penalty)


## The ceiling a reset restores, which is whatever the tower's own stats
## authored - 100 for the Ultimate Orb Keeper.
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
		# "back to full" rather than a figure, because the figure is the
		# TOWER's authored maximum and this resource has no tower in hand -
		# every reader of this line is already looking at the mana bar.
		text += (" Each cast lowers its own maximum mana by %d. Below %d"
			+ " maximum mana it resets back to full and lowers the maximum"
			+ " mana of other %s towers within %s by %d.") % [
			max_mana_cost, max_mana_floor, display_name,
			StringUtil.trim_number(neighbour_cells), neighbour_penalty]
	return text
