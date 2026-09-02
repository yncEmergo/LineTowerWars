class_name TechRegistry
extends RefCounted

## Every technology this build contains, looked up by the id a command names it
## with, by the square it draws in, and by the element and path it unlocks.
##
## Built by SCANNING the folder ContentConfig names, the same way abilities and
## unit types are, and for the same reason: a hand-kept list is a second copy
## of the content that is wrong the first time somebody forgets a line. There
## is no WALK here, unlike AbilityRegistry - a technology sits on nobody's card
## and is reachable from nothing, so the scan is the only way one is ever found.
##
## The id is authored on the technology, never derived from a position here, so
## adding or removing one cannot renumber anything else. This class only
## collects them and complains about what is authored wrong: a missing id, two
## technologies claiming the same one, an element missing one of its three, two
## technologies on the same grid square, and a cross requirement that is not
## the bijection unit_data.md 2.3 says it is.

## Ids count from 1 so 0 can mean "nobody assigned one".
const NO_TECH: int = 0

## What a resource file can be called. Two spellings because an exported build
## converts text resources to binary - same reason as AbilityRegistry.
const RESOURCE_EXTENSIONS: Array[String] = ["tres", "res"]

var _by_id: Dictionary = {}
## Element -> Kind -> TechDefinition, so "the Basic of this element" is a
## lookup rather than a scan over everything.
var _by_element: Dictionary = {}


## Collects everything under one folder. Call once, at boot.
func build(folder: String) -> void:
	_by_id.clear()
	_by_element.clear()
	if folder.is_empty():
		Log.err("TechRegistry was given no folder, the Research Center will be empty")
		return
	_scan_folder(folder)


## The technology an id names, or null when nothing claims it. Callers must
## expect null: a command can arrive naming an id this build does not contain,
## which is what a mismatched build looks like and has to be rejected.
func tech_for(id: int) -> TechDefinition:
	if !_by_id.has(id):
		return null
	return _by_id[id] as TechDefinition


## The technology that unlocks an element at all, which both of its paths
## require first.
func basic_for(element: TechDefinition.Element) -> TechDefinition:
	if !_by_element.has(element):
		return null
	return (_by_element[element] as Dictionary).get(TechDefinition.Kind.BASIC) as TechDefinition


## The three technologies of one element, in no particular order. Empty for an
## element this build contains none of.
##
## The whole element rather than one of its kinds, which is what the technology
## DISCS ask: their two upgrades are gated on OWNING TWO OF THE THREE and on
## owning all three, and there is no single id that means either. See
## DiscUpgradeAbility.
func for_element(element: TechDefinition.Element) -> Array[TechDefinition]:
	var found: Array[TechDefinition] = []
	if !_by_element.has(element):
		return found
	for tech in (_by_element[element] as Dictionary).values():
		found.append(tech as TechDefinition)
	return found


## Every technology in the build, ascending by id.
##
## Ascending because two machines must agree on the order: a random Ultimate is
## rolled from a list built out of this, on the shared match RNG, and a
## dictionary's own order is an implementation detail that has no business
## deciding which tower a player is handed.
func all() -> Array[TechDefinition]:
	var ids: Array = _by_id.keys()
	ids.sort()
	var found: Array[TechDefinition] = []
	for id in ids:
		found.append(_by_id[id] as TechDefinition)
	return found


## The twenty technologies that unlock a tower path, ascending by id. One per
## Ultimate tower, which is what makes this the list a random Ultimate rolls
## over.
func path_techs() -> Array[TechDefinition]:
	var found: Array[TechDefinition] = []
	for tech in all():
		if tech.is_path():
			found.append(tech)
	return found


func count() -> int:
	return _by_id.size()


## Reports everything authored wrong across the whole set. One call at boot,
## alongside the other content checks.
func validate() -> bool:
	var complete: bool = true
	for tech in all():
		complete = tech.validate() && complete
	complete = _validate_elements() && complete
	complete = _validate_slots() && complete
	complete = _validate_cross_requirements() && complete
	return complete


# --- the scan -------------------------------------------------------------

