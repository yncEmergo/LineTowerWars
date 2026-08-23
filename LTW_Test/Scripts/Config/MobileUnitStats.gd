class_name MobileUnitStats
extends UnitStats

## Stats for a unit that moves: the builder and creeps.
##
## Kept separate from UnitStats so a tower's stats file never shows movement
## fields it can never use, which is where balancing mistakes come from.

@export_group("Movement")
## World units per second.
@export var move_speed: float = 6.0
## How fast the unit turns to face its movement direction, in radians per second.
@export var turn_speed: float = 12.0
## Distance at which the unit counts as having arrived.
@export var arrive_threshold: float = 0.03
