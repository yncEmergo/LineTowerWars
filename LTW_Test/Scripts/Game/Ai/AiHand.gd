class_name AiHand
extends RefCounted

## The AI's HANDS: finding the button and pressing it.
##
## Everything an AI does to the world goes through here, and everything here
## goes through `Commands` - the same road a player's click takes, into the same
## ability, refused by the same world. **That is the whole of why an AI cannot
## cheat**: it is not trusted not to, it is simply never given another way in.
## It pays the gold, it waits the build time, and the area refuses its
## placements exactly as it refuses yours.
##
## It is also what keeps the brain readable. An AI that reached for
## `builder.order_build` directly would be one refactor away from bypassing the
## price; one that has to find the ability on the card is answering the same
## question a player answers, which is "is this button there and can I press
## it".
##
## Statics rather than an object, because none of it holds anything: every
## question is asked of a unit that is passed in.

## Whether a unit is in a state to be given an order at all.
static func is_usable(unit: Unit) -> bool:
	return unit != null && is_instance_valid(unit) && unit.is_alive()


## The BuildTowerAbility on a builder's card that places one named tower, or
## null when the builder cannot place it.
##
## Walked over the card rather than looked up in a table, because the card is
## what the server checks an order against: an ability that is not reachable
## from the builder's own menu is one the order road would refuse, so an AI that
## found it another way would only be submitting orders that bounce.
static func build_ability(builder: Unit, stats: BuildingStats) -> BuildTowerAbility:
	if builder == null || stats == null:
		return null
	for entry in _card_of(builder):
		var build: BuildTowerAbility = entry as BuildTowerAbility
		if build != null && build.tower_stats == stats:
			return build
	return null


## Every tower this builder can place right now, in card order.
##
## What a profile that names no opening tower falls back to, and the honest
## source for it: whatever the build menu offers is what a player would have to
## choose from too.
static func buildable_towers(builder: Unit) -> Array[BuildingStats]:
	var found: Array[BuildingStats] = []
	for entry in _card_of(builder):
		var build: BuildTowerAbility = entry as BuildTowerAbility
		if build != null && build.tower_stats != null:
			found.append(build.tower_stats)
	return found


## The whole of a unit's card, submenus included, flattened.
##
## Recursive because the card is a TREE: Build sits in the top row as a submenu
## holding the towers, so a search of the row alone would find no tower at all -
## which is the same thing CommandService._reaches has to say about validating
## a build order, reached from the other side.
static func _card_of(unit: Unit) -> Array:
	var found: Array = []
	_collect(unit.current_abilities(), found, {})
	return found


static func _collect(entries: Array, into: Array, seen: Dictionary) -> void:
	for entry in entries:
		var ability: UnitAbility = entry as UnitAbility
		if ability == null || seen.has(ability):
			continue
		seen[ability] = true
		into.append(ability)
		_collect(ability.submenu_abilities(), into, seen)


## The UPGRADE on a tower's card that takes it one rung toward a named target,
## or null when there is no route from here to there.
##
## **A tower knows what is ABOVE it and never what is below**, which is the
## shape the whole roster is authored in: one .tres per rung, each naming only
## the next. So "get me to the Ultimate Firelord" is answered by walking
## forward from where the tower is now and taking the first step whose branch
## can still reach the target.
##
## The walk is bounded by the chain itself - every rung is strictly more
## expensive than the one below it, so it terminates - and `seen` guards against
## a chain somebody authors into a loop, which would otherwise be an infinite
## descent rather than a refused order.
static func upgrade_toward(tower: Building, target_type_id: int) -> UpgradeTowerAbility:
	if tower == null || tower.stats == null:
		return null
	if target_type_id == UnitTypeRegistry.NO_TYPE:
		return null
	if tower.stats.unit_type_id == target_type_id:
		return null

	for entry in tower.current_abilities():
		var upgrade: UpgradeTowerAbility = entry as UpgradeTowerAbility
		if upgrade == null || upgrade.tower_stats == null:
			continue
		if branch_reaches(upgrade.tower_stats, target_type_id, {}):
			return upgrade
	return null


