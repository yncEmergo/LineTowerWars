class_name SpellcasterPassive
extends TowerPassive

## Arcane 1, the whole Spellslinger line: the tower that casts spells on its
## own clock as well as shooting.
##
## unit_data.md 4.1 gives it two things that run side by side:
##
##   FROSTFIRE   cast on a timer at a creep in range, burning it for a long
##               while and chilling it deeper with every tick. Its damage GROWS
##               with every target the tower has hit since the last cast, which
##               is what makes a Spellslinger over a busy lane worth so much
##   ARCANE ORB  at full mana, one attack is spent as a splashing orb instead
##
## The Ultimate adds AETHER ATTUNEMENT: everything the tower deals is dealt a
## second time to one attuned creep. Its manual target-setting is NOT BUILT -
## the tower attunes to whatever it is currently shooting instead, which is
## what the automatic half of the source does anyway. See game_rules.md.

## Where the cast clock, the growth counter and the attuned creep are kept.
const CAST_KEY: String = "frostfire_timer"
const GROWTH_KEY: String = "frostfire_growth"
const ATTUNE_KEY: String = "aether_target"
const ATTUNE_TIMER_KEY: String = "aether_timer"
## Whether the attack now landing was paid for as an orb. Set when the mana is
## spent and cleared when the shot arrives, so a projectile in flight cannot
## be overtaken by the next one and splash twice.
const ORB_KEY: String = "arcane_orb_armed"

@export_group("Spellcaster")
## Mana regenerated per second.
@export var regen_per_second: float = 10.0

@export_group("Frostfire")
## Seconds between casts.
@export var cast_seconds: float = 3.34
## How far it reaches to pick a creep, in player cells.
@export var cast_cells: float = 4.69
## Spell Damage a second it deals.
@export var damage_per_second: float = 90.0
## How long it burns for.
@export var duration_seconds: float = 15.0
## Movement taken per tick of it, and the most that may reach.
@export var slow_per_tick: float = 0.08
@export var slow_cap: float = 0.40
## Extra damage per creep the tower has hit since the last cast, as a share.
@export var growth_per_target: float = 0.10

@export_group("Arcane Orb")
## Mana one orb costs. The Ultimate spends a share of its maximum instead,
## which is what its own .tres authors here.
@export var orb_mana_cost: int = 50
## Flat bonus damage the orb carries.
@export var orb_bonus_damage: int = 110
## Radius the orb splashes over, in player cells.
@export var orb_splash_cells: float = 1.41

@export_group("Aether Attunement")
## Share of the damage dealt that is re-applied to the attuned creep, or 0 on
## the tiers with no attunement at all.
@export var attune_share: float = 0.0
## Seconds between one re-application and the next.
@export var attune_interval: float = 0.5


func mana_per_second(_tower: Building) -> float:
	return regen_per_second


func on_tick(tower: Building, delta: float) -> void:
	_advance_frostfire(tower, delta)
	_advance_attunement(tower, delta)


## The orb is a plain flat bonus on one attack, paid for out of mana. It is
## authored as bonus damage rather than as a second attack, because it IS the
## attack - the source describes an attack being "spent as" an orb.
func bonus_damage(tower: Building, _target: Unit, _rolled: int) -> int:
	if !tower.spend_mana(orb_mana_cost):
		return 0
	tower.ability_state[ORB_KEY] = true
	return orb_bonus_damage


## The orb's splash, and the growth counter Frostfire reads. Both are per creep
## struck, which is why they are here rather than in bonus_damage.
func on_hit(tower: Building, target: Unit, dealt: int, is_primary: bool) -> void:
	tower.ability_state[GROWTH_KEY] = int(tower.ability_state.get(GROWTH_KEY, 0)) + 1

	if attune_share > 0.0 && is_primary && target != null:
		tower.ability_state[ATTUNE_KEY] = target.unit_id

	if !is_primary || !bool(tower.ability_state.get(ORB_KEY, false)) || target == null:
		return
	tower.ability_state[ORB_KEY] = false
	# The orb's own splash is measured from where it landed, like every other
	# splash in the game. It is not the tower's attack splash: an orb tower
	# authors none, so this is the only thing that covers ground.
	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, target.global_position, orb_splash_cells):
		if creep != target:
			creep.take_damage(dealt, DamageTable.DamageType.SPELL, true)


func _advance_frostfire(tower: Building, delta: float) -> void:
	var left: float = float(tower.ability_state.get(CAST_KEY, cast_seconds)) - delta
	if left > 0.0:
		tower.ability_state[CAST_KEY] = left
		return
	tower.ability_state[CAST_KEY] = cast_seconds

	if tower.area == null || tower.stats == null || !tower.can_attack():
		return
	var creep: Creep = HitPattern.random_in_radius(
		tower.area, tower.global_position, cast_cells, tower.stats.attack)
	if creep == null:
		return

	var hit_count: int = int(tower.ability_state.get(GROWTH_KEY, 0))
	tower.ability_state[GROWTH_KEY] = 0
	var scaled: float = damage_per_second * (1.0 + growth_per_target * float(hit_count))
	creep.status().burn(self, scaled, duration_seconds)
	# Deeper with every tick it burns, which is why the chill is applied at its
	# full cap in one go rather than per tick: nothing here runs per tick.
	creep.status().chill(self, resource_path, slow_cap, slow_cap, duration_seconds)


## Re-applies the tower's own output to the creep it is attuned to.
##
## The attuned creep is remembered by UNIT ID, so one that dies simply stops
## resolving and nothing here can keep a freed node alive.
func _advance_attunement(tower: Building, delta: float) -> void:
	if attune_share <= 0.0:
		return

	var left: float = float(tower.ability_state.get(ATTUNE_TIMER_KEY, 0.0)) - delta
	if left > 0.0:
		tower.ability_state[ATTUNE_TIMER_KEY] = left
		return
	tower.ability_state[ATTUNE_TIMER_KEY] = attune_interval

	var session: MatchSession = References.match_session
	var id: int = int(tower.ability_state.get(ATTUNE_KEY, MatchSession.NO_UNIT))
	if session == null || id == MatchSession.NO_UNIT || tower.stats == null:
		return

	var target: Unit = session.unit_for(id)
	if target == null || !is_instance_valid(target) || !target.is_alive():
		return
	var damage: int = int(round(float(tower.stats.attack.damage_max) * attune_share))
	target.take_damage(damage, DamageTable.DamageType.SPELL)


func effect_text() -> String:
	var text: String = ("Regenerates %s mana per second. Casts Frostfire every"
		+ " %ss on a creep within %s cells for %s Spell Damage per second over"
		+ " %ss, slowing it up to %s%%; each target hit since the last cast"
		+ " raises that by %s%%. At full mana an attack is spent as an Arcane"
		+ " Orb: +%s damage splashing %s cells.") % [
		StringUtil.trim_number(regen_per_second),
		StringUtil.trim_number(cast_seconds),
		StringUtil.trim_number(cast_cells),
		StringUtil.trim_number(damage_per_second),
		StringUtil.trim_number(duration_seconds),
		StringUtil.trim_number(slow_cap * 100.0),
		StringUtil.trim_number(growth_per_target * 100.0),
		StringUtil.compact_number(orb_bonus_damage),
		StringUtil.trim_number(orb_splash_cells),
	]
	if attune_share > 0.0:
		text += (" Aether Attunement re-applies %d%% of its damage to the"
			+ " creep it is shooting every %ss.") % [
			int(round(attune_share * 100.0)), StringUtil.trim_number(attune_interval)]
	return text
