class_name TorrentPassive
extends TowerPassive

## Water 2, the whole Sludge Monstrosity line: an aura that grinds every creep
## near it slower whether or not the tower is shooting them.
##
## unit_data.md 4.10: creeps in a radius are slowed a step every second and a
## half, up to a cap, and every third attack stuns the primary target. The
## Ultimate adds an amplification to every PHYSICAL attack that lands on a
## creep in its radius, which makes it the mirror of the Titan Vault - one
## helps spells, the other helps everything else.
##
## The slow ACCUMULATES on the same clock for every creep in range, so a creep
## walking through the aura is slower the longer it takes - which is the one
## slow in the game that punishes a long maze rather than a short one.

const AURA_KEY: String = "torrent_aura"
const STEP_KEY: String = "torrent_step"
const COUNT_KEY: String = "torrent_count"
const TARGET_KEY: String = "torrent_target"

@export_group("Torrent")
## Radius of the aura, in player cells.
@export var aura_cells: float = 3.0
## Seconds between one step of the slow and the next.
@export var step_seconds: float = 1.5
## Movement taken per step, as a share.
@export var slow_per_step: float = 0.048
## The most it may reach.
@export var slow_cap: float = 0.24

@export_group("Stun")
## Attacks between one stun and the next, or 0 for none.
@export var stun_every: int = 3
## How long the stun holds.
@export var stun_seconds: float = 1.0
## Whether the stun needs the SAME target that many times in a row rather than
## simply that many attacks. The Ultimate's rule.
@export var stun_needs_same_target: bool = false

@export_group("Crippling Decay")
## Extra share of PHYSICAL damage creeps in the aura take, or 0 on the tiers
## that only slow.
@export var physical_amplification: float = 0.0


## The aura's own clock is the tower's, not each creep's: one step every
## step_seconds, applied to everything standing in range at that moment. A
## creep that walks in halfway through a step simply catches the next one.
## The aura, beating on the stacking interval because one beat is one stack.
##
## It BUILDS on a creep rather than landing whole - see GameConfig's aura
## section - so everything it applies is scaled by how tight its grip on that
## creep currently is. The chill keeps its own separate `step_seconds` clock on
## top of that: the grip decides how HARD each step lands, the step clock
## decides how OFTEN one is taken.
func on_tick(tower: Building, delta: float) -> void:
	if tower.area == null || !tower.can_attack():
		return
	if !aura_due(tower, AURA_KEY, delta, aura_stack_interval()):
		return

	var step: float = float(tower.ability_state.get(STEP_KEY, 0.0)) + aura_stack_interval()
	var stepping: bool = step >= step_seconds
	tower.ability_state[STEP_KEY] = 0.0 if stepping else step

	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, tower.global_position, aura_cells):
		var share: float = grip_aura(self, creep)
		if share <= 0.0:
			continue
		var status: StatusEffects = creep.status()
		if stepping:
			# The chill's own window is longer than the step, so a creep in the
			# aura keeps climbing rather than losing ground between steps.
			status.chill(self, resource_path, slow_per_step * share, slow_cap,
				step_seconds * 3.0)
		if physical_amplification > 0.0:
			status.amplify_physical(self, physical_amplification * share, AURA_HOLD_SECONDS)


## The stun is counted on the attack, so a shot still in the air cannot be
## overtaken and stun twice.
func on_attack(tower: Building, target: Unit) -> void:
	if stun_every <= 0:
		return

	var id: int = MatchSession.NO_UNIT if target == null else target.unit_id
	if stun_needs_same_target:
		if int(tower.ability_state.get(TARGET_KEY, MatchSession.NO_UNIT)) != id:
			tower.ability_state[TARGET_KEY] = id
			tower.ability_state[COUNT_KEY] = 0
	tower.ability_state[COUNT_KEY] = int(tower.ability_state.get(COUNT_KEY, 0)) + 1


func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	if !is_primary || stun_every <= 0 || target == null:
		return
	if int(tower.ability_state.get(COUNT_KEY, 0)) % stun_every != 0:
		return

	var status: StatusEffects = status_of(target)
	if status != null:
		status.stun(self, stun_seconds)


func effect_text() -> String:
	var text: String = ("Creeps within %s are slowed a further %s%% every"
		+ " %ss they stay in it, up to %s%%, and shed it again once they"
		+ " leave.") % [
		StringUtil.trim_number(aura_cells),
		StringUtil.trim_number(slow_per_step * 100.0),
		StringUtil.trim_number(step_seconds),
		StringUtil.trim_number(slow_cap * 100.0),
	]
	if stun_every > 0:
		var how: String = "Attacking the same target %d times in a row stuns" \
			if stun_needs_same_target else "Every %d%s attack stuns"
		var counted: Array = [stun_every] if stun_needs_same_target \
			else [stun_every, StringUtil.ordinal_suffix(stun_every)]
		text += " %s for %ss." % [
			how % counted, StringUtil.trim_number(stun_seconds)]
	if physical_amplification > 0.0:
		text += " Creeps in the aura also take +%s%% damage from physical attacks." \
			% StringUtil.trim_number(physical_amplification * 100.0)
	return text


## The aura. Every tier of the line has one, so this always answers.
func display_radius(_unit: Unit) -> float:
	return aura_cells
