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
## end zone of the row above to the creep spawn of the row below.
@export var area_row_gap_cells: float = 6.0

@export_group("Creeps")
## Creeps appear within this many cells of the very top of the spawn zone, at a
## random x across the full width. See game_rules.md.
@export var creep_spawn_margin_cells: float = 1.5
## Ceiling on the crowding push an ordinary creep takes from the ones around
## it, as a share of its own speed. Below 1 so a push can never cancel forward
## movement: an uncapped sum over a dense clump shoved creeps a cell a frame
## into the walls.
##
## ZERO, and that is a rule rather than a value nobody got round to setting:
## the roster is sent in packs and one lane holds a hundred of them, so
## ordinary creeps walk through their own kind. Shoving a hundred bodies apart
## pairwise was the second most expensive loop in the whole tick and invisible
## under that many creeps anyway. Anything above zero switches it back on for
## them, at that price. See game_rules.md.
@export var creep_separation_limit: float = 0.0
## The same ceiling for an ATTACKER creep, which is the one kind that still
## crowds. There are few of them, they are commanded one at a time, and a stack
## of them standing inside each other on one tower is something their owner
## would be looking straight at.
@export var attacker_separation_limit: float = 0.6
## How much room an ATTACKER creep keeps around itself, as a share of its own
## selection circle. Two attackers may never stand closer than the sum of the
## two, and this is the HARD half of crowding: the push above steers a creep
## that is walking, where this holds wherever the tick left it.
##
## A share of the SELECTION CIRCLE rather than a length of its own, so the room
## a creep claims is the ring the player is looking at - a bigger attacker
## takes more of it without a second number per creep. At 1.0 two rings would
## just touch, so anything below overlaps them by design.
##
## Zero switches the hard half off entirely and leaves only the soft push,
## which is what every creep in the game had before.
@export var attacker_personal_space_ratio: float = 0.5
## How near its ordered point an ATTACKER has to be before the crowd already
## standing on it counts as arriving, in player cells.
##
## Without it a pack ordered onto one point never settles: the first creep
## there holds the point and the rest slide round the outside looking for a way
## in that the rule above will never give them. With it they stop where they
## are blocked, which is how a pack piles up in any other RTS.
@export var attacker_crowd_arrive_cells: float = 1.5
## Radius of EVERY creep aura, in player cells. One value for the whole game
## rather than a per creep one, so an aura is the same size whichever creep
## brings it and a player only ever has to learn the shape once. Auras also do
## not stack: the best one in range applies. See game_rules.md.
##
## The source game gives every creep aura 700 AoE, which snaps to 5.5 at the
## quarter every reach in the game is stated in (unit_data.md 3).
@export var creep_aura_radius_cells: float = 5.5
## Side of one cell in the grid an area keeps its creeps in, so a search reads
## the ones NEAR a point instead of all of them. See CreepIndex.
##
## PURE PERFORMANCE - no answer changes with it, only how long it takes to
## arrive, because every caller still tests the exact distance. It sits here
## with idle_target_scan_ticks rather than in the script for the same reason
## that one does: it is a number worth turning while measuring.
##
## Smaller cells return fewer creeps that were never in reach, and cost more
## dictionary lookups per query. Around half the commonest reach is the sensible
## band; the lane is only a few cells wide, so the depth axis is where this
## actually buys anything.
@export var creep_index_cell_size: float = 2.0
## How often a creep re-reads the auras standing around it, in seconds.
##
## A GAMEPLAY value as well as a pacing one: it is how long a creep keeps a
## buff it has walked out of, and how long it waits for one it has walked into.
## Neither answer can change fast enough for a fraction of a second to show,
## which is what makes it safe to lengthen - but it is not free, so it is a
## number to choose rather than to maximise.
##
## The sweep is spread across the interval by unit id (see Creep._aura_phase),
## so lengthening it lowers the total work AND widens the spread. Both matter:
## the spread is what stops a wave that spawned together from sweeping together
## and turning a flat cost into a spike, which is the mistake
## AttackComponent._next_scan_wait already documents for tower targeting.
@export var creep_aura_refresh_seconds: float = 0.5
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
## Seconds a technology disc takes to morph back down to an inactive one.
##
## Its own figure and deliberately the longest of the three morphs, because the
## source game made it one: 11.7a raised it from three seconds to five to
## discourage swapping discs on the fly to answer an incoming send. A disc is
## meant to be a decision about the shape of a maze rather than a switch, and
## the wait is what makes that true. unit_data.md 1.8.
@export var disc_morph_down_seconds: float = 5.0
## How often a technology disc re-reads what is standing around it, in seconds.
##
## The same quarter-second beat every other aura in the game runs on, and for
## the same reason: nothing a disc grants can change fast enough for a quarter
## second to show, and running one every tick would have each disc walk the
## whole maze twenty times a second. See TowerPassive.AURA_REFRESH_SECONDS.
@export var disc_aura_refresh_seconds: float = 0.25
## How long each of those grants is applied for.
##
## Comfortably longer than the beat above, so a tower standing inside a disc's
## radius never flickers between refreshes. What it costs is that a tower whose
## disc has just been sold keeps the boon for the rest of the window, which is
## a fraction of a second and is the cheap half of the trade.
@export var disc_aura_hold_seconds: float = 1.0
## Seconds a destroyed tower leaves its cells unbuildable. The cells are
## walkable again immediately - it is only the rebuild that waits, which is
## what stops an attacker's work being undone the instant it finishes.
## unit_data.md 1.5.
@export var rubble_seconds: float = 7.0
## Share of its maximum health a standing building regenerates per second.
##
## One figure for every building at every tier, on the same terms as
## build_seconds: unit_data.md 1.4 states it once for the whole tower roster,
## so restating it on every stats file would only be a hundred places to edit
## it. Towers are the only buildings anything can damage, so in practice this
## IS the tower rule - it simply costs nothing to let it read as the rule for
## a building.
##
## A SHARE rather than points per second, so one figure keeps meaning the same
## thing across a roster whose health spans two orders of magnitude.
@export_range(0.0, 1.0, 0.001) var building_health_regen_ratio: float = 0.015