## Whether a target type is anywhere up this branch, the tower itself included.
##
## Public because the brain asks it of a tower that does not exist yet: "which
## of the towers I could PLACE here can still climb to what the plan wants" is
## the same walk one rung earlier. See AiPlayer._placeable_for.
static func branch_reaches(stats: BuildingStats, target_type_id: int,
		seen: Dictionary = {}) -> bool:
	if stats == null || seen.has(stats):
		return false
	seen[stats] = true
	if stats.unit_type_id == target_type_id:
		return true

	for entry in stats.abilities:
		var upgrade: UpgradeTowerAbility = entry as UpgradeTowerAbility
		if upgrade != null && branch_reaches(upgrade.tower_stats, target_type_id, seen):
			return true
	return false


## The cheapest upgrade a tower can take right now, whatever branch it leads to.
##
## What an AI with no opinion about where a maze is GOING falls back to: a maze
## of 10g towers that quietly climbs a tier at a time is still a maze that gets
## harder, and it is what an easy opponent should be doing. A profile with a
## saved layout wants upgrade_toward instead, because the layout has an opinion.
static func cheapest_upgrade(tower: Building) -> UpgradeTowerAbility:
	var best: UpgradeTowerAbility = null
	for entry in tower.current_abilities():
		var upgrade: UpgradeTowerAbility = entry as UpgradeTowerAbility
		if upgrade == null || upgrade.tower_stats == null:
			continue
		if best == null || upgrade.gold_cost() < best.gold_cost():
			best = upgrade
	return best


## The send on a sender's card for one creep type, or null when that creep is
## not in this match at all - which the card already answers, because a creep
## the settings left out is not on it. See SendBuilding.current_abilities.
static func send_ability(sender: SendBuilding, creep_stats: CreepStats) -> SendCreepAbility:
	if sender == null || creep_stats == null:
		return null
	for entry in sender.current_abilities():
		var send: SendCreepAbility = entry as SendCreepAbility
		if send != null && send.creep_stats == creep_stats:
			return send
	return null


## Every send on a sender's card, in card order.
static func sends_on(sender: SendBuilding) -> Array[SendCreepAbility]:
	var found: Array[SendCreepAbility] = []
	if sender == null:
		return found
	for entry in sender.current_abilities():
		var send: SendCreepAbility = entry as SendCreepAbility
		if send != null && send.creep_stats != null:
			found.append(send)
	return found


# --- pressing ---------------------------------------------------------------

## Orders a tower at a world point. The AI's whole build road.
##
## `queued` chains it behind whatever the builder is already doing, exactly as
## holding shift does for a player - which is what lets an AI that can afford
## four towers order four walks instead of standing still between them.
static func order_build(slot: int, builder: Unit, ability: BuildTowerAbility,
		world_point: Vector3, queued: bool) -> void:
	if !is_usable(builder) || ability == null:
		return
	var target: AbilityTarget = AbilityTarget.new()
	target.position = world_point
	target.has_position = true
	Commands.submit_for(slot, ability, [builder], target, queued)


## Orders one rung of an upgrade on a tower. Nothing to aim at: the tower is
## already standing on the cell the upgrade will occupy.
static func order_upgrade(slot: int, tower: Building, ability: UpgradeTowerAbility) -> void:
	if !is_usable(tower) || ability == null:
		return
	Commands.submit_for(slot, ability, [tower], AbilityTarget.new())


## Buys one pack of creeps. Sending needs no aim either - where they go is the
## send ring's answer rather than the sender's.
static func order_send(slot: int, sender: SendBuilding, ability: SendCreepAbility) -> void:
	if !is_usable(sender) || ability == null:
		return
	Commands.submit_for(slot, ability, [sender], AbilityTarget.new())


## Spends the free research on one Ultimate, rolled by the match's own RNG.
##
## The Research Center's own random button rather than a choice of this AI's,
## and deliberately so for now: which Ultimate a computer opponent SHOULD open
## on is a balance question nobody has answered yet, and rolling is the honest
## placeholder - it is what the mode a human can pick already does, and it never
## claims to be a decision. A profile that should favour one is a later change
## to this one line.
static func order_random_ultimate(slot: int) -> void:
	Commands.submit_player_action_for(slot, Command.PlayerAction.RANDOM_ULTIMATE)


## Spends it on ONE NAMED Ultimate: the same press the Show Ultimates row of the
## Research Center makes, named by the PATH technology that leads to the tower.
##
## The rules are TechManager's and refuse it exactly as they refuse a player's -
## it is only offered while the free allowance still covers the whole set, which
## at the start of a match it does.
static func order_ultimate(slot: int, tech_id: int) -> void:
	Commands.submit_player_action_for(
		slot, Command.PlayerAction.CHOOSE_ULTIMATE, tech_id
	)
