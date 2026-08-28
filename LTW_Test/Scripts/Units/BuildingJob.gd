class_name BuildingJob
extends RefCounted

## What a tower is busy with right now, as ONE object the UI can ask
## everything: what to call it, what to picture it as, how far through it is
## and how long is left.
##
## One object rather than four getters on Building, which is already well over
## gdlint's public method ceiling. It is also the shape a caller wants - a
## panel drawing a progress row needs all four answers or none of them.
##
## Built fresh by Building.current_job() rather than kept, because progress
## moves every tick and a stored copy would be a second answer that can go
## stale. It is four fields, and one is only ever built for a tower somebody
## is looking at.
##
## CONSTRUCTION is deliberately not one of these. A tower going up already
## says so with its health climbing from 1 to full, and a second bar over the
## first would say the same thing twice. See game_rules.md.

enum Kind {
	SELLING,
	## Turning into the next tier up, or into an element off an Elemental Core.
	UPGRADING,
	## Coming back down to a bare Elemental Core, which is the way out of an
	## element. Same countdown as an upgrade, opposite direction.
	RETURNING,
}

var kind: Kind = Kind.SELLING
## How far through, 0 to 1.
var progress: float = 0.0
## Seconds still to run. What the panel counts down, because a player thinks
## in seconds and not in ticks.
var seconds_left: float = 0.0
## The picture of what this job is ABOUT: the tower itself while it is being
## sold, and what it is becoming while it morphs.
var icon: Texture2D = null


## What the panel calls this job. Here rather than on the panel because it is
## the one place that knows a RETURNING tower is not just another upgrade.
func label() -> String:
	match kind:
		Kind.SELLING:
			return "Selling"
		Kind.UPGRADING:
			return "Upgrading"
		Kind.RETURNING:
			return "Reverting"
		_:
			Log.err("BuildingJob has a kind it cannot name", kind)
			return ""
