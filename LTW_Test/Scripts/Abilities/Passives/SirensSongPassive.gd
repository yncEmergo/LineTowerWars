class_name SirensSongPassive
extends CreepPassive

## Banks a point per hit, and at the top heals itself, grows its own pool and
## hands the pack its armour back.
##
## The Naga Siren trait. unit_data.md 6.6: "any damage taken gives +1 mana. At
## full mana (50) gains +50 maximum mana and heals 15% of max health; creeps
## within 300 AoE recover 1.6 armour if below their base armour, once per creep
## per 5 sec."
##
## The SAME SHAPE as Chaotic Void two tiers below it - a point per hit, spent
## at the top on a heal - and deliberately so: a player who learned to burst a
## Voidwalker rather than chip it already knows what to do here. What is new is
## the RISING CEILING. Every cast makes the next one further away, so a Naga
## Siren heals fast early and slowly later, and a maze that cannot kill one in
## its first two casts is not going to be rescued by the third being cheaper.
##
## The ARMOUR half is the pack half, and it undoes a specific kind of maze:
## anything that eats armour - a Firelord, an Ancient Warden, a Leviathan -
## spends its whole walk being handed back what it took. It restores rather
## than granting, so it can never lift a creep above what it started with.
##
## The per-creep gate lives on the CREEP being helped, keyed so that two Naga
## Sirens walked together feed one clock instead of one each.

## Key the per-creep gate is stored under, shared by every Naga Siren.
const GATE_KEY: String = "sirens_song"

@export_group("Settings")
## Mana banked per hit that actually lands.
@export var mana_per_hit: int = 1
## Share of MAXIMUM health restored when the pool fills.
@export_range(0.0, 1.0, 0.01) var heal_share: float = 0.15
## Mana added to the ceiling each time it fills.
@export var ceiling_gain: int = 50

@export_group("Pack")
## How far the armour reaches, in player cells. The source states 300, which
## snaps to 2.25 at the quarter every reach is stated in - unit_data.md 3.
@export var radius_cells: float = 2.25
## Armour points handed back to each creep caught.
@export var armor_restored: float = 1.6
## Seconds before the same creep may be helped again, by any Naga Siren.
@export var creep_gate_seconds: float = 5.0


func on_damage_taken(creep: Creep, _lost: float,
		_damage_type: DamageTable.DamageType) -> void:
	var pool: CreepMana = creep.mana()
	if pool == null:
		Log.err("Sirens Song is on a creep whose stats give it no mana",
			creep.name)
		return
	if !pool.gain(mana_per_hit):
		return

	pool.drain()
	pool.raise_ceiling(ceiling_gain)
	creep.heal(float(creep.max_health()) * heal_share)
	_restore_pack(creep)


## Hands armour back to everything near it that has had some eaten.
##
## The gate is checked before the restore rather than after, and the restore
## reports whether it did anything - so a creep at full armour is passed over
## without burning its five seconds, and the next Naga Siren cast finds it
## again the moment a tower has taken something off it.
func _restore_pack(creep: Creep) -> void:
	if armor_restored <= 0.0:
		return
	for other: Creep in TargetFinder.creeps_in_radius(
			creep.area, creep.global_position, radius_cells):
		var status: StatusEffects = other.status_or_null()
		if status == null || status.is_immune(GATE_KEY):
			continue
		if status.restore_armor(armor_restored):
			status.set_immune(GATE_KEY, creep_gate_seconds)


func effect_text() -> String:
	return ("Any damage taken gives %d mana. At full mana it heals %d%% of"
		+ " its maximum health, raises its own mana ceiling by %d, and restores"
		+ " %s armor to every creep within %s that is below its own base"
		+ " armor - at most once every %s seconds per creep.") % [
		mana_per_hit, roundi(heal_share * 100.0), ceiling_gain,
		StringUtil.trim_number(armor_restored),
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(creep_gate_seconds),
	]
