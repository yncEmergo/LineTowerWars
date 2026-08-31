class_name UnfathomablePowerPassive
extends CreepPassive

## Cannot be killed, and cannot be helped either.
##
## The Demon trait, and the last-resort stalemate breaker of the whole game.
## unit_data.md 6.5 and 6.6: "invulnerable, ignores friendly auras, food cost
## 5", sent one at a time, stock of four, one replenished every 32 seconds.
##
## IT ALWAYS LEAKS. There is no defence, no counterplay and nothing to build:
## a Demon walks the maze, takes its two lives and walks the next one. What
## stops it deciding a match on its own is entirely economic - 4,200,000 gold
## per send, no income at all, five population, and a reserve that refills once
## every half minute.
##
## Two of the three are answered elsewhere. The invulnerability is its ARMOUR
## TYPE, which is how everything in the game that cannot be hurt says so and
## needs no flag; the food is its population on its stats file.
##
## What is here is the third, which nothing else in the roster does: it hears
## no aura at all, its own included. So a Demon cannot be hurried along by a
## packmate, cannot be armoured further, and cannot be healed by one - which
## for an invulnerable creep matters only as a statement about what it is. See
## Creep._refresh_aura, which asks this once and then skips the search.

func ignores_auras() -> bool:
	return true


func effect_text() -> String:
	return ("Cannot be damaged by anything, and is deaf to every friendly aura"
		+ " - its own included.")
