@tool
class_name PiercingProjectile
extends VisualEffect3D

## One straight-line shot in flight, spawned by a PierceDelivery.
##
## The sibling of Projectile rather than a subclass of it: they share the fact
## that they are a thing moving through the world and nothing else. A Projectile
## homes on one creep, arrives, and resolves once. This one commits to a
## DIRECTION at launch, never turns, damages everything it passes and then
## expires - it has no target and can end having hit nothing at all.
##
## SIMULATION, so it lives under the projectiles root and moves on the physics
## tick. Safe on both machines for the reason every shot is: a client flies and
## lands its own, and Unit.take_damage is the single gate on health actually
## moving (multiplayer.md 3.4).
##
## THE SEGMENT IS WHAT STRIKES, not the point. At its authored speed this shot
## covers several creep widths in one tick, so testing only where it ended up
## would have it walk through a creep without touching it. Everything within
## reach of the line covered THIS tick is struck, in the order it was passed,
## which is also what makes a damage ramp down the line mean anything.
##
## @tool only so the mesh previews in the editor. The flight stands aside there.

## How far past its own hit radius the search looks, in cells, to allow for the
## widest body in the game. Only a coarse filter: everything it returns is then
## measured against the segment exactly.
const BODY_ALLOWANCE: float = 0.6

## Height above the ground the shot levels out at, so it flies THROUGH the
## creeps it is there to pierce instead of over their heads. The same height a
## homing shot aims for - see Projectile.TARGET_HEIGHT.
const STRIKE_HEIGHT: float = 0.3

## Cells of travel spent dropping from the muzzle to that height. Purely
## visual: every strike test below is FLAT, so how high the spike is riding
## never decides whether it hit anything. It is here so the shot still looks
## like it left the tip of the crystal it came out of.
const LEVEL_OUT_CELLS: float = 1.5

var _delivery: PierceDelivery
var _hit: AttackHit
## Committed at launch and never changed. This shot does not turn.
var _direction: Vector3 = Vector3.FORWARD
var _travelled: float = 0.0
## Creeps already struck, so one shot can never hit the same creep twice.
var _struck: Dictionary = {}
## How many creeps it has gone through, which is what the ramp counts.
var _passed: int = 0
## Read off the tower's passives once at launch rather than per tick: they are
## shared resources holding no state, and the tower may be sold mid flight.
var _limit: int = 0
var _ramp: float = 0.0
## The passive whose mana drain this shot carries, and its two numbers. Kept as
## the ABILITY rather than as a bare rate because a status effect is named on
## the wire by whatever applied it, and the debuff row draws that ability's
## icon. Null for every tier that crystalizes nothing, which is all but one.
var _drain_source: TowerPassive = null
var _drain_rate: float = 0.0
var _drain_seconds: float = 0.0
var _flying: bool = false
## Where the shot left, and the height it settles to, for the level out above.
var _launch_height: float = 0.0
var _flight_height: float = 0.0


## Starts the flight. Call after the projectile is in the tree, since it sets a
## global position. `direction` must be flat and normalised.
func launch(delivery: PierceDelivery, hit: AttackHit, from: Vector3,
		direction: Vector3) -> void:
	_delivery = delivery
	_hit = hit
	_direction = direction
	global_position = from
	# Placed, not moved: without this the interpolator would streak it in from
	# wherever this node was last drawn. Same reason Projectile does it.
	reset_physics_interpolation()
	look_at(from + direction, Vector3.UP)

	_launch_height = from.y
	var ground: float = 0.0 if hit.area == null else hit.area.global_position.y
	_flight_height = ground + STRIKE_HEIGHT

	for passive: TowerPassive in hit.passives:
		_limit = maxi(_limit, passive.pierce_targets())
		_ramp = maxf(_ramp, passive.pierce_ramp())
		var rate: float = passive.mana_drain_rate()
		if rate > _drain_rate:
			_drain_rate = rate
			_drain_seconds = passive.mana_drain_window()
			_drain_source = passive

	_flying = true
	play()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() || !_flying || _delivery == null || _hit == null:
		return

	var step: float = _delivery.speed * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + _direction * step
	to.y = lerpf(_launch_height, _flight_height,
		clampf((_travelled + step) / LEVEL_OUT_CELLS, 0.0, 1.0))

	_strike_between(from, to)
	global_position = to

	_travelled += step
	if _travelled >= _delivery.travel_cells || _spent():
		queue_free()


