class_name ToggleGridAbility
extends UnitAbility

## Shows or hides the build grid over EVERY maze at once.
##
## **Local only.** The grid is an overlay drawn for one player on one machine:
## the server has no grid at all, and the other players have no business being
## told about yours. So this never becomes a command and never leaves the
## machine - see UnitAbility.is_local_only().
##
## It is an ability rather than a bare key binding because that is where the
## player already looks for what a unit can do: it gets a card slot, a hotkey
## that follows the slot, and a tooltip, all for free and all in the same place
## as everything else the builder does.


## Never a command. This changes a mesh's visibility, nothing else.
func is_local_only() -> bool:
	return true


## Every maze, not only the owner's: where a tower can go is worth reading in
## an opponent's lane as well as your own, and a toggle that left half the
## board in a different state would be a second thing to keep track of.
##
## The unit's OWN grid decides which way the switch goes, because that is the
## one the player thinks of as "the grid". Everything else follows it, so the
## grids cannot drift apart however they got where they are.
func execute(unit: Unit, _target: AbilityTarget) -> void:
	var manager: PlayerManager = References.player_manager
	if unit == null || manager == null:
		return

	var own: BuildGrid = null if unit.area == null else unit.area.build_grid()
	var showing: bool = own.visible if own != null else _any_visible(manager)

	var changed: int = 0
	for area in manager.areas():
		var grid: BuildGrid = area.build_grid()
		if grid == null:
			continue
		grid.visible = !showing
		changed += 1

	Log.info("Build grid toggled", {"visible": !showing, "grids": changed})


## Pointless with no grid anywhere to draw.
func can_execute(unit: Unit) -> bool:
	var manager: PlayerManager = References.player_manager
	return unit != null && manager != null && !manager.areas().is_empty()


## Fallback for a unit standing in no area at all: if any grid is up, the
## switch is "on" and pressing it turns them all off.
func _any_visible(manager: PlayerManager) -> bool:
	for area in manager.areas():
		var grid: BuildGrid = area.build_grid()
		if grid != null && grid.visible:
			return true
	return false
