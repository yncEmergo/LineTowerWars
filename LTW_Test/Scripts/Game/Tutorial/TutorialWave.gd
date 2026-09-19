class_name TutorialWave
extends Resource

## One wave a lesson sends into the player's lane: a creep, how many SENDS of
## it, and how long after the lesson opens.
##
## Counted in sends rather than in creeps, so a wave is what an opponent could
## really have bought: a Sheep send is its whole pack - two Sheep and a Timber
## Wolf - exactly as SendBuilding spawns it. Two entries with the same delay are
## one mixed wave.
##
## A sub-resource of the lesson that owns it, in the same .tres. Shared and
## stateless like the lesson: which waves have gone out is TutorialDirector's.

@export_group("Settings")
## Seconds after the lesson opens before this wave spawns. Long enough that the
## player has read what the lesson says is coming before it arrives.
@export var delay_seconds: float = 3.0
## The creep that is sent, as a res:// path to its CreepStats.
@export_file("*.tres") var creep_path: String = ""
## How many sends of it, each one a whole pack.
@export var sends: int = 1


## The creep this wave sends, or null for one authored wrong.
func creep() -> CreepStats:
	if creep_path.is_empty() || !ResourceLoader.exists(creep_path):
		return null
	return ResourceLoader.load(creep_path, "") as CreepStats


func validate(lesson: String) -> bool:
	if creep() == null:
		Log.err("A tutorial wave names no loadable creep", {
			"lesson": lesson, "path": creep_path,
		})
		return false
	if sends <= 0:
		Log.err("A tutorial wave sends nothing", lesson)
		return false
	return true
