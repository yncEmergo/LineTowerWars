class_name TutorialReachStep
extends TutorialStep

## Finished once the player owns a tower that a named tower UPGRADES INTO.
##
## Written for the Elemental Core, whose whole point is what it becomes: a
## lesson about elemental towers is finished by an elemental tower standing in
## the maze, whichever element the player took. Asked of the upgrade chain
## rather than of a list of names, so a roster that gains an element needs
## nothing changed here.

@export_group("Objective")
## The tower whose upgrades count, as a res:// path to its BuildingStats. The
## tower itself does not count - owning a Core is not owning an elemental tower.
@export_file("*.tres") var from_tower_path: String = ""


func is_complete(director: TutorialDirector) -> bool:
	if director == null:
		return false
	var from: BuildingStats = _from_tower()
	return from != null && director.owns_tower_reached_from(from)


func validate() -> bool:
	var complete: bool = super()
	if from_tower_path.is_empty() || !ResourceLoader.exists(from_tower_path):
		Log.err("A lesson waits on a tower's upgrades and names no tower", title)
		complete = false
	return complete


func _from_tower() -> BuildingStats:
	if from_tower_path.is_empty() || !ResourceLoader.exists(from_tower_path):
		return null
	return ResourceLoader.load(from_tower_path, "") as BuildingStats
