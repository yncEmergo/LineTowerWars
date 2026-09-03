class_name DumpDescriptions
extends Node

## SCAFFOLDING. Prints every ability tooltip exactly as a player reads it, so
## the wording can be reviewed without opening the game.
##
##   godot --headless --path . res://Scenes/Dev/dump_descriptions.tscn
##
## Delete with the rest of Scripts/Dev when the review is done.


func _ready() -> void:
	_dump_folder("res://Resources/UnitStats", "EVERY UNIT")
	_dump_loose_abilities()
	get_tree().quit()


func _dump_folder(folder: String, title: String) -> void:
	print("\n################ %s ################" % title)
	for path in _files_under(folder):
		var stats: Resource = load(path)
		if stats == null || !("unit_type_id" in stats):
			continue
		print("\n=== %s  (id %d)  %s" % [
			stats.get("display_name"), stats.get("unit_type_id"), path])
		var list: Array = stats.get("abilities")
		if list == null:
			continue
		for entry in list:
			if entry != null:
				_print_ability(entry, stats)


func _print_ability(entry: Resource, owner_stats: Resource = null) -> void:
	var data: AbilityTooltipData = entry.call("tooltip_data", "", null)
	var text: String = "" if data == null else data.description
	# A tooltip built with no unit behind it leaves its {placeholders} standing,
	# which is right in the game and misleading in a review dump - so where the
	# owning stats are in hand, they are handed over.
	if owner_stats != null && text.contains("{"):
		text = entry.call("description_text", owner_stats)
	var extra: String = ""
	if data != null:
		for row: PackedStringArray in data.stats:
			extra += "\n      | %s: %s" % [row[0], row[1]]
		for row: PackedStringArray in data.specials:
			extra += "\n      * %s: %s" % [row[0], row[1]]
	print("  - [%s] %s (id %s)\n      %s%s" % [
		entry.get_script().get_global_name(), entry.get("display_name"),
		entry.get("ability_id"), text.replace("\n", "\n      "), extra,
	])


func _dump_loose_abilities() -> void:
	print("\n################ EVERY ABILITY FILE ################")
	for path in _files_under("res://Resources/Abilities"):
		var res: Resource = load(path)
		if res == null || res.get_script() == null || !("ability_id" in res):
			continue
		print("\n--- %s" % path)
		_print_ability(res)


func _files_under(folder: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = folder.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_files_under(full))
		elif entry.ends_with(".tres"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
