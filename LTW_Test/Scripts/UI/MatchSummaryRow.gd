class_name MatchSummaryRow
extends HBoxContainer

## One player's line on the summary screen.
##
## A prefab rather than labels built in code, for the reason PlayerStatRow is
## one: the columns are going to be argued with. Which numbers are worth a
## column is the open question about this whole screen, and moving one should be
## editing a scene rather than editing a loop.
##
## The column widths are authored here and again on the header inside
## match_summary.tscn, and the two have to agree or the header stops sitting
## over the numbers it names - the same duplication PlayerStatRow already
## carries, and worth the same trade.
##
## It reads a MatchStatLine and nothing else. The match it describes is long
## gone by the time this is filled in.

@export_group("References")
@export var _placement_label: Label
@export var _name_label: Label
@export var _ultimate_label: Label
@export var _sent_label: Label
@export var _killed_label: Label
@export var _stolen_label: Label
@export var _lost_label: Label
@export var _towers_label: Label
@export var _income_label: Label
@export var _spent_label: Label


## Fills the row in. The colour comes in already decided, because who is worth
## highlighting is a question about the whole table rather than about one row.
func show_line(line: MatchStatLine, color: Color) -> void:
	if line == null:
		return

	_write(_placement_label, line.placement_text(), color)
	_write(_name_label, line.display_name, color)
	_write(_ultimate_label, _ultimate_text(line), color)
	_write(_sent_label, StringUtil.compact_number(line.creeps_sent), color)
	_write(_killed_label, StringUtil.compact_number(line.creeps_killed), color)
	_write(_stolen_label, str(line.lives_stolen), color)
	_write(_lost_label, str(line.lives_lost), color)
	_write(_towers_label, _tower_text(line), color)
	_write(_income_label, StringUtil.compact_number(line.peak_income), color)
	_write(_spent_label, StringUtil.compact_number(line.gold_spent()), color)


## Built, sold and destroyed in one cell, because the three only mean anything
## against each other: eight towers built and six sold is a very different match
## from eight built and none.
func _tower_text(line: MatchStatLine) -> String:
	return "%d / %d / %d" % [line.towers_built, line.towers_sold, line.towers_lost]


## What they opened on. The first is the one that matters - the free allowance
## buys exactly one Ultimate - and a match long enough to finish a second says
## so with a plus rather than by growing the column.
func _ultimate_text(line: MatchStatLine) -> String:
	if line.ultimates.is_empty():
		return "-"
	if line.ultimates.size() == 1:
		return line.ultimates[0]
	return "%s  +%d" % [line.ultimates[0], line.ultimates.size() - 1]


func _write(label: Label, text_value: String, color: Color) -> void:
	if label == null:
		return
	label.text = text_value
	label.add_theme_color_override("font_color", color)
