class_name UpgradeTowerAbility
extends TowerOrderAbility

## Turns the tower it sits on into the next one up its line.
##
## IMMEDIATE targeting: there is nothing to aim at. The tower is already
## standing on the cell the upgrade will occupy, which is the whole reason
## upgrading is a different thing from building - it needs no placement test,
## it can never block a maze, and it can never be refused for want of room.
##
## **An upgrade is an ability on the TOWER, not an entry in the build menu.**
## That is what keeps the builder's card four buttons long however deep the
## roster grows: a player follows one line by pressing the tower they
## already own, rather than hunting a tier in a menu. A tower that splits into
## two branches simply carries two of these, and the Elemental Core - which
## splits ten ways - carries them behind one submenu button.
##
## The ability names only the tower ABOVE it. Nothing here knows or cares what
## tower it is sitting on, so one .tres per rung is all a branch costs, and a
## rung inserted into a line later touches exactly its two neighbours.
##
## Stateless like every ability: the countdown, the cancel and the gold all
## belong to the tower, see Building.upgrade_to().


func execute(unit: Unit, _target: AbilityTarget) -> void:
	if unit == null:
		return
	if tower_stats == null:
		Log.err("UpgradeTowerAbility has no tower stats assigned", display_name)
		return

	var building: Building = unit as Building
	if building == null:
		Log.err("UpgradeTowerAbility was run on something that is not a building", unit.name)
		return
	building.upgrade_to(tower_stats)


## Greyed out while the tower is busy being something else, and while its owner
## cannot pay. Both are re-checked by the tower itself when the order arrives,
## since gold can be spent between the button lighting up and the click.
func can_execute(unit: Unit) -> bool:
	if unit == null || tower_stats == null:
		return false

	var building: Building = unit as Building
	if building == null:
		return false
	if building.is_under_construction() || building.is_selling() || building.is_upgrading():
		return false

	return _owner_has_tech(unit) && _owner_can_afford(unit)


func _time_label() -> String:
	return "Upgrade time"
