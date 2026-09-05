class_name Disc
extends Building

## A technology disc: a building that fills a hole in a maze instead of walling
## one.
##
## Everything structural about it is a Building's - it is placed on the grid,
## it claims a cell, it is bought and morphed through the same abilities and it
## replicates as an ordinary unit type - so this class is small on purpose and
## should stay that way. What makes a disc a disc is three things, and only the
## first of them is code:
##
##   IT IS NOT A WALL. Creeps walk straight over it, which its stats say with
##   BuildingStats.blocks_movement and PlayerArea reads as CELL_WALKABLE. That
##   is the whole design of the thing: a disc is what you put in the empty
##   squares your maze already has, so the shape of a maze and the discs in it
##   are two decisions instead of one. See game_rules.md, Technology discs
##
##   IT CANNOT BE ATTACKED. Armour type Invulnerable, authored on its stats,
##   which is all it takes: TargetFinder finds only attackable buildings, so an
##   attacker creep never sees one. unit_data.md 1.5
##
##   IT CANNOT ATTACK. Its stats carry no AttackStats and its prefab carries no
##   AttackComponent, so there is nothing here to switch off
##
## The one rule that needed a class of its own is the SELECTION, and it is the
## rule Building.selection_class() has been describing since before any disc
## existed: the kinds never mix, so a box drawn across a maze comes back as
## towers or as discs and never as both. A mixed card would have to offer
## Attack and Prioritize to things that cannot attack.

## Which square of the card the disc's own effect claims, and where its two
## upgrades sit, are the .tres files' to say - see Tools/ModelGen/disc_content.py.
## Nothing about the layout is authored here.


## Discs are their own selection class. See the class docstring, and
## Building.selection_class(), which has named this case for a while.
func selection_class() -> StringName:
	return Unit.SELECT_DISC


## How long a morph takes. An upgrade UP is the ordinary build time like every
## other rung in the game; morphing back DOWN to an inactive disc takes its own
## longer count.
##
## Longer deliberately, and not a number this file chose: 11.7a raised it from
## three seconds to five to discourage swapping discs on the fly to answer an
## incoming send, which is exactly the decision a five second wait is meant to
## make expensive. unit_data.md 1.8.
func _upgrade_time() -> float:
	if !is_returning():
		return super()
	var config: GameConfig = References.game_config
	return 5.0 if config == null else config.disc_morph_down_seconds


## Name of the layer an upgrade grows. See _apply_visual_height.
const GLYPH_NODE: StringName = &"Glyph"

## Name of the round worked plate under it, which is what a BUILD grows.
##
## The layer under THAT - the square foundation - is deliberately not named
## here and is never scaled: it is the patch that says a building is here, and
## it is at full size the instant one is ordered. A tower's is too, and gets it
## for free rather than by rule, because a tower's ramp is on Y and a flat
## square scaled on Y is the same flat square. A disc's ramp is on the two axes
## it actually has, so what a tower gets for nothing this has to say out loud.
const PLATE_NODE: StringName = &"Plate"


## A disc GROWS OUT rather than up, and an UPGRADE grows only its colour.
##
## Building scales the visual on Y over a construction, which is exactly right
## for something that rises out of the ground and says nothing whatsoever about
## a flat quad lying on it: a plane scaled on Y is the same plane, so a disc
## driven by the inherited rule would look finished the instant it was ordered.
## So the same ramp is spent on the axes a disc actually has.
##
## WHICH LAYER it is spent on is the interesting half. A disc is three flat
## layers - a square foundation, a round plate, and the element circle - and
## only the last of them is what an upgrade buys: the tier IS the size of that
## circle. So an upgrade grows the circle out of the middle of a plate that
## never moves, which is a picture of exactly what was paid for.
##
## A RETURN runs it backwards. Morphing down to a bare disc is the element
## being taken AWAY, so the circle shrinks out of a plate that does not move
## and nothing grows at all - a countdown that grew anything would be a picture
## of the opposite trade.
##
## The inactive disc has no circle to grow, so its BUILD opens the PLATE out
## from a point instead. That is the right answer for it too: nothing about it
## is arriving in the middle of something already standing there.
##
## What never moves either way is the square FOUNDATION under both layers. It
## is the patch that says the square is claimed, and it is claimed the instant
## the disc is ordered - so growing it would draw the claim arriving late, and
## would be the one thing on the grid whose footprint appears to change size.
##
## Deliberately not a fade, which would be the obvious answer and is not
## available: opacity would have to be written per building, and gl_compatibility
## has no per-instance shader uniforms. See CLAUDE.md.
func _apply_visual_height(progress: float) -> void:
	var root: Node3D = _rising_visual()
	var glyph: Node3D = root.get_node_or_null(NodePath(GLYPH_NODE)) as Node3D

	if glyph == null:
		# No circle to move. That is the inactive disc being BUILT, so what
		# opens out from a point is the PLATE - the round mechanism being set
		# into a square of ground that is already claimed. The foundation under
		# it does not move at all: it is the patch saying the square is taken,
		# and a build that grew it would be drawing a claim arriving late.
		#
		# A RETURN never lands here: the disc keeps its own model for the whole
		# countdown, so there is always a circle. If one ever did, leaving the
		# scale alone is the honest answer - a morph DOWN has nothing to grow.
		if is_returning():
			return
		var plate: Node3D = root.get_node_or_null(NodePath(PLATE_NODE)) as Node3D
		if plate == null:
			return
		var opening: float = lerpf(CONSTRUCTION_START_HEIGHT, 1.0, progress)
		root.scale = Vector3.ONE
		plate.scale = Vector3(opening, 1.0, opening)
		return

	# A RETURN runs the same ramp BACKWARDS. Morphing down to a bare disc takes
	# the element away, so what the countdown should show is the colour
	# shrinking out of a plate that stays exactly where it is - and never
	# anything growing, which would be a picture of the opposite trade.
	var spread: float = lerpf(CONSTRUCTION_START_HEIGHT, 1.0, progress)
	if is_returning():
		spread = lerpf(1.0, CONSTRUCTION_START_HEIGHT, progress)

	# The layers under it are left exactly as authored either way. Scaling the
	# root as well would move the foundation and the plate along with the
	# circle, which is the thing this override exists to stop.
	root.scale = Vector3.ONE
	glyph.scale = Vector3(spread, 1.0, spread)


## A RETURN shows no preview of what is arriving, unlike every other morph.
##
## Building stands the target's model up in place of this one and rises it over
## the countdown, which is right when something is being BOUGHT: the player is
## waiting for a thing they have not got yet and should be looking at it. A
## return is the other direction. What arrives is a bare disc - the same square
## foundation and the same round plate this one is already standing on, minus
## its colour - so swapping the model in would replace the disc with a picture
## of itself and then grow that picture from a point.
##
## So this one keeps its OWN visuals for the whole countdown and lets
## _apply_visual_height shrink the colour out of them. Nothing is hidden and
## nothing is instanced, which also makes calling the return off free: there is
## no preview to clear and the circle simply goes back to full size.
func _show_upgrade_preview(target_stats: BuildingStats) -> void:
	if is_returning():
		return
	super(target_stats)
