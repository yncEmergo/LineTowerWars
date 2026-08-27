class_name BuildTowerAbility
extends TowerOrderAbility

## Places one specific tower.
##
## PLACEMENT targeting, so choosing it shows a snapped footprint preview that
## turns red where the tower cannot go. The actual legality test lives on
## PlayerArea, because it depends on that area's occupied cells and on a creep
## path still existing afterwards.
##
## Only ever names a tower at the BOTTOM of a chain - the three 10g Basic
## towers, and the 200g Elemental Core. Everything above them is reached by
## upgrading the one below it, so the build menu stays four buttons long however
## many tiers the roster grows. See UpgradeTowerAbility.
##
## Everything about describing the tower it names is TowerOrderAbility's.


func execute(unit: Unit, target: AbilityTarget) -> void:
	if unit == null || !target.has_position:
		return
	if tower_stats == null:
		Log.err("BuildTowerAbility has no tower stats assigned", display_name)
		return
	if !unit.has_method("order_build"):
		return
	unit.order_build(tower_stats, target.position)


func can_execute(unit: Unit) -> bool:
	if unit == null || tower_stats == null || !unit.has_method("order_build"):
		return false
	return _owner_has_tech(unit) && _owner_can_afford(unit)


func _time_label() -> String:
	return "Build time"
