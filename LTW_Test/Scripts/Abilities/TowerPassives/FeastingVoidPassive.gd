class_name FeastingVoidPassive
extends TowerPassive

## Void 2, the whole Leviathan line: eats armour, and turns what it eats into
## attack damage of its own - which it loses again if it stops shooting.
##
## unit_data.md 4.9: every hit takes armour permanently and grants the tower
## attack damage, up to a cap, and the whole bonus RESETS after a few seconds
## without attacking. So a Leviathan in the middle of a maze is enormous and
## the same tower at the back of one is worth its base damage and nothing else.
##
## The Ultimate adds life steal once it is at its maximum, which is what lets
## one hold a lane against attacker creeps rather than only against walkers.
##
## The reset is what makes this different from the Alchemist's permanent
## bonus, and it is why the two lines can share a shape without sharing a
## script: one is a reward for killing and the other is a reward for not
## stopping.

const BONUS_KEY: String = "feast_bonus"
const IDLE_KEY: String = "feast_idle"

@export_group("Feasting Void")
## Armour eaten per hit, permanently, down to zero.
@export var armor_per_hit: float = 0.17
## Attack damage gained per hit.
@export var damage_per_hit: float = 1.5
## The most the bonus may reach.
@export var damage_cap: float = 90.0
## Seconds without attacking that empty it again.
@export var idle_reset: float = 3.0

@export_group("Hungering Void")
## Share of the damage dealt healed back at MAXIMUM bonus, or 0 on the tiers
## with no life steal.
##
## Against EVERYTHING the shot cost, splash included. unit_data.md 4.9 states
## it "against its primary target" and this is a deliberate departure from the
## source: the Leviathan carries splash at every tier, so the source's reading
## paid the life steal out of a fraction of the tower's own damage and paid it
## least against the packed waves a tower holding a lane is there for. The
## Ancient Warden and the Divineshroom were read the same way for the same
## reason - see TowerPassive.on_area_hit.
@export var life_steal: float = 0.0


func permanent_bonus(tower: Building) -> int:
	return int(tower.ability_state.get(BONUS_KEY, 0.0))


func bonus_damage(tower: Building, _target: Unit, _rolled: int) -> int:
	return permanent_bonus(tower)


## The idle clock runs on the tick and is cleared by attacking, exactly as the
## Scorpion's is - the difference is what it does when it runs out.
func on_tick(tower: Building, delta: float) -> void:
	var idle: float = float(tower.ability_state.get(IDLE_KEY, 0.0)) + delta
	tower.ability_state[IDLE_KEY] = idle
	if idle >= idle_reset:
		tower.ability_state[BONUS_KEY] = 0.0


func on_attack(tower: Building, _target: Unit) -> void:
	tower.ability_state[IDLE_KEY] = 0.0


func apply_debuffs(_tower: Building, target: Unit) -> void:
	var status: StatusEffects = status_of(target)
	if status != null:
		status.erode_armor(self, armor_per_hit, 0.0)


## What the tower EATS, which is stated per hit rather than per creep - so a
## splash that brushed six creeps feeds it once, exactly as it did before the
## armour half moved above. That half stays HERE and must not move to
## on_area_hit, or a Leviathan over a wave would reach its cap in one shot.
func on_hit(tower: Building, _target: Unit, dealt: int, _is_primary: bool) -> void:
	var held: float = float(tower.ability_state.get(BONUS_KEY, 0.0))
	tower.ability_state[BONUS_KEY] = minf(damage_cap, held + damage_per_hit)
	_steal(tower, dealt, held)


## The LIFE STEAL half, which is stated as a share of damage and so counts
## every creep the shot cost - see the life_steal export for the departure from
## the source that is. Nothing is banked here: the bonus is per shot and on_hit
## has already banked it.
func on_area_hit(tower: Building, _target: Unit, dealt: int) -> void:
	_steal(tower, dealt, float(tower.ability_state.get(BONUS_KEY, 0.0)))


## `held` is the bonus to test the cap against, and the two hooks read it a
## beat apart on purpose. on_hit passes what the tower held BEFORE this shot
## banked its own step, so the swing that arrives at the cap does not also pay
## out - "at maximum bonus" means it had to already be there. The splash runs
## after that bank and so reads the banked figure, which differs only on the
## single shot that reaches the cap and only for the creeps around the one it
## aimed at. Not worth a per-shot memo to make exact.
func _steal(tower: Building, dealt: int, held: float) -> void:
	if life_steal > 0.0 && held >= damage_cap:
		tower.heal(int(round(float(dealt) * life_steal)))


func effect_text() -> String:
	var text: String = ("Each hit permanently takes %s armor and grants the"
		+ " tower +%s attack damage, up to +%s. The bonus resets if the tower"
		+ " does not attack for %ss.") % [
		StringUtil.trim_number(armor_per_hit),
		StringUtil.trim_number(damage_per_hit),
		StringUtil.compact_number(int(damage_cap)),
		StringUtil.trim_number(idle_reset),
	]
	if life_steal > 0.0:
		text += " At maximum bonus it heals for %s%% of the damage it deals." \
			% StringUtil.trim_number(life_steal * 100.0)
	return text
