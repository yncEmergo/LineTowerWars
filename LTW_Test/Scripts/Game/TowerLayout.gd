class_name TowerLayout
extends Resource

## What stands where in one player's buildable zone, as authored ids and grid
## cells - and nothing about how any of it got there.
##
## It is deliberately the SMALLEST honest description of a maze: which building
## TYPE (unit_type_id) sits at which internal cell. No gold, no construction
## progress, no mana, no invested total, no unit ids - all of those are facts
## about a match, and a layout has to survive being loaded into a different
## one. Everything a restored building needs beyond its type is read back off
## its own stats, which is the same rule a build order follows.
##
## Named by unit_type_id rather than by a resource path, on exactly the grounds
## UnitTypeRegistry exists for: a path is a silent break the day a .tres moves,
## and an index renumbers every entry the moment a unit type is added.
##
## Cells are INTERNAL cells, anchored top-left, and they are AREA-LOCAL - the
## same numbers Building.cell carries. So a layout captured in one player's
## area restores into any other player's area unchanged, which is what makes it
## a template rather than a screenshot.
##
## A Resource rather than JSON so it is typesafe, inspectable and can be
## authored: a layout saved at runtime lands in user://, and a template shipped
## with the game would be an ordinary .tres under Resources/. Both load through
## the same load_file().
##
## Today its only caller is the developer layout cheat (CheatController), which
## is why nothing here knows about gold or technology: the cheat grants what it
## restores. If saved layouts ever become a player-facing template feature the
## FILE does not change, only who may press it and what it costs.

## Which building type each entry is, by its authored unit_type_id.
##
## Two parallel arrays rather than one array of a sub-resource, because a
## sub-resource per tower would write thirty nested blocks into the .tres where
## this writes two lines. Kept in step by capture() and read only through
## entry_count(), which refuses to walk past the shorter of them.
@export var unit_type_ids: PackedInt32Array = PackedInt32Array()
## Top-left internal cell of each entry's footprint, in the same order.
@export var cells: Array[Vector2i] = []
## Internal width and depth of the area this was captured in.
##
## Recorded so a layout taken on a differently sized grid says so, rather than
## silently dropping half its towers off an edge. It is a WARNING and not a
## refusal: every cell is still checked on its own merits by can_place, so a
## layout that happens to fit a changed grid loads fine.
@export var grid_size: Vector2i = Vector2i.ZERO


## Everything placed in an area right now, in tree order.
##
## Every Building child, which is towers AND technology discs - a maze without
## the discs filling its holes is half a layout. Structurally rather than by
## filtering: the builder is a MobileUnit and a sender is not a Building at
## all, so neither can turn up here. The same argument as
## TargetFinder.buildings_in_radius.
static func capture(area: PlayerArea) -> TowerLayout:
	var layout: TowerLayout = TowerLayout.new()
	if area == null:
		return layout

	layout.grid_size = Vector2i(area.internal_width(), area.internal_depth())
	for child: Node in area.get_children():
		var building: Building = child as Building
		if building == null || building.cell.x < 0 || building.cell.y < 0:
			continue

		var type_id: int = UnitTypeRegistry.NO_TYPE
		if building.stats != null:
			type_id = building.stats.unit_type_id
		if type_id == UnitTypeRegistry.NO_TYPE:
			# The same hole that would make it unreplicable, reached the other
			# way round: an unnumbered type cannot be named in a file either.
			Log.warn("Building has no unit_type_id and was left out of the layout",
				building.name)
			continue

		layout.unit_type_ids.append(type_id)
		layout.cells.append(building.cell)
	return layout


