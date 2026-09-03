class_name ChaoticVoidPassive
extends CreepPassive

## Banks a point of mana per hit taken and spends the lot on a heal.
##
## The Voidwalker's trait, and the first thing in the game that gives a CREEP
## mana - see CreepMana. unit_data.md 6.6: "Any damage taken gives +1 mana; at
## 26 mana heals 5% of maximum health and resets."
##
## PER HIT, never per point of damage. That is the whole shape of it: a
## Voidwalker is worn down faster by many small hits than by a few heavy ones,
## which is the exact opposite of Hardened Skin further up the roster and is
## why the two read as different creeps rather than as one number apart.
##
## The 26 itself is NOT here. It is the creep's mana ceiling and lives on its
## stats with the rest of what the creep is, so a tooltip reading the pool and
## this passive filling it can never disagree about how full full is.

@export_group("Settings")
## Mana banked per hit that actually lands.
@export var mana_per_hit: int = 1
## Share of MAXIMUM health restored when the pool fills. Of maximum rather than
## of what is missing, so the heal is the same size whether it lands on a creep
## at half health or one that has barely been scratched.
@export_range(0.0, 1.0, 0.01) var heal_share: float = 0.05


## Every hit banks, and the one that fills the pool spends it in the same call.
##
## The heal lands on the creep that was just struck, so a killing blow is
## already resolved before this runs and cannot be undone by it - a Voidwalker
## is healed out of trouble, never out of death. Bringing one back is what a
## revive is for, and this is not one.
func on_damage_taken(creep: Creep, _lost: float,
		_damage_type: DamageTable.DamageType) -> void:
	var pool: CreepMana = creep.mana()
	if pool == null:
		Log.err("Chaotic Void is on a creep whose stats give it no mana",
			creep.name)
		return

	if !pool.gain(mana_per_hit):
		return

	pool.drain()
	creep.heal(float(creep.max_health()) * heal_share)


func effect_text() -> String:
	return ("Any damage taken gives %d mana. At full mana it heals %d%% of"
		+ " its maximum health and empties the pool.") % [
		mana_per_hit, roundi(heal_share * 100.0),
	]
