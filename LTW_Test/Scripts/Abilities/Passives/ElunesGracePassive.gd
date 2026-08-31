class_name ElunesGracePassive
extends CreepPassive

## Makes the creep untouchable the first time anything hits it, and again when
## it is half dead.
##
## The Huntress trait. unit_data.md 6.6: "15 sec invulnerability shield the
## first time damage is taken (once), plus a 5 sec shield at 50% health."
##
## FIFTEEN SECONDS IS ENORMOUS, and it is what the creep is for. A Huntress
## walks the whole first stretch of a maze with every shot in it landing on
## nothing, so what a defender is really being asked is whether their maze can
## kill one in the ten seconds after the ward drops - and the second ward, at
## half health, is there to make sure the answer is usually no.
##
## Both windows are ONCE PER CREEP and are recorded on the CREEP, never here:
## this resource stands in for every Huntress on the field, so a flag stored on
## it would be spent for all of them the moment any single one was shot at. Two
## separate uses, which is why the creep counts them rather than flagging them
## - see Creep.spend_count().
##
## A WARD, not the invulnerable armour type. The type is permanent and also
## refuses heals; this is a window, and a warded Huntress still regenerates,
## is still shot at, still walks and can still be slowed. See StatusEffects.

@export_group("Settings")
## Seconds of the first ward, which lands on the first damage of any kind.
@export var first_seconds: float = 15.0
## Seconds of the second ward.
@export var second_seconds: float = 5.0
## Health share at or below which the second ward lands.
@export_range(0.0, 1.0, 0.05) var second_at_health: float = 0.5


## The first ward would have to fire BEFORE the hit that triggered it to save
## the creep from that hit, which nothing here can do - so it fires after, and
## the creep pays for exactly one shot. That is the source rule read literally
## and is also the only version that cannot make a creep unkillable by walking
## it into a lane that never quite lands a second attack.
func on_damage_taken(creep: Creep, _lost: float,
		_damage_type: DamageTable.DamageType) -> void:
	var used: int = creep.spend_count(self)
	if used == 0:
		creep.spend(self)
		creep.status().ward(self, first_seconds)
		return

	if used > 1 || creep.max_health() <= 0:
		return
	if creep.current_health > float(creep.max_health()) * second_at_health:
		return

	creep.spend(self)
	creep.status().ward(self, second_seconds)


func effect_text() -> String:
	return ("Takes no damage at all for %s seconds the first time it is hit,"
		+ " and again for %s seconds the first time it falls below %d%%"
		+ " health.") % [
		StringUtil.trim_number(first_seconds),
		StringUtil.trim_number(second_seconds),
		roundi(second_at_health * 100.0),
	]
