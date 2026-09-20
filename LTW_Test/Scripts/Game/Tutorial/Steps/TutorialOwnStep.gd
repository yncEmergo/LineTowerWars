class_name TutorialOwnStep
extends TutorialStep

## Finished once the player has spent the technologies this task names and owns
## a number of towers of one exact type.
##
## **The research and the tower are ONE task on purpose.** "Research Fire, then
## raise the Core to a Magma Well" is one thing to learn, and splitting it into
## a research task and a build task doubles the rows a player ticks off without
## teaching them anything the first row did not. The technologies are named on
## TutorialStep.tech_ids, which is also the only list the Research Center will
## accept while the task is up, so what is pointed at and what is waited for
## cannot drift apart.
##
## Written for UPGRADE tasks, where what the lesson wants is towers standing as
## something - a Magma Well, an Ultimate Firelord - rather than presses of a
## button: an upgrade takes a moment, and it is the tower that comes out of it
## that the next task needs. Read off the ground, so an upgrade still going on
## does not count yet.
##
## **Naming the technologies matters even where the upgrade itself is gated on
## them**, because an Ultimate's CROSS requirement is not: the ability that
## raises a Greater Firelord to the Ultimate asks only for the Firelord path,
## so a task that waited on the tower alone could be finished without the two
## technologies it is teaching. See game_rules.md, Technology.

@export_group("Objective")
## The tower type, as a res:// path to its BuildingStats.
@export_file("*.tres") var tower_path: String = ""
## How many of them.
@export var count: int = 1


func is_complete(director: TutorialDirector) -> bool:
	var counted: Vector2i = progress(director)
	return counted.y > 0 && counted.x >= counted.y


## Technologies bought and towers standing, against both totals - so the number
## in the task's brackets moves on the research as well as on the upgrade.
func progress(director: TutorialDirector) -> Vector2i:
	return Vector2i(techs_owned(director) + _owned(), tech_ids.size() + maxi(1, count))


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
