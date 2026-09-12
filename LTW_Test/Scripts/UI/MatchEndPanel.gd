class_name MatchEndPanel
extends Control

## The end of a match, over the match: who finished where, and the one button
## out of it.
##
## It draws the SAME table the corner panel draws all game, in the middle of the
## screen and in finishing order, and hides the corner one while it is up - the
## placements are the point at that moment, and two copies of them on one screen
## is one too many.
##
## **It owns no rule and decides nothing.** PlayerManager settles the standings
## and says when the match is over; this is told. What it reads off MatchStats
## is a record that was already taken, and the button hands that record to the
## summary screen rather than working anything out on the way.
##
## Two ways it can learn the match ended, and both are needed:
##
##   the SIGNAL, which fires on every machine that runs the world. Under
##   lockstep that is every peer, so this is the whole story for the shipped
##   game and for a single player run.
##
##   the STANDINGS, watched as a safety net for a replication client, which
##   simulates nothing and is told its placement in the snapshot instead. The
##   latch means whichever arrives first is the one that counts.

@export_group("References")
## Everything that is hidden until the match is over. Separate from this node so
## the node itself stays in the tree answering signals.
@export var _panel: Control
@export var _title_label: Label
@export var _subtitle_label: Label
## Parent for the rows, filled once. Nothing here ever changes afterwards: the
## match is over and no number on it can move again.
@export var _row_list: VBoxContainer
@export var _continue_button: Button
## The corner table, hidden while this is up. Held rather than found, so nothing
## has to know where the HUD parents it.
@export var _corner_panel: Control

@export_group("Settings")
## The row prefab, shared with the corner panel: the same row, in a bigger box.
@export var _row_scene: PackedScene

## So the result is only ever drawn once, whichever of the two roads reached it.
var _shown: bool = false

var _players: PlayerManager:
	get:
		return References.player_manager

var _session: MatchSession:
	get:
		return References.match_session


func _ready() -> void:
	# A match is not paused when it ends, but something else may be holding the
	# world - a stall, above all - and a player who has just won should not have
	# to wait for a packet to be told so.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _panel != null:
		_panel.hide()
	if _continue_button != null:
		_continue_button.pressed.connect(_on_continue_pressed)
	# Deferred for the reason PlayerStatsPanel's wiring is: the player states are
	# created in Main._ready, which runs after every child's _ready.
	_connect_match.call_deferred()


func _connect_match() -> void:
	var manager: PlayerManager = _players
	var session: MatchSession = _session
	if manager == null || session == null:
		Log.warn("MatchEndPanel found no PlayerManager or MatchSession, it can never open")
		return

	manager.match_ended.connect(_on_match_ended)
	for slot in range(1, session.player_count() + 1):
		var state: PlayerState = manager.state_for(slot)
		if state != null:
			state.standing_changed.connect(_on_standing_changed)


func _on_match_ended(winner_slot: int) -> void:
	_open(winner_slot)


## The safety net. A replication client is never told the match ended, only that
## its placement changed - so the same question PlayerManager asks itself is
## asked here, over numbers that DO arrive in the snapshot.
##
## **It waits for a WINNER and not merely for the match to be over**, and that
## is not defensive coding, it is the race this net kept losing. Standings are
## settled one player at a time: the moment the last loser is given their
## placement the match IS over by every test, and the survivor has not been
## given first place yet. Opening there names a winner of 0, which draws DEFEAT
## on the screen of the player who just won. The signal fires again a line
## later with the answer on it.
func _on_standing_changed() -> void:
	if _shown:
		return
	var manager: PlayerManager = _players
	if manager == null || !manager.is_match_over():
		return
	var winner: int = _winner_from_standings(manager)
	if winner != 0:
		_open(winner)


## Whoever holds first place, for the road that was not handed a winner.
func _winner_from_standings(manager: PlayerManager) -> int:
	var session: MatchSession = _session
	if session == null:
		return 0
	for slot in range(1, session.player_count() + 1):
		var state: PlayerState = manager.state_for(slot)
		if state != null && state.placement == 1:
			return slot
	return 0


func _open(winner_slot: int) -> void:
	if _shown:
		return
	_shown = true

	if _corner_panel != null:
		_corner_panel.hide()
	if _panel != null:
		_panel.show()
	_draw_heading(winner_slot)
	_build_rows()
	if _continue_button != null:
		_continue_button.grab_focus()
	Log.info("Match over screen shown", {"winner": winner_slot})


## Says what happened to YOU first and what happened to the match second, which
## is the order a player reads it in. A machine that plays no slot - a spectator
## later, a dedicated server that somehow drew a HUD - is told the result
## without being told it was theirs.
func _draw_heading(winner_slot: int) -> void:
	var session: MatchSession = _session
	if _title_label != null:
		if session != null && session.is_local_player(winner_slot):
			_title_label.text = "VICTORY"
		elif session != null && session.local_slot() != 0:
			_title_label.text = "DEFEAT"
		else:
			_title_label.text = "MATCH OVER"

	if _subtitle_label == null:
		return
	if session == null || winner_slot == 0:
		_subtitle_label.text = ""
		return
	_subtitle_label.text = "%s wins." % session.display_name_for(winner_slot)


## In FINISHING ORDER, unlike the corner table, which keeps slot order all match
## so it does not reshuffle itself as players die. Here the order IS the result.
func _build_rows() -> void:
	if _row_list == null || _row_scene == null:
		Log.err("MatchEndPanel cannot build rows, the list or the row prefab is missing")
		return

	var manager: PlayerManager = _players
	var session: MatchSession = _session
	if manager == null || session == null:
		return

	for child in _row_list.get_children():
		_row_list.remove_child(child)
		child.queue_free()

	for slot in _finishing_order(manager, session):
		var state: PlayerState = manager.state_for(slot)
		if state == null:
			continue
		var row: PlayerStatRow = _row_scene.instantiate() as PlayerStatRow
		if row == null:
			Log.err("MatchEndPanel row prefab root does not have a PlayerStatRow script")
			return
		_row_list.add_child(row)
		row.show_player(
			session.display_name_for(slot), state, session.is_local_player(slot)
		)


## Slots by placement, best first, and by slot within a placement so two
## machines draw the same table the same way round.
func _finishing_order(manager: PlayerManager, session: MatchSession) -> Array[int]:
	var slots: Array[int] = []
	for slot in range(1, session.player_count() + 1):
		if manager.state_for(slot) != null:
			slots.append(slot)

	slots.sort_custom(func(a: int, b: int) -> bool:
		var left: int = manager.state_for(a).placement
		var right: int = manager.state_for(b).placement
		# A placement of 0 is somebody still standing, which after the match is
		# decided means nobody - but a match abandoned early can reach here, and
		# an unplaced player belongs at the bottom rather than at the top.
		left = left if left > 0 else 9999
		right = right if right > 0 else 9999
		if left != right:
			return left < right
		return a < b
	)
	return slots


## Out of the match and into the summary, carrying the record with it.
##
## The record is TAKEN rather than read, so the match scene can go: everything
## the next screen draws is already in the resource by the time this returns.
## Leaving is MatchStart's job and is the same call the in-match menu makes -
## goodbye first, socket second, so a deliberate leave does not look like a
## crash to the other players.
func _on_continue_pressed() -> void:
	var summary: MatchSummary = null
	if References.match_stats != null:
		summary = References.match_stats.take_summary()
	else:
		Log.warn("MatchEndPanel found no MatchStats, the summary will be empty")

	MatchStart.leave_match()
	MenuNavigation.to_match_summary(self, summary)
