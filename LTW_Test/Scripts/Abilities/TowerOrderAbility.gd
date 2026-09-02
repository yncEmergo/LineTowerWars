@abstract
class_name TowerOrderAbility
extends UnitAbility

## Shared half of every ability that NAMES a tower: placing one, and upgrading
## into one.
##
## Both point at the tower's STATS rather than at its prefab. The stats
## resource is the authority on what the tower is - its price, its footprint,
## its model, its attack - and it names its own prefab by path, so nothing here
## has to spawn a tower to find out what one costs. That is what lets a tooltip
## quote a price and a damage range without a single node being created.
##
## It exists because the two abilities describe the same thing in the same
## words. A player comparing "build a Lesser Cannon" against "upgrade into a
## Cannon" is reading the same card, and two copies of that card would drift
## the first time one of them learned about a new stat.
##
## What each subclass still owns is the VERB: what pressing it does, and what
## has to be true for it to be pressable at all.

@export_group("Tower")
## Everything this names, and the only thing it names. The prefab comes off it
## through tower_stats.scene().
@export var tower_stats: BuildingStats
## Technology the ordering player must own before this may be pressed, or 0 for
## one that needs none - which is every Basic tower.
##
## An ID rather than a TechDefinition, and that is forced rather than a
## preference: the twenty cross requirements already form a closed cycle of
## ext_resources (TechDefinition.ultimate_cross_tech_id says why), and a tower
## holding a technology resource would drag that whole cycle into memory the
## moment anything read a price off it. An id costs nothing until something
## resolves it, exactly as a scene path does.
##
## The check is the SAME call the Research Center makes, TechManager.owns, so
## there is no second copy of the rule. It is asked of the tower's OWNER rather
## than of whoever is looking, exactly as affordability is.
@export var required_tech_id: int = 0


## The tower this names, so the registry finds the abilities on its card - and
## through them the tier above it, all the way up a branch.
func reached_stats() -> Array[UnitStats]:
	var reached: Array[UnitStats] = []
	if tower_stats != null:
		reached.append(tower_stats)
	return reached


## The tower's own picture, so the button that builds it and the button that
## upgrades into it can never show different things.
func icon_texture() -> Texture2D:
	if tower_stats != null && tower_stats.icon != null:
		return tower_stats.icon
	return icon


## Price of the tower, read from its own stats.
func gold_cost() -> int:
	if tower_stats == null:
		return 0
	return tower_stats.gold_cost


## Footprint in player cells, so a preview can size itself before anything is
## built.
func footprint_cells() -> Vector2i:
	if tower_stats == null:
		return Vector2i.ONE
	return tower_stats.footprint_cells


## Whether what this places is a WALL, off the stats for the same reason the
## footprint is: the build preview has to answer it about a ghost.
func blocks_movement() -> bool:
	return tower_stats == null || tower_stats.blocks_movement


## Visual-only scene taken from the tower's stats, so a ghost is the same mesh
## that gets placed.
func model_scene() -> PackedScene:
	if tower_stats == null:
		return null
	return tower_stats.model_scene()


## Whether the ordering player has researched what this tower needs.
##
## True when nothing is required, and true when there is no technology manager
## at all - a bare test scene must stay usable, the same way _owner_can_afford
## passes with no PlayerManager.
func _owner_has_tech(unit: Unit) -> bool:
	if required_tech_id == 0:
		return true
	var manager: TechManager = References.tech_manager
	if manager == null || unit == null:
		return true
	return manager.owns(unit.owner_player_id, required_tech_id)


## What this tower is waiting on, as a line for its tooltip, or empty when it
## is not waiting on anything. Named rather than "requires technology", because
## a player looking at a greyed square needs to know WHICH one to go and buy.
func _tech_requirement_text() -> String:
	if required_tech_id == 0:
		return ""
	var session: MatchSession = References.match_session
	var registry: TechRegistry = null if session == null else session.techs()
	var tech: TechDefinition = null if registry == null else registry.tech_for(required_tech_id)
	if tech == null:
		return "Requires a technology this build does not contain."
	return "Requires %s." % tech.display_name


## Whether the ordering player can currently pay for this tower.
##
## Answered against the OWNER of the unit rather than against whoever is
## looking: on a server validating a command there is no local player at all,
## and on a client watching an opponent's tower the answer must be about them.
func _owner_can_afford(unit: Unit) -> bool:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return true
	var state: PlayerState = manager.state_for(unit.owner_player_id)
	return state == null || state.can_afford(gold_cost())


## Describes the TOWER rather than the order, the same way a send describes the
## creep: every number comes off the tower's own stats file, so the card cannot
## quote a price it does not charge or a range the tower does not have.
func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)
	var info: BuildingStats = tower_stats
	if info == null:
		return data

	data.title = info.display_name
	data.gold_cost = info.gold_cost
	data.add_stat("Health", str(info.max_health))
	data.add_stat("Armor", info.armor_text(info.armor))

	# A tower that cannot attack - none today, but the shape allows it - leaves
	# out the whole block rather than printing a line that only ever says none.
	if info.attack != null:
		data.add_stat("Damage", info.damage_text())
		data.add_stat("Attack speed", info.attack.attack_speed_text())
		data.add_stat("Range", info.attack.range_text())
		data.add_stat("Targets", info.attack.target_types_text())

	# What the whole tower has cost by the time it is standing, which is the
	# number a player weighing one branch against another is actually after.
	# Left out where it equals the price, so a 10g tower does not say 10 twice.
	if info.total_gold_cost > info.gold_cost:
		data.add_stat("Total invested", StringUtil.compact_number(info.total_gold_cost))

	if info.max_mana > 0:
		data.add_stat("Mana", str(info.max_mana))

	var config: GameConfig = References.game_config
	if config != null:
		data.add_stat(_time_label(), "%.1fs" % config.build_seconds)
	_add_attack_effects(data, info)
	_add_passives(data, info)

	var requirement: String = _tech_requirement_text()
	if !requirement.is_empty():
		data.add_special("Technology", requirement)
	return data


## Lists the tower's own named abilities on the card that buys it, so a player
## weighing one path against another reads what the tower DOES rather than only
## what it costs. Each passive writes its own line off its own numbers.
func _add_passives(data: AbilityTooltipData, info: BuildingStats) -> void:
	for entry in info.abilities:
		var passive: TowerPassive = entry as TowerPassive
		if passive != null:
			data.add_special(passive.display_name, passive.passive_text())


## What the time line on the card is called. Building and upgrading spend the
## same number of seconds and a player is waiting for different things, so each
## subclass names it.
@abstract func _time_label() -> String


## An ability with no stats, or stats that name a prefab which is not there, is
## a dead button. Both are worth one message at boot.
func validate(seen: Dictionary) -> bool:
	if tower_stats == null:
		Log.err("Tower ability has no tower stats assigned", display_name)
		return false

	var complete: bool = tower_stats.validate(seen)
	if tower_stats.scene_path.is_empty():
		Log.err("Tower ability names a tower with no scene_path, nothing could be placed", {
			"ability": display_name,
			"tower": tower_stats.display_name,
		})
		complete = false

	return complete


## Describes splash and anything else the attack does on impact, in the same
## block a unit's passives use. Each effect writes its own line off its own
## numbers, so a tooltip cannot quote a radius the tower does not have.
func _add_attack_effects(data: AbilityTooltipData, info: BuildingStats) -> void:
	if info.attack == null:
		return

	for effect: AttackEffect in info.attack.effects:
		if effect == null || effect.effect_name().is_empty():
			continue
		data.add_special(effect.effect_name(), effect.description_text())
