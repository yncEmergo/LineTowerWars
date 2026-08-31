class_name CreepMana
extends RefCounted

## The mana pool a creep runs one of its traits on.
##
## Mana used to be a TOWER thing and nothing else had any. Tier 2 is where that
## stops: the Voidwalker's Chaotic Void banks a point per hit taken and spends
## the lot on a heal, and tiers 3 and 4 bring five more traits shaped the same
## way - Spiritual Aid, Wind Rush, Chaos Barrier, Mana Drain, Siren's Song. See
## unit_data.md 6.6.
##
## An object the creep OWNS rather than three fields on it, for the same reason
## StatusEffects is one: the vast majority of creeps in a maze have no mana at
## all, and a creep whose stats give it no pool never allocates this, never
## ticks it and never draws it.
##
## **The creep owns it and its passives write into it.** A passive is a shared
## stateless resource - one chaotic_void.tres is every Voidwalker on the field -
## so a count stored there would be every Voidwalker's count at once. This is
## where it really lives.
##
## AUTHORITY ONLY, enforced at the door exactly as StatusEffects does it: every
## mutator returns immediately on a client, which draws the number the server
## sent it. See multiplayer.md 3.4.
##
## Whole numbers, because every mana figure in the roster is counted rather
## than measured: 26 to heal, full at 6, full at 14 starting from 10.

## The most it holds, and what it holds now.
var maximum: int = 0
var current: int = 0


## Builds the pool a creep's stats describe, or null when they describe none.
##
## A static maker rather than a constructor the creep has to guard, so "does
## this creep have mana" is asked once, here, and the creep simply keeps what
## comes back.
static func of(stats: CreepStats) -> CreepMana:
	if stats == null || stats.max_mana <= 0:
		return null

	var pool: CreepMana = CreepMana.new()
	pool.maximum = stats.max_mana
	pool.current = clampi(stats.starting_mana, 0, pool.maximum)
	return pool


func is_full() -> bool:
	return current >= maximum


func ratio() -> float:
	if maximum <= 0:
		return 0.0
	return clampf(float(current) / float(maximum), 0.0, 1.0)


## Adds mana, never past the ceiling. Reports whether the pool is now FULL, so
## a passive that spends at full reads one answer rather than adding and then
## asking again.
func gain(amount: int) -> bool:
	if amount != 0 && MatchSession.is_authority():
		current = clampi(current + amount, 0, maximum)
	return is_full()


## Takes mana, refusing to go below zero. Reports whether there was enough,
## so a passive can gate on the spend itself rather than checking first.
func spend(amount: int) -> bool:
	if amount <= 0 || current < amount:
		return false
	if MatchSession.is_authority():
		current -= amount
	return true


## Empties the pool, which is what nearly every creep trait does on firing:
## the source game writes them as "at N mana, do X and reset".
func drain() -> void:
	if MatchSession.is_authority():
		current = 0


## Raises the ceiling, which one tier 4 trait does to itself. The mana already
## held is untouched, so a pool that was full is simply no longer full.
func raise_ceiling(amount: int) -> void:
	if amount > 0 && MatchSession.is_authority():
		maximum += amount


## Mana handed down by the server, which is the only thing that moves it on a
## client. Deliberately not routed through gain(): that is a rule the server
## runs, and this is a number arriving.
func set_replicated(value: int) -> void:
	current = clampi(value, 0, maximum)


## What the unit panel draws under the portrait. Mana blue, because it IS mana
## and must read as the same thing a tower's does.
func as_resource() -> TowerResource:
	return TowerResource.mana(current, maximum)
