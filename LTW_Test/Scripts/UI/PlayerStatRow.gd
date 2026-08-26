class_name PlayerStatRow
extends HBoxContainer

## One player's line in the stats panel: who they are, and how they are doing.
##
## A prefab rather than labels built in code, for the same reason LobbySlot is
## one: the row is going to grow. A player colour swatch, a ping, a spectate
## click and a highlight for whoever you are currently sending into all belong
## here, and none of them wants to be threaded through a builder function.
##
## The column widths are authored twice, here and on the icon header inside
## match_hud.tscn, and the two have to agree or the header stops sitting over
## the numbers it names. They are sized to the widest thing each column can
## ever hold rather than to today's numbers: three digits of life, four
## characters of compacted income or value ("9.9M"), and a two digit ordinal
## placement ("15th"). Only the name column is elastic, and a name too long
## for it ends in an ellipsis.

@export_group("References")
@export var _name_label: Label
@export var _life_label: Label
@export var _income_label: Label
@export var _value_label: Label
@export var _placement_label: Label

@export_group("Settings")
## The local player, so two windows on one machine are still tellable apart.
@export var _local_color: Color = Color(1.0, 0.85, 0.35, 1.0)
@export var _player_color: Color = Color(0.86, 0.88, 0.92, 1.0)
## Somebody who is out. Their row stays, because their placement is the point.
@export var _eliminated_color: Color = Color(0.5, 0.52, 0.58, 1.0)


## Fills the row in. Everything comes in already decided, so the row itself
## never has to ask who is local or what a number means.
func show_player(player_name: String, state: PlayerState, is_local: bool) -> void:
	if state == null:
		return

	var out: bool = state.placement != 0
	var color: Color = _eliminated_color if out else (
		_local_color if is_local else _player_color
	)

	_write(_name_label, player_name, color)
	_write(_life_label, str(maxi(0, state.lives)), color)
	_write(_income_label, StringUtil.compact_number(state.income), color)
	_write(_value_label, StringUtil.compact_number(state.value), color)
	_write(_placement_label, _placement_text(state.placement), color)


## Nothing until they are out, which is exactly when a placement becomes a
## fact rather than a guess at the current standings.
func _placement_text(placement: int) -> String:
	if placement <= 0:
		return "---"
	return "%d%s" % [placement, _ordinal_suffix(placement)]


## 1st, 2nd, 3rd, 4th. The teens are the exception every ordinal function
## forgets: 11th, 12th and 13th, not 11st.
func _ordinal_suffix(number: int) -> String:
	var last_two: int = number % 100
	if last_two >= 11 && last_two <= 13:
		return "th"
	match number % 10:
		1:
			return "st"
		2:
			return "nd"
		3:
			return "rd"
	return "th"


func _write(label: Label, text_value: String, color: Color) -> void:
	if label == null:
		return
	label.text = text_value
	label.add_theme_color_override("font_color", color)
