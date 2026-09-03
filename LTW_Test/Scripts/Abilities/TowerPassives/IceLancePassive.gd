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
## Mana a creep loses per second when the lance crystalizes it, and for how
## long. 0 for the two tiers that crystalize nothing.
##
## unit_data.md 4.5 words it as the creep's mana REGENERATION being crystalized,
## and taking points off the pool is how that is served: a Shaman filling at a
## point a second under this fills at what is left of one, and a creep with no
## regeneration simply empties. Only the handful of creeps whose traits run on
## a pool have anything to lose - see CreepMana - and the rest are refused by
## StatusEffects.drain_mana rather than by anything here.
##
## The lance applies it to EVERY creep the spike passes rather than only to the
## one aimed at, which is PiercingProjectile's job. See mana_drain_rate.
@export var mana_drain_per_second: float = 0.0
@export var mana_drain_seconds: float = 0.0


func pierce_targets() -> int:
	return max_targets


func pierce_ramp() -> float:
	return damage_per_target


func mana_drain_rate() -> float:
	return mana_drain_per_second


func mana_drain_window() -> float:
	return mana_drain_seconds


func effect_text() -> String:
	var text: String = ("Attacks fire a spike that flies in a straight line"
		+ " rather than homing, piercing every creep in its path up to %d of"
		+ " them and ignoring armor entirely. Damage rises %s%% per creep"
		+ " passed.") % [
		max_targets, StringUtil.trim_number(damage_per_target * 100.0)]
	if mana_drain_per_second > 0.0:
		text += (" Creeps that use mana for their abilities lose %s of it per"
			+ " second for %ss.") % [
			StringUtil.trim_number(mana_drain_per_second),
			StringUtil.trim_number(mana_drain_seconds)]
	return text
