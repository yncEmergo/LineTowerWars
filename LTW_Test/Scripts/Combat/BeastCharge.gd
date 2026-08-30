@tool
class_name BeastCharge
extends VisualEffect3D

## The beast the Beastmaster line sends down the lane at full mana.
##
## A thing RUNNING through the maze rather than a shot: it leaves the tower on
## a committed heading, ploughs through every ground creep standing in a wide
## band along that heading, and stops when it has run its distance. It hits
## everything - there is no cap on how many creeps it may go through - and it
## can end having hit nothing at all.
##
## The sibling of PiercingProjectile, not a subclass: they share the straight
## line and the segment test and nothing else. A pierce is an ATTACK, resolved
## through a delivery and an AttackHit with a ramp down its path; this is an
## ABILITY, carrying its own damage and its own stun, dealing the same to the
## first creep and the twentieth. Folding the two together would mean a
## delivery with no attack behind it and a hit with no roll in it.
##
## NO PHYSICS, like everything else that moves in this game. The beast is a
## point walking a line and a creep is caught when the distance from its centre
## to the SEGMENT covered this tick is small enough. Testing the segment rather
## than the endpoint is not optional even at this speed - one tick of it is
## most of a cell, which is most of a creep.
##
## GROUND creeps only. The source says so, and it is also what a thing running
## along the floor should do.
##
## SIMULATION, so it lives under the projectiles root and moves on the physics
## tick - and it is safe on both machines for the reason every shot is: a
## client runs its own copy for the look of it, and Unit.take_damage and
## StatusEffects both stand aside there, so nothing it touches actually moves.
##
## @tool only so the model previews in the editor. The run stands aside there.

## How far past its own hit radius the search looks, in cells, to allow for the
## widest body in the game. A coarse filter only: everything it returns is then
## measured against the segment exactly.
const BODY_ALLOWANCE: float = 0.6

var _passive: BloodthirstPassive
var _area: PlayerArea
## Committed at launch and never changed. The beast does not turn.
var _direction: Vector3 = Vector3.FORWARD
var _travelled: float = 0.0
## Creeps already trampled, so one charge can never hit the same creep twice.
var _struck: Dictionary = {}
var _running: bool = false


## Starts the run. Call after the beast is in the tree, since it sets a global
## position. `direction` must be flat and normalised.
func launch(passive: BloodthirstPassive, area: PlayerArea, from: Vector3,
		direction: Vector3) -> void:
	_passive = passive
	_area = area
	_direction = direction
	global_position = from
	# Placed, not moved: without this the interpolator would streak it in from
	# wherever this node was last drawn. Same reason a projectile does it.
	reset_physics_interpolation()
	look_at(from + direction, Vector3.UP)
	_running = true
	play()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() || !_running || _passive == null:
		return

	var step: float = _passive.beast_speed * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + _direction * step

	_trample_between(from, to)
	global_position = to

	_travelled += step
	if _travelled >= _passive.beast_cells:
		queue_free()


## Everything standing in the band covered this tick, nearest first.
##
## Nearest first costs nothing here - the beast deals the same to all of them -
## and is kept because the order it strikes in is the order a player watches it
## happen in, and an impact popping behind the beast reads as a bug.
func _trample_between(from: Vector3, to: Vector3) -> void:
	if _area == null:
		return

	var reach: float = _passive.beast_radius + BODY_ALLOWANCE
	var middle: Vector3 = (from + to) * 0.5
	var search: float = from.distance_to(to) * 0.5 + reach

	var found: Array = []
	for creep: Creep in TargetFinder.creeps_in_radius(_area, middle, search):
		if _struck.has(creep) || creep.is_flying():
			continue
		if MathsUtil.flat_segment_distance(creep.global_position, from, to) \
				> _passive.beast_radius + creep.body_radius():
			continue
		found.append([MathsUtil.flat_dot(creep.global_position - from, to - from), creep])

	found.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for entry in found:
		_trample(entry[1] as Creep)


## One creep going under it. The damage and the knockdown both belong to the
## passive, which is the authority on what this tower's beast is worth.
func _trample(creep: Creep) -> void:
	_struck[creep] = true
	_passive.trample(creep)
