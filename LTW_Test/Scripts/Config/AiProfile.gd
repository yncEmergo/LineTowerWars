class_name AiProfile
extends Resource

## One AI DIFFICULTY: everything about how a computer opponent plays, as data.
##
## A resource per difficulty rather than a branch per difficulty in the brain,
## for the reason every other piece of content here is one: what an Easy AI does
## differently from a Hard one is a set of NUMBERS and a maze, and numbers are
## authored rather than compiled. Adding a difficulty is a .tres.
##
## **The design this follows is Age of Empires II's, and is worth stating
## because it is the part most easily got wrong.** Difficulty comes from BETTER
## DECISIONS, not from cheating and not mainly from reflexes: a harder AI mazes
## better, buys the towers that actually counter what is coming, and keeps its
## income ahead. Mechanical handicaps - how often it thinks, how often it simply
## fails to - are here too, and they belong at the EASY end only: an opponent
## that plays the same game slowly is a worse teacher than one that plays a
## simpler game properly.
##
## **Nothing here lets an AI cheat, and that is structural rather than a
## promise.** Every order it gives goes down the road a player's order takes -
## through `Commands`, into the same ability, refused by the same world - so it
## pays the same gold, waits the same build time and is refused the same
## placements. There is no branch anywhere that hands an AI anything.

@export_group("Identity")
## What the setup screen calls this difficulty.
@export var display_name: String = "Normal"
@export_multiline var description: String = ""
## The name an AI player is given in a match, with %d standing for which one it
## is - so a match against three of them does not have three rows all reading
## the same thing.
@export var player_name_pattern: String = "%s AI %d"
## Whether this difficulty is offered to a player setting a match up.
##
## False for a profile that exists to be a SPARRING PARTNER rather than an
## opponent - the tutorial's, which builds a short maze, never sends and never
## researches, because a player being taught how a creep walks should not be
## losing a match while they read. Nothing else about it is special: it is an
## ordinary profile and the brain cannot tell the difference.
@export var selectable: bool = true

@export_group("Pacing")
## Seconds between one pass of the rules and the next.
##
## THE REACTION TIME, and the honest one: the AI does not look at the world
## between passes, so anything that changes is noticed up to this long
## afterwards. Long is what makes an Easy AI feel slow to answer a wave; short
## does NOT by itself make a Hard one good, which is the trap - see the note at
## the top of the class.
@export var decision_seconds: float = 0.6
## Chance a whole pass is simply skipped, 0 to 1. What "sloppy" is: the AI is
## not thinking a worse thought, it is not thinking at all for a beat.
##
## Deliberately a skipped PASS rather than a worse decision. An AI that
## deliberately makes bad choices teaches a player bad habits; one that is
## merely slower off the mark plays the same game less well.
@export_range(0.0, 1.0, 0.05) var distraction_chance: float = 0.0
## How many towers it may ORDER in one pass. More than one is what lets a rich
## AI catch its maze up rather than dribbling one tower per beat for ever.
@export var builds_per_pass: int = 1


@export_group("Mazing")
## A saved maze this AI builds, as a res:// path to a TowerLayout - the same
## resource a player's blueprint is, so a maze worth playing against is one a
## human saved from their own builder and dropped in a folder.
##
## Empty falls back to the GENERATED zigzag below, which is the simplest maze
## the game has: rows of towers with one gap, alternating sides, so creeps walk
## left and right down the lane. That is what an easy AI should build, and it is
## what the tutorial teaches first - see AiMazePlan.
##
## A PATH rather than the resource, for the rule CLAUDE.md gives: a .tres held
## here would load the whole layout the moment anything read a difficulty name
## off this file.
@export_file("*.tres") var maze_layout_path: String = ""
## How many rows of the generated zigzag to lay down. Fewer is a shorter maze
## and so a shorter walk for a creep, which is most of what makes an easy AI
## easy to leak.
@export var zigzag_rows: int = 12
## Player cells of corridor between one row of towers and the next. One is the
## tightest a creep can walk; wider is a shorter path through the same lane.
@export var zigzag_corridor_cells: int = 1
## Which tower the AI opens with, as a res:// path to its BuildingStats. It has
## to be one the builder can actually place - a 10g Basic or the Elemental Core
## - because everything above those is reached by upgrading.
##
## Empty takes whatever the builder's build menu offers first, so a profile that
## says nothing still plays.
@export_file("*.tres") var base_tower_path: String = ""

