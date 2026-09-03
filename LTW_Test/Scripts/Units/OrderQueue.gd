class_name OrderQueue
extends RefCounted

## The chain of tasks a unit is working through, head first.
##
## One of these per COMMANDABLE unit, created lazily the first time an order
## reaches it. A creep walking a maze pays nothing for it - not a tick, not an
## allocation - which matters because nearly every unit in a match is one.
##
## **The head is what the unit is doing right now.** It is started once, then
## supervised every tick until its ability says the task is finished, and then
## dropped so the next one starts. Nothing here knows what any of those tasks
## MEAN: whether a walk has arrived, whether a tower has been started and
## whether a creep has died are all the ability's own answers - see
## UnitAbility.is_task_complete.
##
## Holding the current task IN the queue rather than beside it is what makes
## the whole thing one list to draw, one list to replicate and one list to
## clear. The builder walking to its first tower and the four towers waiting
## behind it are the same kind of thing, and the player is looking at all five.
##
## AUTHORITY ONLY, and enforced at the door the way StatusEffects is: every
## method that changes the chain returns immediately on a client. A client runs
## no simulation, so a queue it advanced itself would be running a second world
## beside the one it is being sent (multiplayer.md 3.4). What a client has
## instead is `_replicated`, which is the drawing half of the same list handed
## down by the server.

## The chain, head first, on the AUTHORITY.
var _orders: Array[QueuedOrder] = []
## The same chain as the SERVER last reported it, and meaningful on a CLIENT
## only. Only the tasks that DRAW something are in it - see
## QueuedOrder.draws_marker - because it exists to put markers on the ground
## and a task nobody can see is one nothing has to be told about.
var _replicated: Array[QueuedOrder] = []

var _unit: Unit


func _init(unit: Unit) -> void:
	_unit = unit


## The queue for a unit, built on first use and remembered on the unit itself.
##
## A static rather than a method on Unit, so a unit that is never given an
## order carries one null field and no queue at all, and so Unit gains no
## public method for something only three abilities ever ask about.
static func of(unit: Unit) -> OrderQueue:
	if unit == null:
		return null
	if unit.order_queue == null:
		unit.order_queue = OrderQueue.new(unit)
	return unit.order_queue


## The chain as THIS machine is entitled to read it, which is the real one on
## the authority and whatever the server last sent on a client.
##
## The one place that question is answered, so nothing drawing a marker has to
## know whether it is running the world or watching one - the same shape
## ActiveAbilityState.cooldown() has.
func orders() -> Array[QueuedOrder]:
	if MatchSession.is_authority():
		return _orders
	return _replicated


func is_empty() -> bool:
	return orders().is_empty()


## Adds a task to the end of the chain, which is what SHIFT does.
##
## Started at once when it lands on an empty queue, so a shift-clicked order
## given to an idle unit is as immediate as a plain one. Anything behind it
## waits for its turn.
func enqueue(ability: UnitAbility, target: AbilityTarget) -> void:
	if !MatchSession.is_authority() || ability == null:
		return

	_orders.append(QueuedOrder.of(ability, target))
	if _orders.size() == 1:
		_start(_orders[0])
	_changed()


## Throws the whole chain away and starts this task instead, which is what an
## order given WITHOUT shift does.
##
## The rule the player sees is "a new order wipes the plan", and it is one
## rule rather than two: clearing cancels whatever the head was in the middle
## of, and the new task then starts from a unit that is doing nothing.
func replace(ability: UnitAbility, target: AbilityTarget) -> void:
	if !MatchSession.is_authority() || ability == null:
		return

	clear()
	enqueue(ability, target)


## Drops every task, and stops the unit doing the one it had started.
##
## Both halves matter and they are different: emptying the list stops anything
## FURTHER happening, and cancelling the head stops what is happening NOW. A
## builder told to move while walking to a tower it queued has to actually
## forget that tower, or it would place it the moment the walk carried it past.
func clear() -> void:
	if !MatchSession.is_authority():
		return

	var had_any: bool = !_orders.is_empty()
	_orders.clear()
	_cancel_current()
	if had_any:
		_changed()


