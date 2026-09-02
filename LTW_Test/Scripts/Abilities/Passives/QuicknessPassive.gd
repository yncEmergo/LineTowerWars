class_name QuicknessPassive
extends CreepPassive

## Half the shots from the far end of a maze simply miss it.
##
## The second Huntress trait. unit_data.md 6.6: "50% chance to dodge attacks
## from towers with 900 or more attack range."
##
## THE RANGE CONDITION IS THE DESIGN. A dodge that worked on everything would
## just be a health multiplier; this one is a statement about WHICH towers,
## and it turns the long ranged half of a maze - the towers a player builds
## precisely so they cover everything - into the half that cannot reliably
## touch a Huntress. Short ranged towers land every shot, which is the answer
## the defender is being pointed at.
##
## Only the DIRECT hit is dodgeable. Splash, burns and on-hit effects land
## whatever happened to the shot that carried them - see AttackHit._dodged -
## because dodging an area is not something the source game lets anything do,
## and a creep shrugging off every effect on the map at fifty percent would not
## be a dodge.

@export_group("Settings")
## Chance the attack misses, 0 to 1.
@export_range(0.0, 1.0, 0.05) var chance: float = 0.5
## The reach a tower needs for this to apply at all, in player cells. The
## source states 900, which is 7.03 cells at the divisor every other reach in
## the game uses - see unit_data.md 3.
@export var from_range_cells: float = 7.031


func dodge_chance(attack_range: float) -> float:
	return chance if attack_range >= from_range_cells else 0.0


func effect_text() -> String:
	return "Has a %d%% chance to dodge any attack from a tower reaching %s cells or more." \
		% [roundi(chance * 100.0), StringUtil.trim_number(from_range_cells)]
