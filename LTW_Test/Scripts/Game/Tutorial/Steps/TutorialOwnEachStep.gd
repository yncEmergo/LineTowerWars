class_name TutorialOwnEachStep
extends TutorialStep

## Finished once the player owns at least one tower of EACH of several types -
## an Ultimate Firelord and a Greater Annihilation Glyph.
##
## For an open task whose goal is towers standing rather than how they got
## there: which Core became which, where in the maze they went and what was sold
## on the way are the player's own business. Read off the ground, so a tower
## still mid-upgrade does not count yet. See TutorialOwnStep for many of one.

@export_group("Objective")
## The tower types, as res:// paths to their BuildingStats.
@export_file("*.tres") var tower_paths: Array[String] = []


func is_complete(director: TutorialDirector) -> bool:
	var counted: Vector2i = progress(director)
	return counted.y > 0 && counted.x >= counted.y


func progress(_director: TutorialDirector) -> Vector2i:
	var standing: Dictionary = {}
	var area: PlayerArea = _local_area()
	if area != null:
		for child in area.get_children():
			var building: Building = child as Building
			if building != null && building.stats != null:
				standing[building.stats.resource_path] = true
	var owned: int = 0
	for path in tower_paths:
		if standing.has(path):
			owned += 1
	return Vector2i(owned, tower_paths.size())


func validate() -> bool:
	var complete: bool = super()
	if tower_paths.is_empty():
		Log.err("A lesson waits on towers and names none", resource_path)
		complete = false
	for path in tower_paths:
		if !ResourceLoader.exists(path):
			Log.err("A lesson waits on a tower that does not resolve", path)
			complete = false
	return complete
