class_name IceLancePassive
extends TowerPassive

## Ice 2, the whole Crystal line: the one path in the game that ignores a
## creep's armour VALUE entirely.
##
## unit_data.md 4.5: the attack pierces and hits every creep in a line towards
## the target, up to a limit, and the damage GROWS per creep passed - so a
## Crystal aimed down a packed lane is worth several times what it is worth
## against one straggler, and the whole line is paid for with lower base damage.
##
## THE PIERCE ITSELF IS THE ATTACK'S, NOT THIS ABILITY'S. The Crystal fires a
## PierceDelivery: a real spike that leaves the tower, flies in a straight line
## and damages what it passes as it passes it. So this passive no longer walks
## a line of its own - it is asked, through pierce_targets and pierce_ramp, how
## far that shot may go and how hard it hits down the line, and the shot does
## the rest. That is what makes a creep walking into the line after the shot
## left get hit, and the creep it was aimed at able to step out of the way.
##
## Ignoring armour value is done by dealing the trailing hits as SPELL damage,
## which is what already ignores both the matrix and the points
## (game_rules.md). The FIRST creep struck is the tower's own Piercing attack
## and goes through the matrix as usual; everything behind it is the lance.
## Which type a trailing hit takes is authored on the delivery, since it is the
## delivery that lands them.
##
## Deliberately NOT a splash. A lance is a line, and a radius around the impact
## would catch the creeps standing beside the lane rather than the ones the
## shot went through.

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


func pierce_targets() -> int:
	return max_targets


func pierce_ramp() -> float:
	return damage_per_target


func effect_text() -> String:
	var text: String = ("Attacks fire a spike that flies in a straight line"
		+ " rather than homing, piercing every creep in its path up to %d of"
		+ " them and ignoring armor entirely. Damage rises %s%% per creep"
		+ " passed.") % [
		max_targets, StringUtil.trim_number(damage_per_target * 100.0)]
	if mana_drain_per_second > 0.0:
		text += (" Creeps that use mana lose %s of it per second for %ss."
			+ " (Not implemented: creeps carry no mana yet.)") % [
			StringUtil.trim_number(mana_drain_per_second),
			StringUtil.trim_number(mana_drain_seconds)]
	return text
