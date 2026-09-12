class_name SummaryHighlightRow
extends HBoxContainer

## One "best of the match" line on the summary screen: what the superlative was,
## who took it, and with what number.
##
## A prefab for the same reason every other row in this project is one, and this
## one earns it more than most: what these lines SAY is the part of the summary
## most likely to change, and a row built in a loop would put the layout inside
## the loop with it.

@export_group("References")
@export var _title_label: Label
@export var _name_label: Label
@export var _value_label: Label


## Everything already decided: which superlative, who won it, what it was worth
## and what colour that player is drawn in.
func show_best(title: String, player_name: String, value_text: String,
		color: Color) -> void:
	if _title_label != null:
		_title_label.text = title
	if _name_label != null:
		_name_label.text = player_name
		_name_label.add_theme_color_override("font_color", color)
	if _value_label != null:
		_value_label.text = value_text
