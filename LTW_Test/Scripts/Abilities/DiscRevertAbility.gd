class_name DiscRevertAbility
extends ReturnToCoreAbility

## Morphs a technology disc back down to an inactive one, in place.
##
## The disc half of Return to Core, and it IS that ability rather than a copy
## of it: the same in-place countdown, the same preview of what is arriving,
## the same cancel, and the same refund of everything sunk above what stays in
## the cell. What it names instead of the Elemental Core is the inactive disc,
## by path for exactly the reasons ReturnToCoreAbility names the Core by one.
##
## Two things differ, and only one of them is here.
##
## THE CLOCK is five seconds rather than three, which the source game raised
## deliberately in 11.7a to discourage swapping discs on the fly to counter an
## incoming send. A disc should be a decision about the shape of a maze, and a
## five second wait is what makes it one. The real one is Disc._upgrade_time
## and this class only quotes it, so the card and the countdown cannot drift.
##
## THE 2,500 GOLD of the inactive disc stays sunk in the cell, exactly as the
## Core's 200 does, and that needs nothing said here at all: _refund_return
## reads the target's own total_gold_cost and the answer follows.
##
## Carried by every disc that has an element, and never by the inactive one,
## which has nothing to go back to.


## The disc's own wait, so the card quotes what the building will actually
## serve. unit_data.md 1.8.
func _return_seconds(config: GameConfig) -> float:
	return config.disc_morph_down_seconds
