class_name PoisonPassive
extends TowerPassive

## Unholy 1, the whole Gravedigger line: stacks poison on several creeps at
## once and detonates it once it is deep enough.
##
## unit_data.md 4.8: every hit stores a share of the damage dealt as a stack of
## poison, and at ten stacks the creep takes everything stored at once as Spell
## Damage. The lower tiers blow it up in the creep's own face; the Ultimate
## spreads it over everything around it, and detonates on DEATH as well - so a
## Gravedigger clearing a pack chains through it.
##
## The poison lives on the CREEP rather than on the tower, which is what lets
## two Gravediggers stack into the same explosion instead of each keeping a
## count nobody can see. The CEILING lives there with it, for the same reason:
## ten stacks is ten stacks from any Gravedigger, and a creep already at ten
## takes nothing more from the next hit until something detonates it.

## Key the per-creep explosion cooldown is kept under, on the CREEP - so two
## Gravediggers cannot take turns detonating the same creep every tick.
const COOLDOWN_KEY: String = "poison_burst"

@export_group("Poison")
## Creeps struck alongside the primary target.
@export var additional_targets: int = 1
## Share of the damage dealt stored per hit.
@export var stack_share: float = 0.20
## Stacks at which it goes off.
@export var stacks_to_explode: int = 10
## Seconds before the same creep may explode again.
@export var explosion_cooldown: float = 3.0

@export_group("Pestilence")
## Radius the explosion covers, or 0 to deal it to the creep itself alone.
@export var explosion_cells: float = 0.0
## Whether killing a poisoned creep sets it off whatever its stack count is.
@export var explodes_on_death: bool = false


func extra_targets(_tower: Building) -> int:
	return additional_targets


func on_hit(tower: Building, target: Unit, dealt: int, _is_primary: bool) -> void:
	var status: StatusEffects = status_of(target)
	if status == null:
		return

	var stacks: int = status.add_poison(self, float(dealt) * stack_share,
		stacks_to_explode)
	if stacks < stacks_to_explode || status.is_immune(COOLDOWN_KEY):
		return
	status.set_immune(COOLDOWN_KEY, explosion_cooldown)
	_detonate(tower, target, status)


func on_kill(tower: Building, target: Unit) -> void:
	if !explodes_on_death || target == null:
		return
	var status: StatusEffects = status_of(target)
	if status != null:
		_detonate(tower, target, status)


## Empties the stored poison into damage. Where it lands is the whole
## difference between the tiers: the lower ones give it back to the creep that
## has been carrying it, and the Ultimate throws it over everything nearby.
func _detonate(tower: Building, target: Unit, status: StatusEffects) -> void:
	var stored: int = status.take_poison()
	if stored <= 0:
		return

	if explosion_cells <= 0.0:
		target.take_damage(stored, DamageTable.DamageType.SPELL)
		return
	spell_burst(tower.area, target.global_position, explosion_cells, stored)


func effect_text() -> String:
	var text: String = ("Strikes %d additional %s and stores %d%% of the"
		+ " damage dealt as poison, up to %d stacks from any tower of this"
		+ " line. At full stacks the stored damage is dealt as Spell Damage,"
		+ " once every %ss.") % [
		additional_targets, StringUtil.plural("creep", additional_targets),
		int(round(stack_share * 100.0)),
		stacks_to_explode, StringUtil.trim_number(explosion_cooldown),
	]
	if explosion_cells > 0.0:
		text += " It bursts over %s rather than into the creep alone." \
			% StringUtil.trim_number(explosion_cells)
	if explodes_on_death:
		text += " A poisoned creep that dies bursts as well."
	return text
