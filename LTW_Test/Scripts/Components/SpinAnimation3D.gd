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
## The on-demand mode SPINS DOWN rather than stopping, which is the whole point
## of it: a blade that snaps to a halt the instant its creep dies reads as a
## bug, where one that coasts reads as a machine. It also never interrupts
## itself between attacks - it is looking at whether a target exists, not at
## whether one is being hit right now, so a blade chewing through a pack stays
## at full speed the whole way through.

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
## How quickly it changes between the two, in turns per second per second.
## Lower takes longer to wind up and longer to coast down.
@export var spin_change_rate: float = 2.5
## Axis turned around, in the spinning node's own space.
@export var axis: Vector3 = Vector3.UP

## Current speed, eased towards whichever of the two above applies.
var _speed: float = 0.0


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

	_speed = move_toward(_speed, _wanted_speed(), spin_change_rate * delta)
	if is_zero_approx(_speed):
		return
	_spinner.rotate(axis.normalized(), _speed * TAU * delta)


## What this should be turning at right now.
##
## A unit that cannot attack at all - one still going up, or mid-upgrade -
## counts as having nothing to kill, so a tower under construction winds down
## rather than spinning while it is still being assembled.
func _wanted_speed() -> float:
	if _unit == null:
		return turns_per_second
	if !_unit.can_attack() || _unit.attack_component == null:
		return idle_turns_per_second
	return turns_per_second if _unit.attack_component.has_target() \
		else idle_turns_per_second
