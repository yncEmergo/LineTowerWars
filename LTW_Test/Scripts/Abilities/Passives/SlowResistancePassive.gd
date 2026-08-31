class_name SlowResistancePassive
extends CreepPassive

## Shrugs off some or all of any slow.
##
## Deliberately generic rather than named after one creep, because tier 4 has
## two of these and they are the same knob at two settings: Stoneskin Fortitude
## is "100% resistance to slow effects" and nothing else in the roster is
## outright immune.
##
## The MAGNITUDE and not the duration, which is a separate question with a
## separate hook - see CreepPassive. A creep can shrug off how far a slow goes
## without shortening how long it lasts, and the roster has creeps that do one,
## the other, and both.
##
## Distinct from a CAP, which is the other shape a slow resistance takes: this
## blunts every chill as it lands, and Goblin Engineering refuses to let the
## pile go past a line however many towers stack on it. See SlowCapPassive.

@export_group("Settings")
## Share of a chill magnitude that still lands. 0 is outright immunity.
@export_range(0.0, 1.0, 0.05) var chill_ratio: float = 0.0


func chill_taken_ratio() -> float:
	return chill_ratio


func effect_text() -> String:
	if chill_ratio <= 0.0:
		return "Cannot be slowed at all."
	return "Takes %d%% less of every slow applied to it." \
		% roundi((1.0 - chill_ratio) * 100.0)
