class_name TutorialSelectStep
extends TutorialStep

## Finished once the unit named by guide_unit is selected.
##
## The first thing the tutorial asks, before anything costs gold: find your
## builder and select it. The arrows do the telling - one over the builder's
## HUD button, one hovering over the builder itself - and this only checks.


func is_complete(director: TutorialDirector) -> bool:
	return director != null && TutorialGuide.is_selected(guide_unit)


func validate() -> bool:
	var complete: bool = super()
	if guide_unit == Select.NONE:
		Log.err("A lesson waits for a unit to be selected and names none", title)
		complete = false
	return complete
