class_name ReturnToCoreAbility
extends UnitAbility

## Takes an elemental tower back down to a bare Elemental Core, in place.
##
## The way OUT of an element. Every elemental tower is reached by morphing a
## Core and then upgrading, and until this existed the only way to change your
## mind about a cell was to sell what was standing on it and build a new Core
## there - which gives the cell up for the length of a sale and a build, and a
## maze is made of cells.
##
## **The morph run backwards, so it runs on the morph's machinery**: the same
## in-place countdown, the same preview of what is arriving, the same cancel.
## What differs is the clock and the money, and both of those belong to the
## tower - see Building.return_to_core.
##
## Carried by every elemental tower WORTH 800 GOLD OR MORE, which is the 800g
## tower of each element and everything above it. Below that there is nothing
## to return: an element's 200g base tower cost exactly what the Core cost and
## is already one free morph away from being one.
##
## It NAMES THE CORE BY PATH rather than holding its stats, and that is forced
## rather than tidy. The Core's card reaches all ten elements, each element
## reaches its own tiers, and every one of those tiers carries this very
## ability - so a stats reference here would close a cycle of ext_resources
## through the whole roster. TechDefinition.ultimate_cross_tech_id sidesteps
## the same cycle with an id; a path does it here, and costs nothing until
## somebody presses the button.

@export_group("Return")
## The Elemental Core's stats, as a res:// path. Loaded on first use and
## cached, on the same terms as UnitStats.scene_path.
@export_file("*.tres") var core_stats_path: String = ""

## The loaded Core, and whether loading it has been tried. Derived from this
## resource's own @export and identical for every tower sharing it, which is
## what makes caching it here safe - see UnitAbility on shared state.
var _cached_core: BuildingStats = null
var _core_loaded: bool = false


func execute(unit: Unit, _target: AbilityTarget) -> void:
	var building: Building = unit as Building
	if building == null:
		Log.err("Return to Core was run on something that is not a building",
			"nothing" if unit == null else unit.name)
		return

	var core: BuildingStats = core_stats()
	if core == null:
		# core_stats() has already said why, once.
		return
	building.return_to_core(core)


## Greyed out while the tower is busy being something else, which is the same
## test every upgrade on the card makes. There is no gold question: a return
## charges nothing.
func can_execute(unit: Unit) -> bool:
	var building: Building = unit as Building
	if building == null:
		return false
	if building.is_under_construction() || building.is_selling() || building.is_upgrading():
		return false
	return core_stats() != null


## The Elemental Core's stats, or null with one message naming this ability.
##
## The load is deferred and cached rather than being an ext_resource, see the
## class docstring. Nothing extra is pulled into memory by it in practice: the
## builder's build menu already names the Core, so it is loaded long before any
## tower is standing to press this.
func core_stats() -> BuildingStats:
	if _core_loaded:
		return _cached_core
	_core_loaded = true

	if core_stats_path.is_empty():
		Log.err("Return to Core names no Core stats", display_name)
		return null
	if !ResourceLoader.exists(core_stats_path):
		Log.err("Return to Core stats path does not resolve", {
			"ability": display_name,
			"path": core_stats_path,
		})
		return null

	_cached_core = ResourceLoader.load(core_stats_path) as BuildingStats
	if _cached_core == null:
		Log.err("Return to Core stats path did not load as BuildingStats", {
			"ability": display_name,
			"path": core_stats_path,
		})
	return _cached_core


## Deliberately empty. The Core is already reached from the builder's build
## menu, which is the only way one is ever placed, so naming it here would only
## walk the same subtree again - and would force the load the path exists to
## avoid. See AbilityRegistry.
func reached_stats() -> Array[UnitStats]:
	var empty: Array[UnitStats] = []
	return empty


## What the return costs and what it hands back, off the config and off the
## Core's own stats, so the card cannot quote a wait the tower does not serve
## or a share it does not pay.
func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)

	var config: GameConfig = References.game_config
	if config != null:
		data.add_stat("Return time", "%.1fs" % config.return_to_core_seconds)
		data.add_stat("Refunded", "%d%%" % int(round(config.sell_refund_ratio * 100.0)))

	var core: BuildingStats = core_stats()
	if core != null:
		data.add_stat("Stays sunk", str(core.total_gold_cost))
	return data


## A path that does not resolve is a dead button, and this one sits on most of
## the elemental roster. core_stats() caches, so the reason is reported once
## however many cards ask.
func validate(_seen: Dictionary) -> bool:
	return core_stats() != null
