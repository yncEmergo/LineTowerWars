class_name BuilderStats
extends MobileUnitStats

## Stats for the builder specifically.
##
## Only the builder places towers, so build range would be dead weight on
## every creep's stats file.

@export_group("Building")
## How close the builder must get to a tower's centre before it can start it.
## Per game_rules.md the builder only has to be in range - it does not stay
## to construct, and is free again immediately.
@export var build_range: float = 1.0


## The builder's card is the one card in the game that may never be empty.
##
## Everything the player does with a builder is on it - Move, Build, the grid,
## the plans - so a builder with no abilities is not a unit with fewer options,
## it is a game that cannot be played. Most units may legitimately have none:
## a Ghoul has no card at all, which is why this cannot be a rule on UnitStats.
##
## It is a check rather than a comment because of how the card can go missing:
## **a typed array in a .tres is all or nothing.** One entry that fails to load
## empties the whole `abilities` array with no error, and the editor then saves
## that emptiness back, pruning the ext_resource lines with it. That happened
## once, and the only symptom was a builder with no buttons and a clean log.
## See CLAUDE.md.
func validate(seen: Dictionary) -> bool:
	var complete: bool = super(seen)
	if abilities.is_empty():
		Log.err("The builder has no abilities, its command card would be empty",
			display_name)
		complete = false
	return complete
