@abstract
class_name VoidSpreadPassive
extends TowerPassive

## The half of Void that SPREADS: a tower that turns one of its neighbours into
## another of itself, free.
##
## Three towers do it and they differ only in WHEN. The base pair spends a mana
## bar filling up once and converts a cheap Basic tower; the Ultimate Harbinger
## does it on a clock, over and over, to the tier below it. So the picking and
## the converting live here and each subclass answers "now?" for itself.
##
## THE CONVERSION IS A FREE INSTANT SWAP, never an upgrade. No gold changes
## hands, no countdown runs, and the tower being converted is not the one paying
## for it - Building.upgrade_to would charge its owner and start a timer, so
## this goes through Building.transform_into, which is the same replacement
## path the far end of an upgrade uses and hands nothing down.
##
## TOWERS ARE NAMED BY unit_type_id HERE, not by a BuildingStats reference, and
## that is not a style choice. An ability that held its own tower's stats would
## be a reference CYCLE - the stats name the ability, the ability names the
## stats - and it would make loading one tower's card drag every tower it can
## convert into memory with it. An id costs nothing until something actually
## spreads, reads plainly in a .tres, and is exactly what CLAUDE.md reserves
## ids for.

@export_group("Void Spread")
## What a converted tower becomes, by unit_type_id. In practice the tower this
## passive sits on, which is why it is authored rather than derived: a
## Voidalisk converts a Voidling into a Voidalisk, not into whatever the
## Voidling would have upgraded to.
@export var becomes_type_id: int = 0
## Which towers may be taken, by unit_type_id. Anything not on this list is
## safe, which is how elemental towers are kept out of it - they are simply
## never listed.
@export var converts_type_ids: PackedInt32Array = PackedInt32Array()
## How far it reaches for something to convert, in player cells.
@export var reach_cells: float = 3.0


## Finds a tower worth taking and takes it. Answers whether it converted one,
## so a caller that only gets one attempt can tell a hit from a miss.
##
## Authority only, and explicitly: this REPLACES a node, which is the far end
## of what a passive is normally allowed to do on its own.
func spread(tower: Building) -> bool:
	if becomes_type_id <= 0 || tower.area == null || !MatchSession.is_authority():
		return false

	var target: BuildingStats = _becomes()
	if target == null:
		Log.err("Void spread names a unit type this build does not have",
			becomes_type_id)
		return false

	var victim: Building = _pick(tower)
	if victim == null:
		return false

	victim.transform_into(target)
	Log.info("Void spread", {"tower": tower.name, "converted": victim.name})
	return true


## The best tower in reach, or null.
##
## CHEAPEST FIRST, then nearest. The cheap rung is what the Void line wants to
## eat - taking a 10g tower costs its owner almost nothing and taking a 30g one
## costs real value - so price is the first question and distance only breaks
## the tie among equals. Ordering the authored list instead would make the
## answer depend on the order somebody happened to type it in.
func _pick(tower: Building) -> Building:
	var best: Building = null
	var best_price: int = 0
	var best_distance: float = 0.0

	# Cheapest first, then nearest - and a tower tying on BOTH falls to whichever
	# the walk reached first, which is child order under the area. That is the
	# order the build commands arrived in, so every machine reaches the same one.
	# The narrowest case of the dependency TargetFinder._scan describes at length.
	for child: Node in tower.area.get_children():
		var other: Building = child as Building
		if other == null || other == tower || !_may_convert(other):
			continue
		var offset: Vector3 = other.global_position - tower.global_position
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance > reach_cells:
			continue

		var price: int = (other.stats as BuildingStats).total_gold_cost
		if best == null || price < best_price \
				|| (price == best_price && distance < best_distance):
			best = other
			best_price = price
			best_distance = distance
	return best


## A tower may be taken when its type is one of the authored ones and it is
## standing rather than busy being something else. A tower mid-build, mid-sale
## or mid-upgrade is refused: transform_into would refuse it anyway, and
## picking it would waste the attempt on a tower that could not have been had.
func _may_convert(other: Building) -> bool:
	if other.is_under_construction() || other.is_selling() || other.is_upgrading():
		return false
	var stats: BuildingStats = other.stats as BuildingStats
	return stats != null && int(stats.unit_type_id) in converts_type_ids


## The stats of what this makes, or null when the build does not contain it.
func _becomes() -> BuildingStats:
	var session: MatchSession = References.match_session
	if session == null:
		return null
	return session.unit_types().stats_for(becomes_type_id) as BuildingStats


## What this turns things into, for a tooltip. Falls back to a generic phrase
## rather than to an id, which would mean nothing to a player.
##
## A bare noun, never one carrying its own article: the sentences this sits in
## put one in front of it, and a fallback reading "another Void tower" made one
## of them say "into a another Void tower".
func _becomes_name() -> String:
	var stats: BuildingStats = _becomes()
	return "Void tower" if stats == null else stats.display_name


## How far it reaches for something to convert, which is the one number that
## decides where a Void tower is worth standing. Answered by the whole line -
## the pair that spread once and the Ultimate that spreads on a clock.
func display_radius(_unit: Unit) -> float:
	return reach_cells
