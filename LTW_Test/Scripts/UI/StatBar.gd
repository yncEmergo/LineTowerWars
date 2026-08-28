class_name StatBar
extends Control

## One flat bar on the HUD: a trough with a fill that runs left to right.
##
## Two ColorRects rather than a themed ProgressBar. A ProgressBar's fill is a
## StyleBox, which is a Resource and so shared between every instance of this
## prefab - colouring one bar green and the next gold would mean duplicating a
## StyleBox per bar at runtime anyway. Anchoring a rectangle is the same effect
## with nothing to duplicate and nothing to theme.
##
## The colour is an @export rather than a constant because the same prefab is
## the health bar, the mana bar and the job bar, and which is which is a
## property of where it was placed. Placeholder values either way - see the
## look rules in game_rules.md.

@export_group("References")
## The part that grows. Its right anchor IS the ratio, so the fill follows the
## bar's width for free at any panel size.
@export var _fill: ColorRect

@export_group("Settings")
@export var fill_color: Color = Color(0.24, 0.80, 0.28, 1.0)

var _ratio: float = 1.0


func _ready() -> void:
	if _fill == null:
		Log.err("StatBar has no fill assigned in its prefab", name)
		return
	_fill.color = fill_color
	_apply()


## Sets the filled proportion, 0 to 1.
func set_ratio(ratio: float) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _ratio):
		return
	_ratio = clamped
	_apply()


func _apply() -> void:
	if _fill == null:
		return
	_fill.anchor_right = _ratio
	# The anchor moves the rectangle's RIGHT edge; the offset has to be put
	# back to zero or the fill keeps whatever width it was authored at and the
	# anchor only slides it sideways.
	_fill.offset_right = 0.0
