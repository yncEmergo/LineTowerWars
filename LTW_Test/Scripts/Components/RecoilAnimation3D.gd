class_name RecoilAnimation3D
extends Node

## Kicks something backwards the moment its unit's attack lands, then eases it
## home.
##
## PRESENTATION ONLY. It listens to the AttackComponent and decides nothing.
##
## Driven by `attacked` rather than by `attack_started`, unlike
## SlamAnimation3D: a recoil is the CONSEQUENCE of a shot leaving, so it starts
## when the shot does. A tower with no windup still gets its full kick, which is
## why every barrel in the roster can use this and only the heavy swings need a
## windup authored.
##
## Backwards means +Z, because Godot's forward is -Z and every tower model in
## the project points its muzzle down -Z.
##
## Backwards along the NODE'S OWN Z, not its parent's. A Cannon's barrel is a
## tilted pivot, and a kick along the parent's axis would shove it sideways
## through its own bore instead of back down it. For anything unrotated the two
## are the same thing, which is why this is easy to get wrong and never notice.

@export_group("References")
## The unit that attacks.
@export var _unit: Unit
## What kicks. Usually the barrel or the rack, never the whole turret - a
## tower that shoves its own base into the ground reads as broken.
@export var _recoiling: Node3D

@export_group("Settings")
## How far back it travels, in world units.
@export var distance: float = 0.06
## Seconds to snap back at the moment of the shot. Very short: the kick should
## look instant and the RETURN is what the eye actually follows.
@export var kick_seconds: float = 0.04
## Seconds spent easing back to rest.
@export var recover_seconds: float = 0.16

## Where the node was authored, which the kick is measured from.
var _rest: Vector3 = Vector3.ZERO
## Counts up through the kick, then down through the recovery.
var _kick_left: float = 0.0
var _recover_left: float = 0.0


func _ready() -> void:
	if _unit == null || _recoiling == null:
		Log.err("RecoilAnimation3D is missing a unit or a node to kick", name)
		return

	_rest = _recoiling.position
	# Animated on the RENDER frame, so it must opt out of physics interpolation
	# the way SpinAnimation3D does, or it jitters.
	_recoiling.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	# The attack component registers itself on the unit in ITS _ready, which
	# may not have run yet.
	_unit.ready.connect(_connect_to_attack)
	if _unit.is_node_ready():
		_connect_to_attack()


func _connect_to_attack() -> void:
	var attack: AttackComponent = _unit.attack_component
	if attack == null:
		Log.err("RecoilAnimation3D's unit has no attack to kick for", _unit.name)
		return
	if !attack.attacked.is_connected(_on_attacked):
		attack.attacked.connect(_on_attacked)


func _on_attacked(_target: Unit) -> void:
	_kick_left = kick_seconds
	_recover_left = recover_seconds


func _process(delta: float) -> void:
	if _recoiling == null:
		return

	if _kick_left > 0.0:
		_kick_left = maxf(0.0, _kick_left - delta)
		var into: float = 1.0 - _kick_left / maxf(0.0001, kick_seconds)
		_apply(into)
		return

	if _recover_left > 0.0:
		_recover_left = maxf(0.0, _recover_left - delta)
		var back: float = _recover_left / maxf(0.0001, recover_seconds)
		# Squared, so it leaves the kick fast and settles slowly.
		_apply(back * back)


func _apply(amount: float) -> void:
	# basis.z is the node's own backwards axis expressed in its parent's space,
	# which is the space `position` is in.
	_recoiling.position = _rest + _recoiling.transform.basis.z * (distance * amount)
