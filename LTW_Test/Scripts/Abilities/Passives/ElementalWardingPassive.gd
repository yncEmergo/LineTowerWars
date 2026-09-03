class_name ElementalWardingPassive
extends CreepPassive

## Braces against whatever kind of damage has hurt the creep most, and can move
## that brace every few seconds.
##
## The Shaman trait. unit_data.md 6.6: "gains 70% damage resistance against
## whichever damage type has dealt it the most damage. Can swap resistance once
## every 3 sec."
##
## THE SWAP GATE IS THE WHOLE THING. Without one a Shaman would simply resist
## whatever hit it last and a maze of two damage types would never get through
## at all. With it, the counter is to CHANGE what is shooting: three seconds of
## a Shaman braced against the wrong thing is a real window, and a lane built
## out of a single damage type never gets one.
##
## Which is also why it reads the damage that ACTUALLY LANDED rather than what
## the towers rolled. What the brace should point at is whatever is really
## taking the creep apart, and a type that looks huge on paper and arrives
## through the armour matrix as a scratch is not it.
##
## The ledger lives on the CREEP, see CreepWarding: this resource is every
## Shaman on the field at once and may remember nothing.

@export_group("Settings")
## Share of damage of the warded type the creep still takes. 0.30 is the
## source figure of "70% damage resistance".
@export_range(0.0, 1.0, 0.01) var damage_ratio: float = 0.30
## Seconds the brace has to stay where it is before it may move.
@export var swap_seconds: float = 3.0


func damage_taken_ratio(creep: Creep, damage_type: DamageTable.DamageType,
		_is_aoe: bool) -> float:
	if creep == null:
		return 1.0
	return damage_ratio if creep.warding().is_warded_against(damage_type) else 1.0


## Every hit goes into the ledger, in the type it landed as.
##
## Including one of the warded type, deliberately: what the ledger measures is
## how much a type has cost this creep, and the answer to "what is hurting me
## most" must not stop counting the thing the creep is already braced against -
## or the brace would flip away from a lane that is still killing it.
func on_damage_taken(creep: Creep, lost: float,
		damage_type: DamageTable.DamageType) -> void:
	creep.warding().record(damage_type, lost)


func on_tick(creep: Creep, delta: float) -> void:
	if creep.warding().advance(delta):
		creep.warding().hold_for(swap_seconds)


func effect_text() -> String:
	return ("Takes %d%% less damage of whichever damage type has hurt it"
		+ " most, and can change which type once every %s seconds.") % [
		roundi((1.0 - damage_ratio) * 100.0),
		StringUtil.trim_number(swap_seconds),
	]
