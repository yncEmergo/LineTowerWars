class_name CreepPackEntry
extends Resource

## One OTHER creep type that comes along when a creep is sent.
##
## A send normally spawns some number of the creep that was bought, and that
## number is CreepStats.pack_size. This is for the send that also brings
## something else: the Sheep arrives as two Sheep and one Timber Wolf, and the
## Timber Wolf is not buyable on its own at all.
##
## Deliberately does NOT name the creep being sent, only its companions, so no
## stats file ever has to reference itself. pack_size stays the count of the
## creep whose file this sits in, and this array is everything on top of it.
##
## An array of these rather than one companion field, for the reason anything
## stacking is an array in this project: a pack that grows a second escort is
## another entry rather than a second pair of fields.

@export_group("Pack")
## What comes along. Its own stats decide everything about it once it is on the
## field, exactly as they would if it had been sent directly.
@export var creep_stats: CreepStats
## How many of them one send spawns.
@export var count: int = 1
