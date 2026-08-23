class_name SpinAnimation3D
extends Node

## Turns a node at a constant rate, forever.
##
## Placeholder motion for a tower whose model is its own attack: a grinder's
## blade spins whether or not anything is in range. It deliberately knows
## nothing about the attack, so it can never fall out of step with one.

@export_group("References")
## What to turn. Its own parent in every prefab so far, wired explicitly rather
## than walked to, like every other reference in the project.
@export var _spinner: Node3D

@export_group("Settings")
## Turns per second. A negative value spins the other way.
@export var turns_per_second: float = 1.5
## Axis turned around, in the spinning node's own space.
@export var axis: Vector3 = Vector3.UP


func _ready() -> void:
	if _spinner == null:
		Log.err("SpinAnimation3D has no node to turn assigned in its prefab", name)
		return

	# Animated on the RENDER frame, not the simulation tick. Godot's physics
	# interpolation assumes a transform only changes on a tick, so an
	# interpolated node moved in _process jitters - visibly on some machines and
	# not others. Opting out is the documented fix.
	_spinner.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	if _spinner == null || is_zero_approx(turns_per_second):
		return
	_spinner.rotate(axis.normalized(), turns_per_second * TAU * delta)
