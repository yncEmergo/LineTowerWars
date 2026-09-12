class_name AiMazePlan
extends RefCounted

## WHERE an AI is going to put its towers, and in what order.
##
## A plan is a list of internal cells with a target tower type against each, and
## nothing else. It is not a maze standing in the world and it never orders
## anything: the brain walks it, one entry at a time, as gold allows, and the
## area refuses an entry exactly as it refuses a player's build order.
##
## **Two ways a plan is made, and the first is the one that matters long term.**
##
##   A SAVED LAYOUT. A TowerLayout - the very resource a player's blueprint is -
##   names a type and a cell per tower, so a maze worth playing against is one a
##   person built, saved from their own builder and dropped into the profile.
##   That is the whole feature: teaching the AI a new maze is a file, not code.
##
##   THE GENERATED ZIGZAG, for a profile that names no layout. Rows of towers
##   across the lane with a single gap, alternating sides, so creeps walk left,
##   right, left down the whole length of it. It is the simplest maze the game
##   has and the first thing the tutorial teaches, which is exactly why an easy
##   opponent should be building it: a player learning the shape should be
##   playing against the shape.
##
## **The build ORDER is front to back**, whichever way the plan was made. A
## tower defence is lost at the top of the lane, so the row nearest the spawn
## goes up first and the maze grows downwards - which is also how a person
## builds one, so an AI half way through a maze looks like a player half way
## through a maze rather than like a scatter of towers.

## One entry: where a tower goes, and which one it is meant to end up as.
##
## The TARGET rather than the tower to place, because most of a real maze is
## towers nothing can build directly - the builder places a 10g Basic or an
## Elemental Core, and everything above those is reached by upgrading. So an
## entry says where the maze is going and the brain works out the next rung. See
## AiHand.
class Entry extends RefCounted:
	var cell: Vector2i = Vector2i(-1, -1)
	var target_type_id: int = UnitTypeRegistry.NO_TYPE

	func _init(at: Vector2i, target: int) -> void:
		cell = at
		target_type_id = target


var _entries: Array[Entry] = []


func entries() -> Array[Entry]:
	return _entries


func size() -> int:
	return _entries.size()


func entry_at(index: int) -> Entry:
	if index < 0 || index >= _entries.size():
		return null
	return _entries[index]


## The plan one profile plays in one area.
##
## The area is needed because a plan is in INTERNAL CELLS and the grid's shape
## is the area's to answer - and because the generated zigzag has to know how
## wide the lane is and where the buildable rows start and stop.
static func for_profile(profile: AiProfile, area: PlayerArea) -> AiMazePlan:
	var plan: AiMazePlan = AiMazePlan.new()
	if profile == null || area == null:
		return plan

	var layout: TowerLayout = profile.maze_layout()
	if layout != null && layout.entry_count() > 0:
		plan._from_layout(layout)
	else:
		plan._generate_zigzag(profile, area)
	plan._sort_front_to_back()
	plan._aim_at_ultimate(profile)
	return plan


## Points a share of the plan at the profile's Ultimate rather than at a Basic
## tower.
##
## **Basic towers do not win matches** (game_rules.md), so a maze made only of
## them is a maze that loses late however long it is. What a cell TARGETS is
## what the brain upgrades it towards, and a target up an elemental branch
## resolves back down to the Elemental Core when it is built - so one field here
## is the whole of "this AI ends up with elemental towers".
##
## Spread EVENLY through the plan rather than taken off the front, because the
## plan is in build order: taking the first third would put every elemental
## tower at the top of the lane and leave the rest of it Basic for ever. Every
## Nth cell instead, so the maze improves all over as it grows.
##
## It is deliberately crude. It says how MUCH of the maze goes elemental and
## nothing at all about WHERE, which is the thing a real opponent decides - a
## Warden at the front, Sludge spread so its slow covers everything. That wants
## a plan that names a ROLE per cell, which is the next thing to build here.
func _aim_at_ultimate(profile: AiProfile) -> void:
	if profile.elemental_share <= 0.0 || _entries.is_empty():
		return

	var session: MatchSession = References.match_session
	if session == null:
		return
	var tower: BuildingStats = profile.ultimate_tower(session.techs())
	if tower == null:
		return

	# One in every `stride`, so a share of 0.25 aims every fourth cell.
	var stride: int = maxi(1, int(round(1.0 / clampf(profile.elemental_share, 0.05, 1.0))))
	# **NOT from the first cell, and this is the difference between an AI that
	# gets there and one that deadlocks.** See AiProfile.elemental_after_towers,
	# which is where the measurement is written down.
	var opening: int = maxi(0, profile.elemental_after_towers)
	var aimed: int = 0
	for index in range(_entries.size()):
		if index < opening || (index - opening) % stride != 0:
			continue
		_entries[index].target_type_id = tower.unit_type_id
		aimed += 1

	Log.info("AI maze aims at an Ultimate", {
		"tower": tower.display_name, "cells": aimed, "of": _entries.size(),
	})


