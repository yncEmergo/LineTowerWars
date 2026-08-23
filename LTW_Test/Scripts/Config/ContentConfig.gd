class_name ContentConfig
extends Resource

## Where the content this build contains actually lives on disk.
## Stored as Resources/Config/content_config.tres, reached via
## References.content_config.
##
## It exists because a folder cannot be walked from a reference: every other
## content question in this project is answered by following a resource to the
## next one, but "what abilities does this build contain" has no starting point
## to follow FROM. An orphan ability - one on no card yet, or one whose card
## went away - is reachable from nothing, and it still has to hold its id.
##
## That matters most when content is being made rather than when it is
## finished: a new ability gets its number the moment the file exists, before
## anybody has put it on a card, so no two abilities can ever be authored into
## the same id while a card is still being built. See AbilityRegistry and
## multiplayer.md D12.
##
## A folder rather than a list, deliberately. A list would be the hand-kept
## register D12 exists to avoid, and would be wrong the first time somebody
## forgot to add a line to it.

@export_group("Folders")
## Every ability in the build, searched recursively. Sub-folders are included,
## which is what makes Abilities/Passives part of it without being named.
@export_dir var abilities_folder: String = "res://Resources/Abilities"
## Every unit type in the build, searched the same way. Replication names a
## spawn by unit_type_id, so a type missing from here is a unit that spawns on
## the server and appears on nobody.
@export_dir var unit_stats_folder: String = "res://Resources/UnitStats"


## Reports every folder that does not resolve. Called at boot alongside the
## other content checks, because a folder that has been moved or renamed makes
## the registry quietly smaller rather than loudly broken.
func validate() -> bool:
	var complete: bool = true
	complete = _validate_folder(abilities_folder, "abilities_folder") && complete
	complete = _validate_folder(unit_stats_folder, "unit_stats_folder") && complete
	return complete


func _validate_folder(folder: String, field_name: String) -> bool:
	if folder.is_empty():
		Log.err("ContentConfig folder is empty", field_name)
		return false
	if !DirAccess.dir_exists_absolute(folder):
		Log.err("ContentConfig folder does not resolve", {
			"field": field_name,
			"folder": folder,
		})
		return false
	return true
