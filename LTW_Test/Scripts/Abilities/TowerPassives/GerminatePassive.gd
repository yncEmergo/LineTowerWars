class_name GerminatePassive
extends TowerPassive

## Earth 2, the whole Scorpion line: the single-target assassin that is worth
## the most against something that has just walked into range.
##
## unit_data.md 4.2 gives it two halves that reward opposite things:
##
##   IDLING   after more than a second with nothing to shoot, the next few
##            attacks are worth more, scaled by how long the tower waited. A
##            Scorpion in a quiet corner of a maze hits like a Greater tower
##   CRIT     a chance to hit for half again, rising as the target's health
##            falls. The finisher half, and the reason the line has no splash
##
## The Ultimate replaces the fixed crit damage with its own mana, resets that
## mana on a kill, and refreshes the idle bonus to its maximum on a kill too -
## so an Ultimate Scorpion clearing a pack is at full power the whole way
## through it rather than only on the first creep.

## Seconds the tower has been standing idle, and how many boosted attacks are
## left of what that bought.
const IDLE_KEY: String = "germinate_idle"
const CHARGES_KEY: String = "germinate_charges"
const BONUS_KEY: String = "germinate_bonus"

@export_group("Germinate")
## Idling for less than this counts as not idling at all, so a tower firing at
## its normal rate never banks anything.
@export var idle_threshold: float = 1.0
## Bonus damage per half second idle, as a share.
@export var bonus_per_half_second: float = 0.1
## The most idling can be worth, as a share.
@export var max_idle_bonus: float = 0.5
## Attacks the banked bonus is spread over.
@export var idle_charges: int = 5

@export_group("Critical strike")
## Extra damage a critical strike deals, as a share. Ignored when the Ultimate
## reads its mana instead.
@export var crit_bonus: float = 0.5
## The highest the chance may climb as the target's health falls.
@export var max_crit_chance: float = 0.5

@export_group("Lethal Strike")
## Mana gained per attack, or 0 on the tiers that use none.
@export var mana_per_attack: float = 0.0
## Mana a kill resets the tower to.
@export var kill_mana: int = 100
## Whether the idle bonus guarantees a critical strike, and whether a kill
## refreshes it to its maximum. Both are the Ultimate's alone.
@export var idle_guarantees_crit: bool = false


## The idle clock runs whether or not the tower has anything to shoot, and is
## CLEARED by attacking. That is the whole of it: a tower that just fired has
## been idle for no time at all.
func on_tick(tower: Building, delta: float) -> void:
	tower.ability_state[IDLE_KEY] = float(tower.ability_state.get(IDLE_KEY, 0.0)) + delta


## Cashes the idle clock in. Done on the ATTACK rather than on the hit, because
## it is a property of the tower having waited and not of what it waited for.
func on_attack(tower: Building, _target: Unit) -> void:
	tower.gain_mana(mana_per_attack)

	var idle: float = float(tower.ability_state.get(IDLE_KEY, 0.0))
	tower.ability_state[IDLE_KEY] = 0.0
	if idle <= idle_threshold:
		# Not idle enough to bank anything, so this attack spends one of
		# whatever is already banked.
		tower.ability_state[CHARGES_KEY] = maxi(
			0, int(tower.ability_state.get(CHARGES_KEY, 0)) - 1)
		return

	var halves: float = floorf(idle / 0.5)
	tower.ability_state[BONUS_KEY] = minf(max_idle_bonus, bonus_per_half_second * halves)
	tower.ability_state[CHARGES_KEY] = idle_charges - 1


func bonus_damage(tower: Building, target: Unit, rolled: int) -> int:
	var bonus: float = _idle_bonus(tower)
	if _crits(target, bonus > 0.0):
		bonus += _crit_share(tower)
	return int(round(float(rolled) * bonus))


func on_kill(tower: Building, _target: Unit) -> void:
	if mana_per_attack <= 0.0:
		return
	tower.current_mana = mini(tower.max_mana, kill_mana)
	if idle_guarantees_crit:
		tower.ability_state[BONUS_KEY] = max_idle_bonus
		tower.ability_state[CHARGES_KEY] = idle_charges


## What the banked idle bonus is worth on this attack, or 0 once its charges
## have run out.
func _idle_bonus(tower: Building) -> float:
	if int(tower.ability_state.get(CHARGES_KEY, 0)) < 0:
		return 0.0
	if int(tower.ability_state.get(CHARGES_KEY, 0)) == 0:
		return 0.0
	return float(tower.ability_state.get(BONUS_KEY, 0.0))


## Whether this attack crits. The chance rises as the target's health falls, so
## a Scorpion is a finisher; the Ultimate's idle bonus guarantees it outright.
func _crits(target: Unit, idle_boosted: bool) -> bool:
	if target == null || target.max_health() <= 0:
		return false
	if idle_guarantees_crit && idle_boosted:
		return true

	var missing: float = 1.0 - float(target.current_health) / float(target.max_health())
	return MatchSession.match_rng().randf() < max_crit_chance * missing


## What a critical strike is worth. Fixed on the lower tiers; the Ultimate
## spends its own mana as the percentage, which is what makes killing things
## the way to keep it high.
func _crit_share(tower: Building) -> float:
	if mana_per_attack <= 0.0:
		return crit_bonus
	return float(tower.current_mana) / 100.0


func effect_text() -> String:
	var text: String = ("Idling over %ss banks +%s%% damage per half second"
		+ " (up to +%s%%) for the next %d attacks. Attacks critically strike"
		+ " for +%s%% with up to a %s%% chance, rising as the target weakens.") % [
		StringUtil.trim_number(idle_threshold),
		StringUtil.trim_number(bonus_per_half_second * 100.0),
		StringUtil.trim_number(max_idle_bonus * 100.0),
		idle_charges,
		StringUtil.trim_number(crit_bonus * 100.0),
		StringUtil.trim_number(max_crit_chance * 100.0),
	]
	if mana_per_attack > 0.0:
		text += (" Gains %s mana per attack and crits for its current mana"
			+ " instead; a kill resets mana to %d and refreshes the idle"
			+ " bonus in full.") % [StringUtil.trim_number(mana_per_attack), kill_mana]
	return text
