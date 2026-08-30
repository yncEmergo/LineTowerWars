class_name AncientBloomPassive
extends TowerPassive

## Primal 1, the whole Primalist line: the only tower in the game that makes
## GOLD, and it makes less the more of them you build.
##
## unit_data.md 4.7: every attack pays its owner, reduced by a large step for
## every other Primal technology tower standing nearby, down to a floor. So the
## economy tower wants to be SPREAD OUT through a maze rather than stacked in a
## corner, which is the only anti-clustering rule in the game outside the
## Ultimate Orb Keeper's - and the Ultimate lifts it entirely.
##
## The blast is the second half: mana regenerates on a clock, and at full mana
## the tower flattens the ground around its target and takes armour off
## everything caught. Half the mana comes back when it caught too few, so a
## Primalist over an empty lane keeps its charge rather than wasting it.

const REFUND_KEY: String = "bloom_refund"

@export_group("Ancient Bloom")
## Gold paid per attack before crowding is taken off.
@export var gold_per_attack: int = 120
## Gold taken off per nearby Primal tower.
@export var gold_per_neighbour: int = 48
## The least an attack may ever pay.
@export var minimum_gold: int = 12
## How far it looks for neighbours, in player cells. 0 lifts the rule entirely,
## which is what the Ultimate authors.
@export var crowding_cells: float = 1.95

@export_group("Blast")
## Mana regenerated per second.
@export var regen_per_second: float = 13.0
## Magic Physical Damage the blast deals. Physical, not Spell - the source says
## "Magic Physical Damage", which goes through the armour matrix like anything
## else. See unit_data.md 1.1.
@export var blast_damage: int = 350
## Radius it covers, in player cells.
@export var blast_cells: float = 1.56
## Armour taken off everything caught, and for how long. Temporary here, unlike
## Earth's, because the source states a duration.
@export var armor_reduction: float = 1.0
@export var armor_seconds: float = 7.0
## Catching this many or fewer refunds half the mana.
@export var refund_below: int = 4
@export var refund_share: float = 0.5


func mana_per_second(_tower: Building) -> float:
	return regen_per_second


## The gold is paid per ATTACK rather than per creep hit, which matters because
## the Primalist line is single target and a multishot would otherwise multiply
## a player's whole economy.
func on_attack(tower: Building, _target: Unit) -> void:
	if !MatchSession.is_authority():
		return

	var manager: PlayerManager = References.player_manager
	if manager == null:
		return
	var state: PlayerState = manager.state_for(tower.owner_player_id)
	if state != null:
		state.gain(_payout(tower))


func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	if !is_primary || target == null || !tower.has_full_mana() || tower.area == null:
		return

	tower.drain_mana()
	var caught: int = 0
	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, target.global_position, blast_cells):
		creep.take_damage(blast_damage, DamageTable.DamageType.MAGIC, true)
		creep.status().change_armor(self, -armor_reduction, armor_seconds)
		caught += 1

	if caught <= refund_below:
		tower.gain_mana(float(tower.max_mana) * refund_share)


## What one attack pays, after the crowd standing around this tower.
##
## The neighbours counted are towers carrying THIS VERY passive resource, which
## is identity rather than a type check - and it is also why the Quarry and the
## Coreway no longer count towards it, exactly as 12.4a states: they carry
## BreakPassive instead.
func _payout(tower: Building) -> int:
	if crowding_cells <= 0.0:
		return gold_per_attack

	var neighbours: int = 0
	for child: Node in tower.area.get_children():
		var other: Building = child as Building
		if other == null || other == tower || !(self in other.tower_passives()):
			continue
		var offset: Vector3 = other.global_position - tower.global_position
		if Vector2(offset.x, offset.z).length() <= crowding_cells:
			neighbours += 1

	return maxi(minimum_gold, gold_per_attack - gold_per_neighbour * neighbours)


func effect_text() -> String:
	var text: String = "Generates %s gold per attack" % StringUtil.compact_number(gold_per_attack)
	if crowding_cells > 0.0:
		text += ", reduced by %s for every other Primalist within %s cells, down to %s" % [
			StringUtil.compact_number(gold_per_neighbour),
			StringUtil.trim_number(crowding_cells),
			StringUtil.compact_number(minimum_gold)]
	text += (". Regenerates %s mana per second; at full mana it blasts for %s"
		+ " Magic damage within %s cells and takes %s armor for %ss. Half the"
		+ " mana returns if it catches %d creeps or fewer.") % [
		StringUtil.trim_number(regen_per_second),
		StringUtil.compact_number(blast_damage),
		StringUtil.trim_number(blast_cells),
		StringUtil.trim_number(armor_reduction),
		StringUtil.trim_number(armor_seconds),
		refund_below,
	]
	return text
