class_name HealthBar3D
extends Bar3D

## Worldspace health bar: green for remaining health, red for missing.
##
## Everything about DRAWING a bar lives on Bar3D, which the tower's job bar
## uses too. What is left here is the one thing that is health's alone: whether
## the bar is drawn at all is the player's choice, held on UserSettings.
##
## Every bar answers that question for itself out of the ratio it already has,
## so a unit taking its first hit reveals its own bar with no manager watching.
## Changing the setting mid-match is the one case a bar cannot notice on its
## own, which is what the group is for.

## Every live bar, so the options screen can refresh all of them at once when
## the setting changes. Nothing else uses it, and nothing else should: a bar
## going from full to damaged already updates itself.
const GROUP: String = "health_bars"

const COLOR_MISSING: Color = Color(0.65, 0.13, 0.13, 1.0)
const COLOR_FILL: Color = Color(0.24, 0.80, 0.28, 1.0)


func _ready() -> void:
	fill_color = COLOR_FILL
	empty_color = COLOR_MISSING
	add_to_group(GROUP)
	super()


## Re-reads the player's choice. Called on every ratio change, and on the whole
## group by the options screen when that choice is changed mid-match.
func refresh_visibility() -> void:
	match UserSettings.health_bar_display:
		UserSettings.HealthBarDisplay.ALWAYS:
			visible = true
		UserSettings.HealthBarDisplay.WHEN_DAMAGED:
			visible = _ratio < 1.0
		UserSettings.HealthBarDisplay.NEVER:
			visible = false
		_:
			Log.err("HealthBar3D has a display mode it does not know",
				UserSettings.health_bar_display)
			visible = true


func _on_ratio_changed() -> void:
	refresh_visibility()
