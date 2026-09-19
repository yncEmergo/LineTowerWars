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

## What has to happen for a moment to fire. Every one of them is about the
## player's OWN creeps in somebody else's lane - what they sent, not what was
## sent at them.
enum Trigger {
	## One of their creeps has walked past leak_row, where nothing in a maze
	## that stops at the top of the lane can reach it any more.
	CREEP_ABOUT_TO_LEAK,
	## They have a flyer in play.
	FLYER_SENT,
	## They have an attacker in play.
	ATTACKER_SENT,
}

@export_group("Settings")
@export var trigger: Trigger = Trigger.CREEP_ABOUT_TO_LEAK
@export var title: String = ""
@export_multiline var body: String = ""
## Seconds between the creep being first seen and the moment firing, so a flyer
## has left the spawn and is visibly FLYING before the world stops on it.
@export var delay_seconds: float = 0.0
## For CREEP_ABOUT_TO_LEAK: the row a creep has to reach, 1-based and counted
## the way the numbers down the side of the lane count, so an author can read it
## straight off the board.
@export var leak_row: int = 20


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
