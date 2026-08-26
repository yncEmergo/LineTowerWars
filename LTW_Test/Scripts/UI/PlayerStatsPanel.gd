class_name PlayerStatsPanel
extends PanelContainer

## Everybody in the match and how they are doing: lives, income, what they have
## built, and where they finished once they are out.
##
## EVERY player, not just the local one, because almost nothing here is worth
## knowing in isolation. A life is stolen rather than lost, so your gain is
## somebody's loss; income and value are only meaningful against what the other
## players have; and a placement is the whole record of a match that has no end
## screen yet.
##
## Redrawn from a signal rather than polled: the four numbers on it change on
## discrete events - a leak, an income tick, a tower going up - and PlayerState
## already says so.
##
## **The name is a placeholder.** game_rules.md wants an anonymous mode where a
## player is known by their COLOUR instead, chosen as part of a game mode
## selection that does not exist yet, and player colours themselves are still
## unscheduled (multiplayer.md L1). Until both land, this is the display name.
##
## Connects on a deferred call rather than straight away, because the player
## states are created in Main._ready, which runs after every child's _ready.

@export_group("References")
## Parent for the rows, refilled whenever anything on them changes.
@export var _row_list: VBoxContainer
## The status bar beside this panel. The two sit in one band across the top of
## the screen, so this one is never allowed to be shorter than that one - which
## matters most once the rows can be toggled away and only the header is left.
##
## Taken from the bar rather than written down twice, so changing the bar's
## font or padding moves both and neither can drift.
@export var _height_source: Control

@export_group("Settings")
## The row prefab. A node's own prefab stays a PackedScene export.
@export var _row_scene: PackedScene

## Slots in the order they are drawn, which is slot order and never changes
## during a match - a table that reorders itself as players die is unreadable.
var _slots: Array[int] = []


func _ready() -> void:
	_match_source_height()
	if _height_source != null:
		_height_source.minimum_size_changed.connect(_match_source_height)
	_connect_states.call_deferred()


## Holds this panel to at least the height of the bar beside it. Follows the
## bar's own minimum rather than its current size, which is already known this
## early and does not wait for a layout pass.
func _match_source_height() -> void:
	if _height_source == null:
		return
	custom_minimum_size.y = _height_source.get_combined_minimum_size().y


func _connect_states() -> void:
	var manager: PlayerManager = References.player_manager
	var session: MatchSession = References.match_session
	if manager == null || session == null:
		Log.err("PlayerStatsPanel found no PlayerManager or MatchSession on References")
		return

	_slots.clear()
	for slot in range(1, session.player_count() + 1):
		var state: PlayerState = manager.state_for(slot)
		if state == null:
			continue
		_slots.append(slot)
		# One handler for every signal on every player: the table is rebuilt
		# whole, so which number moved does not matter.
		state.lives_changed.connect(_on_changed)
		state.income_changed.connect(_on_changed)
		state.standing_changed.connect(_redraw)

	_redraw()


func _on_changed(_value: int) -> void:
	_redraw()


func _redraw() -> void:
	if _row_list == null || _row_scene == null:
		Log.err("PlayerStatsPanel cannot build rows, the list or the row prefab is missing")
		return

	var manager: PlayerManager = References.player_manager
	var session: MatchSession = References.match_session
	if manager == null || session == null:
		return

	for child in _row_list.get_children():
		_row_list.remove_child(child)
		child.queue_free()

	for slot in _slots:
		var state: PlayerState = manager.state_for(slot)
		if state == null:
			continue
		var row: PlayerStatRow = _row_scene.instantiate() as PlayerStatRow
		if row == null:
			Log.err("PlayerStatsPanel row prefab root does not have a PlayerStatRow script")
			return
		_row_list.add_child(row)
		row.show_player(
			session.display_name_for(slot), state, session.is_local_player(slot)
		)