## Damages everything standing on the line covered this tick, nearest first.
##
## Nearest first is a rule rather than a tidiness: the damage grows per creep
## already passed, so striking them out of order would ramp the shot backwards
## along its own path.
func _strike_between(from: Vector3, to: Vector3) -> void:
	if _hit.area == null:
		return

	var reach: float = _delivery.hit_radius + BODY_ALLOWANCE
	var middle: Vector3 = (from + to) * 0.5
	var search: float = from.distance_to(to) * 0.5 + reach

	var found: Array = []
	for creep: Creep in TargetFinder.creeps_in_radius(_hit.area, middle, search):
		if _struck.has(creep):
			continue
		var offset: Vector3 = creep.global_position - from
		var along: float = MathsUtil.flat_dot(offset, to - from)
		if MathsUtil.flat_segment_distance(creep.global_position, from, to) \
				> _delivery.hit_radius + creep.body_radius():
			continue
		found.append([along, creep])

	found.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for entry in found:
		if _spent():
			return
		_strike(entry[1] as Creep, to)


## One creep taking the shot.
##
## The FIRST creep struck is an ordinary hit and goes through the whole
## pipeline - the tower's passives, its on-hit effects, kill credit. Everything
## behind it takes what the shot did on its way past, ramped by how many bodies
## it has already gone through, and in whatever type the delivery says a
## trailing hit is dealt as.
func _strike(creep: Creep, at: Vector3) -> void:
	_struck[creep] = true
	_crystalize(creep)
	# Once per creep passed rather than once per shot: a spike going through
	# five creeps should show five bursts, which is the only way a player can
	# see how much a piercing shot actually did. Turned to face back along the
	# flight rather than back at the tower, since a shot this long can be
	# nowhere near the line from the tower by the time it strikes.
	_delivery.spawn_impact(creep.global_position, creep.global_position - _direction)

	if _passed == 0:
		_passed = 1
		_hit.resolve(creep, at)
		return

	var scaled: float = float(_hit.damage) * (1.0 + _ramp * float(_passed))
	creep.take_damage(int(round(scaled)),
		_delivery.trailing_type(_hit.damage_type), false)
	_passed += 1


## Crystalizes this creep's mana regeneration, if the shot carries a drain and
## the creep has a pool to lose any from.
##
## Applied to EVERY creep the spike passes, the primary included, which is why
## it is here rather than in the on_hit hook: that hook runs for the creep the
## tower aimed at and for nothing behind it, and a lance that drained only its
## first target would be worth almost nothing.
##
## Before the damage rather than after, so a creep the shot kills outright is
## not handed a debuff on its way out. The write itself is refused on a client
## by StatusEffects, so that is not checked here.
##
## The POOL is checked here even though drain_mana refuses one without it,
## because status() builds a StatusEffects on the spot for whatever asks. Most
## of the roster has no mana, and a lance goes through twenty creeps a shot, so
## asking first is what keeps this from allocating one for each of them.
func _crystalize(creep: Creep) -> void:
	if _drain_source == null || creep == null || creep.mana() == null:
		return
	creep.status().drain_mana(_drain_source, _drain_rate, _drain_seconds)


## Whether the shot has gone through as many creeps as it is allowed to. A
## limit of 0 is no opinion, which is a shot that pierces until it runs out of
## distance.
func _spent() -> bool:
	return _limit > 0 && _passed >= _limit
