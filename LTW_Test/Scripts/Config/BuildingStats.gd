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
## Seconds a sale takes. The building stays standing and keeps blocking until
## it completes, so a cancelled sale changes nothing.
@export var sell_time: float = 1.5
## Command card shown while the building is being sold. Normally just cancel,
## which is what makes the sale interruptible.
@export var selling_abilities: Array[UnitAbility] = []
## Footprint in player cells. Towers are always 1 x 1 per game_rules.md,
## which is 2 x 2 internal cells.
@export var footprint_cells: Vector2i = Vector2i.ONE
## Seconds until construction finishes. Currently 2 per game_rules.md.
@export var build_time: float = 2.0
## Reserved for the economy. Nothing checks it yet.
@export var gold_cost: int = 0


## The two cards a building swaps down to are cards like any other, and the
## registry has to see them: while a tower goes up its only button is Cancel
## Build, and while it comes down its only button is Cancel Sell. Neither sits
## in `abilities`, which is why they have to be added here by hand.
func card_abilities() -> Array[UnitAbility]:
	var every: Array[UnitAbility] = super()
	every.append_array(construction_abilities)
	every.append_array(selling_abilities)
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
