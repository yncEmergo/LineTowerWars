class_name SlowCapPassive
extends CreepPassive

## However many towers chill it, it never falls below a floor.
##
## Goblin Engineering. unit_data.md 6.6: "cannot be chilled or slowed by more
## than 25%."
##
## A CEILING ON THE PILE, which is a different thing to a resistance and is
## worth being clear about. A resistance blunts each chill as it lands, so four
## towers still add up to something large; this refuses the TOTAL past a line,
## so the fourth tower chilling a Goblin Shredder is doing nothing at all.
##
## Which is what makes it read against a chill maze specifically. A lane built
## on stacking slows is the thing this creep was sent to walk through, and it
## walks through it at three quarters speed whatever that lane costs.

@export_group("Settings")
## The most it may ever be slowed, as a share of its speed.
@export_range(0.0, 1.0, 0.05) var slow_cap: float = 0.25


func max_slow_share() -> float:
	return slow_cap


func effect_text() -> String:
	return "Is never slowed by more than %d%% in total." % roundi(slow_cap * 100.0)
