class_name DamageBlockPassive
extends CreepPassive

## Takes a flat amount off every hit, whatever it was.
##
## Last in the damage pipeline, after the matrix and after armour points, so it
## is worth most against many small hits and least against one big one - which
## is the whole point of a flat block. A hit is never blocked away entirely:
## anything that lands still does at least 1, see game_rules.md.

@export_group("Settings")
## Points removed from each incoming hit.
@export var block_amount: int = 10


func damage_block() -> int:
	return maxi(0, block_amount)


func effect_text() -> String:
	return "Blocks %d damage from every hit it takes." % maxi(0, block_amount)
