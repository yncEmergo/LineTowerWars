class_name StallPanel
extends Control

## The screen a lockstep STALL puts up: who the match is waiting for, how long
## it has been waiting, and a way out.
##
## **A stall is a hard freeze of the whole world, and until this existed it was
## completely silent.** `LockstepService` holds the tree the moment a peer's word
## for a turn has not arrived, which stops the camera, the HUD and
## `CommandController` - and `GameMenu` opens off `CommandController`, so the
## player could not even reach the menu that lets them leave. A peer that is hard
## killed takes ENet about five and a half seconds to notice, and the disconnect
## grace runs on top of that, so the honest description of the old behaviour is
## "the game freezes for fifteen seconds with no message and no way out".
##
## Every lockstep RTS ships this panel. It is the cheap half of degrading
## gracefully rather than freezing - the expensive half is lengthening the turn
## for a slow peer the way Age of Empires did, which this does not do.
##
## **It runs while the tree is paused**, which is what PROCESS_MODE_ALWAYS is
## for, on exactly the same grounds as `DraftPanel`.
##
## It POLLS rather than listening to `turn_stalled` alone, because it has to
## answer two questions the signal cannot: whether the stall is still going, and
## how long it has lasted. One signal fires at the start and nothing marks the
## end, so a panel driven by it would have to be told to hide by something else.

@export_group("References")
## Everything that is hidden between stalls, which is all of it. Separate from
## this node so the node itself stays in the tree doing the polling.
@export var _panel: Control
## Names the peers whose turn has not arrived.
@export var _status_label: Label
## How long the wait has lasted, so a player can tell a hiccup from a crash.
@export var _elapsed_label: Label
## Leaves the match. The whole reason this panel has to exist rather than a
## label: while the tree is held there is no other way out.
@export var _leave_button: Button

@export_group("Settings")
## How long a stall has to last before this appears, in seconds.
##
## **Not zero, and that matters.** A stall of a tick or two is ordinary - peers
## finish loading at different moments, so one at match start is close to
## guaranteed - and a panel that flashed up for every one of them would be worse
## than the freeze it reports. This is long enough that a healthy match never
## shows it and short enough that a real one is explained quickly.
@export var _appear_after_seconds: float = 0.6

## How long the current stall has lasted, or 0 when there is none.
var _stalled_for: float = 0.0


func _ready() -> void:
	# The one screen besides the draft that must answer while the world is held
	# still - and unlike the draft, this one is the ONLY way out. See
	# MatchSession.hold.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _panel != null:
		_panel.hide()
	if _leave_button != null:
		_leave_button.pressed.connect(_on_leave_pressed)


func _process(delta: float) -> void:
	if !Lockstep.is_stalled():
		_stalled_for = 0.0
		if _panel != null && _panel.visible:
			_panel.hide()
		return

	# Wall clock on purpose. The match clock is stopped - that is what a stall
	# IS - so it cannot measure its own length, and this number is for a human
	# rather than for the simulation.
	_stalled_for += delta
	if _stalled_for < _appear_after_seconds:
		return

	if _panel != null && !_panel.visible:
		_panel.show()
	_refresh()


func _refresh() -> void:
	if _status_label != null:
		_status_label.text = "Waiting for %s" % _waiting_for_text()
	if _elapsed_label != null:
		_elapsed_label.text = "%.0f seconds" % _stalled_for


## Who the match is waiting on, by the name they chose rather than by peer id.
##
## A peer that has already been forgotten by the lobby still has to be named
## somehow, because being unable to say who is missing is most of what made the
## freeze frightening.
func _waiting_for_text() -> String:
	var names: PackedStringArray = PackedStringArray()
	var session: MatchSession = References.match_session
	var setup: MatchSetup = null if session == null else session.setup()

	for peer: int in Lockstep.waiting_on():
		var found: String = ""
		if setup != null:
			for player: MatchPlayer in setup.players:
				if player != null && player.network_id == peer:
					found = player.display_name
					break
		if found.is_empty():
			found = "the server" if peer == NetworkService.SERVER_PEER_ID else "a player"
		names.append(found)

	if names.is_empty():
		return "the match"
	return ", ".join(names)


## Leaving is a DELIBERATE leave, exactly as the in-game menu's is: telling the
## server first is what stops it reading as a crash and holding everybody else
## through the disconnect grace for nothing. See GameMenu.
func _on_leave_pressed() -> void:
	MatchStart.leave_match()
	MenuNavigation.to_main_menu(self)
