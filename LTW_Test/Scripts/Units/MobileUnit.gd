class_name MobileUnit
extends Unit

## A unit that moves around the field: the builder and creeps.
##
## Movement lives here rather than on Unit so that buildings never inherit a
## move_to() they can never use.
##
## Movement runs in _physics_process rather than _process so unit simulation
## stays on a fixed timestep, which matters once this becomes a multiplayer
## game.

var _target_position: Vector3 = Vector3.ZERO
var _is_moving: bool = false

## Movement values live on the mobile subclass of UnitStats, so this narrows
## the base stats once rather than casting at every use.
var _mobile_stats: MobileUnitStats:
	get:
		return stats as MobileUnitStats


func _ready() -> void:
	super()
	if stats != null && _mobile_stats == null:
		Log.err("MobileUnit needs MobileUnitStats but got plain UnitStats", name)
	_target_position = global_position


## Issues a move order. The target is clamped into the unit's own area, since
## a unit may never leave it.
func move_to(world_target: Vector3) -> void:
	if area == null:
		Log.err("MobileUnit has no area assigned, ignoring move order", name)
		return
	_target_position = area.clamp_point(world_target)
	_is_moving = true


func stop() -> void:
	_is_moving = false
	_target_position = global_position


func is_moving() -> bool:
	return _is_moving


func _physics_process(delta: float) -> void:
	# 3.4: a client runs no simulation of its own. What it draws is what the
	# server sent, so anything that would advance the world here has to stand
	# aside. See MatchSession.is_authority().
	if !MatchSession.is_authority():
		return

	if !_is_moving || _mobile_stats == null:
		return

	var current: Vector3 = global_position
	var to_target: Vector3 = _target_position - current
	to_target.y = 0.0

	var distance: float = to_target.length()
	if distance <= _mobile_stats.arrive_threshold:
		_arrive()
		return

	var direction: Vector3 = to_target / distance
	var step: float = _mobile_stats.move_speed * delta
	if step >= distance:
		_arrive()
	else:
		global_position = current + direction * step

	_face_direction(direction, delta)


func _arrive() -> void:
	global_position = Vector3(_target_position.x, 0.0, _target_position.z)
	_is_moving = false


## Snaps to face a world point with no turn animation, for moments where the
## unit should already be looking the right way rather than swinging round.
func face_instantly(world_point: Vector3) -> void:
	var to_point: Vector3 = world_point - global_position
	to_point.y = 0.0
	if to_point.length_squared() <= 0.0001:
		return
	rotation.y = atan2(-to_point.x, -to_point.z)


func _face_direction(direction: Vector3, delta: float) -> void:
	# Unit prefabs face -z, matching the builder's nose marker.
	var desired: float = atan2(-direction.x, -direction.z)
	rotation.y = rotate_toward(rotation.y, desired, _mobile_stats.turn_speed * delta)
