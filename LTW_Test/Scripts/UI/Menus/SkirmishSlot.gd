class_name SkirmishSlot
extends PanelContainer

## One seat in the single player setup screen: who is in it, what colour they
## are, and - for a computer opponent - how hard.
##
## A prefab rather than a row built in code, for the reason LobbySlot is one:
## the row is going to grow. A handicap, a fixed lane, a named personality and a
## remove button all belong here, and none of them wants to be threaded through
## a builder function.
##
## **Deliberately not LobbySlot itself.** The two look alike and answer
## different questions: a lobby row shows somebody who has JOINED and lets only
## your own row choose a colour, where this one is a seat the player is
## CONFIGURING and the difficulty is the whole point of it. Sharing the scene
## would mean a row with half its controls hidden in each of the two places it
## is used, which is how a prefab stops being readable.
##
## Nothing here decides anything. It reports the choice upwards and is redrawn
## from whatever the screen hands back.

## The difficulty on this row was changed. Carries the index into AiConfig.
signal difficulty_chosen(difficulty: int)

@export_group("References")
@export var _index_label: Label
@export var _name_label: Label
## The colour this seat plays in, so the setup screen reads like the lobby does.
@export var _color_swatch: ColorRect
## Shown on an AI row and hidden on the player's own, where there is nothing to
## choose.
@export var _difficulty_option: OptionButton
## What the row is, for a seat with no dropdown: "You".
@export var _role_label: Label

@export_group("Settings")
@export var _local_color: Color = Color(1.0, 0.85, 0.35, 1.0)
@export var _ai_color: Color = Color(0.86, 0.88, 0.92, 1.0)

## Set while the dropdown is being filled in, so writing to it does not read
## back as the player choosing something.
var _applying: bool = false


func _ready() -> void:
	if _difficulty_option != null:
		_difficulty_option.item_selected.connect(_on_difficulty_selected)


## Draws the seat the player themselves sit in: no dropdown, and their own
## colour.
func show_player(slot: int, player_name: String, swatch: Color) -> void:
	_fill(slot, player_name, swatch, _local_color)
	if _difficulty_option != null:
		_difficulty_option.hide()
	if _role_label != null:
		_role_label.show()
		_role_label.text = "You"


## Draws a computer opponent: the difficulties it could be, and the one it is.
func show_ai(slot: int, player_name: String, swatch: Color,
		difficulties: PackedStringArray, chosen: int) -> void:
	_fill(slot, player_name, swatch, _ai_color)
	if _role_label != null:
		_role_label.hide()
	if _difficulty_option == null:
		return

	_applying = true
	_difficulty_option.show()
	_difficulty_option.clear()
	for entry: String in difficulties:
		_difficulty_option.add_item(entry)
	if chosen >= 0 && chosen < difficulties.size():
		_difficulty_option.selected = chosen
	_applying = false


func _fill(slot: int, player_name: String, swatch: Color, text_color: Color) -> void:
	if _index_label != null:
		_index_label.text = str(slot)
	if _name_label != null:
		_name_label.text = player_name
		_name_label.add_theme_color_override("font_color", text_color)
	if _color_swatch != null:
		_color_swatch.color = swatch


func _on_difficulty_selected(index: int) -> void:
	if !_applying:
		difficulty_chosen.emit(index)
