class_name BloodthirstPassive
extends TowerPassive

## Primal 2, the whole Beastmaster line: strikes two creeps at a time, and at
## full mana sends a beast tearing down the lane through everything in its path.
##
## unit_data.md 4.7: the beast is a LINE rather than a splash - it runs from
## the tower towards where the attack landed, damaging and stunning the ground
## creeps it passes through, and a creep can only be knocked down by one every
## few seconds. That is the whole reason the line exists: it is the only thing
## in the game that reaches down a lane rather than around a point.
##
## The Ultimate's manual STAMPEDE TARGET (hotkey R in the source) is NOT BUILT.
## The beast always runs at whatever the attack landed on, which is the source's
## own default; being able to aim it by hand is a command card entry and a
## targeting mode, and it is written down in game_rules.md rather than here.

const IMMUNE_KEY: String = "beast_stun"

@export_group("Bloodthirst")
## Creeps struck alongside the primary target.
@export var additional_targets: int = 1
## How far this tower's multishot reaches, in player cells. Named rather than
## taking the game's shared reach, because the source states its own.
@export var multishot_cells: float = 3.12
## Mana gained per creep struck.
@export var mana_per_target: float = 5.0

@export_group("The beast")
## How far it runs, in player cells.
@export var beast_cells: float = 5.47
## Creeps it may pass through.
@export var beast_targets: int = 12
## Siege Physical Damage it deals to each of them.
@export var beast_damage: int = 240
## How long it knocks one down for.
@export var stun_seconds: float = 0.5
## Seconds before the same creep may be knocked down again.
@export var stun_cooldown: float = 8.0

@export_group("Stampede")
## Extra damage per cell of range to the target, as a share, or 0 on the tiers
## that do not scale with distance.
@export var range_bonus_per_cell: float = 0.0
## The most that may reach.
@export var max_range_bonus: float = 0.0


func extra_targets(_tower: Building) -> int:
	return additional_targets


func extra_target_range(_tower: Building) -> float:
	return multishot_cells


## The Ultimate hits harder the further away its target is, which is the
## opposite of every other tower in the game and is what makes a Beastmaster
## want to sit at the BACK of a maze rather than in the thick of it.
func bonus_damage(tower: Building, target: Unit, rolled: int) -> int:
	if range_bonus_per_cell <= 0.0 || target == null:
		return 0
	var offset: Vector3 = target.global_position - tower.global_position
	var cells: float = Vector2(offset.x, offset.z).length()
	var share: float = minf(max_range_bonus, range_bonus_per_cell * cells)
	return int(round(float(rolled) * share))


func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	tower.gain_mana(mana_per_target)
	if !is_primary || target == null || !tower.has_full_mana():
		return

	tower.drain_mana()
	_unleash(tower, target)


## Sends the beast: everything standing on the line from the tower towards the
## creep it hit, out to its own reach.
##
## GROUND creeps only, which the source states and which is also what a thing
## running along the floor should do. The stun carries its own per-creep
## cooldown, so a Beastmaster firing constantly cannot lock a pack in place.
func _unleash(tower: Building, target: Unit) -> void:
	if tower.stats == null:
		return

	for creep: Creep in HitPattern.line(tower.area, tower.global_position,
			target.global_position, beast_cells, beast_targets, tower.stats.attack):
		if creep.is_flying():
			continue
		creep.take_damage(beast_damage, DamageTable.DamageType.SIEGE, true)
		var status: StatusEffects = creep.status()
		if !status.is_immune(IMMUNE_KEY):
			status.set_immune(IMMUNE_KEY, stun_cooldown)
			status.stun(stun_seconds)


func effect_text() -> String:
	var text: String = ("Strikes %d additional creep within %s cells and gains"
		+ " %s mana per creep hit. At full mana it unleashes a beast up to %s"
		+ " cells towards the target, dealing %s Siege damage to the ground"
		+ " creeps in its path and stunning them for %ss - once every %ss per"
		+ " creep.") % [
		additional_targets,
		StringUtil.trim_number(multishot_cells),
		StringUtil.trim_number(mana_per_target),
		StringUtil.trim_number(beast_cells),
		StringUtil.compact_number(beast_damage),
		StringUtil.trim_number(stun_seconds),
		StringUtil.trim_number(stun_cooldown),
	]
	if range_bonus_per_cell > 0.0:
		text += " Damage rises %s%% per cell of range to the target, up to +%s%%." % [
			StringUtil.trim_number(range_bonus_per_cell * 100.0),
			StringUtil.trim_number(max_range_bonus * 100.0)]
	return text
