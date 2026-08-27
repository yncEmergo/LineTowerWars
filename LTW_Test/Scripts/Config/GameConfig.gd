class_name GameConfig
extends Resource

## Grid, area, match and rule values.
## Mirrors game_rules.md - keep the two in sync when rules change.
## Stored as Resources/Config/game_config.tres, reached via References.game_config.

@export_group("Match")
## Number of player areas to build. The prototype targets a 1v1.
@export var player_count: int = 1
## Which player the local client controls.
@export var local_player_id: int = 1

@export_group("Grid")
## World size of one player-facing cell.
## Deliberately 1.0 so world coordinates and the cell coordinates used in
## game_rules.md are identical. A tower at rule position 4.5|15.0 sits at
## world x=4.5, z=15.0 inside its area, which keeps debugging trivial.
@export var cell_size: float = 1.0
## Each player cell is subdivided into this many internal cells per axis, so
## half-cell tower positions land on whole internal numbers.
@export var internal_cells_per_cell: int = 2

@export_group("Player Area")
@export var area_width_cells: int = 8
@export var spawn_depth_cells: int = 3
@export var build_depth_cells: int = 30
@export var end_depth_cells: int = 1
## Strip above the walkable area that the send building stands on. Outside the
## walkable space and outside the grid, so nothing ever paths through it.
@export var send_zone_depth_cells: float = 3.0
## Empty space between neighbouring player areas along x.
@export var area_gap_cells: float = 4.0

@export_group("Map")
## The map is a grid of area slots, filled left to right and then row by row.
## Six by two is the Warcraft III Line Tower Wars layout the prototype copies,
## and the two together are the most players a match can hold - keep
## MenuConfig.max_players at or under their product.
@export var area_columns: int = 6
@export var area_rows: int = 2
## Empty space between one row of areas and the next along z, measured from the
## end zone of the row above to the send strip of the row below.
@export var area_row_gap_cells: float = 6.0

@export_group("Creeps")
## Creeps appear within this many cells of the very top of the spawn zone, at a
## random x across the full width. See game_rules.md.
@export var creep_spawn_margin_cells: float = 1.5
## Radius of EVERY creep aura, in player cells. One value for the whole game
## rather than a per creep one, so an aura is the same size whichever creep
## brings it and a player only ever has to learn the shape once. Auras also do
## not stack: the best one in range applies. See game_rules.md.
##
## The source game gives every creep aura 700 AoE, which is 5.47 cells at the
## same divisor every other reach in the game uses (unit_data.md 3).
@export var creep_aura_radius_cells: float = 5.47
## How far a MULTISHOT reaches for its further targets, in player cells.
##
## One value for the whole game, exactly as the creep aura radius is and for
## the same reason: a multishot picks several single targets standing near the
## one that was aimed at, and a player should learn that distance once rather
## than per tower. game_rules.md is the rule.
##
## The source game states these AoEs at 400-500 for the towers that name one at
## all; 3 cells is 384 at the divisor every other reach uses. A passive that
## really does name its own - the Beastmaster - overrides it through
## TowerPassive.extra_target_range.
@export var multishot_reach_cells: float = 3.0

@export_group("Buildings")
## Send buildings a player's strip has room for, filled left to right.
##
## Four because the source game gives each creep TIER its own send building,
## and twelve creeps is exactly one 4 x 3 command card. Only the first of them
## exists so far; the number is here now so the one that does stands where it
## will still stand once the other three are built. See unit_data.md 6.1.
@export var send_building_slots: int = 4
## Seconds a building takes to go up, and the same figure an UPGRADE takes.
##
## One value for every tower at every tier, which is what unit_data.md 1.4
## states, so it lives here rather than being restated on a hundred stats
## files that would all have to be edited together to change it.
@export var build_seconds: float = 2.0
## Seconds a sale takes. The building stays standing and keeps blocking until
## it completes, so a cancelled sale changes nothing.
##
## Here for the same reason build_seconds is: unit_data.md 1.8 gives every
## building one sell time and varies only the refund, which is
## sell_refund_ratio below.
@export var sell_seconds: float = 3.0
## Seconds an elemental tower takes to come back down to a bare Elemental
## Core. Its own figure rather than the sell time, because the two are
## different jobs: a sale takes the cell away, a return hands it back as a
## Core, and one wants to be quicker than the other the day either is tuned.
##
## The tower stays standing and keeps blocking for the whole countdown,
## exactly as an upgrade does, so a return can never be used to open a path.
## See ReturnToCoreAbility.
@export var return_to_core_seconds: float = 3.0
## Seconds a destroyed tower leaves its cells unbuildable. The cells are
## walkable again immediately - it is only the rebuild that waits, which is
## what stops an attacker's work being undone the instant it finishes.
## unit_data.md 1.5.
@export var rubble_seconds: float = 7.0

@export_group("Combat")
## How near the primary target a creep has to be to be picked up by multishot,
## in player cells. One value for the whole game rather than a per tower one,
## so "next to the target" means the same everywhere. See game_rules.md.
## NOT BUILT: multishot itself does not exist yet.
@export var multishot_range_cells: float = 1.5

