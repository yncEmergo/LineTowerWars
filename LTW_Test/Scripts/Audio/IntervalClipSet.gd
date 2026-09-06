class_name IntervalClipSet
extends AudioClipSet

## A clip set that wants to keep coming back: wind, distant battle, a creep
## muttering while it walks. Carries how long to wait between plays, and
## nothing else.
##
## THE WAITING IS NOT DONE HERE. A resource is SHARED - one .tres is the same
## object for every unit referencing it - so a timer living on this would be one
## timer for every ambience in the world at once. Same rule as UnitAbility: the
## data is on the resource, the state is on whatever is using it. See CLAUDE.md.
##
## Comes from another project as IntervalAudioStream, where the looping was a
## static recursive coroutine that re-entered itself forever. Renamed and left
## as data on the way in.

@export_group("Settings")
## Seconds to wait after a clip ends before the next one, picked uniformly
## between the two. x is the shortest wait, y the longest.
##
## A RANGE rather than a number, because a fixed gap is heard as a rhythm the
## moment two of them overlap, and a maze has many. Spelled "interval" - the
## original had it as the German "intervall".
@export var interval_seconds: Vector2 = Vector2(5.0, 10.0)


## A wait for one play, from this set's range.
##
## Takes the RNG rather than reaching for a global one, so an ambience driven
## from a deterministic context can stay deterministic. Nothing needs that today
## - audio is presentation and never simulation - but the alternative costs a
## caller nothing and closes the question.
func pick_wait(rng: RandomNumberGenerator = null) -> float:
	var shortest: float = minf(interval_seconds.x, interval_seconds.y)
	var longest: float = maxf(interval_seconds.x, interval_seconds.y)
	if rng != null:
		return rng.randf_range(shortest, longest)
	return randf_range(shortest, longest)
