class_name CreepDive
extends RefCounted

## One Phoenix dive in progress: where it started, which way it went, how far
## through it is, and what it has burned on the way.
##
## The Phoenix is the only creep in the game its owner AIMS, so this is the
## only piece of creep movement that is neither a route nor a straight run down
## the lane. See DiveAbility, which starts one, and Creep._physics_process,
## which hands it the tick.
##
## An object the creep OWNS rather than five fields on it, the same shape
## CreepMana, CreepWarding and StatusEffects already take: a dive is a thing
## that exists for four seconds on one creep in a thousand, and every other
## creep in a maze should allocate nothing for it and ask nothing about it.
##
## THE ARC IS ONE SINE. Distance along the aimed direction is
## sin(pi * progress) times the reach, so the Phoenix leaves at speed, turns at
## the far end without stopping, and arrives back where it started exactly as
## the clock runs out. Out and back is the whole of what the source describes,
## and a curve that has to be authored as a keyframed path would be three
## numbers nobody could read off a .tres.
##
## HEIGHT IS NOT PART OF IT. The Phoenix flies, so it is already at cruising
## height and stays there - and nothing in this game is measured in three
## dimensions anyway, so an arc through the air would be decoration that
## changed nothing. What the arc describes is ground covered.
##
## AUTHORITY ONLY. A client draws the Phoenix wherever the snapshot puts it and
## never runs one of these; every mutator here is reached from the creep's own
## _physics_process, which a client leaves at the door. multiplayer.md 3.4.

## Where the dive began, which is also where it ends.
var _origin: Vector3 = Vector3.ZERO
## Which way it went, flat and normalised.
var _direction: Vector3 = Vector3.ZERO
## How far out it reaches at the turn, in cells.
var _reach: float = 0.0
## Seconds the whole dive takes, and how many have passed.
var _total: float = 0.0
var _elapsed: float = 0.0
## Damage dealt per second to towers under it, how far that reaches, and the
## fraction of a point built up but not yet dealt.
var _damage_per_second: float = 0.0
var _damage_radius: float = 0.0
var _carry: float = 0.0


## Builds a dive aimed at a point. Null when there is no direction in it at all
## - a Phoenix told to dive at the spot it is standing on has been aimed at
## nothing, and one that started would simply hover for four seconds.
static func toward(creep: Creep, point: Vector3, reach: float, seconds: float,
		damage_per_second: float, damage_radius: float) -> CreepDive:
	if creep == null || seconds <= 0.0 || reach <= 0.0:
		return null

	var flat: Vector3 = point - creep.global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return null

	var dive: CreepDive = CreepDive.new()
	dive._origin = creep.global_position
	dive._direction = flat.normalized()
	dive._reach = reach
	dive._total = seconds
	dive._damage_per_second = damage_per_second
	dive._damage_radius = damage_radius
	return dive


## How far through the dive is, 0 to 1. What a card draws as a sweep.
func progress() -> float:
	if _total <= 0.0:
		return 1.0
	return clampf(_elapsed / _total, 0.0, 1.0)


## Moves the creep along the arc and burns whatever is under it, and answers
## whether the dive is still running.
##
## The position is WRITTEN rather than stepped towards, which is the one place
## a creep does that: everything else in the game moves by asking how far it
## may go this tick, and a dive is a fixed path over a fixed clock. It is also
## what makes the return leg exact - a Phoenix that stepped home would arrive
## a little short or a little long depending on what had slowed it.
func advance(creep: Creep, delta: float) -> bool:
	if creep == null || !is_instance_valid(creep) || !creep.is_alive():
		return false

	_elapsed += delta
	var along: float = sin(PI * progress()) * _reach
	var to: Vector3 = _origin + _direction * along
	creep.dive_to(Vector3(to.x, creep.global_position.y, to.z), _direction)
	_burn(creep, delta)
	return _elapsed < _total


## Spell damage to every tower under the Phoenix, dealt a tick at a time.
##
## The fraction is carried between ticks exactly as burning and regeneration
## carry theirs, so a rate that comes to seven and a half points a tick really
## deals seven and a half rather than seven.
##
## SPELL damage, which is what the source states, so it ignores the armour
## matrix and the tower armour points alike - a dive lands for the same number
## on a Fortified tower as on an Unarmoured one. See DamageTable.
func _burn(creep: Creep, delta: float) -> void:
	if _damage_per_second <= 0.0 || _damage_radius <= 0.0:
		return

	_carry += _damage_per_second * delta
	var whole: int = int(_carry)
	if whole <= 0:
		return
	_carry -= float(whole)

	for tower: Building in TargetFinder.buildings_in_radius(
			creep.area, creep.global_position, _damage_radius):
		tower.take_damage(whole, DamageTable.DamageType.SPELL, true)
