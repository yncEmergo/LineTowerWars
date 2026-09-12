class_name DraftOption
extends Button

## One of the Ultimates a DRAFT is offering: its picture, its name, the four
## technologies it comes with, and the press that takes it.
##
## It is the Research Center's Ultimate square at the size of a decision. The
## same three things say which tower it is - the element's own hue behind it,
## the Ultimate's own icon over that, and the four technologies under it - so a
## player who has learned to read that row reads this without learning anything
## new. What is different is only that this is one of three choices filling the
## middle of the screen rather than one of twenty squares in a grid.
##
## A prefab rather than a button built in code, for the reason every other card
## square is one: everything on it is content, and none of it belongs in a loop.
##
## **It gives no order and knows no rule.** It says which technology was
## pressed; the screen above hands that to `Commands`, the one road every player
## order takes, and the server refuses it if it is not one of the three.

## This option was pressed. Carries the technology by its authored id, which is
## what a command names it with.
signal chosen(tech_id: int)

## Tint for an option once this player has already chosen. The three stay on
## screen so they can see what they took, and the two they did not take go quiet
## rather than disappearing.
const TAKEN_MODULATE: Color = Color(0.45, 0.45, 0.45, 1.0)
## Tint for the one they DID take, on the same terms every other lit square in
## this HUD is lit: above 1 on purpose.
const CHOSEN_MODULATE: Color = Color(1.35, 1.22, 0.72, 1.0)

@export_group("References")
## The Ultimate tower's own picture. A TextureRect rather than the Button's
## `icon` for the reason TechSlot's is one: a Button draws its icon before its
## children, so a coloured child would cover it.
@export var _icon_rect: TextureRect
## The element's own hue behind everything else, so three strangers read as
## three elements at a glance.
@export var _background: ColorRect
## Fallback for a build with no art for this tower: the element and its path
## number, e.g. "F1".
@export var _fallback_label: Label
@export var _name_label: Label
@export var _element_label: Label
@export var _requirement_label: Label

var _tech_id: int = TechRegistry.NO_TECH


func _ready() -> void:
	# On PRESS rather than release, the same input-latency choice every other
	# square in this HUD carries. See SendTierButton.
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	pressed.connect(_on_pressed)


## Draws one Ultimate.
##
## The requirement is passed in rather than worked out here, because what an
## Ultimate needs is TechManager's answer and a button has no business asking it
## twice. `taken` says whether this player has already chosen, which is what
## turns the row from three buttons into a record of what was picked.
func show_tech(tech: TechDefinition, requirement_text: String, taken: bool) -> void:
	if tech == null:
		return

	_tech_id = tech.tech_id
	# Godot only offers a tooltip while the text is non-empty.
	tooltip_text = "%s\n%s" % [tech.ultimate_name, requirement_text]

	var picture: Texture2D = tech.ultimate_icon()
	if _icon_rect != null:
		_icon_rect.texture = picture
		_icon_rect.visible = picture != null
	if _fallback_label != null:
		_fallback_label.visible = picture == null
		_fallback_label.text = tech.grid_label()
	if _background != null:
		_background.color = tech.element_color()
	if _name_label != null:
		_name_label.text = tech.ultimate_name
	if _element_label != null:
		_element_label.text = tech.short_name()
	if _requirement_label != null:
		_requirement_label.text = requirement_text

	disabled = taken
	modulate = Color.WHITE if !taken else TAKEN_MODULATE


## Marks this as the one that was taken. Separate from show_tech because the
## screen above is what knows which of the three it was - this button only ever
## reported the press.
func mark_chosen() -> void:
	modulate = CHOSEN_MODULATE


func _on_pressed() -> void:
	if _tech_id != TechRegistry.NO_TECH:
		chosen.emit(_tech_id)
