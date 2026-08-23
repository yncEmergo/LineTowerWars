class_name BuildTowerAbility
extends UnitAbility

## Places one specific tower.
##
## PLACEMENT targeting, so choosing it shows a snapped footprint preview that
## turns red where the tower cannot go. The actual legality test lives on
## PlayerArea, because it depends on that area's occupied cells and on a creep
## path still existing afterwards.
##
## Points at the tower's STATS, not at its prefab. The stats resource is the
## authority on what the tower is - its price, its footprint, its model - and
## it names its own prefab by path, so nothing here has to spawn a tower to
## find out what one costs. That is what lets a tooltip quote a price without
## a single node being created.

@export_group("Build")
## Everything this places, and the only thing this ability names. The prefab
## comes off it through tower_stats.scene().
@export var tower_stats: BuildingStats


## The tower this names, so the registry finds the abilities on its card.
func reached_stats() -> Array[UnitStats]:
	var reached: Array[UnitStats] = []
	if tower_stats != null:
		reached.append(tower_stats)
	return reached


func execute(unit: Unit, target: AbilityTarget) -> void:
	if unit == null || !target.has_position:
		return
	if tower_stats == null:
		Log.err("BuildTowerAbility has no tower stats assigned", display_name)
		return
	if !unit.has_method("order_build"):
		return
	unit.order_build(tower_stats, target.position)


func can_execute(unit: Unit) -> bool:
	if unit == null || tower_stats == null || !unit.has_method("order_build"):
		return false

	var manager: PlayerManager = References.player_manager
	if manager == null:
		return true
	var state: PlayerState = manager.state_for(unit.owner_player_id)
	return state == null || state.can_afford(gold_cost())


## Visual-only scene the build preview shows, taken from the tower's stats so
## the ghost is the same mesh that gets placed.
func model_scene() -> PackedScene:
	if tower_stats == null:
		return null
	return tower_stats.model_scene()


## Price of the tower, read from its own stats.
func gold_cost() -> int:
	if tower_stats == null:
		return 0
	return tower_stats.gold_cost


## Footprint in player cells, so the preview can size itself before anything
## is built.
func footprint_cells() -> Vector2i:
	if tower_stats == null:
		return Vector2i.ONE
	return tower_stats.footprint_cells


## Describes the tower rather than the order, the same way a send describes the
## creep: every number comes off the tower's own stats file.
func tooltip_data(hotkey_label: String = "") -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label)
	var info: BuildingStats = tower_stats
	if info == null:
		return data

	data.title = info.display_name
	data.gold_cost = info.gold_cost
	data.add_stat("Health", str(info.max_health))
	data.add_stat("Armor", info.armor_text(info.armor))
	data.add_stat("Damage", info.damage_text())

	# Which is what a player actually compares towers on, so it goes next to the
	# damage rather than below the build time.
	if info.attack != null:
		data.add_stat("Attack speed", info.attack.attack_speed_text())
		data.add_stat("Range", info.attack.range_text())

	data.add_stat("Build time", "%.1fs" % info.build_time)
	_add_attack_effects(data, info)
	return data


## A build ability with no stats, or stats that name a prefab which is not
## there, is a dead button. Both are worth one message at boot.
func validate(seen: Dictionary) -> bool:
	if tower_stats == null:
		Log.err("BuildTowerAbility has no tower stats assigned", display_name)
		return false

	var complete: bool = tower_stats.validate(seen)
	if tower_stats.scene_path.is_empty():
		Log.err("Buildable tower has no scene_path, nothing could be placed", {
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