@export_group("Economy")
## **THREE FLOORS, AND THE ORDER OF THEM IS THE WHOLE ECONOMY.**
##
## Each rule refuses to spend below its own floor, so gold filling up switches
## the rules on one at a time: an AI with a little sends, with more also builds,
## and with a lot also upgrades. The floors therefore go UP in the order the
## spending matters least.
##
## It took two measurements to arrive at. With no floors at all the cheapest
## rule wins every race against an empty purse and the AI does nothing but that
## one thing - the first version built a beautiful maze and never sent a creep
## in twenty minutes. With ONE shared floor the same thing happens one rule
## along: upgrades, being cheap and constant, ate every coin and the maze
## stopped growing at eight towers.
##
## Gold kept back rather than SENDING. Lowest of the three, because income
## compounds and a tower does not (game_rules.md, Economy) - an AI that will not
## send is an AI that loses slowly to one that does.
@export var send_floor_gold: int = 20
## Gold kept back rather than placing a NEW TOWER.
##
## Zero until the maze is worth defending, so an AI still opens by building flat
## out - see min_towers_before_sending.
@export var build_floor_gold: int = 50
## Gold kept back rather than UPGRADING. Highest of the three, which is what
## makes upgrading the thing a RICH AI does: a maze that is still growing needs
## the gold more than one tower does.
@export var upgrade_floor_gold: int = 150
## How much of the maze has to be standing before the floors start applying and
## before anything is sent.
##
## An AI that sent on its first beat would have bought creeps it cannot survive
## the answer to, and one that held gold back from its first coin would have no
## maze when the first wave arrived.
@export var min_towers_before_sending: int = 8
## Seconds between one send and the next.
##
## It does NOT reset on a beat it could not afford: once the beat is due the AI
## sends the moment it can pay, which is what makes an income tick land as a
## send rather than as a wasted beat.
@export var send_seconds: float = 12.0
## Highest creep tier it will ever buy from. 1 keeps an easy AI on the opening
## roster for the whole match.
@export var max_send_tier: int = 4
## Whether it spends on UPGRADES at all. An AI that never upgrades is a wall of
## 10g towers, which is what an easy one should be.
@export var upgrades_towers: bool = true

@export_group("Technology")
## Whether it spends its free research on an Ultimate at the start of the match.
##
## The standard human opening (unit_data.md 2.3), so an AI that does not do it
## is several tiers behind by the time anything reaches its maze - which is
## exactly what makes an easy one easy.
@export var takes_opening_ultimate: bool = true

## Reports everything authored wrong on this one profile, at boot, the way every
## other content file in the project is checked.
##
## The maze path is the one worth checking: the editor does not rewrite a path
## string when a .tres moves, so a renamed blueprint would silently turn a Hard
## AI into one that builds the generated zigzag - which looks like a tuning
## mistake rather than a missing file.
func validate() -> bool:
	var complete: bool = true
	if display_name.is_empty():
		Log.err("AI profile has no display name", resource_path)
		complete = false
	if !maze_layout_path.is_empty() && !ResourceLoader.exists(maze_layout_path):
		Log.err("AI profile names a maze layout that does not resolve", {
			"profile": display_name,
			"path": maze_layout_path,
		})
		complete = false
	if !base_tower_path.is_empty() && !ResourceLoader.exists(base_tower_path):
		Log.err("AI profile names a base tower that does not resolve", {
			"profile": display_name,
			"path": base_tower_path,
		})
		complete = false
	return complete


## The maze this profile plays, or null when it builds the generated one.
##
## Loaded on first ask rather than held, for the reason the path is a path: a
## setup screen listing four difficulties should not pull four mazes into memory
## to draw four names.
##
## No type hint on the load, and the existence check is ResourceLoader's. Both
## are the export trap CLAUDE.md records: a hint naming a SCRIPT class refuses
## the load outright from a pack, and FileAccess cannot see a remapped resource
## at all. The cast below is what checks the type, and always was.
func maze_layout() -> TowerLayout:
	if maze_layout_path.is_empty() || !ResourceLoader.exists(maze_layout_path):
		return null
	return ResourceLoader.load(maze_layout_path, "") as TowerLayout


## The tower this profile opens with, or null to take whatever the builder
## offers first.
func base_tower() -> BuildingStats:
	if base_tower_path.is_empty() || !ResourceLoader.exists(base_tower_path):
		return null
	return ResourceLoader.load(base_tower_path, "") as BuildingStats
