class_name StopAbility
extends UnitAbility

## Cancels whatever the unit is currently doing, and everything it was going
## to do next.
##
## Two halves and they are different: stop() ends the task in progress - the
## walk, the tower the builder was on its way to start - and clearing the order
## queue throws away the chain waiting behind it. Stopping without the second
## would leave the unit walking off to the next waypoint a tick later, which
## reads as a button that did not work.
##
## NOT itself an order, so it is never queued: shift-Stop is still a Stop, and
## a chain of them would be a chain of nothing. It is also the one non-order on
## the card that wipes the chain, which is exactly what a player means by it.


func execute(unit: Unit, _target: AbilityTarget) -> void:
	if unit == null:
		return
	if unit.order_queue != null:
		unit.order_queue.clear()
	if unit.has_method("stop"):
		# BOTH, not one or the other. Clearing a chain already halts the unit,
		# so this used to be an else - but a halt is now the only way to call a
		# Phoenix dive off, and a Phoenix that had been given an order at some
		# point has a queue and would have skipped it. Calling stop() on a unit
		# that has already stopped says the same thing twice and costs nothing.
		unit.stop()


func can_execute(unit: Unit) -> bool:
	return unit != null && unit.has_method("stop")
