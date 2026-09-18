class_name TutorialOwnStep
extends TutorialStep

## Finished once the player owns a number of towers of one exact type.
##
## Written for UPGRADE tasks, where what the lesson wants is towers standing as
## something - two Archers, then two Lesser Cannons - rather than presses of a
## button: an upgrade takes a moment, and it is the tower that comes out of it
## that the next task needs. Read off the ground, so an upgrade still going on
## does not count yet.

@export_group("Objective")
## The tower type, as a res:// path to its BuildingStats.
@export_file("*.tres") var tower_path: String = ""
## How many of them.
@export var count: int = 1


func is_complete(director: TutorialDirector) -> bool:
	return director != null && _owned() >= maxi(1, count)


func progress(_director: TutorialDirector) -> Vector2i:
	return Vector2i(_owned(), maxi(1, count))


func validate() -> bool:
	var complete: bool = super()
	if _tower() == null:
		Log.err("A lesson waits on towers of a type it does not name", title)
		complete = false
	return complete


func _owned() -> int:
	var wanted: BuildingStats = _tower()
	var area: PlayerArea = _local_area()
	if wanted == null || area == null:
		return 0
	var owned: int = 0
	for child in area.get_children():
		var building: Building = child as Building
		if building != null && building.stats == wanted:
			owned += 1
	return owned


func _tower() -> BuildingStats:
	if tower_path.is_empty() || !ResourceLoader.exists(tower_path):
		return null
	return ResourceLoader.load(tower_path, "") as BuildingStats
