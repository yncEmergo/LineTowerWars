class_name EtherealAuraPassive
extends CreepPassive

## Hands one creep near it a couple of armour points, for good, every few
## seconds.

## The Crypt Fiend, and the only aura in the roster that does not act on
## everything in range at once: "permanently +2 armour to a RANDOM creep within
## 700 radius every 6 sec" (unit_data.md 6.6).
##
## Which makes it a different shape of thing to every other creep aura. An aura
## is a field a creep stands in and loses the moment it walks out; this is a
## GIFT, and it is kept. So it is not answered through aura_armor_bonus() at
## all - it is a clock that reaches into one creep and writes on it, and what it
## writes survives the Crypt Fiend dying.
##
## RANDOM rather than the weakest or the nearest, which is what the source says
## and is also what makes it read: a pack walked past a maze together slowly
## thickens all over rather than growing one armoured champion. Rolled on the
## match RNG so every machine picks the same creep - see MatchSession.
##
## The CLOCK lives on the creep, because this resource is every Crypt Fiend on
## the field at once and may remember nothing. See Creep.advance_passive_clock.

@export_group("Settings")
## Seconds between gifts.
@export var interval_seconds: float = 6.0
## Armour points handed over each time.
@export var armor_bonus: float = 2.0


func on_tick(creep: Creep, delta: float) -> void:
	if armor_bonus <= 0.0 || !creep.is_alive():
		return
	if !creep.advance_passive_clock(self, interval_seconds, delta):
		return

	var reachable: Array[Creep] = TargetFinder.creeps_in_radius(
		creep.area, creep.global_position, CreepPassive.aura_radius())
	if reachable.is_empty():
		return

	var picked: Creep = reachable[
		MatchSession.match_rng().randi_range(0, reachable.size() - 1)]
	picked.status().bless_armor(self, armor_bonus)


func effect_text() -> String:
	return "Permanently grants +%s armor to a random creep within %s cells every %s seconds." % [
		StringUtil.trim_number(armor_bonus),
		StringUtil.trim_number(CreepPassive.aura_radius()),
		StringUtil.trim_number(interval_seconds),
	]
