class_name CancelOrderAbility
extends UnitAbility

## Backs out of whatever the command card is in the middle of.
##
## One button for two situations, because to a player they are the same thing -
## "I did not mean to press that":
##   - an ability is ARMED and waiting for a target. Cancelling drops the order
##   - the card is showing a SUBMENU. Cancelling returns to the unit's own card
##
## It is the same key in both, and the same key as every other cancel in the
## game, so backing out is one habit rather than three.
##
## **Local only.** Nothing here changes the world: an order that was never
## given needs no telling, and a card is drawn on one machine for one player.
##
## **It never executes**, exactly like BuildMenuAbility, and for the same
## reason: this is CARD NAVIGATION, and the card belongs to the unit panel. The
## panel recognises this ability and backs out itself.
##
## That is also what keeps it out of a dependency cycle. Reaching the command
## controller from here would mean naming its class, and the controller already
## names UnitAbility - the two would refuse to resolve, which is exactly what
## happened when this was written the other way round.
##
## Deliberately NOT the same resource as Cancel Build or Cancel Sell. Those
## stop something the world is already doing and hand gold back; this one only
## ever puts a card back the way it was.


## Never a command. It un-does something that never left this machine.
func is_local_only() -> bool:
	return true


## Navigation, so it never reaches the command controller. See the note above.
func execute(_unit: Unit, _target: AbilityTarget) -> void:
	pass


## Always pressable while it is on the card at all: the panel only puts it
## there when there IS something to back out of, so a greyed out cancel would
## be a state that cannot happen.
func can_execute(_unit: Unit) -> bool:
	return true
