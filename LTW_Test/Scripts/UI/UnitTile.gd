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
