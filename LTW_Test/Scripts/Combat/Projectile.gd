@tool
class_name Projectile
extends VisualEffect3D

## One shot in flight, spawned by a ProjectileDelivery and freed when it lands.
##
## A VisualEffect3D for its opacity setting and nothing else - the flight
## itself is simulation, not decoration. @tool only so that opacity previews in
## the editor; every gameplay method below stands aside there, and
## _physics_process already does by way of having no delivery to fly for.
##
## Homes on its target, so a creep cannot outwalk a shot already aimed at it.
## When the target dies mid flight the projectile keeps going to where it last
## was and lands there anyway, which is what lets a cannon orb still splash
## the crowd its primary target was standing in.
##
## Lives under the shared effects root rather than under the tower, so a tower
## sold while its shot is in the air does not delete that shot. Nothing here
## reads the tower at all: everything it needs came along in the AttackHit.
##
## Travel is tracked flat on the xz plane with the height put back on top,
## because the game is played flat. Speed is therefore ground speed, and the
## arc never steals from it.

## Height above a target's origin that shots aim for, so they strike the body
## rather than the ground under it. A placeholder visual value, like the rest
## of the primitive art.
const TARGET_HEIGHT: float = 0.3

## Distance at which the projectile counts as having arrived.
const ARRIVE_THRESHOLD: float = 0.08

## Seconds a projectile may stay in the air before it gives up and lands where
## it is. Nothing should ever reach this, it is here so a shot chasing a creep
## it can never catch cannot live forever.
const MAX_LIFETIME: float = 6.0

## The share of its full arc a shot fired at point blank range still bows.
## Above zero so a short shot keeps the character of the weapon that threw it -
## a mortar lobbing dead flat at one cell reads as a different tower.
const ARC_FLOOR: float = 0.15

var _delivery: ProjectileDelivery
var _hit: AttackHit
var _target: Unit
## Where the projectile is flying, refreshed while the target is alive and then
## frozen at its last known position.
var _goal: Vector3 = Vector3.ZERO
var _launch_point: Vector3 = Vector3.ZERO
## Flat distance at launch, which the arc and the climb are measured against.
## Frozen on purpose: recomputing it while homing would make the arc jitter.
var _launch_distance: float = 1.0
var _elapsed: float = 0.0
var _landed: bool = false
## How high this particular shot bows, from the distance it was fired over.
## Frozen at launch for the same reason `_launch_distance` is - see there.
var _arc_peak: float = 0.0


## Starts the flight. Call after the projectile is in the tree, since it sets a
## global position.
func launch(delivery: ProjectileDelivery, hit: AttackHit, from: Vector3, target: Unit) -> void:
	_delivery = delivery
	_hit = hit
	_target = target
	_launch_point = from
	_goal = from
	global_position = from
	# Placed, not moved: without this the interpolator would streak it in from
	# wherever it was last drawn, which for a fresh creep is the world origin.
	reset_physics_interpolation()

	_refresh_goal()
	_launch_distance = maxf(0.001, _flat_distance_to_goal())
	_arc_peak = _arc_peak_for(_launch_distance)
	# Before the first step rather than after it, so an arrow is never drawn for
	# a frame still pointing whichever way the prefab happened to be built.
	_face_travel(_goal - global_position)


func _physics_process(_engine_delta: float) -> void:
	# **The SIMULATION's second, never the engine's.** The parameter is the real
	# time this frame took, which is exactly what must not reach gameplay once a
	# servo can pace the engine - see MatchSession._sim_ticks_per_second.
	var delta: float = MatchSession.tick_seconds()
	if _landed || _delivery == null || _hit == null:
		return

	_elapsed += delta
	if _elapsed >= MAX_LIFETIME:
		Log.warn("Projectile gave up chasing its target", {"projectile": name})
		_land()
		return

	_refresh_goal()

	var step: float = _delivery.speed * delta
	if _flat_distance_to_goal() <= maxf(step, ARRIVE_THRESHOLD):
		_land()
		return

	_advance(step)


func _advance(step: float) -> void:
	var here: Vector2 = Vector2(global_position.x, global_position.z)
	var there: Vector2 = Vector2(_goal.x, _goal.z)
	var next: Vector2 = here + (there - here).normalized() * step

	var progress: float = _progress(next.distance_to(there))

	var previous: Vector3 = global_position
	global_position = Vector3(
		next.x,
		lerpf(_launch_point.y, _goal.y, progress) + _arc_offset(progress),
		next.y
	)
	_face_travel(global_position - previous)


## How far along its flight the shot is, 0 to 1, measured from what is LEFT
## rather than from what has been covered.
##
## The two only agree while the target stands still. A creep walking towards an
## incoming shot brings the arrival forward, so a shot counting what it has
## travelled arrives partway through its own descent and lands in mid air - and
## the further a shot falls, the more of a gap that is. Counting backwards from
## the remaining distance is self correcting: whatever the target did, zero left
## to fly is zero height left to lose.
##
## `_launch_distance` stays frozen, which is what the arc needs - see the note
## on it. This only changes which end the progress is measured from.
func _progress(remaining: float) -> float:
	return clampf(1.0 - remaining / _launch_distance, 0.0, 1.0)


## Height the arc adds partway along the flight. A half sine, so it is zero at
## both ends and highest in the middle.
func _arc_offset(progress: float) -> float:
	if _arc_peak <= 0.0:
		return 0.0
	return sin(progress * PI) * _arc_peak


## How high THIS shot bows, worked out once at launch from how far it has to go.
##
## `arc_height` is the peak of a shot at full range; a shorter one bows less, in
## proportion, down to a small floor. That floor is what stops a point blank
## shot going perfectly flat and losing the character of the weapon entirely.
##
## IT USED TO BE A FLAT HEIGHT, and that was wrong in a way that only shows at
## close range. A Cannon lobbing 3.4 world units - about four times the height
## of the tower firing it - looks like a mortar when the creep is at the edge of
## its reach, and looks absurd when the creep is one cell away, because it threw
## the same enormous bow either way. What a player reads as "wrong" is the
## SHORT shot, which is also the one they see most.
##
## Capped at full range rather than growing without limit, because a shot that
## keeps climbing the further it goes stops reading as the same weapon - which
## is the other half of the same complaint.
func _arc_peak_for(distance: float) -> float:
	if _delivery.arc_height <= 0.0:
		return 0.0
	var full: float = maxf(0.001, _delivery.arc_full_distance)
	var reach: float = clampf(distance / full, 0.0, 1.0)
	return _delivery.arc_height * (ARC_FLOOR + (1.0 - ARC_FLOOR) * reach)


func _flat_distance_to_goal() -> float:
	return Vector2(_goal.x - global_position.x, _goal.z - global_position.z).length()


## Keeps aiming at the live target, and holds the last known point once it is
## gone so the shot still lands somewhere sensible.
func _refresh_goal() -> void:
	if _target == null || !is_instance_valid(_target):
		_target = null
		return
	_goal = _target.global_position + Vector3(0.0, TARGET_HEIGHT, 0.0)


func _face_travel(direction: Vector3) -> void:
	# A step with no horizontal component has no usable heading, and look_at
	# would fail on the degenerate up vector.
	if absf(direction.x) < 0.0001 && absf(direction.z) < 0.0001:
		return
	look_at(global_position + direction, Vector3.UP)


func _land() -> void:
	_landed = true
	_delivery.on_impact(_hit, _target, _goal)
	queue_free()
