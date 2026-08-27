class_name IceLancePassive
extends TowerPassive

## Ice 2, the whole Crystal line: the one path in the game that ignores a
## creep's armour VALUE entirely.
##
## unit_data.md 4.5: the attack pierces and hits every creep standing in a line
## towards the target, out to the tower's own reach. The damage GROWS per creep
## passed, so a Crystal aimed down a packed lane is worth several times what it
## is worth against one straggler - and the whole line is paid for with lower
## base damage.
##
## Ignoring armour value is done by dealing the pierce as SPELL damage, which
## is what already ignores both the matrix and the points (game_rules.md). The
## primary hit is the tower's own Piercing attack and goes through the matrix
## as usual; everything behind it is the lance.
##
## Deliberately NOT a splash. A lance is a walk down a line, and a radius
## around the impact would catch the creeps standing beside the lane rather
## than the ones the shot went through.

@export_group("Ice Lance")
## Creeps the lance may pass through, the primary target included.
@export var max_targets: int = 15
## Extra damage per creep already passed, as a share. 0.05 is the +5% of the
## source, applied cumulatively down the line.
@export var damage_per_target: float = 0.05
## Mana a creep loses per second when the lance crystalizes it, or 0 for the
## tiers that do not. NOT BUILT: creeps have no mana in this project yet, so
## the Ultimate's mana drain is authored, described and inert. See
## game_rules.md.
@export var mana_drain_per_second: float = 0.0
@export var mana_drain_seconds: float = 0.0


func on_hit(tower: Building, target: Unit, dealt: int, is_primary: bool) -> void:
	if !is_primary || target == null || tower.area == null || tower.stats == null:
		return

	var attack: AttackStats = tower.stats.attack
	var behind: Array[Creep] = HitPattern.line(
		tower.area, tower.global_position, target.global_position,
		attack.attack_range, max_targets - 1, attack)

	# Counting from 1 rather than 0: the primary target is the first creep the
	# lance passed through, so the one behind it is already the second.
	var passed: int = 1
	for creep: Creep in behind:
		if creep == target:
			continue
		var scaled: float = float(dealt) * (1.0 + damage_per_target * float(passed))
		creep.take_damage(int(round(scaled)), DamageTable.DamageType.SPELL)
		passed += 1


func effect_text() -> String:
	var text: String = ("Attacks pierce every creep in a line towards the"
		+ " target, up to %d of them, ignoring armor entirely. Damage rises"
		+ " %s%% per creep passed.") % [
		max_targets, StringUtil.trim_number(damage_per_target * 100.0)]
	if mana_drain_per_second > 0.0:
		text += (" Creeps that use mana lose %s of it per second for %ss."
			+ " (Not implemented: creeps carry no mana yet.)") % [
			StringUtil.trim_number(mana_drain_per_second),
			StringUtil.trim_number(mana_drain_seconds)]
	return text
