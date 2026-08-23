class_name UnitTile
extends Button

## One unit's slot in the multi-selection grid.
##
## Clicking it narrows the selection down to that single unit, which is the
## standard way to pull one unit out of a group.
##
## A prefab like CommandSlot, because these will grow icons and per-unit health
## bars rather than staying plain labels.

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
	text = _short_label(new_unit)
	tooltip_text = _tooltip(new_unit)


## Empty tiles are hidden rather than shown blank, which is also what happens
## to units past the grid's capacity: still selected, just not pictured.
func clear() -> void:
	unit = null
	visible = false
	disabled = true
	text = ""
	tooltip_text = ""


## Initials of the unit's name, until real portraits exist.
func _short_label(target: Unit) -> String:
	if target.stats == null:
		return "?"

	var label: String = ""
	for word in target.stats.display_name.split(" ", false):
		label += word.substr(0, 1)
	return label.to_upper().substr(0, 3)


func _tooltip(target: Unit) -> String:
	if target.stats == null:
		return ""
	return "%s\n%d / %d" % [
		target.stats.display_name, target.current_health, target.max_health()
	]


func _on_pressed() -> void:
	if unit == null || !is_instance_valid(unit):
		return
	unit_clicked.emit(unit)
