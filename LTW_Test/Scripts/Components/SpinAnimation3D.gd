class_name SpinAnimation3D
extends Node

## Turns a node, either forever or only while its unit has something to kill.
##
## Placeholder motion for anything that reads as machinery: a grinder's blade,
## an orbit of shards, an Ultimate's halo. It deliberately knows nothing about
## when an attack lands, so it can never fall out of step with one - what it
## knows is whether there is a target at all.
##
## TWO MODES, and which one is in use is simply whether `_unit` is wired:
##
##   always      no unit. Turns at turns_per_second forever. Halos and orbits,
##               which are decoration and should not stop for anything
##   on demand   a unit. Spins up while it has a target and coasts back down to
##               idle_turns_per_second when it does not
##
## The on-demand mode never interrupts itself between attacks - it is looking at
## whether a target exists, not at whether one is being hit right now, so a
## blade chewing through a pack stays at full speed the whole way through.
##
## HOW FAST IT CHANGES between the two rates is `spin_change_rate`, and it is
## the one setting here with an argument on both sides. Easing was the original
## answer, on the reasoning that a blade snapping to a halt the instant its
## creep dies reads as a bug where one that coasts reads as a machine. The Basic
## tower roster now sets the rate high enough to be effectively instant, because
## what a player actually read from the ease was a machine that is slow to
## start - on the branch whose whole identity is the fastest attack in the game.
##
## Both remain available and neither is wrong; it is a per-user tuning value
## rather than a rule. A halo or an orbit, which has no unit and simply turns
## forever, never reaches this code at all.

@export_group("References")
## What to turn. Its own parent in every prefab so far, wired explicitly rather
## than walked to, like every other reference in the project.
@export var _spinner: Node3D
## The unit whose targeting drives the spin. Leave EMPTY for something that
## should simply turn forever.
@export var _unit: Unit

@export_group("Settings")
## Turns per second while running. A negative value spins the other way.
@export var turns_per_second: float = 1.5
## Turns per second with nothing to kill. Ignored without a unit. 0 coasts to a
## stop; a small value idles instead, which suits something that is always
## powered and merely not working.
@export var idle_turns_per_second: float = 0.0
## The LEAST time a spin runs for once it has started, in seconds, however
## briefly there was something to kill.
##
## The fastest towers in the game attack three times a second and often kill in
## one hit, so without a floor a saw meeting a weak creep TWITCHES: a few
## degrees of turn, a stop, a few more. What a player reads from that is a
## machine that is broken rather than one that is quick. Most of a second means
## the blade always completes a recognisable run, and a tower chewing through a
## pack simply never reaches the end of it.
##
## Ignored without a unit - something that turns forever has nothing to floor.
@export var minimum_run_seconds: float = 0.0
## How quickly it changes between the two, in turns per second per second.
## Lower takes longer to wind up and longer to coast down.
@export var spin_change_rate: float = 2.5
## Axis turned around, in the spinning node's own space.
@export var axis: Vector3 = Vector3.UP

## Current speed, eased towards whichever of the two above applies.
var _speed: float = 0.0
## Seconds of guaranteed running still owed. Refilled while there is a target
## and counted down once there is not.
var _run_left: float = 0.0


func _ready() -> void:
	if _spinner == null:
		Log.err("SpinAnimation3D has no node to turn assigned in its prefab", name)
		return

	_speed = turns_per_second if _unit == null else idle_turns_per_second

	# Animated on the RENDER frame, not the simulation tick. Godot's physics
	# interpolation assumes a transform only changes on a tick, so an
	# interpolated node moved in _process jitters - visibly on some machines and
	# not others. Opting out is the documented fix.
	_spinner.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	if _spinner == null:
		return

	if _working():
		_run_left = minimum_run_seconds
	else:
		_run_left = maxf(0.0, _run_left - delta)

	_speed = move_toward(_speed, _wanted_speed(), spin_change_rate * delta)
	if is_zero_approx(_speed):
		return
	_spinner.rotate(axis.normalized(), _speed * TAU * delta)


## What this should be turning at right now.
func _wanted_speed() -> float:
	if _unit == null:
		return turns_per_second
	if _working() || _run_left > 0.0:
		return turns_per_second
	return idle_turns_per_second


## Whether there is something to kill RIGHT NOW, before the minimum run time
## has had its say.
##
## A unit that cannot attack at all - one still going up, or mid-upgrade -
## counts as having nothing to kill, so a tower under construction winds down
## rather than spinning while it is still being assembled.
func _working() -> bool:
	if _unit == null:
		return false
	if !_unit.can_attack() || _unit.attack_component == null:
		return false
	return _unit.attack_component.has_target()