@export_group("Combat")
## How many ticks a unit waits before searching for a target AGAIN after a
## search that found nothing. 1 is every tick, which is what this used to be.
##
## It exists because of what most of a full maze is doing at any moment: a
## tower with nothing in range never fires, so its cooldown never starts, and
## the "only search when the cooldown is ready" throttle never applies to it.
## It searched the whole lane every tick for the whole match and found nothing
## every time, which was the largest single cost in a loaded tick.
##
## The price is reaction time: a creep walking into range is noticed up to this
## many ticks late. Read it against physics_ticks_per_second in project.godot
## for what that is in seconds. A tower that HAS a target, or is on cooldown,
## is not affected at all - this only ever delays a search that was going to
## come back empty.
@export var idle_target_scan_ticks: int = 4
## How near the primary target a creep has to be to be picked up by multishot,
## in player cells. One value for the whole game rather than a per tower one,
## so "next to the target" means the same everywhere. See game_rules.md.
## NOT BUILT: multishot itself does not exist yet.
@export var multishot_range_cells: float = 1.5

@export_group("Auras")
## A TOWER AURA DOES NOT LAND AT FULL STRENGTH. It builds on a creep in equal
## steps and drains off again once the creep is out of it, so walking through
## the edge of one is worth a fraction of standing in the middle of it.
##
## The numbers are here rather than on each aura because they are the SHAPE of
## the mechanic rather than the strength of any one tower: what an aura does is
## its own business, how fast it grips is the game's.
##
## Shared by every stacking aura in the roster, which is what makes them read
## as one mechanic a player learns once instead of three that happen to be
## similar.
##
## How many steps a creep can hold. Each is worth an equal share of the aura's
## full strength, so five stacks is 20% per stack.
@export var aura_max_stacks: int = 5
## Seconds between one tower adding a stack and it being able to add another.
##
## PER TOWER, deliberately: a creep standing in two of the same aura gains two
## stacks in that time and reaches full strength twice as fast. Massing the
## same support tower is meant to be worth something.
@export var aura_stack_seconds: float = 0.5
## How long a creep must go untouched by an aura before it starts losing
## stacks. What makes the grip LINGER: crossing a gap between two auras, or
## briefly outrunning one, does not send the creep back to nothing.
##
## A creep sitting at full stacks still counts as touched, so an aura that can
## give it nothing more is still holding on to it.
@export var aura_idle_seconds: float = 1.0
## Seconds per stack lost once that idle window has passed.
@export var aura_decay_seconds: float = 0.5

@export_group("Economy")
## Gold every player starts with, see game_rules.md.
##
## THE DEFAULT A LOBBY OFFERS rather than the number every match uses: the host
## chooses this one in the room and MatchSettings carries what they agreed. The
## same is true of the four values below it - see MatchSettings.defaults.
@export var starting_gold: int = 40
## Income every player starts with, paid out on every tick.
@export var starting_income: int = 20
## Seconds between income payouts.
@export var income_interval: float = 10.0
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