## Builds this layout into an area, free and finished, and answers how many
## went up.
##
## NON-DESTRUCTIVE and per entry: anything already standing keeps its cell and
## the entry that wanted it is skipped with a line in the log. So pressing it
## twice is a no-op rather than a second maze, and pressing it over a
## half-built one fills in the rest.
##
## Order does not matter, which is worth knowing before somebody tries to sort
## these. can_place's route test is monotone in walls - a path through the full
## layout is also a path through any prefix of it - so no entry can be refused
## for sealing an area that the whole layout leaves open.
##
## AUTHORITY ONLY, and its caller is what guarantees that: this spawns
## buildings, which is simulation. See CommandService.
func restore(area: PlayerArea) -> int:
	if area == null:
		return 0

	var session: MatchSession = References.match_session
	if session == null:
		Log.err("A layout cannot be restored with no MatchSession")
		return 0

	var here: Vector2i = Vector2i(area.internal_width(), area.internal_depth())
	if grid_size != Vector2i.ZERO && grid_size != here:
		Log.warn("Layout was captured on a different grid, entries may not fit", {
			"captured": grid_size,
			"area": here,
		})

	var placed: int = 0
	for index in range(entry_count()):
		if _place_one(area, session, unit_type_ids[index], cells[index]):
			placed += 1
	return placed


## How many entries can actually be read. The shorter of the two arrays, so a
## file somebody hand-edited badly loads what is whole rather than reading off
## the end of one of them.
func entry_count() -> int:
	return mini(unit_type_ids.size(), cells.size())


## Writes this layout out, creating the folder if it is not there yet. A path
## rather than a fixed location, so the same call saves into user:// and into a
## shipped template folder.
func save_file(path: String) -> bool:
	if path.is_empty():
		Log.err("A layout needs somewhere to be saved")
		return false

	var folder: String = path.get_base_dir()
	if !folder.is_empty() && !DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)

	var result: Error = ResourceSaver.save(self, path)
	if result != OK:
		Log.err("Layout could not be written", {"path": path, "error": result})
		return false
	return true


## Reads a layout back, or null when there is nothing readable there.
##
## CACHE_MODE_IGNORE because this is the one resource in the game that changes
## while the game is running. Saving and then loading in the same session would
## otherwise hand back Godot's cached copy of the file as it was the first time
## anything read it - which looks exactly like a save that did not work.
##
## `load_file` rather than `load`: a static is reached through the SCRIPT, which
## is itself a Resource, so a static sharing a name with something Object
## already owns binds to that instead and silently does nothing. See CLAUDE.md.
static func load_file(path: String) -> TowerLayout:
	if path.is_empty() || !FileAccess.file_exists(path):
		Log.warn("No layout file to load", {"path": path})
		return null

	var layout: TowerLayout = ResourceLoader.load(
		path, "TowerLayout", ResourceLoader.CACHE_MODE_IGNORE
	) as TowerLayout
	if layout == null:
		Log.err("That file did not load as a tower layout", {"path": path})
		return null
	return layout


## One entry, or false when it was refused. Everything that can refuse it is
## the area's own answer or the registry's - there is no rule here that the
## simulation does not already own.
func _place_one(area: PlayerArea, session: MatchSession, type_id: int,
		cell: Vector2i) -> bool:
	var stats: BuildingStats = session.unit_types().stats_for(type_id) as BuildingStats
	if stats == null:
		Log.warn("Layout names a building type this build does not contain",
			{"type": type_id})
		return false

	var footprint: Vector2i = area.cells_to_internal(stats.footprint_cells)
	if !area.can_place(cell, footprint, stats.blocks_movement):
		Log.info("Layout entry does not fit and was skipped", {
			"type": type_id,
			"cell": cell,
		})
		return false

	# After the placement tests, so a refused entry never pulls a prefab into
	# memory - the same order Builder._start_pending_build loads one in.
	var scene: PackedScene = stats.scene()
	if scene == null:
		Log.err("Layout building type names no loadable prefab", stats.display_name)
		return false

	var building: Building = scene.instantiate() as Building
	if building == null:
		Log.err("Layout building prefab root is not a Building", stats.display_name)
		return false

	# Set before the node enters the tree, so nothing ever sees it owned by the
	# default player - which would read as an enemy tower for one call.
	building.owner_player_id = area.player_id
	area.add_child(building)
	# start_built, so the maze is there to test with rather than going up over
	# the next half minute. invested_gold comes off the TYPE rather than being
	# counted, on the same grounds Building.adopt takes it from there: there is
	# one road to owning a given tower and so one figure it can have sunk into
	# it, which keeps the sell refund honest on a tower nobody paid for.
	building.place(area.player_id, area, cell, stats.total_gold_cost, true)
	return true
