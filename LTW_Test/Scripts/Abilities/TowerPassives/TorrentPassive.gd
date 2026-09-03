class_name TorrentPassive
extends TowerPassive

## Water 2, the whole Sludge Monstrosity line: an aura that grinds every creep
## near it slower whether or not the tower is shooting them.
##
## unit_data.md 4.10 states this as "slowed by X% every 1.5 sec, up to Y%", and
## the game it is copied from does NOT work that way - which is a correction to
## that document rather than to this file. There is ONE stack, it lands every
## half second, and everything the aura does is read off it: the slow and, on
## the Ultimate, the physical amplification. There is no second clock.
##
## Every third attack also stuns the primary target, which is on the attack and
## not on the aura. The Ultimate's amplification makes it the mirror of the
## Titan Vault - one helps spells, the other helps everything else.
##
## So a creep walking through is slower the longer it takes, and slower again
## for every Sludge Monstrosity reaching it: each tower lands its own stack on
## its own half-second beat, so standing in two of them fills the pile twice as
## fast. It is the one slow in the game that punishes a long maze rather than a
## short one.

const AURA_KEY: String = "torrent_aura"
const COUNT_KEY: String = "torrent_count"
const TARGET_KEY: String = "torrent_target"

@export_group("Torrent")
## Radius of the aura, in player cells.
@export var aura_cells: float = 3.0
## Movement taken PER STACK, as a share. The stack is the aura's only clock, so
## this is what one half-second in the radius is worth.
@export var slow_per_stack: float = 0.048
## The most it may reach however many stacks are held. Reached at 5 stacks on
## the Lesser and at 4 on the two above it, which is what the source's two
## numbers come to - see the class note.
@export var slow_cap: float = 0.24
## The key this line's STACK PILE and its slow both live under. Every tier
## shares it, so a Lesser and an Ultimate over one creep feed one pile - which
## fills twice as fast for the two of them - and state one slow, the stronger
## of the two winning. Authored rather than taken off the .tres for that
## reason; see StatusEffects.touch_aura.
@export var slow_source: String = "sludge_monstrosity"

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


## The aura, beating on the stacking interval because one beat is one stack.
##
## ONE stack drives everything, and it is read rather than accumulated: the
## slow is what the pile is worth RIGHT NOW, re-stated on every beat, so it
## moves the instant a stack lands or drains. That is the whole reason this no
## longer has a clock of its own - a second ramp on top of the stack ramp left
## the debuff row reading full grip while the creep was barely slowed.
##
## The clock is the TOWER's, not each creep's, so a creep that walks in halfway
## through a beat simply catches the next one - and two towers on their own
## beats land two stacks in the time one lands one.
func on_tick(tower: Building, delta: float) -> void:
	if tower.area == null || !tower.can_attack():
		return
	if !aura_due(tower, AURA_KEY, delta, aura_stack_interval()):
		return

	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, tower.global_position, aura_cells):
		var share: float = grip_aura(self, creep, slow_source)
		if share <= 0.0:
			continue
		var status: StatusEffects = creep.status()
		# STATED rather than added to, because the pile is the whole answer.
		# Two tiers over one creep feed one pile and the stronger of the two
		# wins the number, which is what slow() already does with its key.
		var held: int = aura_stacks_on(creep, slow_source)
		status.slow(self, slow_source, minf(slow_per_stack * float(held), slow_cap),
			AURA_HOLD_SECONDS, false)
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
		+ " %ss they stand there, to a maximum of %s%%. Every Sludge"
		+ " Monstrosity reaching a creep adds its own, so the slow builds"
		+ " faster the more of them there are, and fades once it leaves.") % [
		StringUtil.trim_number(aura_cells),
		StringUtil.trim_number(slow_per_stack * 100.0),
		StringUtil.trim_number(aura_stack_interval()),
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
