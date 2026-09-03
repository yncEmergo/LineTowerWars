class_name ShieldBar3D
extends Bar3D

## Worldspace bar for damage standing in FRONT of a unit's health, drawn just
## above the health bar.
##
## Teal, and above rather than below, because that is what an RTS or an RPG has
## drawn a shield as for thirty years: the bar that has to be emptied before the
## green one starts moving. A player reads it without being told.
##
## Unlike the health bar it is not the player's to switch off. A shield is the
## reason a unit is not dying, so a Behemoth walking a lane with its health bar
## hidden would otherwise look like a creep nothing was hurting.
##
## It has a BACKGROUND, unlike the second-resource bar under a tower: the empty
## part is how much of the shield has already been spent, which for the one
## creep that carries a big one is the whole question a player is asking of it.
## That is what StatusEffects.shield_max is kept for.
##
## It POLLS its unit, for exactly the reason ResourceBar3D does: a shield moves
## from the damage pipeline, from whatever granted it, and on a client from a
## replication update that went nowhere near either, and none of them raises a
## signal.

## Height above the health bar. The bars nearly touch, so the two read as one
## stack rather than as two unrelated readouts.
const GAP: float = 0.16

## Share of an ordinary bar's thickness. Two thirds - thinner than the health
## bar it hangs off, thicker than a tower's second resource, because a shield
## is the number being spent while a player watches.
const HEIGHT_SHARE: float = 0.66

@export_group("References")
## The unit this reads. Its own owner, wired by the unit that made it.
@export var _unit: Unit


func _ready() -> void:
	fill_color = TowerResource.SHIELD_FILL
	empty_color = TowerResource.SHIELD_EMPTY
	bar_height = BAR_HEIGHT * HEIGHT_SHARE
	super()
	# Straight away rather than on the first frame: the one creep that carries a
	# shield is shielded from the moment it spawns, so a frame of an empty bar
	# would be a frame of a Behemoth looking dead.
	_refresh()


## Assigns the unit to read. Call before the bar enters the tree, like the
## colours: _ready is what takes the first reading.
func watch(unit: Unit) -> void:
	_unit = unit


func _process(_delta: float) -> void:
	_refresh()


## Shown only while there is a shield to show, so a unit that has spent its own
## - or never had one - carries nothing at all rather than an empty rectangle.
func _refresh() -> void:
	if _unit == null || !is_instance_valid(_unit):
		visible = false
		return

	var ceiling: float = _unit.shield_maximum()
	visible = ceiling > 0.0
	if visible:
		set_ratio(clampf(_unit.shield_points() / ceiling, 0.0, 1.0))
