class_name SparkAnimation3D
extends Node

## Throws a burst of particles off its unit the moment an attack lands.
##
## PRESENTATION ONLY. It listens to the AttackComponent and decides nothing,
## exactly like the recoil and the slam next to it - and like them it is
## driven by `attacked` rather than by `attack_started`, because the burst is
## the CONSEQUENCE of the shot leaving rather than the wind-up to it.
##
## The particle node lives in the MODEL rather than here, sitting quiet with
## `emitting` off, and this only restarts it. That split is the same one every
## animation component makes: the model owns what the tower is made of and can
## be handed to a build ghost safely, and the prefab owns anything that needs
## the unit. A ghost carrying a particle node that never emits costs nothing.
##
## Restarting rather than toggling `emitting` is deliberate. A one-shot burst
## that is already running has to be cut off and thrown again when the tower
## fires faster than the burst lasts, and restart() is the only call that does
## that - setting `emitting = true` on a system that is already true does
## nothing at all, which reads as a tower that stops sparking under fire.

@export_group("References")
## The unit that attacks.
@export var _unit: Unit
## What throws the sparks. Its own model's node, wired by path in the prefab.
@export var _sparks: CPUParticles3D


func _ready() -> void:
	if _unit == null || _sparks == null:
		Log.err("SparkAnimation3D is missing a unit or a particle node", name)
		return

	# The attack component registers itself on the unit in ITS _ready, which
	# may not have run yet.
	_unit.ready.connect(_connect_to_attack)
	if _unit.is_node_ready():
		_connect_to_attack()


func _connect_to_attack() -> void:
	var attack: AttackComponent = _unit.attack_component
	if attack == null:
		Log.err("SparkAnimation3D's unit has no attack to spark for", _unit.name)
		return
	if !attack.attacked.is_connected(_on_attacked):
		attack.attacked.connect(_on_attacked)


func _on_attacked(_target: Unit) -> void:
	if _sparks != null:
		_sparks.restart()
