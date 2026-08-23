class_name UnitTypeRegistry
extends RefCounted

## Every KIND of unit this build contains, looked up by the id a spawn names it
## with. The same shape as AbilityRegistry, for the same reasons (D12).
##
## It exists because replication has to say WHAT was spawned, and the honest
## answers are all bad except this one. A resource path is forty bytes on a
## message sent twenty times a second, and it turns a renamed file into a
## silent desync. A prefab reference cannot cross a wire at all. An index into
## some list renumbers every unit the moment one is added.
##
## Built by scanning the unit stats folder named by ContentConfig, which gets
## the orphans too: a creep nothing sends yet still owns its number, so a creep
## added next week cannot be authored into the same one. That is the same
## argument the ability scan is there for.
##
## A miss is meaningful and must not be papered over: it means the other
## machine is running content this one does not have, and a spawn that cannot
## be identified has to be refused rather than guessed at.

## Ids count from 1 so 0 can mean "nobody assigned one".
const NO_TYPE: int = 0

var _by_id: Dictionary = {}
## Every stats resource found, by resource, so validate() can report the ones
## carrying no id at all - which by definition are not in _by_id.
var _seen: Dictionary = {}


## Collects every unit type under a folder, including sub-folders. Call once,
## at boot.
func build(folder: String) -> void:
	_by_id.clear()
	_seen.clear()
	_scan_folder(folder)


## The stats an id names, or null for an id this build does not contain.
func stats_for(id: int) -> UnitStats:
	if !_by_id.has(id):
		return null
	return _by_id[id] as UnitStats


func count() -> int:
	return _by_id.size()


## Reports every unit type nobody numbered. An unnumbered type is invisible to
## replication, so a creep carrying one would spawn on the server and never
## appear on any client - which looks like a networking fault and is not one.
func validate() -> bool:
	var complete: bool = true
	for stats in _seen.keys():
		var entry: UnitStats = stats as UnitStats
		if entry != null && entry.unit_type_id == NO_TYPE:
			Log.err("Unit type has no unit_type_id, it can never be replicated",
				entry.display_name)
			complete = false
	return complete


func _scan_folder(folder: String) -> void:
	if folder.is_empty():
		return

	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		Log.err("Unit stats folder could not be opened, nothing can be replicated", folder)
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if !entry.begins_with("."):
				_scan_folder(folder.path_join(entry))
		else:
			_scan_file(folder.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


## Both resource spellings, because an exported build converts text resources
## to binary and leaves a .remap behind. Same reasoning as AbilityRegistry.
func _scan_file(path: String) -> void:
	var real_path: String = path.trim_suffix(".remap")
	if !(real_path.get_extension().to_lower() in AbilityRegistry.RESOURCE_EXTENSIONS):
		return
	if !ResourceLoader.exists(real_path):
		return

	var stats: UnitStats = ResourceLoader.load(real_path) as UnitStats
	if stats == null:
		return
	_seen[stats] = true
	_register(stats)


## An unnumbered type is left out rather than stored under 0, so stats_for(0)
## can never accidentally resolve to something.
func _register(stats: UnitStats) -> void:
	var id: int = stats.unit_type_id
	if id == NO_TYPE:
		return

	var existing: UnitStats = _by_id.get(id) as UnitStats
	if existing != null && existing != stats:
		Log.err("Two unit types claim the same unit_type_id", {
			"id": id,
			"first": existing.display_name,
			"second": stats.display_name,
		})
		return
	_by_id[id] = stats
