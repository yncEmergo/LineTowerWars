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


func is_queueable() -> bool:
	return true


## The one ability where queueing asks LESS than pressing does, and the gold is
## the whole of the difference.
##
## A tower is paid for at the moment the builder starts it, not when the button
## was pressed - so a chain of five towers on one tower's worth of gold is a
## perfectly sensible thing to ask for: income arrives while the builder walks,
## and one that still cannot be paid for when its turn comes is dropped there
## with a warning. The TECHNOLOGY requirement is not like that at all: a tower
## nobody has researched is one the player may not build, now or in four
## towers' time, so it is still refused here.
func can_queue(unit: Unit) -> bool:
	if unit == null || tower_stats == null || !unit.has_method("order_build"):
		return false
	return _owner_has_tech(unit)


## Done the moment the tower is STARTED, which is what the builder's pending
## order going empty means - see game_rules.md: the builder places a tower and
## is free immediately, it never stays to construct.
##
## An order the builder refused on arrival - the spot was taken, the gold ran
## out - clears the same field, and that is the same answer on purpose: either
## way this task is over and the next one should start.
func is_task_complete(unit: Unit, _target: AbilityTarget) -> bool:
	if unit == null || !unit.has_method("has_pending_build"):
		return true
	return !unit.has_pending_build()


func _time_label() -> String:
	return "Build time"
