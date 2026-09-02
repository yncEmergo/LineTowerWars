class_name CreepWarding
extends RefCounted

## What has hurt one creep and by how much, and which damage type it is
## currently braced against.
##
## The Shaman's Elemental Warding and nothing else: "gains 70% damage
## resistance against whichever damage type has dealt it the most damage, and
## can swap that resistance once every 3 seconds" (unit_data.md 6.6).
##
## An object the creep OWNS, for the same reason CreepMana and StatusEffects
## are: the passive that fills this is one shared resource standing in for
## every Shaman on the field, so a ledger stored there would be all of theirs
## added together. Built lazily by the passive, so no other creep in a maze
## allocates it, ticks it or draws it.
##
## The SWAP GATE is the whole character of it. Without one the creep would
## simply resist whatever hit it last, and a maze of two damage types would
## never get through; with one, a player who changes what they are shooting
## with gets three full seconds of the Shaman braced against the wrong thing.
##
## AUTHORITY ONLY, enforced at the door as everywhere else: a client draws the
## creep the server sent it and runs no ledger of its own. multiplayer.md 3.4.

## Damage type meaning "braced against nothing yet".
const NONE: int = -1

## damage type -> total damage that type has actually landed on this creep.
## Sparse: a type nothing has hit the creep with is not in here at all.
var _totals: Dictionary = {}
## The type currently resisted, or NONE before anything has hurt it.
var _warded: int = NONE
## Seconds before the brace may move to another type.
var _swap_left: float = 0.0


## Whether damage of this type is the one currently being resisted.
func is_warded_against(damage_type: DamageTable.DamageType) -> bool:
	return _warded != NONE && int(damage_type) == _warded


## The damage type currently resisted, or NONE.
func warded_type() -> int:
	return _warded


## Records damage that ACTUALLY LANDED, in the type it landed as.
##
## The landed figure rather than the attacker's roll, exactly as every other
## reading in the roster is: what the ledger should point at is whatever is
## really taking the creep apart, and a type that reads huge on paper and
## arrives blunted is not it.
func record(damage_type: DamageTable.DamageType, amount: float) -> void:
	if amount <= 0.0 || !MatchSession.is_authority():
		return
	var key: int = int(damage_type)
	_totals[key] = float(_totals.get(key, 0.0)) + amount


## Counts the swap gate down and moves the brace onto the worst type if it has
## come round. Answers whether the brace actually moved, which is only worth
## knowing to a caller that wants to say so.
func advance(delta: float) -> bool:
	if !MatchSession.is_authority():
		return false

	_swap_left = maxf(0.0, _swap_left - delta)
	if _swap_left > 0.0:
		return false

	var worst: int = _worst_type()
	if worst == NONE || worst == _warded:
		return false

	_warded = worst
	return true


## Restarts the gate. Called by the passive after a swap it announced, so the
## interval is the passive's number and this only holds the clock.
func hold_for(seconds: float) -> void:
	if seconds > 0.0 && MatchSession.is_authority():
		_swap_left = seconds


## Whichever type has landed the most damage over this creep's whole life, or
## NONE while nothing has hurt it.
##
## Ties are broken by the LOWER type index rather than by insertion order, so
## two machines running the same match brace against the same thing. A
## dictionary's key order is not something replication may depend on.
func _worst_type() -> int:
	var best: int = NONE
	var best_total: float = 0.0
	for key: int in _totals:
		var total: float = float(_totals[key])
		if total > best_total || (is_equal_approx(total, best_total) && key < best):
			best = key
			best_total = total
	return best
