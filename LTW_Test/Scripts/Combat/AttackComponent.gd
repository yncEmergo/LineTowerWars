class_name AttackComponent
extends Node

## Makes its unit attack by itself: acquire a target, keep aiming at it, and
## fire whenever the cooldown allows.
##
## A component rather than a subclass, because attacking crosses the split
## between what a unit IS: towers attack, the builder will, attacker creeps
## will, and none of those share a base class below Unit. Everything that is
## per unit lives here - the cooldown and the current target - while the shared
## numbers stay on the unit's AttackStats.
##
## Towers need no attack order and no command card entry. A tower with this
## component simply shoots, which is why nothing here talks to abilities.

## Raised the moment an attack is fired, before it lands. Attack animations
## hang off this once towers have real models.
signal attacked(target: Unit)

## Height above the unit's origin that shots leave from when no muzzle node was
## wired. A placeholder visual value, like the rest of the primitive art.
const MUZZLE_FALLBACK_HEIGHT: float = 0.7

@export_group("References")
## The unit this attacks for. Its own parent in every prefab so far, wired
## explicitly rather than walked to, like every other reference in the project.
@export var _unit: Unit
## Where shots leave from. Optional: an instant attack with no visual does not
## need one, and the unit's own centre stands in.
@export var _muzzle: Node3D
## Part of the model that turns to face the target, usually the barrel.
## Optional, since a grinder or a stomper has nothing to aim.
@export var _turret_head: Node3D

@export_group("Settings")
## How fast the turret swings around to a new target, in radians per second.
## Purely visual: a tower fires whether or not it has finished turning, so this
## can never cost damage.
@export var turret_turn_speed: float = 10.0

## Seconds left before the next attack may fire.
var _cooldown: float = 0.0
var _target: Creep

var _attack: AttackStats:
	get:
		if _unit == null || _unit.stats == null:
			return null
		return _unit.stats.attack


## Registered on the unit rather than wired from it, so no prefab has to carry
## the same link twice. The component already names its unit through an
## @export; this is that one reference read back the other way, which is what
## lets an ability reach the attack of whatever unit it was handed.


func _ready() -> void:
	if _unit == null:
		Log.err("AttackComponent has no unit assigned in its prefab", get_parent().name)
		return
	if _attack == null:
		Log.err("AttackComponent's unit has no AttackStats", _unit.name)

	_unit.attack_component = self


## Whether this component currently has something to shoot. Read by the UI.
func has_target() -> bool:
	return _target != null && is_instance_valid(_target)


## Orders this unit onto one specific creep, the way an attack order works in
## any RTS. Answers whether the order was taken.
##
## Refused when the creep is out of range, and refused QUIETLY: per the rules a
## tower told to shoot something it cannot reach keeps shooting whatever it was
## already on, rather than standing idle waiting for the creep to wander in.
## That is what makes the order safe to give to a whole selection at once - the
## towers that can reach it switch, the rest carry on.
##
## The commanded target is then an ordinary target: it is dropped when it dies
## or leaves range, and the tower goes back to picking its own.
func order_target(creep: Creep) -> bool:
	var attack: AttackStats = _attack
	if attack == null || _unit == null || !_unit.can_attack():
		return false
	if !TargetFinder.can_be_hit_by(creep, attack):
		return false
	if !TargetFinder.is_in_range(_origin(), creep, attack.attack_range):
		return false

	_target = creep
	return true

func _physics_process(delta: float) -> void:
	var attack: AttackStats = _attack
	if attack == null || _unit == null || !_unit.can_attack():
		return

	_cooldown = maxf(0.0, _cooldown - delta)
	_drop_lost_target(attack)

	# Scanning only when the tower could actually shoot keeps the cost down: a
	# tower on cooldown has nothing to do with a new target anyway, and it goes
	# on aiming at the last one meanwhile.
	if _target == null && _cooldown <= 0.0:
		_target = TargetFinder.best_target(_unit.area, _origin(), attack)

	if _target == null:
		return

	_aim(delta)
	if _cooldown <= 0.0:
		_fire(attack)


## Forgets a target that died, left range, or stopped being a legal target.
func _drop_lost_target(attack: AttackStats) -> void:
	if _target == null:
		return
	if !TargetFinder.is_in_range(_origin(), _target, attack.attack_range):
		_target = null
		return
	if !TargetFinder.can_be_hit_by(_target, attack):
		_target = null


func _fire(attack: AttackStats) -> void:
	_cooldown = attack.cooldown_seconds()

	var hit: AttackHit = AttackHit.new()
	hit.damage = attack.roll_damage(MatchSession.match_rng())
	hit.damage_type = attack.damage_type
	hit.is_aoe = attack.is_aoe_damage
	hit.effects = attack.effects
	hit.area = _unit.area
	hit.attacker_player_id = _unit.owner_player_id

	if attack.delivery == null:
		# An attack with no delivery is a half authored resource. Landing it
		# instantly makes that visible in play rather than as silence.
		Log.err("AttackStats has no delivery assigned", _unit.name)
		hit.resolve(_target, _target.global_position)
	else:
		attack.delivery.deliver(hit, _muzzle_position(), _target)

	attacked.emit(_target)


## Point range is measured from, which is the unit itself rather than the
## muzzle: a barrel swinging around must not change how far a tower reaches.
func _origin() -> Vector3:
	return _unit.global_position


func _muzzle_position() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	return _unit.global_position + Vector3(0.0, MUZZLE_FALLBACK_HEIGHT, 0.0)


## Swings the turret around towards the target, flat on the xz plane. Models
## face -Z by Godot's convention, which is what the angle is built from.
func _aim(delta: float) -> void:
	if _turret_head == null:
		return

	var offset: Vector3 = _target.global_position - _turret_head.global_position
	if absf(offset.x) < 0.0001 && absf(offset.z) < 0.0001:
		return

	var wanted: float = atan2(-offset.x, -offset.z)
	_turret_head.global_rotation.y = rotate_toward(
		_turret_head.global_rotation.y, wanted, turret_turn_speed * delta
	)
