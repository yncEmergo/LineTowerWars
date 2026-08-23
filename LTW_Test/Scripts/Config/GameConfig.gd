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

@export_group("Creeps")
## Creeps appear within this many cells of the very top of the spawn zone, at a
## random x across the full width. See game_rules.md.
@export var creep_spawn_margin_cells: float = 1.5
## Radius of EVERY creep aura, in player cells. One value for the whole game
## rather than a per creep one, so an aura is the same size whichever creep
## brings it and a player only ever has to learn the shape once. Auras also do
## not stack: the best one in range applies. See game_rules.md.
@export var creep_aura_radius_cells: float = 3.0

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
## Share of a building's invested gold returned when it is sold.
## Invested gold includes upgrades once those exist.
@export_range(0.0, 1.0, 0.05) var sell_refund_ratio: float = 0.7

@export_group("Rules")
## Ceiling on a player's living sent creeps, as the sum of their population
## costs. Displayed today; nothing enforces it yet.
@export var population_cap: int = 100
@export var life_pool: int = 200
@export var min_starting_lives: int = 25


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


## World origin of a player area. Areas sit side by side along x, with
## player 1 leftmost. player_id is 1-based.
func area_origin(player_id: int) -> Vector3:
	return Vector3(float(player_id - 1) * area_stride_x(), 0.0, 0.0)
