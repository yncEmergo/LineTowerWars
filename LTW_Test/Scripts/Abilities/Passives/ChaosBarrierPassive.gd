class_name ChaosBarrierPassive
extends CreepPassive

## Turns a draining pool of mana into damage resistance.
##
## The Chaos Wardens trait. unit_data.md 6.6: "damage taken is reduced based on
## current mana percentage. Loses 5% mana every sec. Maximum mana 100."
##
## A CLOCK RUNNING DOWN, which is what makes it read: a fresh Chaos Warden is
## very hard to kill and is measurably softer every second it stays alive, so a
## maze that cannot burst it simply waits it out. Twenty seconds from full to
## empty, with nothing the defender has to do.
##
## Unless the creep refills it. Mana Drain, its other trait, empties a tower to
## do exactly that - which is the whole design of this creep and the reason the
## two traits ship together: what a Chaos Warden is really doing is trading the
## maze mana for time.
##
## `?` HOW MUCH resistance a full pool is worth is a CHOICE. The source says
## "based on current mana percentage" and states no figure at all, so the
## share below is this project. It is authored rather than hard coded for
## exactly that reason.
##
## The pool itself is on the creep stats with the rest of what the creep is -
## the ceiling of 100 included. This owns the rule, never the number.

@export_group("Settings")
## Share of damage taken off at FULL mana. Scales straight down with the pool,
## so a creep at half mana takes half of this.
@export_range(0.0, 1.0, 0.01) var reduction_at_full: float = 0.75
## Share of the MAXIMUM pool lost per second.
@export_range(0.0, 1.0, 0.01) var drain_per_second: float = 0.05


func damage_taken_ratio(creep: Creep, _damage_type: DamageTable.DamageType,
		_is_aoe: bool) -> float:
	if creep == null:
		return 1.0
	var pool: CreepMana = creep.mana()
	if pool == null:
		return 1.0
	return clampf(1.0 - reduction_at_full * pool.ratio(), 0.0, 1.0)


func on_tick(creep: Creep, delta: float) -> void:
	var pool: CreepMana = creep.mana()
	if pool != null:
		pool.decay(drain_per_second, delta)


func effect_text() -> String:
	return ("Takes up to %d%% less damage, scaled by how full its mana is, and"
		+ " loses %d%% of its maximum mana every second.") % [
		roundi(reduction_at_full * 100.0),
		roundi(drain_per_second * 100.0),
	]
