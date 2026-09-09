class_name SwayAnimation3D
extends Node

## Rocks a node back and forth about an axis, around wherever it started,
## forever.
##
## The third of the three idle-motion placeholders, with BobAnimation3D and
## SpinAnimation3D, and it exists for the one thing neither of those can do: a
## piece of CLOTH. A pennant does not turn like a halo or rise like a floating
## core - it leans into the wind and comes back.
##
## It is what an Ultimate BASIC tower has instead of the turning metal ring the
## roster used to give it. Motion is the loudest signal a top down camera has,
## so the roster reserves it for the top of the price ladder and nothing below
## an Ultimate gets a moving part that is not its own attack (game_rules.md
## under Presentation). When the metal came off that roster the ring went with
## it, and the top rung needed something to say "this is the expensive one"
## that was not another lump of stone.
##
## TWO WAVES RATHER THAN ONE, which is the only real decision in here. A single
## sine is a metronome: the eye picks the period up in about two seconds and
## the flag stops reading as cloth and starts reading as a wiper blade. A
## second, faster, smaller wave at an irrational ratio to the first never
## repeats at any period a player can spot, and costs one more sin().
##
## Deliberately knows nothing about the unit it is on, so it can never fall out
## of step with an attack, a build or a sale - it is presentation and only that.

@export_group("References")
## What to rock. Its own parent in every model so far, wired explicitly rather
## than walked to, like every other reference in the project.
@export var _swaying: Node3D

@export_group("Settings")
## How far it leans from rest, in degrees, at the top of the slow wave.
@export var degrees: float = 9.0
## Full there-and-back cycles per second of the SLOW wave.
@export var cycles_per_second: float = 0.35
## Where in the cycle this one starts, 0 to 1. Two pennants on one tower at the
## same phase read as one flag drawn twice, so anything placed in a group
## should be offset.
@export_range(0.0, 1.0, 0.01) var phase: float = 0.0
## Axis leaned about, in the swaying node's own space. Z rocks a pennant from
## side to side across a mast standing on Y.
@export var axis: Vector3 = Vector3.BACK

## How big the second wave is as a share of the first, and how much faster it
## runs. The ratio is deliberately not a whole number - see the note above.
@export_range(0.0, 1.0, 0.01) var ripple_share: float = 0.34
@export var ripple_ratio: float = 2.7

## Rotation the node was authored at, which the sway is measured from.
var _rest: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0


func _ready() -> void:
	if _swaying == null:
		Log.err("SwayAnimation3D has no node to sway assigned in its model", name)
		return

	_rest = _swaying.rotation
	_elapsed = phase / maxf(0.0001, cycles_per_second)

	# Animated on the RENDER frame, not the simulation tick. Godot's physics
	# interpolation assumes a transform only changes on a tick, so an
	# interpolated node moved in _process jitters - visibly on some machines
	# and not others. Opting out is the documented fix, same as
	# BobAnimation3D and SpinAnimation3D.
	_swaying.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	if _swaying == null || is_zero_approx(degrees):
		return

	_elapsed += delta
	var slow: float = sin(_elapsed * cycles_per_second * TAU)
	var fast: float = sin(_elapsed * cycles_per_second * ripple_ratio * TAU)
	var lean: float = slow * (1.0 - ripple_share) + fast * ripple_share

	_swaying.rotation = _rest + axis.normalized() * deg_to_rad(degrees) * lean
