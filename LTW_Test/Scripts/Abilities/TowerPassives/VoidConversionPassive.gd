class_name VoidConversionPassive
extends VoidSpreadPassive

## The Ultimate Harbinger's second ability: every so often, one Greater
## Harbinger standing near it becomes another Ultimate. Free.
##
## The same spread the base pair does, on the two axes that matter to a player
## turned the other way round. It is NOT tied to mana, because the Harbinger's
## mana is already spent on its rift - and it REPEATS, because a tower this
## expensive earning one free copy of itself and then stopping would be a
## footnote rather than a reason to build it.
##
## IT HAS A CARD SQUARE OF ITS OWN, which is why it is a separate ability
## rather than a second half of the rift. A wait that repeats is a thing a
## player plans around, and the only place the game can show a wait is a slot -
## the sweep over it IS this ability's readout, and that is exactly what
## charge_progress is for.
##
## A tick that finds nothing eligible is NOT wasted, unlike the base pair's one
## chance: the clock simply starts again. Nothing is lost by waiting because
## the tower is going to be standing there anyway.

## Keys the clock is kept under, on the tower rather than here: this resource
## is every Ultimate Harbinger on the field at once.
const LEFT_KEY: String = "void_convert_left"

@export_group("Void Conversion")
## Seconds between attempts.
@export var period_seconds: float = 60.0


func on_tick(tower: Building, delta: float) -> void:
	if period_seconds <= 0.0:
		return

	var left: float = _left(tower) - delta
	if left > 0.0:
		tower.ability_state[LEFT_KEY] = left
		return

	# Restarted before the attempt, so a tick that converts nothing costs the
	# same as one that does and the clock never drifts.
	tower.ability_state[LEFT_KEY] = period_seconds
	spread(tower)


## How ready the next attempt is, 0 to 1, which is what draws the sweep over
## this ability's square. Read every frame by CommandSlot.
func charge_progress(unit: Unit) -> float:
	var tower: Building = unit as Building
	if tower == null || period_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - _left(tower) / period_seconds, 0.0, 1.0)


## Seconds left on this tower's clock. A tower that has never ticked reads as a
## full wait rather than as ready, so a freshly built Ultimate does not convert
## its neighbour on the frame it finishes.
func _left(tower: Building) -> float:
	return float(tower.ability_state.get(LEFT_KEY, period_seconds))


func effect_text() -> String:
	return ("Every %s seconds, one tower it can take within %s cells becomes"
		+ " a %s, for free. Costs no mana and repeats for as long as the tower"
		+ " stands; a turn that finds nothing simply starts the wait again."
		+ " The fill over this square is how long is left.") % [
		StringUtil.trim_number(period_seconds),
		StringUtil.trim_number(reach_cells),
		_becomes_name(),
	]
