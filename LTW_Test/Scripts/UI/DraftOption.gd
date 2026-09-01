class_name DraftOption
extends Button

## One of the Ultimates a DRAFT is offering: its name, the four technologies it
## comes with, and the press that takes it.
##
## A prefab rather than a button built in code, for the reason every other card
## square is one: it will gain a picture and a tooltip the day the Ultimates
## have art, and none of that belongs in a loop.
##
## It gives no order of its own. It says which technology was pressed and the
## screen above it hands that to `Commands`, the one road every player order
## takes.

## This option was pressed. Carries the technology by its authored id, which is
## what a command names it with.
signal chosen(tech_id: int)

@export_group("References")
@export var _name_label: Label
@export var _element_label: Label
@export var _requirement_label: Label

var _tech_id: int = TechRegistry.NO_TECH


func _ready() -> void:
	pressed.connect(_on_pressed)


## Draws one Ultimate. The requirement is passed in rather than worked out
## here, because what an Ultimate needs is TechManager's answer and a button
## has no business asking it twice.
func show_tech(tech: TechDefinition, requirement_text: String) -> void:
	if tech == null:
		return
	_tech_id = tech.tech_id
	if _name_label != null:
		_name_label.text = tech.ultimate_name
	if _element_label != null:
		_element_label.text = tech.short_name()
		# The element's own hue, the same one its Research Center square and
		# its towers carry, so the three on offer read apart at a glance.
		_element_label.add_theme_color_override("font_color", tech.element_color())
	if _requirement_label != null:
		_requirement_label.text = requirement_text


func _on_pressed() -> void:
	if _tech_id != TechRegistry.NO_TECH:
		chosen.emit(_tech_id)
