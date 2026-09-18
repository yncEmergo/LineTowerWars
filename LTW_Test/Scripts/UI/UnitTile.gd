class_name UnitTile
extends Button

## One unit's slot in the multi-selection grid.
##
## Clicking it narrows the selection down to that single unit, which is the
## standard way to pull one unit out of a group.
##
## A prefab like CommandSlot, because these will grow per-unit health bars
## rather than staying plain buttons.

signal unit_clicked(unit: Unit)

@export_group("References")
## Border drawn over the icon while this unit is in the active subgroup.
##
## A child laid over the button rather than a swapped stylebox. The prefab's
## own normal and hover boxes are theme overrides already, so a second pair
## would have to be kept in step with them - and neither sets a content margin,
## so each side falls back to its BORDER WIDTH and a thicker border would
## silently change the padding and jump the icon. See CLAUDE.md.
@export var _highlight: Control

var unit: Unit


func _ready() -> void:
	pressed.connect(_on_pressed)
	clear()


func set_unit(new_unit: Unit) -> void:
	if new_unit == null || !is_instance_valid(new_unit):
		clear()
		return

	unit = new_unit
	visible = true
	disabled = false
	# Tiles are pooled and refilled rather than freed, so a mark left behind by
	# the last selection would reappear on an unrelated unit. Cleared HERE as
	# well as in clear(), because this is the path a refill takes.
	set_highlighted(false)
	# The prefab sets expand_icon, without which a Button grows to fit whatever
	# it is given - see CommandSlot for the same trap.
	icon = new_unit.stats.icon if new_unit.stats != null else null
	tooltip_text = _tooltip(new_unit)


## Empty tiles are hidden rather than shown blank, which is also what happens
## to units past the grid's capacity: still selected, just not pictured.
func clear() -> void:
	unit = null
	visible = false
	disabled = true
	icon = null
	tooltip_text = ""
	set_highlighted(false)


## Whether this unit is in the active subgroup.
##
## A BORDER rather than a size change, which is what Warcraft draws: the strip
## is a fixed grid, so a bigger tile would reflow the whole row every time the
## subgroup was cycled - and the point of the strip is that it holds still.
func set_highlighted(value: bool) -> void:
	if _highlight != null:
		_highlight.visible = value


func _tooltip(target: Unit) -> String:
	if target.stats == null:
		return ""
	return "%s\n%d / %d" % [
		target.stats.display_name, target.display_health(), target.max_health()
	]


func _on_pressed() -> void:
	if unit == null || !is_instance_valid(unit):
		return
	unit_clicked.emit(unit)
