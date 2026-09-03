class_name AttackAbility
extends UnitAbility

## Sends a unit to fight: onto one named target, or onto a patch of ground.
##
## UNIT_OR_GROUND targeting, so arming it takes whichever the next left click
## lands on. It is also the ability behind a right click on a unit, which is
## the same resource serving the command card and the context sensitive right
## click, exactly as Move does for the ground.
##
## **It is an attack-MOVE, and that is the whole shape of it.** Aimed at a
## creep, a unit that can walk closes the distance and then kills it. Aimed at
## the ground, it walks there and fights whatever comes into reach on the way -
## and what it finds it COMMITS to, chasing that one until it is dead or gone
## before the walk resumes. A TOWER cannot walk, so for a tower the movement
## half simply does not happen and what is left is the plain "shoot that one"
## order it always had.
##
## What a given unit may be aimed at is the ATTACK's question and not this
## one's: a tower refuses anything that is not a creep it can reach, and an
## attacker creep refuses anything that is not a tower. So one resource sits on
## both cards and neither has to know about the other.
##
## Giving the order to a whole selection is safe: a unit that cannot target the
## creep at all refuses quietly and carries on, so one click across twenty
## towers switches only the ones that can actually help. A tower that CAN
## target it but cannot reach it keeps the order and keeps shooting what it
## can, switching the moment the creep walks in - see AttackComponent.
##
## A tower with no order still picks its own targets. This never turns the
## automatic behaviour off, it only overrides which creep is current.
##
## As an ORDER it chains: shift queues one behind another, and the task is over
## when the named creep dies, or when an attack-move has reached its point with
## nothing left in reach. A chain behind it waits the whole time, which is the
## point of the commitment above - the next order must not start while the unit
## is still in a fight it was sent into.


func execute(unit: Unit, target: AbilityTarget) -> void:
	if unit == null || target == null || unit.attack_component == null:
		return

	if target.unit != null:
		unit.attack_component.order_attack(target.unit)
		return

	# Aimed at the ground. Any standing order goes, because this is an order
	# to go somewhere and fight rather than to finish anything in particular.
	unit.attack_component.clear_order()
	if target.has_position && unit.has_method("move_to"):
		unit.move_to(target.position)


## The ORDER question rather than can_attack, and the difference is the whole
## of what lets an attacker be re-aimed. A creep that is walking may not FIRE,
## but it may certainly be TOLD to fight - the order is what stops the walk.
## See Unit.can_take_attack_order.
func can_execute(unit: Unit) -> bool:
	return unit != null && unit.attack_component != null && unit.can_take_attack_order()


func is_queueable() -> bool:
	return true


## Steers the fight for one tick: close on what was named, or walk on towards
## the point and stop for whatever gets in the way.
##
## Only for units that can WALK. A tower has nothing to steer - its standing
## order is resolved by its own attack component, which is where the range test
## belongs anyway.
func advance_task(unit: Unit, target: AbilityTarget, _delta: float) -> void:
	if unit == null || unit.attack_component == null || !unit.has_method("move_to"):
		return

	var attack: AttackComponent = unit.attack_component
	var ordered: Unit = attack.ordered_target()
	if ordered != null:
		_chase(unit, attack, ordered)
		return

	# An attack-MOVE stops for anything at all, which is the difference between
	# the two: a named target is the only thing worth stopping for above, and
	# down here everything is.
	#
	# **What it finds it COMMITS to**, by making it a standing order exactly as
	# if the player had clicked it. Without that the walk resumes the moment the
	# creep steps out of reach, so the unit lands one hit, watches it leave and
	# carries on - which is what an attack-move looked like. Chasing it is then
	# the branch above, and the task is not finished until it is dead or gone.
	var found: Unit = attack.current_target()
	if found != null:
		attack.order_attack(found)
		_chase(unit, attack, found)
		return

	if target.has_position && !unit.has_arrived_at(target.position):
		unit.move_to(target.position)


func is_task_complete(unit: Unit, target: AbilityTarget) -> bool:
	if unit == null || unit.attack_component == null:
		return true

	# A named creep still standing is a task still running, however far away it
	# is and whoever else is shooting it.
	if unit.attack_component.ordered_target() != null:
		return false
	# It named one and that one is gone, killed here or by somebody else. The
	# id rather than the reference, because a dead unit resolves to null and
	# the two cases have to read differently - see AbilityTarget.unit_id.
	if target.unit_id != MatchSession.NO_UNIT:
		return true

	# An attack-move. A tower was never going anywhere, so it is done at once.
	if !unit.has_method("move_to") || !target.has_position:
		return true
	return unit.has_arrived_at(target.position) && !unit.attack_component.has_target()


## Aiming this is the one moment a player is asking how far a tower reaches,
## so arming it puts every selected unit's range circle on the ground.
func shows_attack_range() -> bool:
	return true


## Walks onto a named target until it is in reach, then stands and fights.
## Nothing else is worth stopping for: the player named this one.
##
## **Once it has ARRIVED it only closes again while it could actually SWING.**
## A unit that has reached this target plants itself where it stands and stays
## there for the whole windup and the cooldown behind it, setting off after the
## creep again only when the next attack is ready. Trailing one through a
## cooldown it cannot use is following something for no reason it could act on,
## and it takes the hit-and-run out of the player's hands - which is where it
## belongs.
##
## Approaching for the FIRST time is not gated, and that is the distinction
## has_reached_order draws - CLOSE ONCE, THEN HOLD. The unit has to be in reach
## anyway, so arriving early costs nothing and an order that left it standing
## about for a whole attack period would read as an order that never registered.
## Once it has arrived it stops setting off again until it could swing, and
## re-issuing the order on that same creep does not hand the walk back.
func _chase(unit: Unit, attack: AttackComponent, ordered: Unit) -> void:
	if attack.is_in_reach(ordered):
		_hold(unit)
		return
	if attack.has_reached_order() && !attack.is_ready_to_attack():
		_hold(unit)
		return
	unit.move_to(ordered.global_position)


## Plants the unit where it stands so it can fight. Called rather than simply
## letting the walk continue, because "run at it until in range and then attack"
## means the running stops.
func _hold(unit: Unit) -> void:
	if unit.is_moving():
		unit.stop()