@export_group("Economy")
## Gold every player starts with, see game_rules.md.
@export var starting_gold: int = 20
## Income every player starts with, paid out on every tick.
@export var starting_income: int = 20
## Seconds between income payouts.
@export var income_interval: float = 8.0
## Share of a building's invested gold returned when it is sold, which for an
## upgraded tower is the whole chain rather than the last rung it climbed.
##
## 60% is the source game's figure for a BASIC tower, unit_data.md 1.8. It also
## gives Technology towers 50%, so this stops being one number for the whole
## game the day elemental towers exist - at which point it moves onto
## BuildingStats. One value until then, because a second one today would only
## ever read the same.
@export_range(0.0, 1.0, 0.05) var sell_refund_ratio: float = 0.6

@export_group("Technology")
## Technologies a player gets for nothing at the start of a match. Every one
## after these is paid for, and each costs a step more than the last
## (unit_data.md 2.2). Four is what the whole opening is built around: it is
## exactly one Ultimate tower's requirement.
@export var free_technologies: int = 4
## What the first PAID technology costs. The second costs twice this, the third
## three times, and so on - so the number is the step rather than the price.
@export var technology_cost_step: int = 50000
## How long a technology can be taken back after it is bought. Committing gold
## to the field - starting a build or an upgrade - closes the window early,
## because a tower bought under a technology must not be left standing by one
## that is given back.
@export var technology_undo_seconds: float = 5.0

@export_group("Rules")
## Ceiling on a player's living sent creeps, as the sum of their population
## costs. Displayed today; nothing enforces it yet.
@export var population_cap: int = 100
@export var life_pool: int = 200
@export var min_starting_lives: int = 25

@export_group("Cheats")
## Whether developer cheats respond at all. Off by default and checked by the
## AUTHORITY as well as by the machine the key was pressed on, so a server with
## this off refuses a cheat order however the client asking was built.
@export var cheats_enabled: bool = false
## Gold one press of the gold cheat hands the player. See CheatController.
@export var cheat_gold_amount: int = 9999999


func internal_cell_size() -> float:
	return cell_size / float(internal_cells_per_cell)


func area_depth_cells() -> int:
	return spawn_depth_cells + build_depth_cells + end_depth_cells


func area_width() -> float:
	return float(area_width_cells) * cell_size


func area_depth() -> float:
	return float(area_depth_cells()) * cell_size


func area_stride_x() -> float:
	return area_width() + area_gap_cells * cell_size


## Distance from one row's area origin to the next row's. Counts the send strip
## too, since that hangs above the origin rather than below it, so the gap
## really is empty ground.
func area_stride_z() -> float:
	return send_zone_depth() + area_depth() + area_row_gap_cells * cell_size


func send_zone_depth() -> float:
	return send_zone_depth_cells * cell_size


## The send strip sits above the area, so its z values are negative. The area's
## own origin stays at the top of the walkable space.
func send_zone_start_z() -> float:
	return -send_zone_depth()


func build_zone_start_z() -> float:
	return float(spawn_depth_cells) * cell_size


func build_zone_end_z() -> float:
	return build_zone_start_z() + float(build_depth_cells) * cell_size


## Lives scale down with player count, see game_rules.md.
## max(min_starting_lives, life_pool / player_count rounded to nearest 5)
func starting_lives(count: int) -> int:
	if count <= 0:
		Log.err("starting_lives called with invalid player count", count)
		return min_starting_lives
	var raw: float = float(life_pool) / float(count)
	var rounded: int = int(round(raw / 5.0)) * 5
	return maxi(min_starting_lives, rounded)


## World origin of a player area. Slots fill left to right and then row by
## row, so player 1 is the top left one. player_id is 1-based.
func area_origin(player_id: int) -> Vector3:
	if area_columns <= 0:
		Log.err("GameConfig has no area columns, every area would stack on the origin")
		return Vector3.ZERO

	var index: int = maxi(0, player_id - 1)
	var column: int = index % area_columns
	# Truncating IS the row number, which is what the warning is about.
	@warning_ignore("integer_division")
	var row: int = index / area_columns
	return Vector3(float(column) * area_stride_x(), 0.0, float(row) * area_stride_z())


## How many players the map has room for. A match with more than this has
## nowhere to put the extra areas and stacks them on top of the first row.
func map_slot_count() -> int:
	return maxi(0, area_columns) * maxi(0, area_rows)


## The whole map as an xz rectangle, from the top of the first row's send strip
## to the bottom of the last row's end zone.
##
## Always the FULL grid of slots, whatever the player count: the map is the
## same size in a 1v1 as in a full house and the unused lanes are simply black.
## Both the camera's panning bounds and the minimap's frame come from here, so
## the two can never disagree about how big the world is.
func map_bounds() -> Rect2:
	var top: float = send_zone_start_z()
	var bottom: float = float(maxi(1, area_rows) - 1) * area_stride_z() + area_depth()
	var width: float = float(maxi(1, area_columns) - 1) * area_stride_x() + area_width()
	return Rect2(0.0, top, width, bottom - top)
