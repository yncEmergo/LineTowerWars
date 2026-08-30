class_name LuminousGraspPassive
extends TowerPassive

## Holy 2, the whole Titan Vault line: the support tower that makes everybody
## else's abilities land harder.
##
## unit_data.md 4.4: it strikes a great many creeps at once and leaves each of
## them taking more SPELL DAMAGE and moving slower. Since nearly every tower
## ability in the game deals Spell Damage, a Titan Vault standing behind a maze
## is worth a share of every other tower in it.
##
## THE AURA AND THE ATTACK ARE SEPARATE THINGS. A tier that has an aura debuffs
## through it and through nothing else: its attack is a plain attack that hits a
## great many creeps and applies no effect of its own. The tiers below have no
## aura and put the same debuff on what they hit instead. So the tower never
## does both, and which one it is reads off whether it has a radius at all.
##
## The aura BUILDS rather than landing whole - see GameConfig's aura section.
## Every effect below is scaled by how tight the grip on that creep currently
## is, so a creep crossing the edge of the radius is worth a fraction of one
## parked in the middle of it.

## Key the tower counts its aura refresh under.
const AURA_KEY: String = "luminous_aura"

@export_group("Luminous Grasp")
## Creeps struck alongside the primary target.
@export var additional_targets: int = 6
## Extra share of Spell Damage each of them takes.
@export var spell_amplification: float = 0.12
## How long that lasts.
@export var amplification_seconds: float = 5.0
## Movement taken, as a flat share rather than an accumulating chill: the
## source states one figure per tier rather than a per-hit step.
@export var slow_amount: float = 0.14

@export_group("Titan Defense Mechanism")
## Radius the debuff reaches as an aura, or 0 on the tiers that only debuff
## what they hit.
@export var aura_cells: float = 0.0
## Seconds every slow on a creep in the aura is extended by.
@export var slow_extension: float = 0.0
## Share taken off the attack damage of the creeps in it.
@export var damage_reduction: float = 0.0


func extra_targets(_tower: Building) -> int:
	return additional_targets


## The attack's debuff, on the tiers whose attack carries one. A tower with an
## aura does its work through that instead and its attack stays plain.
func on_hit(_tower: Building, target: Unit, _dealt: int, _is_primary: bool) -> void:
	if aura_cells > 0.0:
		return
	var status: StatusEffects = status_of(target)
	if status == null:
		return
	status.amplify_spell(self, spell_amplification, amplification_seconds)
	status.slow(self, resource_path, slow_amount, amplification_seconds)


## The aura, on the tier that has one. Beats on the stacking interval rather
## than the ordinary aura beat, because one beat is one stack.
func on_tick(tower: Building, delta: float) -> void:
	if aura_cells <= 0.0 || tower.area == null || !tower.can_attack():
		return
	if !aura_due(tower, AURA_KEY, delta, aura_stack_interval()):
		return

	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, tower.global_position, aura_cells):
		var share: float = grip_aura(self, creep)
		if share <= 0.0:
			continue
		var status: StatusEffects = creep.status()
		status.amplify_spell(self, spell_amplification * share, AURA_HOLD_SECONDS)
		status.slow(self, resource_path, slow_amount * share, AURA_HOLD_SECONDS)
		status.weaken_attack(self, 0.0, damage_reduction * share, AURA_HOLD_SECONDS)
		# Lengthens slows as they LAND rather than topping up the ones already
		# running, which is what stops an aura from making every chill on
		# everything standing in it permanent. See lengthen_slows.
		status.lengthen_slows(self, slow_extension * share, AURA_HOLD_SECONDS)


func effect_text() -> String:
	if aura_cells <= 0.0:
		return ("Attacks hit %d additional targets. Everything hit takes"
			+ " +%s%% Spell Damage for %ss and is slowed by %s%%.") % [
			additional_targets,
			StringUtil.trim_number(spell_amplification * 100.0),
			StringUtil.trim_number(amplification_seconds),
			StringUtil.trim_number(slow_amount * 100.0),
		]

	return ("Attacks hit %d additional targets. Creeps within %s cells have"
		+ " their attack damage reduced by %s%%, take %s%% additional Spell"
		+ " Damage, are slowed by %s%% and have their slow duration increased"
		+ " by %ss. The aura builds up the longer a creep stays in it and"
		+ " fades once it leaves.") % [
		additional_targets,
		StringUtil.trim_number(aura_cells),
		StringUtil.trim_number(damage_reduction * 100.0),
		StringUtil.trim_number(spell_amplification * 100.0),
		StringUtil.trim_number(slow_amount * 100.0),
		StringUtil.trim_number(slow_extension),
	]


## The aura, on the tier that has one. A tier that debuffs only what it hits
## answers 0 and is drawn with its attack range alone, which is the truth about
## it - the reach that matters there IS the attack.
func display_radius(_unit: Unit) -> float:
	return aura_cells
