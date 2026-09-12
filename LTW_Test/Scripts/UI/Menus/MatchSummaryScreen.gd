class_name MatchSummaryScreen
extends Control

## What happened over a whole match, read after it is over.
##
## A screen of its own rather than a second page of the result board, because
## the two answer different questions and are read at different moments: the
## board says WHO WON and is read while the world is still on screen behind it,
## and this says what the match was made of and is read once nobody is in a
## hurry.
##
## **It reads a record rather than a match.** By the time it opens the match
## scene is gone - no PlayerManager, no MatchSession, no units - so everything
## on it comes off the MatchSummary handed over on MenuNavigation. That is what
## lets the whole match be freed the instant Continue is pressed.
##
## The rows are built in code from one prefab, the same shape every other list
## in this project uses. Which STATS are shown is deliberately a first pass and
## is meant to be argued with: they are the numbers that were already being
## counted for free, and anything that turns out to be dull can go without
## anything else changing.

@export_group("References")
@export var _title_label: Label
@export var _subtitle_label: Label
## Header row over the columns, so the labels are authored once in the scene
## rather than built beside the rows.
@export var _row_list: VBoxContainer
## The short "best of the match" block under the table.
@export var _highlight_list: VBoxContainer
@export var _menu_button: Button

@export_group("Settings")
@export var _row_scene: PackedScene
## The prefab for one line of the best-of block under the table.
@export var _highlight_scene: PackedScene
## Colour for the row of whoever was playing at this machine, so a player finds
## themselves in a table of twelve at a glance. The same yellow the corner table
## uses for the same job.
@export var _local_color: Color = Color(1.0, 0.85, 0.35, 1.0)
@export var _winner_color: Color = Color(0.62, 0.88, 0.62, 1.0)
@export var _player_color: Color = Color(0.86, 0.88, 0.92, 1.0)

var _summary: MatchSummary = null


func _ready() -> void:
	_summary = MenuNavigation.take_pending_summary()
	if _menu_button != null:
		_menu_button.pressed.connect(_on_menu_pressed)
		_menu_button.grab_focus()

	if _summary == null:
		# Reachable by running this scene on its own from the editor, and by a
		# match that ended with no MatchStats to record it. Neither is worth a
		# crash: the screen says there is nothing to show and the way out works.
		Log.warn("MatchSummaryScreen opened with no summary, there is nothing to show")
		_draw_empty()
		return

	_draw_heading()
	_build_rows()
	_build_highlights()


func _draw_empty() -> void:
	if _title_label != null:
		_title_label.text = "MATCH SUMMARY"
	if _subtitle_label != null:
		_subtitle_label.text = "No record of that match was kept."


func _draw_heading() -> void:
	if _title_label != null:
		_title_label.text = "MATCH SUMMARY"
	if _subtitle_label == null:
		return

	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s played" % _summary.duration_text())
	parts.append("%d players" % _summary.lines.size())
	if _summary.reached_sudden_death:
		parts.append("reached Sudden Death")
	if !_summary.settings_text.is_empty():
		parts.append(_summary.settings_text)
	_subtitle_label.text = "  -  ".join(parts)


## One row per player, in finishing order - the summary was sorted when it was
## taken, so nothing here decides the order.
func _build_rows() -> void:
	if _row_list == null || _row_scene == null:
		Log.err("MatchSummaryScreen cannot build rows, the list or the prefab is missing")
		return

	for child in _row_list.get_children():
		_row_list.remove_child(child)
		child.queue_free()

	for line in _summary.lines:
		if line == null:
			continue
		var row: MatchSummaryRow = _row_scene.instantiate() as MatchSummaryRow
		if row == null:
			Log.err("MatchSummaryScreen row prefab root does not have a MatchSummaryRow script")
			return
		_row_list.add_child(row)
		row.show_line(line, _color_for(line))


## The local player wins over the winner, because the one thing somebody looks
## for first in a table of twelve is their own row.
func _color_for(line: MatchStatLine) -> Color:
	if line.is_local:
		return _local_color
	if line.slot == _summary.winner_slot:
		return _winner_color
	return _player_color


## The short block under the table: who did the most of each thing.
##
## A LIST rather than a fixed set of labels, so a line nobody scored is left out
## entirely instead of reading "nobody" - a 1v1 that ended in four minutes has
## several of those, and a block full of blanks says less than a short one.
func _build_highlights() -> void:
	if _highlight_list == null:
		return

	for child in _highlight_list.get_children():
		_highlight_list.remove_child(child)
		child.queue_free()

	_add_highlight("Most lives stolen", &"lives_stolen", "")
	_add_highlight("Most creeps sent", &"creeps_sent", "")
	_add_highlight("Most creeps killed", &"creeps_killed", "")
	_add_highlight("Most towers built", &"towers_built", "")
	_add_highlight("Highest income", &"peak_income", "")
	_add_highlight("Richest maze", &"peak_value", " gold")
	_add_highlight("Most gold earned from bounty", &"gold_from_bounty", " gold")


func _add_highlight(title: String, field: StringName, suffix: String) -> void:
	if _highlight_scene == null:
		return
	var best: MatchStatLine = _summary.best_at(field)
	if best == null:
		return

	var row: SummaryHighlightRow = _highlight_scene.instantiate() as SummaryHighlightRow
	if row == null:
		Log.err("MatchSummaryScreen highlight prefab root is not a SummaryHighlightRow")
		return
	_highlight_list.add_child(row)
	row.show_best(
		title,
		best.display_name,
		"%s%s" % [StringUtil.compact_number(int(best.get(field))), suffix],
		_color_for(best)
	)


func _on_menu_pressed() -> void:
	MenuNavigation.to_main_menu(self)