## A saved maze, read straight off the file. Nothing is checked here: every cell
## is offered to the area on its own merits when its turn comes, and an entry
## that does not fit is skipped exactly as the layout cheat skips one.
func _from_layout(layout: TowerLayout) -> void:
	for index in range(layout.entry_count()):
		_entries.append(Entry.new(layout.cells[index], layout.unit_type_ids[index]))


## The left-right maze: a row of towers across the lane with one player cell
## left open, and the gap swapping sides every row.
##
## **The gap is what makes it a maze**, and it is why the row does not span the
## full width: creeps walk along the row to the hole, drop through it, and walk
## back along the next one. A tower shooting down a corridor a creep walks the
## whole length of is a tower that fires for the whole time the creep is in
## range, which is the entire lesson - see the tutorial.
##
## The target is the BASE tower, so a plan built this way is a maze of whatever
## the profile opens with and the brain upgrades it in place afterwards. A
## generated maze has no opinion about which tower goes where; a saved one does,
## which is the other half of why saved ones are better.
func _generate_zigzag(profile: AiProfile, area: PlayerArea) -> void:
	var config: GameConfig = References.game_config
	if config == null:
		return

	var step: int = maxi(1, config.internal_cells_per_cell)
	var width: int = area.internal_width()
	var first_row: int = area.build_zone_first_row()
	var last_row: int = area.build_zone_row_end()
	# One row of towers is one player cell deep, and the corridor under it is
	# however many the profile asked for.
	var stride: int = step * (1 + maxi(1, profile.zigzag_corridor_cells))
	# Towers across, leaving exactly one player cell open at one end.
	var across: int = maxi(1, int(width / step) - 1)
	var base: int = _base_type_id(profile)

	for row in range(maxi(1, profile.zigzag_rows)):
		var iz: int = first_row + row * stride
		if iz + step > last_row:
			break
		# Odd rows are pushed one cell right, which leaves their gap on the LEFT.
		var offset: int = step if row % 2 == 1 else 0
		for column in range(across):
			var ix: int = offset + column * step
			if ix + step > width:
				break
			_entries.append(Entry.new(Vector2i(ix, iz), base))


## The row nearest the creep spawn first, and left to right within a row.
##
## Sorted rather than relied on, because a SAVED layout arrives in whatever
## order the towers happened to be created in - which is the order somebody
## clicked them, and is not an order worth inheriting. Ties broken by column so
## two machines walk the same plan the same way, which costs nothing and is what
## makes a plan safe to reuse the day an AI plays a networked match.
func _sort_front_to_back() -> void:
	_entries.sort_custom(func(a: Entry, b: Entry) -> bool:
		if a.cell.y != b.cell.y:
			return a.cell.y < b.cell.y
		return a.cell.x < b.cell.x
	)


## The tower a generated maze is made of: whatever the profile opens with, or
## nothing at all - which the brain reads as "use the first thing the build menu
## offers".
func _base_type_id(profile: AiProfile) -> int:
	var stats: BuildingStats = profile.base_tower()
	return UnitTypeRegistry.NO_TYPE if stats == null else stats.unit_type_id
