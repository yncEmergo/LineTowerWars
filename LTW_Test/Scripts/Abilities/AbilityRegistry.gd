class_name AbilityRegistry
extends RefCounted

## Every ability this build contains, looked up by the id a command names it
## with.
##
## Built from the CONTENT ITSELF rather than from a hand-kept list, so it cannot
## drift out of step with what the game actually holds. That happens two ways,
## and it needs both:
##
##   1. **The walk.** Starts where the player starts - the builder's card and
##      the send building's card - and follows every build menu and every send
##      into the tower and creep stats on the far side, which carry cards of
##      their own. This is the only way an ability defined INSIDE another
##      resource is ever found.
##   2. **The scan.** Every ability file in the abilities folder, whether or not
##      anything points at it. This is the only way an ORPHAN is found - an
##      ability on nobody's card yet, or one whose card went away.
##
## The scan is not redundant with the walk, and the reason is the point of this
## class: an id has to be unique across everything AUTHORED, not just across
## everything currently reachable. An ability sitting in the folder waiting for
## a card still owns its number, so a new ability written next week cannot be
## given the same one. That matters most while content is being made, which is
## exactly when nothing is on a card yet.
##
## So "what happens when the content changes": nothing. A new ability file
## registers itself the moment it exists. A deleted one stops being registered.
## No list to forget to update.
##
## The ID ITSELF is authored on the ability, never derived from a position here,
## so reordering or removing an ability cannot renumber anything else. This
## class only collects them and complains about the two mistakes that matter:
## an ability nobody gave an id, and two abilities claiming the same one.
##
## Ids must never be reused once shipped: a saved replay or an in-flight command
## naming id 12 has to mean the same ability forever.

## Ids count from 1 so 0 can mean "nobody assigned one".
const NO_ABILITY: int = 0

## What a resource file can be called. Two spellings because an exported build
## converts text resources to binary - see _scan_file.
const RESOURCE_EXTENSIONS: Array[String] = ["tres", "res"]

var _by_id: Dictionary = {}
var _seen_stats: Dictionary = {}
var _seen_abilities: Dictionary = {}


## Collects everything. Call once, at boot, with the same roots Main validates.
##
## The walk runs FIRST and the scan second, and that order is load-bearing:
## both mark what they have seen, and a scan that reached a build menu before
## the walk did would stop the walk recursing through it into the towers on the
## far side.
func build(roots: Array[UnitStats]) -> void:
	_by_id.clear()
	_seen_stats.clear()
	_seen_abilities.clear()

	for stats in roots:
		_walk_stats(stats)
	_scan_folder(_abilities_folder())


## The ability an id names, or null when nothing claims it.
##
## Callers must expect null: a command can arrive naming an id this build does
## not contain, which is exactly what a client running mismatched content looks
## like. That has to be rejected, never guessed at.
func ability_for(id: int) -> UnitAbility:
	if !_by_id.has(id):
		return null
	return _by_id[id] as UnitAbility


func count() -> int:
	return _by_id.size()


## Whether every ability found has an id of its own. Reported at boot alongside
## the other content checks, because an unassigned id is invisible until the
## first time somebody presses that button over a network.
func validate() -> bool:
	var complete: bool = true
	for ability in _seen_abilities.keys():
		var entry: UnitAbility = ability as UnitAbility
		if entry != null && entry.ability_id == NO_ABILITY:
			Log.err("Ability has no ability_id, no command can name it", entry.display_name)
			complete = false
	return complete


func _walk_stats(stats: UnitStats) -> void:
	if stats == null || _seen_stats.has(stats):
		return
	_seen_stats[stats] = true

	# card_abilities(), not `abilities`: a building swaps its card down to
	# Cancel while it goes up and while it comes down, and those two entries
	# live in fields of their own.
	for entry in stats.card_abilities():
		_walk_ability(entry as UnitAbility)


func _walk_ability(ability: UnitAbility) -> void:
	if ability == null || _seen_abilities.has(ability):
		return
	_seen_abilities[ability] = true
	_register(ability)

	for sub in ability.submenu_abilities():
		_walk_ability(sub as UnitAbility)
	for reached in ability.reached_stats():
		_walk_stats(reached)


# --- the scan -------------------------------------------------------------

## Every ability file under a folder, including sub-folders, so
## Abilities/Passives is covered without being named.
##
## Scanned rather than listed. A list is the hand-kept register this class
## exists to avoid, and it would be wrong the first time somebody forgot a line.
func _scan_folder(folder: String) -> void:
	if folder.is_empty():
		return

	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		Log.err("Ability folder could not be opened, orphan abilities have no ids", folder)
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		# Skips . and .. and anything Godot hides, .godot included.
		if dir.current_is_dir():
			if !entry.begins_with("."):
				_scan_folder(folder.path_join(entry))
		else:
			_scan_file(folder.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


## One file, if it turns out to be an ability at all.
##
## The extension is checked rather than assumed, because the name on disk is
## not the name in the source tree: an exported build converts text resources
## to binary, so a .tres becomes a .res with a .remap left in its place. Both
## spellings have to be accepted or the registry is right in the editor and
## short in the build, which is the worst way round.
func _scan_file(path: String) -> void:
	var real_path: String = path.trim_suffix(".remap")
	if !(real_path.get_extension().to_lower() in RESOURCE_EXTENSIONS):
		return
	if !ResourceLoader.exists(real_path):
		return

	# Anything in the folder that is not an ability is simply not one - a
	# shared sub-resource, say. Not an error, and not worth a line of log.
	var ability: UnitAbility = ResourceLoader.load(real_path) as UnitAbility
	if ability != null:
		_walk_ability(ability)


func _abilities_folder() -> String:
	var config: ContentConfig = References.content_config
	if config == null:
		Log.err("No ContentConfig on References, abilities on no card will have no ids")
		return ""
	return config.abilities_folder


## An unassigned id is left out of the table rather than stored under 0, so
## ability_for(0) can never accidentally resolve to something.
func _register(ability: UnitAbility) -> void:
	var id: int = ability.ability_id
	if id == NO_ABILITY:
		return

	var existing: UnitAbility = _by_id.get(id) as UnitAbility
	if existing != null && existing != ability:
		Log.err("Two abilities claim the same ability_id", {
			"id": id,
			"first": existing.display_name,
			"second": ability.display_name,
		})
		return
	_by_id[id] = ability