## Runs the chain for one tick: supervise the head, drop it when its ability
## says it is finished, and start whatever was behind it.
##
## Called from the unit's own `_physics_process`, at the TOP of it, so a task
## that starts this tick is walked or swung this tick rather than next.
## Deliberately NOT from a `_physics_process` on Unit: Godot calls only the
## most derived one, and Creep replaces MobileUnit's outright, so a base class
## implementation would silently never run for the units that need it most.
func advance(delta: float) -> void:
	if !MatchSession.is_authority() || _unit == null || !is_instance_valid(_unit):
		return

	var dropped: bool = false
	# A loop rather than one task per tick, because a task can finish the
	# instant it starts - a build refused on the spot, a walk to where the unit
	# already stands - and a chain of those should not take a tick each.
	while !_orders.is_empty():
		var head: QueuedOrder = _orders[0]
		# A task with no ability cannot be run, supervised or finished, so it
		# is dropped rather than left to stall everything behind it. Nothing
		# builds one today; this is a tick loop, and a crash in one takes the
		# whole match with it.
		if head.ability == null:
			_orders.remove_at(0)
			dropped = true
			continue
		if head.started:
			head.ability.advance_task(_unit, head.to_target(), delta)
		else:
			_start(head)

		if !_is_complete(head):
			break

		_orders.remove_at(0)
		dropped = true

	if dropped:
		_changed()


## The tasks that put something on the ground, in order. What the overlay draws
## and what the snapshot carries, which are deliberately the same list.
func drawn_orders() -> Array[QueuedOrder]:
	var drawn: Array[QueuedOrder] = []
	for order in orders():
		if order.draws_marker():
			drawn.append(order)
	return drawn


## Handed down by the server, which is the only way the chain changes on a
## client. Replaces the mirror outright rather than merging into it: a snapshot
## is the whole answer, so a task that is no longer in it is a task that is
## done.
##
## The whole world arrives twenty times a second (3.2), and nearly every one of
## those says exactly what the last one did. So it is COMPARED first: rebuilding
## a builder's four ghosts every tick would be four model scenes instantiated
## and freed per tick for a picture that has not changed.
func set_replicated(incoming: Array[QueuedOrder]) -> void:
	if _matches_replicated(incoming):
		return
	_replicated = incoming
	_changed()


## Whether a snapshot's chain is the one already being drawn. Only the two
## things a marker is built from are compared - which ability and where -
## because those are the only two a change of either would show.
func _matches_replicated(incoming: Array[QueuedOrder]) -> bool:
	if incoming.size() != _replicated.size():
		return false
	for index: int in incoming.size():
		var mine: QueuedOrder = _replicated[index]
		var theirs: QueuedOrder = incoming[index]
		if mine.ability != theirs.ability:
			return false
		if !mine.target_position.is_equal_approx(theirs.target_position):
			return false
	return true


# --- internals ------------------------------------------------------------

## Runs a task for the first time. Marked started either way, including when
## the ability refuses it: a task that cannot run is finished rather than
## stuck, and the chain moves on to the next one.
##
## Asked with can_queue() rather than can_execute(), because this is the
## moment a QUEUED order arrives at. The two differ in exactly one place and
## on purpose - a tower queued behind three others is paid for when the builder
## reaches it, not when the player pressed the button. See BuildTowerAbility.
func _start(order: QueuedOrder) -> void:
	order.started = true
	if order.ability == null:
		return
	if !order.ability.can_queue(_unit):
		Log.warn("Queued order cannot run and is dropped", {
			"unit": _unit.name, "ability": order.ability.display_name,
		})
		return
	order.ability.execute(_unit, order.to_target())


func _is_complete(order: QueuedOrder) -> bool:
	if order.ability == null:
		return true
	return order.ability.is_task_complete(_unit, order.to_target())


## Undoes whatever the head had the unit doing. Both of these are duck typed
## and both are no-ops on a unit that has neither: a tower cannot walk, and
## nothing without an attack has an order to forget.
##
## A unit that WALKS also drops a swing it has already committed to, which the
## standing order above outlives. The two are different lifetimes and the
## player sees both: forgetting the order stops it fighting that creep AGAIN,
## and cancelling the swing stops the blow already on its way - so a builder
## sent off to build sets off at once rather than finishing an arc nobody
## asked for. A TOWER keeps its swing on purpose, see
## AttackComponent.cancel_attack.
func _cancel_current() -> void:
	if _unit == null || !is_instance_valid(_unit):
		return
	if _unit.has_method("stop"):
		_unit.stop()
	if _unit.attack_component != null:
		_unit.attack_component.clear_order()
		if _unit is MobileUnit:
			_unit.attack_component.cancel_attack()


## Tells the overlay to redraw this unit's markers. Null everywhere the
## markers are not - a headless server, a bare test scene - which is why it is
## asked for rather than held.
func _changed() -> void:
	var overlay: OrderOverlay = References.order_overlay
	if overlay != null:
		overlay.refresh_unit(_unit)
