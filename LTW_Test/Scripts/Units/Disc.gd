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


## A disc GROWS OUT rather than up, so that going up reads at all.
##
## Building scales the visual on Y over a construction, which is exactly right
## for something that rises out of the ground and says nothing whatsoever about
## a flat quad lying on it: a plane scaled on Y is the same plane, so a disc
## driven by the inherited rule would look finished the instant it was ordered.
##
## So the same ramp is spent on the axes a disc actually has. It opens out from
## a point to its full square over the countdown, which reads from the top down
## camera the game is played at, and it reads as the SAME event a rising tower
## reads as - something arriving, not something already there.
##
## Deliberately not a fade, which would be the obvious answer and is not
## available: opacity would have to be written per building, and gl_compatibility
## has no per-instance shader uniforms. See CLAUDE.md.
func _apply_visual_height(progress: float) -> void:
	var root: Node3D = _rising_visual()
	var spread: float = lerpf(CONSTRUCTION_START_HEIGHT, 1.0, progress)
	root.scale = Vector3(spread, 1.0, spread)
