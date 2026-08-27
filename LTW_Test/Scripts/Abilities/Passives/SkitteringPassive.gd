class_name SkitteringPassive
extends CreepPassive

## The creep never draws a tower's attention and is always shot at last.
##
## A PRIORITY and not an immunity: a tower with nothing else in range shoots it
## quite happily, and an attack order given by hand goes straight onto it. What
## it buys is that a skittering creep walking with a pack is the last thing the
## pack gets shot at, so it slips through a maze the rest of the pack is busy
## occupying.
##
## Carried as a passive rather than as a flag on the stats because it is a
## MODIFIER on an existing rule rather than a different kind of creep - unlike
## flying, which changes how the creep moves and what can reach it at all. The
## creep reads it once when it collects its passives, so the target search
## costs nothing for it. See Combat/TargetFinder.gd.


func is_skittering() -> bool:
	return true


func effect_text() -> String:
	return "Towers ignore it while anything else is in range, and shoot it last."
