class_name ChillingDeathPassive
extends TowerPassive

## Ice 1, Ultimate Lich: the chill that kills.
##
## unit_data.md 4.5: everything the Lich line already does, plus an aura that
## slows the creeps around it attacking, plus FROSTBITTEN - a creep chilled all
## the way to this tower's cap takes a share of its own MAXIMUM health as Spell
## Damage, once every fifteen seconds.
##
## Frostbitten is the interesting half and the reason this is its own script
## rather than another FrostAttackPassive .tres: it is the one effect in the
## game that reads a status back off a creep and acts on how deep it is, which
## is what makes stacking Liches worth something other than a bigger number.
##
## The chill itself is authored here rather than inherited so an Ultimate Lich
## carries ONE card entry rather than two, and so the .tres reads as the one
## ability unit_data.md names.

## Key the fifteen second Frostbitten window is kept under, on the CREEP.
const FROSTBITE_KEY: String = "frostbite"

## Key the tower counts its aura refresh under.
const AURA_KEY: String = "chilling_death_aura"

@export_group("Chilling Death")
## Movement taken per hit, as a share.
@export var slow_per_hit: float = 0.075
## The most this tower's chill may reach, and the depth Frostbitten needs.
@export var slow_cap: float = 0.45
## How long a chill lasts.
@export var slow_seconds: float = 7.0
## The key this chill accumulates under, shared by every Ultimate Lich.
@export var chill_source: String = "ultimate_lich"

@export_group("Frostbitten")
## Share of the creep's MAXIMUM health dealt as Spell Damage when it reaches
## the cap. Maximum rather than current, so it is worth the same against a
## fresh Tier 4 creep as against one already hurt.
@export var frostbite_share: float = 0.02
## Seconds before the same creep may be Frostbitten again.
@export var frostbite_cooldown: float = 15.0

@export_group("Aura")
## Radius of the attack-speed aura, in player cells.
@export var aura_cells: float = 5.5
## Share taken off the attack speed of every creep inside it.
@export var attack_slow: float = 0.15


## The aura is PUSHED onto the creeps in range on a slow beat rather than
## queried by them, which is the opposite way round from a creep aura - there
## are far fewer aura towers than creeps, so the search belongs to the tower.
##
## It is applied for longer than the gap between refreshes, so a creep standing
## in it never flickers; one walking out keeps it for the rest of the window.
## The aura that blunts what the creeps around it hit for. It BUILDS rather
## than landing whole - see GameConfig's aura section - so its beat is the
## stacking interval and its strength is scaled by the grip on each creep.
func on_tick(tower: Building, delta: float) -> void:
	if aura_cells <= 0.0 || !tower.can_attack() || tower.area == null:
		return
	if !aura_due(tower, AURA_KEY, delta, aura_stack_interval()):
		return

	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, tower.global_position, aura_cells):
		var share: float = grip_aura(self, creep)
		if share > 0.0:
			creep.status().weaken_attack(self, attack_slow * share, 0.0, AURA_HOLD_SECONDS)


func on_hit(_tower: Building, target: Unit, _dealt: int, _is_primary: bool) -> void:
	var status: StatusEffects = status_of(target)
	if status == null:
		return

	status.chill(self, chill_source, slow_per_hit, slow_cap, slow_seconds)
	if status.chill_amount(chill_source) < slow_cap || status.is_immune(FROSTBITE_KEY):
		return

	status.set_immune(FROSTBITE_KEY, frostbite_cooldown)
	var damage: int = int(round(float(target.max_health()) * frostbite_share))
	target.take_damage(maxi(1, damage), DamageTable.DamageType.SPELL)


func effect_text() -> String:
	return ("Each hit slows by %s%% up to %s%% for %ss. A target at full chill"
		+ " is Frostbitten for %s%% of its maximum health as Spell Damage,"
		+ " once every %ss. Creeps within %s attack up to %s%% slower,"
		+ " building up the longer they stay in range.") % [
		StringUtil.trim_number(slow_per_hit * 100.0),
		StringUtil.trim_number(slow_cap * 100.0),
		StringUtil.trim_number(slow_seconds),
		StringUtil.trim_number(frostbite_share * 100.0),
		StringUtil.trim_number(frostbite_cooldown),
		StringUtil.trim_number(aura_cells),
		StringUtil.trim_number(attack_slow * 100.0),
	]


## The attack-speed aura, which is the reason an Ultimate Lich is placed where
## the creeps walk rather than where it can shoot furthest.
func display_radius(_unit: Unit) -> float:
	return aura_cells
