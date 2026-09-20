class_name TutorialMoment
extends Resource

## Something worth stopping the match for the FIRST time it happens, whenever
## that is: the first of the player's creeps about to leak, the first flyer
## they send, the first attacker.
##
## Not a lesson, and that is the point of it being its own resource. A lesson
## is taught in order; these are taught when the player gets there on their own
## - a player who never sends a Shade is never told about flyers, and one who
## sends a tier 2 flyer an hour in is told then. So they live on the script
## beside the lessons rather than in the list, and TutorialDirector watches for
## each of them the whole way through.
##
## When one fires the WORLD is held, the camera is pinned on the creep it is
## about and everything else is dimmed, and the panel says what is happening
## until the player presses OK. Each fires once per tutorial.

## What has to happen for a moment to fire.
##
## **EITHER SIDE of the lane can set one off, whichever gets there first.** A
## moment is about a player meeting the thing for the first time, and meeting
## it is meeting it: the first flyer a player sees may well be one coming AT
## them rather than one they sent, and a player who has just watched a flyer
## sail over their maze is owed the explanation more, not less.
##
## Which side it was is not lost - see incoming_body, because two of the three
## read differently depending on who sent the creep.
enum Trigger {
	## One of their creeps has walked past leak_row, where nothing in a maze
	## that stops at the top of the lane can reach it any more.
	CREEP_ABOUT_TO_LEAK,
	## There is a flyer in play.
	FLYER_SENT,
	## There is an attacker in play.
	ATTACKER_SENT,
}

@export_group("Settings")
@export var trigger: Trigger = Trigger.CREEP_ABOUT_TO_LEAK
@export var title: String = ""
@export_multiline var body: String = ""
## Seconds between the creep being first seen and the moment firing, so a flyer
## has left the spawn and is visibly FLYING before the world stops on it.
@export var delay_seconds: float = 0.0
## Said instead of `body` when the creep that set this off belongs to somebody
## ELSE - their creeps in your lane rather than yours in theirs.
##
## Empty means the same words either way, which is right for anything stated
## about the creep itself: what a flyer IS does not depend on who sent it. It
## is the ones phrased around what the player can DO that need this - a line
## telling them to select their attackers is wrong in front of an attacker
## chewing on their own maze, and a leak that pays them lives is the exact
## opposite of one that costs them.
@export_multiline var incoming_body: String = ""
## For CREEP_ABOUT_TO_LEAK: the row a creep has to reach, 1-based and counted
## the way the numbers down the side of the lane count, so an author can read it
## straight off the board.
@export var leak_row: int = 20


## What to say about this moment, given who sent the creep that set it off.
## Falls back to `body` for a moment that reads the same either way.
func body_for(incoming: bool) -> String:
	if incoming && !incoming_body.is_empty():
		return incoming_body
	return body


## Whether one creep is what this moment is waiting for. `area` is the lane it
## is walking in.
func matches(creep: Creep, area: PlayerArea) -> bool:
	var stats: CreepStats = creep.stats as CreepStats
	if stats == null:
		return false
	match trigger:
		Trigger.FLYER_SENT:
			return stats.is_flying
		Trigger.ATTACKER_SENT:
			return stats.is_attacker
		_:
			return area.world_to_internal_cell(creep.global_position).y >= _leak_cell_row(area)


## The internal row leak_row starts on in one lane.
func _leak_cell_row(area: PlayerArea) -> int:
	var config: GameConfig = References.game_config
	var per_cell: int = 2 if config == null else config.internal_cells_per_cell
	return area.build_zone_first_row() + (maxi(1, leak_row) - 1) * per_cell


func validate() -> bool:
	if title.is_empty() || body.is_empty():
		Log.err("A tutorial moment has nothing to say", resource_path)
		return false
	return true
