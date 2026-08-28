class_name WalkAnimation3D
extends Node

## Walks a creature, by watching how far its unit actually moved.
##
## PRESENTATION ONLY. It decides nothing, asks nothing and is never asked - it
## reads a position that something else already wrote.
##
## DRIVEN BY DISTANCE TRAVELLED rather than by a speed value or an is-moving
## flag, and that is the whole design. A gait measured in metres per stride
## cannot slide: a creep chilled to half speed takes half as many steps in the
## same second, a stunned one stands still, and a Rot Golem covering the same
## ground as a Sheep takes fewer, longer strides because its stride is longer.
## Nothing here has to be told about any of that.
##
## It also means the same component works UNCHANGED ON A CLIENT, which is the
## reason it is worth the extra arithmetic. A client runs no simulation - its
## creeps are moved by the server's snapshot - so anything reading a speed off
## the stats would animate a walk the machine cannot see, while a position
## delta is a position delta wherever it came from. See multiplayer.md 3.4.
##
## ON THE PHYSICS TICK, unlike SpinAnimation3D and BobAnimation3D next door,
## and this is the one thing to get right when copying it. Those two animate on
## the RENDER frame and switch physics interpolation off for the node they
## move, which is correct for a tower: a tower never goes anywhere, so a part
## of it opting out of interpolation costs nothing. A creep DOES go somewhere.
## A leg that opted out would be drawn at the tick position while the body it
## hangs off glided between ticks, so the creature would come apart twice per
## tick, every tick. Animating on the tick instead lets Godot interpolate the
## limb along with everything else, which is exactly what it is for.
##
## HOVERING is the same component with the clock swapped: a flyer has no legs
## to measure a stride with, so a positive `hover_cycles_per_second` drives the
## phase off time instead. What that swings is a Shade's tatters rather than
## its feet, and a wraith drifting on the spot still moves.

@export_group("References")
## The unit whose travel drives the gait. Its own parent in every prefab so
## far, wired explicitly rather than walked to, like every other reference in
## the project.
@export var _unit: Unit
## What bobs and leans. The model's `Gait` node, holding everything above the
## hips. Optional: a creature with no body worth bobbing simply does not.
@export var _body: Node3D
## Hip pivots, swung in turn. Legs on anything that walks, and the trailing
## tatters on anything that hovers.
@export var _legs: Array[Node3D] = []
## Limbs that swing AGAINST the legs. Optional, and left empty on anything
## holding its arms out - a Priest's staff arm reads as broken if it pumps.
@export var _arms: Array[Node3D] = []

@export_group("Gait")
## Where in the cycle each leg sits, 0 to 1, in the same order as `_legs`.
## Two entries at 0.0 and 0.5 is a walk; four alternating is a trot. Any leg
## past the end of this list falls back to 0.
@export var leg_phases: PackedFloat32Array = PackedFloat32Array()
## World units travelled per FULL cycle - both legs forward and back again.
## This is the number that decides whether a creature skates: too long and its
## feet drag, too short and it scurries.
@export var stride_length: float = 0.4
## How far a leg swings from rest at the ends of its stride, in degrees.
@export var swing_degrees: float = 24.0
## How far an arm swings. Smaller than the legs, because it is a counterweight
## rather than a step.
@export var arm_swing_degrees: float = 15.0
## How far the body rises and falls, in world units. TWICE per cycle, once per
## footfall, which is what a walk actually does.
@export var bob_height: float = 0.02
## How far the body tips forward while it is moving, in degrees. It settles
## back upright when the creature stops, so leaning is also how a creep says it
## is under way.
@export var lean_degrees: float = 4.0
## How far the body rolls side to side across the cycle, in degrees.
@export var roll_degrees: float = 2.0

@export_group("Hovering")
## Full cycles per second for something with no legs to measure. 0 means this
## creature walks, and the phase comes from how far it has travelled instead.
@export var hover_cycles_per_second: float = 0.0

@export_group("Settling")
## How quickly the swing fades in and out when the creature starts and stops,
## in shares per second. A gait that snapped to a halt would read as a freeze
## frame rather than as a creature standing still.
@export var settle_rate: float = 5.0
## Speed, in world units per second, above which the gait is considered fully
## under way. Also what the lean and the bob are scaled by below it.
@export var full_speed: float = 1.5

