class_name FocusedLightningPassive
extends TowerPassive

## Lightning 1, the whole Annihilation Glyph line: ramps up on one creep and
## loses everything the moment it looks at another.
##
## unit_data.md 4.6: each attack on the SAME target adds a share of base
## damage, capped at five attacks, and switching resets the bonus to nothing.
## The Ultimate keeps that and chains each attack to two more creeps at full
## damage - which does not reset the ramp, because the chain is not what the
## tower is aimed at.
##
## The ramp is per TOWER and is remembered across attacks, so it lives in
## Building.ability_state: which creep, and how many attacks deep.
##
## Remembered by UNIT ID rather than by the creep object, so a creep that dies
## and a creep that walks out of range look the same to it - and so nothing
## here can keep a freed node alive.

const TARGET_KEY: String = "focus_target"
const STACK_KEY: String = "focus_stacks"

@export_group("Focused Lightning")
## Base damage added per attack on the same target, as a share.
@export var bonus_per_attack: float = 0.5
## The most attacks that count. The sixth adds nothing.
@export var max_stacks: int = 5

@export_group("Annihilation")
## Further creeps each attack chains to at full damage, or 0 for the tiers that
## do not chain at all.
@export var chain_targets: int = 0
## How far each hop of that chain reaches, in player cells.
@export var chain_cells: float = 3.9


## The ramp is counted when the attack COMMITS rather than when it lands,
## because it is a property of what the tower is shooting at - and a projectile
## still in the air must not be able to change what the next shot is worth.
func on_attack(tower: Building, target: Unit) -> void:
	var id: int = MatchSession.NO_UNIT if target == null else target.unit_id
	if int(tower.ability_state.get(TARGET_KEY, MatchSession.NO_UNIT)) != id:
		tower.ability_state[TARGET_KEY] = id
		tower.ability_state[STACK_KEY] = 0
		return
	tower.ability_state[STACK_KEY] = mini(
		max_stacks, int(tower.ability_state.get(STACK_KEY, 0)) + 1)


func bonus_damage(tower: Building, _target: Unit, rolled: int) -> int:
	var stacks: int = int(tower.ability_state.get(STACK_KEY, 0))
	return int(round(float(rolled) * bonus_per_attack * float(stacks)))


## The chain hits at FULL damage, which is what the source states, and takes
## the attack's own damage type rather than becoming Spell Damage: this is the
## same bolt arriving somewhere else, not an ability going off.
##
## And it LOOKS like the same bolt, because it spawns the attack's own impact
## effect on each creep it reaches - which for this tower is an arc strung back
## to the muzzle. The tower is drawing lightning to everything it hit, so
## everything it hit should have lightning drawn to it, and reusing the
## delivery's own effect is what keeps the chained bolts identical to the aimed
## one without this passive knowing what an arc looks like.
func on_hit(tower: Building, target: Unit, dealt: int, is_primary: bool) -> void:
	if !is_primary || chain_targets <= 0 || target == null || tower.stats == null:
		return

	var attack: AttackStats = tower.stats.attack
	var from: Vector3 = _muzzle_of(tower)
	for creep: Creep in HitPattern.chain(tower.area, target, chain_targets,
			chain_cells, attack):
		creep.take_damage(dealt, attack.damage_type)
		if attack.delivery != null:
			attack.delivery.spawn_impact(creep.global_position, from)


## Where the tower's own shots leave from, so a chained arc starts where the
## aimed one did. Falls back to the tower itself, which is only ever reached by
## a tower with no attack component - and one of those never gets here.
static func _muzzle_of(tower: Building) -> Vector3:
	if tower.attack_component == null:
		return tower.global_position
	return tower.attack_component.muzzle_position()


func effect_text() -> String:
	var text: String = ("Each attack on the same target adds +%d%% base"
		+ " damage, up to %d attacks. A new target resets it.") % [
		int(round(bonus_per_attack * 100.0)), max_stacks]
	if chain_targets > 0:
		text += " Each attack also chains to %d more creeps within %s cells at full damage." % [
			chain_targets, StringUtil.trim_number(chain_cells)]
	return text
