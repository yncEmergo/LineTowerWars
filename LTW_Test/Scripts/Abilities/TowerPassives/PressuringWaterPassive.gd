class_name PressuringWaterPassive
extends TowerPassive

## Water 1, the whole Hurricane Elemental line: the anti-air path that does not
## kill flyers so much as PULL THEM OUT OF THE SKY.
##
## unit_data.md 4.10: a chance per attack to paralyze a random air creep
## nearby, which pins it in place and - because a pinned flyer can be shot as
## though it walked the ground (TargetFinder) - hands every ground tower in the
## lane a target it could never otherwise reach. That is worth far more than
## its own damage, and it is why this line is the answer to a flyer wave rather
## than the Divineshroom's raw output.
##
## Every third attack also changes damage type, which is the second half: the
## Lesser and Greater turn it Chaos with a bonus, and the Ultimate spends its
## mana on a fork instead.

const COUNT_KEY: String = "pressure_count"
const IMMUNE_KEY: String = "paralyze"

@export_group("Pressuring Water")
## Chance per attack to paralyze a flyer, 0 to 1.
@export var paralyze_chance: float = 0.5
## How long it holds one, in seconds.
@export var paralyze_seconds: float = 1.5
## How far it reaches for one, in player cells.
@export var paralyze_cells: float = 3.12
## Seconds before the same creep may be paralyzed again.
@export var paralyze_cooldown: float = 9.0

@export_group("Charged attack")
## Attacks between one charged attack and the next.
@export var every: int = 3
## Extra damage a charged attack deals, as a share, or 0 on the Ultimate.
@export var charged_bonus: float = 0.25

@export_group("Raging Tempest")
## Mana gained per creep struck, or 0 on the tiers that use none.
@export var mana_per_target: float = 0.0
## Spell Damage the fork deals to each creep it reaches.
@export var fork_damage: int = 2000
## Mana one forked target costs.
@export var mana_per_fork: int = 10
## How far each hop of the fork reaches, in player cells.
@export var fork_cells: float = 3.12


## The count is advanced when the attack COMMITS, so two shots in the air
## cannot both read the same value and both come out charged.
func on_attack(tower: Building, _target: Unit) -> void:
	tower.ability_state[COUNT_KEY] = int(tower.ability_state.get(COUNT_KEY, 0)) + 1
	_try_paralyze(tower)


## A charged attack turns Chaos on the tiers that author a bonus, and stays its
## own type on the Ultimate, which spends mana instead of changing type.
func damage_type_for(tower: Building, _target: Unit) -> int:
	if charged_bonus <= 0.0 || !_is_charged(tower):
		return -1
	return DamageTable.DamageType.CHAOS


func bonus_damage(tower: Building, _target: Unit, rolled: int) -> int:
	if charged_bonus <= 0.0 || !_is_charged(tower):
		return 0
	return int(round(float(rolled) * charged_bonus))


func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	tower.gain_mana(mana_per_target)
	if !is_primary || mana_per_target <= 0.0 || !_is_charged(tower) || target == null:
		return
	_fork(tower, target)


## The Ultimate's fork: everything the tower has saved up, spent as one target
## per authored slice of mana.
func _fork(tower: Building, target: Unit) -> void:
	var spent: int = tower.drain_mana()
	# Integer division on purpose: the fork reaches one creep per whole slice of
	# mana, and a part-paid slice buys nothing.
	var reach: int = spent / maxi(1, mana_per_fork)
	if reach <= 0 || tower.stats == null:
		return

	for creep: Creep in HitPattern.chain(tower.area, target, reach,
			fork_cells, tower.stats.attack):
		creep.take_damage(fork_damage, DamageTable.DamageType.CHAOS)


func _is_charged(tower: Building) -> bool:
	if every <= 0:
		return false
	return int(tower.ability_state.get(COUNT_KEY, 0)) % every == 0


## Pulls one flyer down. Rolled per attack rather than per hit, and against a
## creep chosen at random from those in range rather than the one being shot -
## which is what the source states, and what makes it worth having on a tower
## that is busy killing something else.
func _try_paralyze(tower: Building) -> void:
	if tower.area == null || MatchSession.match_rng().randf() >= paralyze_chance:
		return

	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, tower.global_position, paralyze_cells):
		if !creep.is_flying() || creep.status().is_immune(IMMUNE_KEY):
			continue
		creep.status().set_immune(IMMUNE_KEY, paralyze_cooldown)
		creep.status().paralyze(self, paralyze_seconds)
		return


func effect_text() -> String:
	var text: String = ("%d%% chance per attack to paralyze an air creep within"
		+ " %s cells for %ss, pinning it in place where ground towers can reach"
		+ " it. Once every %ss per creep.") % [
		int(round(paralyze_chance * 100.0)),
		StringUtil.trim_number(paralyze_cells),
		StringUtil.trim_number(paralyze_seconds),
		StringUtil.trim_number(paralyze_cooldown),
	]
	if charged_bonus > 0.0:
		text += " Every %d%s attack is dealt as Chaos with +%s%% damage." % [
			every, StringUtil.ordinal_suffix(every),
			StringUtil.trim_number(charged_bonus * 100.0)]
	if mana_per_target > 0.0:
		text += (" Gains %s mana per creep hit; every %d%s attack spends it all"
			+ " on a fork dealing %s Chaos damage to one creep per %d mana.") % [
			StringUtil.trim_number(mana_per_target), every,
			StringUtil.ordinal_suffix(every),
			StringUtil.compact_number(fork_damage), mana_per_fork]
	return text
