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