func _scan_folder(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		Log.err("Technology folder could not be opened, no technology has an id", folder)
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


func _scan_file(path: String) -> void:
	var real_path: String = path.trim_suffix(".remap")
	if !(real_path.get_extension().to_lower() in RESOURCE_EXTENSIONS):
		return
	if !ResourceLoader.exists(real_path):
		return

	# Anything in the folder that is not a technology is simply not one.
	var tech: TechDefinition = ResourceLoader.load(real_path) as TechDefinition
	if tech != null:
		_register(tech)


## An unassigned id is left out of the table rather than stored under 0, so
## tech_for(0) can never accidentally resolve to something. It is still
## reported, because a technology with no id is a button no command can name.
func _register(tech: TechDefinition) -> void:
	if tech.tech_id == NO_TECH:
		Log.err("Technology has no tech_id, no command can name it", tech.display_name)
		return

	var existing: TechDefinition = _by_id.get(tech.tech_id) as TechDefinition
	if existing != null && existing != tech:
		Log.err("Two technologies claim the same tech_id", {
			"id": tech.tech_id,
			"first": existing.display_name,
			"second": tech.display_name,
		})
		return

	_by_id[tech.tech_id] = tech
	_index_by_element(tech)


func _index_by_element(tech: TechDefinition) -> void:
	if !_by_element.has(tech.element):
		_by_element[tech.element] = {}
	var kinds: Dictionary = _by_element[tech.element]

	var existing: TechDefinition = kinds.get(tech.kind) as TechDefinition
	if existing != null && existing != tech:
		Log.err("Two technologies claim the same element and path", {
			"element": tech.element_name(),
			"path": tech.path_number(),
			"first": existing.display_name,
			"second": tech.display_name,
		})
		return
	kinds[tech.kind] = tech


# --- the checks -----------------------------------------------------------

## Every element sells exactly three technologies (unit_data.md 2.1). A missing
## one is a path that can never be bought, which is invisible until somebody
## looks for that square in the grid.
func _validate_elements() -> bool:
	var complete: bool = true
	for element in _by_element.keys():
		var kinds: Dictionary = _by_element[element]
		if kinds.size() == 3 || kinds.is_empty():
			continue
		Log.err("Element does not sell all three of its technologies", {
			"element": (kinds.values()[0] as TechDefinition).element_name(),
			"found": kinds.size(),
		})
		complete = false
	return complete


## Two technologies on one square is an authoring mistake rather than something
## to resolve quietly, exactly as it is on a command card.
func _validate_slots() -> bool:
	var complete: bool = true
	var taken: Dictionary = {}
	for tech in all():
		if tech.slot == TechDefinition.NO_SLOT:
			Log.err("Technology claims no grid square, it will draw nowhere",
				tech.display_name)
			complete = false
			continue
		if taken.has(tech.slot):
			Log.err("Two technologies claim the same Research Center square", {
				"square": tech.slot,
				"first": (taken[tech.slot] as TechDefinition).display_name,
				"second": tech.display_name,
			})
			complete = false
			continue
		taken[tech.slot] = tech
	return complete


## The cross requirement is a BIJECTION: twenty Ultimates, twenty element-path
## pairs, and every pair is the requirement of exactly one Ultimate
## (unit_data.md 2.3). So every path technology appears exactly once in the
## right-hand column, and never against its own element.
##
## Checked rather than trusted, because one typo here is a tech tree that reads
## correctly on every single row and is wrong as a whole.
func _validate_cross_requirements() -> bool:
	var paths: Array[TechDefinition] = path_techs()
	var complete: bool = true
	var required_by: Dictionary = {}
	for tech in paths:
		complete = _record_cross(tech, required_by) && complete

	if complete && required_by.size() != paths.size():
		Log.err("Cross requirements are not a bijection, some path is required by nobody", {
			"paths": paths.size(),
			"required": required_by.size(),
		})
		complete = false
	return complete


func _record_cross(tech: TechDefinition, required_by: Dictionary) -> bool:
	var cross: TechDefinition = tech_for(tech.ultimate_cross_tech_id)
	if cross == null || !cross.is_path():
		Log.err("Path technology names a cross requirement that is not a path", {
			"tech": tech.display_name,
			"cross_id": tech.ultimate_cross_tech_id,
		})
		return false
	if cross.element == tech.element:
		Log.err("Path technology's Ultimate requires its own element", tech.display_name)
		return false
	if required_by.has(cross.tech_id):
		Log.err("Two Ultimates require the same element and path", {
			"cross": cross.display_name,
			"first": (required_by[cross.tech_id] as TechDefinition).display_name,
			"second": tech.display_name,
		})
		return false

	required_by[cross.tech_id] = tech
	return true