@export_group("Sudden Death")
## Seconds into the match at which Sudden Death begins, or 0 to switch the
## whole rule off.
##
## THE ONE PLACE A TIER MEANS ANYTHING. Every other creep in the game unlocks
## on its own start delay and stays sendable for the rest of the match; at this
## moment the whole of tier 4 unlocks at once and tiers 1 to 3 stop being
## sendable at all. It is the only time a creep is ever taken AWAY from a
## player. See unit_data.md 1.7 and 6.5.
@export var sudden_death_seconds: float = 1500.0
## The lowest income anybody enters Sudden Death with. A player under it is
## raised to it the moment it starts, so a match that is being lost slowly can
## still afford what the last tier costs. 0 switches the raise off.
@export var sudden_death_income_floor: int = 1000000
## Gold a player is handed when the ring closing gives them a NEW ATTACKER, as
## a multiple of that attacker's current income. 0 switches the rule off.
##
## CATCH-UP GOLD. When a player is eliminated, whoever they were sending into
## suddenly faces the next player round the ring instead - who has been playing
## a different match and may be far richer. This is the one payment that
## acknowledges it: a lump equal to what the new attacker earns per income
## tick, once, at the moment the hand-over happens.
##
## Paid to the DEFENDER, never to the new attacker, and never in a 1v1 - the
## match is already over there, and a player cannot be handed a share of their
## own income. See game_rules.md, Life steal and recycling.
@export var catch_up_gold_share: float = 1.0
## Income above which tier 4 creeps stop paying properly. 0 removes the cap.
@export var income_cap: int = 4000000
## Share of a tier 4 creep's income a player over the cap actually receives.
##
## Only tier 4, deliberately, and only above the cap: everything below is paid
## in full, and a tier 1 send pays in full at any income at all. What the rule
## is for is stopping Sudden Death from compounding, since by then the creeps
## are meant to be ending the match rather than paying for the next one.
@export_range(0.0, 1.0, 0.05) var income_share_above_cap: float = 0.25
@export var life_pool: int = 200
@export var min_starting_lives: int = 25

@export_group("Cheats")
## Whether developer cheats respond at all. Checked by the AUTHORITY as well as
## by the machine the key was pressed on, so a server with this off refuses a
## cheat order however the client asking was built.
##
## This is the master switch and it is NOT the whole answer - see
## cheats_allowed(), which is what everything actually asks.
@export var cheats_enabled: bool = false
## Whether the master switch above still counts once the match is NETWORKED.
##
## OFF, so cheats are a single player testing tool and nothing else. A cheat is
## an ordinary player order that the server grants, which means one player in a
## real match could hand themselves the gold to end it - and the flag that
## would have stopped that is on the SERVER's copy of this file, which is not
## the machine anybody is looking at while they play.
##
## It is a flag rather than a flat refusal because the networked build has to
## be testable: filling a lane in a headless two client run needs the same
## shortcuts a single player run does, and CLAUDE.md's scripted loop is exactly
## where that happens. Turn it on deliberately, on the server, for a test, and
## turn it off again.
@export var cheats_in_multiplayer: bool = false
## Gold one press of the gold cheat hands the player. See CheatController.
@export var cheat_gold_amount: int = 9999999
## Where the layout cheat saves a maze to, and reads one back from. See
## TowerLayout and CheatController.
##
## user:// rather than res:// because it is WRITTEN at runtime, which an
## exported build cannot do to its own data. Point it at a res:// path to load
## a layout shipped with the game instead - the save half will then refuse,
## which is the honest answer.
##
## One file rather than a slot per number, because this is a testing shortcut:
## keeping several means copying the file, and the folder is named in the log
## line every save prints.
@export var cheat_layout_path: String = "user://Layouts/tower_layout.tres"


## Whether a cheat may fire at all: the master switch, and then the networked
## question on top of it.
##
## `is_networked` is passed in rather than worked out here, for the reason
## PresentationConfig.minimap_color_for takes is_local rather than asking: a
## config resource is data about the game and has no business asking the
## network what it is doing. Every caller hands it `Net.is_online()`.
##
## One place rather than the same two-part condition written out in the input
## handler and again in the server's own check, which are the two machines that
## have to agree about it.
func cheats_allowed(is_networked: bool) -> bool:
	return cheats_enabled && (!is_networked || cheats_in_multiplayer)


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


## Distance from one row's area origin to the next row's.
func area_stride_z() -> float:
	return area_depth() + area_row_gap_cells * cell_size


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


## The whole map as an xz rectangle, from the top of the first row's creep
## spawn to the bottom of the last row's end zone.
##
## Always the FULL grid of slots, whatever the player count: the map is the
## same size in a 1v1 as in a full house and the unused lanes are simply black.
## Both the camera's panning bounds and the minimap's frame come from here, so
## the two can never disagree about how big the world is.
func map_bounds() -> Rect2:
	var top: float = 0.0
	var bottom: float = float(maxi(1, area_rows) - 1) * area_stride_z() + area_depth()
	var width: float = float(maxi(1, area_columns) - 1) * area_stride_x() + area_width()
	return Rect2(0.0, top, width, bottom - top)
