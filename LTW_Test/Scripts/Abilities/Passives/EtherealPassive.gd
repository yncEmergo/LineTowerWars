class_name EtherealPassive
extends CreepPassive

## The creep walks THROUGH the maze rather than around it, and mends fast.
##
## The Spirit Walker's, and the only thing in the game that makes a maze worth
## nothing at all. unit_data.md 6.6: "can walk through towers; increased health
## regeneration."
##
## What it costs the sender is speed. An ethereal creep reads none of the
## occupancy grid and goes straight down the lane - so a maze that would have
## walked an ordinary creep back and forth for half a minute does not exist for
## this one, and the tower that would have shot it forty times gets six.
##
## It is NOT flying, and the difference is the whole of why this is worth
## sending. A flyer is out of reach of every tower that cannot hit air; an
## ethereal creep is on the floor and anything at all may shoot it. It skips
## the MAZE, never the towers.
##
## Both halves are answered elsewhere: the walk is Creep.ignores_maze(), which
## is read off is_ethereal() below, and the regeneration is the ordinary
## per-second hook every other regenerating creep uses.

@export_group("Settings")
## Health restored per second.
@export var health_per_second: float = 60.0


func is_ethereal() -> bool:
	return true


func health_regen(_creep: Creep) -> float:
	return maxf(0.0, health_per_second)


func effect_text() -> String:
	return ("Walks straight through towers, ignoring the maze entirely, and"
		+ " regenerates %s health per second. Any tower can still shoot it.") 		% StringUtil.trim_number(health_per_second)