## How far through the cycle the gait is, in cycles. Wrapped, so it never grows
## large enough to lose precision over a long match.
var _phase: float = 0.0
## 0 standing, 1 walking. Eased, which is what `settle_rate` buys.
var _travelling: float = 0.0
## Where the unit was last tick, so this tick's travel can be measured.
var _last_position: Vector3 = Vector3.ZERO
## The height `_body` was authored at, which the bob is measured from.
var _rest_y: float = 0.0
## The stoop, flare or tilt each limb was authored with. The swing is added to
## it rather than replacing it, or every arm in the roster would snap upright
## on the first frame.
var _leg_rest: PackedFloat32Array = PackedFloat32Array()
var _arm_rest: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	if _unit == null:
		Log.err("WalkAnimation3D has no unit to follow assigned in its prefab", name)
		return

	_last_position = _unit.global_position
	if _body != null:
		_rest_y = _body.position.y
	for limb: Node3D in _legs:
		_leg_rest.append(0.0 if limb == null else limb.rotation.x)
	for limb: Node3D in _arms:
		_arm_rest.append(0.0 if limb == null else limb.rotation.x)


func _physics_process(delta: float) -> void:
	if _unit == null || delta <= 0.0:
		return

	var speed: float = _advance(delta)
	# Eased rather than set, so a creep that walks into a stun eases out of its
	# stride instead of freezing halfway through one.
	var wanted: float = clampf(speed / maxf(0.01, full_speed), 0.0, 1.0)
	_travelling = move_toward(_travelling, wanted, settle_rate * delta)

	_apply_legs()
	_apply_arms()
	_apply_body()


## Moves the gait on and answers how fast the unit is going, in world units per
## second. Height is ignored on purpose: a flyer climbing into its lane is not
## taking steps, and every distance in this game is measured flat anyway.
func _advance(delta: float) -> float:
	if hover_cycles_per_second > 0.0:
		_phase = fmod(_phase + hover_cycles_per_second * delta, 1.0)
		# A hover is always "under way" - there is no standing still in the air
		# and its tatters should never settle to a stop.
		return full_speed

	var here: Vector3 = _unit.global_position
	var moved: float = Vector2(here.x - _last_position.x,
		here.z - _last_position.z).length()
	_last_position = here
	# A creep recycled into another maze crosses the whole map in one tick, and
	# without this its legs would spin through a hundred strides on that frame.
	if moved > stride_length:
		return 0.0

	_phase = fmod(_phase + moved / maxf(0.001, stride_length), 1.0)
	return moved / delta


func _apply_legs() -> void:
	var swing: float = deg_to_rad(swing_degrees) * _travelling
	for index: int in _legs.size():
		var limb: Node3D = _legs[index]
		if limb == null:
			continue
		limb.rotation.x = _leg_rest[index] + sin(_leg_phase(index) * TAU) * swing


func _apply_arms() -> void:
	# Half a cycle out of step with the legs: an arm swings against the leg on
	# its own side, which is the difference between a walk and a shamble.
	var swing: float = deg_to_rad(arm_swing_degrees) * _travelling
	for index: int in _arms.size():
		var limb: Node3D = _arms[index]
		if limb == null:
			continue
		var phase: float = _phase + (0.0 if index % 2 == 0 else 0.5)
		limb.rotation.x = _arm_rest[index] - sin(phase * TAU) * swing


func _apply_body() -> void:
	if _body == null:
		return
	# Twice per cycle, because a body rises once per footfall and there are two
	# footfalls in a stride.
	_body.position.y = _rest_y + sin(_phase * 2.0 * TAU) * bob_height * _travelling
	# Negative, because Godot's forward is -Z: a positive rotation about X tips
	# the top of the body BACKWARDS.
	_body.rotation.x = -deg_to_rad(lean_degrees) * _travelling
	_body.rotation.z = sin(_phase * TAU) * deg_to_rad(roll_degrees) * _travelling


func _leg_phase(index: int) -> float:
	if index >= leg_phases.size():
		return _phase
	return _phase + leg_phases[index]
