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
## The Ultimate turns the debuff into an AURA that reaches everything nearby
## whether or not it was struck, and adds a cut to what the creeps in it hit
## for - which is the only thing in the element that helps against attackers.

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


func on_hit(_tower: Building, target: Unit, _dealt: int, _is_primary: bool) -> void:
	_mark(target, true)


## The aura, on the tiers that have one. Pushed onto the creeps in range on a
## slow beat, exactly as the Ultimate Lich's is and for the same reason.
func on_tick(tower: Building, delta: float) -> void:
	if aura_cells <= 0.0 || !aura_due(tower, AURA_KEY, delta):
		return
	if tower.area == null || !tower.can_attack():
		return

	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, tower.global_position, aura_cells):
		_mark(creep, false)
		if damage_reduction > 0.0:
			creep.status().weaken_attack(0.0, damage_reduction, AURA_HOLD_SECONDS)


## `extend` is what separates a creep being STRUCK from one merely standing in
## the aura: the source's "slow duration extended by 2 sec" is a property of a
## slow being applied, so topping it up four times a second for as long as a
## creep loiters would mean a chill that never wore off at all.
func _mark(target: Unit, extend: bool) -> void:
	var status: StatusEffects = status_of(target)
	if status == null:
		return
	status.amplify_spell(spell_amplification, amplification_seconds)
	status.slow(resource_path, slow_amount, amplification_seconds)
	if extend && slow_extension > 0.0:
		status.extend_slows(slow_extension)


func effect_text() -> String:
	var text: String = ("Strikes %d additional creeps. Everything hit takes"
		+ " +%s%% Spell Damage for %ss and is slowed by %s%%.") % [
		additional_targets,
		StringUtil.trim_number(spell_amplification * 100.0),
		StringUtil.trim_number(amplification_seconds),
		StringUtil.trim_number(slow_amount * 100.0),
	]
	if aura_cells > 0.0:
		text += (" Every creep within %s cells is affected whether struck or"
			+ " not, and hits %s%% weaker.") % [
			StringUtil.trim_number(aura_cells),
			StringUtil.trim_number(damage_reduction * 100.0)]
	return text
