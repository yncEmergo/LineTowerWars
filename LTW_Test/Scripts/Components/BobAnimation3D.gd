class_name BobAnimation3D
extends Node

## Floats a node up and down around wherever it started, forever.
##
## Placeholder motion for anything that is meant to read as hovering rather
## than standing: the Sentry line's cores sit on nothing, and a core that hangs
## perfectly still reads as a mistake instead of as magic.
##
## Deliberately knows nothing about the unit it is on, so it can never fall out
## of step with an attack, a build or a sale - it is presentation and only that.

@export_group("References")
## What to float. Its own parent in every prefab so far, wired explicitly
## rather than walked to, like every other reference in the project.
@export var _floater: Node3D

@export_group("Settings")
## How far it travels from its resting height, in world units.
@export var height: float = 0.05
## Full up-and-down cycles per second.
@export var cycles_per_second: float = 0.4
## Where in the cycle this one starts, 0 to 1. Two cores side by side on the
## same phase read as one object cut in half, so anything placed in a group
## should be offset.
@export_range(0.0, 1.0, 0.01) var phase: float = 0.0

## Height the floater was authored at, which the bob is measured from.
var _rest_y: float = 0.0
var _elapsed: float = 0.0


func _ready() -> void:
	if _floater == null:
		Log.err("BobAnimation3D has no node to float assigned in its prefab", name)
		return

	_rest_y = _floater.position.y
	_elapsed = phase / maxf(0.0001, cycles_per_second)

	# Animated on the RENDER frame, not the simulation tick. Godot's physics
	# interpolation assumes a transform only changes on a tick, so an
	# interpolated node moved in _process jitters - visibly on some machines
	# and not others. Opting out is the documented fix, same as
	# SpinAnimation3D.
	_floater.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	if _floater == null || is_zero_approx(height):
		return
	_elapsed += delta
	_floater.position.y = _rest_y + sin(_elapsed * cycles_per_second * TAU) * height
