class_name DevourEssencePassive
extends TowerPassive

## Unholy 2, the whole Alchemist line: a tower that grows permanently stronger
## with every creep it kills.
##
## unit_data.md 4.8: each kill is worth a flat amount of attack damage forever,
## up to a cap, and the bonus survives an upgrade. Once the cap is reached the
## overflow goes to the nearest other Unholy (2) tower, so a maxed Alchemist
## feeds the one next to it rather than wasting kills.
##
## The bonus is PER TOWER and permanent, so it lives in Building.ability_state
## and rides across an upgrade with everything else there. What is carried is
## the DAMAGE, never a stack count: a Lesser tower's fifty kills are worth +100,
## and the Greater tower it becomes still holds +100 even though its own kills
## are worth three apiece. So the stacks a card shows are read BACK out of the
## damage rather than counted alongside it, and the two can never disagree.
##
## That count is also the tower's SECOND RESOURCE - see tower_resource(). The
## Alchemist spends no mana on anything, so the bar under its health is free to
## say the one number that decides what it is worth.
##
## The Ultimate also alters the ARMOUR TYPE of what it hits, to a type the
## player picks off the command card - see ArmorTypeChoiceAbility, which is the
## button, while the applying of it is here.

## Key the eaten damage is kept under. Shared by every tier of the line ON
## PURPOSE: it is the same bonus carried up the chain, and using one key is
## what makes carrying it across an upgrade need no code at all.
const BONUS_KEY: String = "devoured_damage"

@export_group("Devour Essence")
## Attack damage gained per creep killed.
@export var damage_per_kill: int = 2
## The most this tower may ever eat.
@export var damage_cap: int = 100
## How far the overflow reaches for another tower of the same line, in cells.
@export var overflow_cells: float = 2.25

@export_group("Unholy Concoction")
## Seconds an altered armour type lasts, or 0 on the tiers that alter none.
@export var armor_type_seconds: float = 0.0


## What this tower has eaten so far.
##
## A CLIENT takes the server's word for it rather than reading its own key.
## The bonus is bought by KILLING, and a kill only ever happens on the
## authority - a client's copy of this tower would sit at zero all match, with
## its damage line and its stack bar both saying so. See
## Building.replicated_damage_bonus.
func permanent_bonus(tower: Building) -> int:
	if !MatchSession.is_authority():
		return tower.replicated_damage_bonus
	return int(tower.ability_state.get(BONUS_KEY, 0))


## Kills devoured out of the most this tower could ever devour.
##
## Derived from the banked damage rather than counted, for the reason in the
## docstring above: the damage is what survives an upgrade. Both halves are
## divided by the same per-kill value, so the bar reads the same share of full
## either side of one.
func tower_resource(tower: Building) -> TowerResource:
	if damage_per_kill <= 0:
		return null
	return TowerResource.counted(permanent_bonus(tower) / damage_per_kill,
		damage_cap / damage_per_kill)


func bonus_damage(tower: Building, _target: Unit, _rolled: int) -> int:
	return permanent_bonus(tower)


func on_kill(tower: Building, _target: Unit) -> void:
	_feed(tower, damage_per_kill)


func apply_debuffs(tower: Building, target: Unit) -> void:
	if armor_type_seconds <= 0.0 || target == null:
		return
	var status: StatusEffects = status_of(target)
	if status == null:
		return
	# A creep may only ever be altered to a given type once, which
	# StatusEffects enforces - so the answer being refused is normal and not
	# worth reporting.
	status.alter_armor_type(self, ArmorTypeChoiceAbility.chosen_type(tower),
		armor_type_seconds)


## Adds to what this tower has eaten, and passes the excess on.
##
## The overflow is what stops a maxed Alchemist wasting a lane: it looks for
## the nearest tower carrying THIS VERY passive resource, which is identity
## rather than a type check - a Lesser and a Greater Alchemist have different
## caps and do not feed each other, exactly as the source states.
func _feed(tower: Building, amount: int) -> void:
	if amount <= 0:
		return

	var held: int = permanent_bonus(tower)
	var room: int = maxi(0, damage_cap - held)
	tower.ability_state[BONUS_KEY] = held + mini(room, amount)

	var spare: int = amount - mini(room, amount)
	if spare <= 0:
		return
	var neighbour: Building = _nearest_sibling(tower)
	if neighbour != null:
		_feed(neighbour, spare)


func _nearest_sibling(tower: Building) -> Building:
	if tower.area == null:
		return null

	var best: Building = null
	var best_distance: float = overflow_cells
	# `distance <= best_distance` keeps the LAST of two equally close towers,
	# so which one it is depends on child order under the area. That order is
	# the order the build commands arrived in and is the same on every machine,
	# which is the only reason this is safe to leave alone. See TargetFinder's
	# _scan note - the same dependency, on a far hotter path.
	for child: Node in tower.area.get_children():
		var other: Building = child as Building
		if other == null || other == tower || !(self in other.tower_passives()):
			continue
		if other.ability_state.get(BONUS_KEY, 0) >= damage_cap:
			continue
		var offset: Vector3 = other.global_position - tower.global_position
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance <= best_distance:
			best = other
			best_distance = distance
	return best


func effect_text() -> String:
	var text: String = ("Permanently gains +%d attack damage per creep killed,"
		+ " up to +%s, and keeps it across upgrades. Overflow goes to the"
		+ " nearest tower of this line within %s.") % [
		damage_per_kill, StringUtil.compact_number(damage_cap),
		StringUtil.trim_number(overflow_cells),
	]
	if armor_type_seconds > 0.0:
		text += (" Attacks also alter the armor type of creeps hit for %ss, to"
			+ " the type chosen on the command card - once per type per creep.") \
			% StringUtil.trim_number(armor_type_seconds)
	return text


## How far the overflow reaches for the next Alchemist, which is what decides
## whether two of them are worth standing together.
func display_radius(_unit: Unit) -> float:
	return overflow_cells
