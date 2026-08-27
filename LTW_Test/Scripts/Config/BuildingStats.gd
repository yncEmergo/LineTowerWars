class_name BuildingStats
extends UnitStats

## Stats for anything that occupies grid cells: towers, and later the creep
## sending building.
##
## Kept separate from MobileUnitStats so a building's stats file never shows
## movement fields, and a creep's never shows a footprint.
##
## This is also the authority a build ability points at. The ability names the
## STATS, and the stats name their own prefab and their own model, so a tower's
## price, footprint and appearance can never be read out of one file while it
## is spawned from another. See UnitStats.scene_path.

@export_group("Building")
## Visual-only scene shared by the real building and its build preview, as a
## res:// path, so a ghost can never show a different shape to what gets
## placed. A path rather than a PackedScene for the reasons in SceneUtil.
@export_file("*.tscn") var model_scene_path: String = ""
## Command card shown while the building is still going up. Normally just
## cancel, replaced by the finished abilities once construction completes.
@export var construction_abilities: Array[UnitAbility] = []
## Command card shown while the building is being sold. Normally just cancel,
## which is what makes the sale interruptible.
@export var selling_abilities: Array[UnitAbility] = []
## Command card shown while the building is upgrading into another one.
## Normally just cancel, on the same terms as the two above.
##
## A third card rather than a reuse of construction_abilities, because the two
## cancels refund different money: cancelling a build hands back the whole
## tower, cancelling an upgrade hands back only the tier that was being paid
## for. One button that meant either would be the wrong button half the time.
@export var upgrading_abilities: Array[UnitAbility] = []
## Footprint in player cells. Towers are always 1 x 1 per game_rules.md,
## which is 2 x 2 internal cells.
@export var footprint_cells: Vector2i = Vector2i.ONE
## Price of THIS tower alone: what a build costs, or what one upgrade costs.
@export var gold_cost: int = 0
## Mana this building holds at most, or 0 for one that uses none.
##
## HERE rather than on UnitStats because a tower is the only thing in the game
## that has any: an elemental tower's ability is nearly always "gain mana per
## attack, spend it all at full" (unit_data.md section 4), and a creep's stats
## file showing a mana field it can never fill would be noise on every one of
## them.
##
## What FILLS it is the tower's passives, through TowerPassive.mana_per_second
## and TowerPassive.on_attack. This is only the ceiling.
@export var max_mana: int = 0
## Share of that ceiling a tower is built with, 0 to 1. Almost everything
## starts empty; the Doom Guard line starts FULL and decays from there, which
## is the whole of its design.
@export var starting_mana_ratio: float = 0.0
## Every gold piece it takes to end up with one of these, this tier included.
##
## The same as gold_cost for a tower the builder places directly, and the sum
## of the whole chain for anything upgraded into. Authored rather than walked,
## because a tower knows what is ABOVE it and never what is below - an upgrade
## ability names only the next rung, which is what keeps a branch one .tres per
## tier rather than a list somebody has to keep in order.
##
## It exists because a client cannot add up a chain it never watched: a tower
## that was already standing when this machine joined arrives as one snapshot
## record, and the sell refund quoted on it has to be right anyway. On the
## authority `invested_gold` reaches exactly this number on its own, which is
## what validate() checks.
@export var total_gold_cost: int = 0


## The three cards a building swaps down to are cards like any other, and the
## registry has to see them: while a tower goes up its only button is Cancel
## Build, while it comes down its only button is Cancel Sell, and while it
## upgrades its only button is Cancel Upgrade. None of them sits in
## `abilities`, which is why they have to be added here by hand.
func card_abilities() -> Array[UnitAbility]:
	var every: Array[UnitAbility] = super()
	every.append_array(construction_abilities)
	every.append_array(selling_abilities)
	every.append_array(upgrading_abilities)
	return every

## Cached model and whether loading it has been tried, see model_scene().
var _cached_model: PackedScene = null
var _model_loaded: bool = false


## The visual-only model, loaded the first time a ghost or a tower needs it.
## Cached on the same terms as UnitStats.scene().
func model_scene() -> PackedScene:
	if !_model_loaded:
		_model_loaded = true
		_cached_model = SceneUtil.load_scene(model_scene_path, display_name)
	return _cached_model


## Adds the model path to the ones the base class already checks.
func _validate_paths() -> bool:
	var complete: bool = super()

	if !model_scene_path.is_empty() && !SceneUtil.exists(model_scene_path):
		Log.err("Building model_scene_path does not resolve", {
			"building": display_name,
			"path": model_scene_path,
		})
		complete = false

	return complete
