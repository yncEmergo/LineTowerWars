class_name LobbyRoom
extends Control

## The inside of a lobby: who is in it, and the host's Start button.
##
## It owns nothing. The roster is whatever the server last pushed through the
## `Lobby` autoload, so a player arriving or leaving anywhere redraws this
## screen without it having asked. There is no local copy to keep in step.
##
## Leaving and being thrown out are the same code path on purpose: both end as
## "we are no longer in a lobby", and the only difference is the message carried
## back to the browser. That is what makes the host leaving (D23) need no
## special handling here.
##
## The countdown is the same story. This screen never counts: it displays the
## number the SERVER last announced (D24), so every player in the lobby is
## looking at the same one and nobody can start early by lying about a clock.

@export_group("References")
@export var _title_label: Label
@export var _subtitle_label: Label
## Parent for the slot rows, refilled whenever the lobby changes.
@export var _slot_list: VBoxContainer
## The match rules. Shown to everybody and editable by the host alone
## (multiplayer.md 8.2); it looks after that itself.
@export var _settings_panel: LobbySettingsPanel
@export var _status_label: Label
@export var _start_button: Button
@export var _leave_button: Button

@export_group("Settings")
## The slot row prefab. A node's own prefab stays a PackedScene export.
@export var _slot_scene: PackedScene

var _lobby: LobbyInfo = null
## Whole seconds left on the start countdown, or -1 when none is running. The
## number is the SERVER's (D24) - this only displays what it was last told, so
## nothing here counts on its own.
var _countdown: int = -1

var _config: MenuConfig:
	get:
		return References.menu_config


func _ready() -> void:
	_connect_buttons()
	Lobby.current_lobby_changed.connect(_on_current_lobby_changed)
	Lobby.lobby_closed.connect(_on_lobby_closed)
	Lobby.countdown_changed.connect(_on_countdown_changed)
	Lobby.countdown_cancelled.connect(_on_countdown_cancelled)
	Lobby.request_refused.connect(_set_status)

	var lobby: LobbyInfo = Lobby.current()
	if lobby == null:
		lobby = MenuNavigation.pending_lobby
	if lobby == null:
		# Reachable by running this scene on its own from the editor, which is
		# worth keeping possible, so it stands one in rather than erroring out.
		Log.warn("LobbyRoom opened with no lobby, showing a stand-in")
		lobby = _stand_in_lobby()

	show_lobby(lobby)

	# Why we are back, if a match we were loading fell through. After
	# show_lobby, which writes the ordinary status line over it.
	var notice: String = MenuNavigation.take_pending_notice()
	if !notice.is_empty():
		_set_status(notice)


## Puts a lobby on screen: header, slots and the state of the Start button.
func show_lobby(lobby: LobbyInfo) -> void:
	_lobby = lobby
	if _lobby == null:
		return
	# A countdown we are hearing nothing about is not running. The server sends
	# the lobby and the first number in the same frame, so this cannot blank a
	# live countdown.
	if !_lobby.is_starting:
		_countdown = -1

	if _title_label != null:
		_title_label.text = _lobby.lobby_name
	if _subtitle_label != null:
		_subtitle_label.text = "Free for all  -  %s players" % _lobby.players_text()

	_build_slots()
	# After the slots, because the automatic life total follows the player
	# count and the panel is told what that is.
	if _settings_panel != null:
		_settings_panel.show_lobby(_lobby, _is_host_here())
	_update_start_button()
	_update_status()


## Whether this machine may edit the rules.
##
## The stand-in lobby - this scene opened on its own from the editor - has no
## server and therefore no host, and answering "nobody" there would make the
## whole panel dead in the one situation somebody is looking at it on purpose.
func _is_host_here() -> bool:
	return Lobby.current() == null || Lobby.is_host()


# --- lobby updates --------------------------------------------------------

## Null means we are out of it - left, thrown out, or the server went away.
## The message, if there is one, arrives separately on lobby_closed.
func _on_current_lobby_changed(lobby: LobbyInfo) -> void:
	if lobby == null:
		MenuNavigation.to_lobby_browser(self)
		return
	show_lobby(lobby)


func _on_lobby_closed(reason: String) -> void:
	# Handed across the scene change so the browser can say why we are back.
	MenuNavigation.pending_notice = reason


func _build_slots() -> void:
	if _slot_list == null || _slot_scene == null:
		Log.err("LobbyRoom cannot build slots, the list or the slot prefab is missing")
		return

	for child in _slot_list.get_children():
		_slot_list.remove_child(child)
		child.queue_free()

	for index in range(1, _lobby.max_players + 1):
		var slot: LobbySlot = _slot_scene.instantiate() as LobbySlot
		if slot == null:
			Log.err("LobbyRoom slot prefab root does not have a LobbySlot script")
			return
		_slot_list.add_child(slot)
		_fill_slot(slot, index)


func _fill_slot(slot: LobbySlot, index: int) -> void:
	var player: MatchPlayer = _player_in_slot(index)
	if player == null:
		slot.show_open(index)
		return

	# Two client windows on one machine look identical, so say which is which.
	var label: String = player.display_name
	if player.network_id == Net.peer_id():
		label += "  (you)"
	slot.show_player(index, label, player.network_id == _lobby.host_id)


func _player_in_slot(index: int) -> MatchPlayer:
	for player in _lobby.members:
		if player != null && player.slot == index:
			return player
	return null


## Start belongs to the host alone, and it is the same button as Cancel (D24):
## for those five seconds there is nothing else the host can usefully do, so
## the button says the one thing that is left.
##
## Every state here is also checked on the server. This is the courtesy that
## stops a player pressing a button that would only be refused.
func _update_start_button() -> void:
	if _start_button == null:
		return

	if !Lobby.is_host():
		_start_button.disabled = true
		_start_button.text = "Starting..." if _is_counting() else "Waiting for the host"
		return

	if _is_counting():
		_start_button.disabled = false
		_start_button.text = "Cancel Start (%d)" % _countdown
		return

	_start_button.disabled = !_has_enough_players()
	_start_button.text = "Start Game"


func _update_status() -> void:
	if _is_counting():
		_set_status("The match begins in %d..." % _countdown)
		return
	if !_has_enough_players():
		_set_status("Waiting for players - %d of %d needed to start." % [
			_lobby.player_count(), _config.min_players if _config != null else 2,
		])
		return
	if Lobby.is_host():
		_set_status("Ready. Press Start when everyone is here.")
		return
	_set_status("Ready. Waiting for the host to start the match.")


func _is_counting() -> bool:
	return _countdown >= 0


func _has_enough_players() -> bool:
	if _config == null:
		return _lobby.player_count() >= 2
	return _lobby.player_count() >= _config.min_players


## The number is pushed once per whole second by the server, so everyone in
## the lobby is looking at the same one.
func _on_countdown_changed(seconds_left: int) -> void:
	_countdown = seconds_left
	_update_start_button()
	_update_status()


## A cancelled countdown is not a state to recover from - it never happened,
## and the host may press Start again at once.
func _on_countdown_cancelled(reason: String) -> void:
	_countdown = -1
	_update_start_button()
	_set_status(reason)


func _connect_buttons() -> void:
	if _start_button != null:
		_start_button.pressed.connect(_on_start_pressed)
	if _leave_button != null:
		_leave_button.pressed.connect(_on_leave_pressed)


func _set_status(text_value: String) -> void:
	if _status_label != null:
		_status_label.text = text_value


func _stand_in_lobby() -> LobbyInfo:
	var lobby: LobbyInfo = LobbyInfo.new()
	var host_name: String = LobbyIdentity.display_name()
	lobby.max_players = 2 if _config == null else _config.default_lobby_size
	lobby.lobby_name = (
		host_name if _config == null else _config.default_lobby_name(host_name)
	)
	lobby.add_member(MatchPlayer.create(1, host_name, 0))
	lobby.host_id = 0
	lobby.settings = MatchSettings.defaults(References.game_config)
	return lobby


func _on_start_pressed() -> void:
	if _is_counting():
		Lobby.cancel_start()
		return
	Lobby.start()


## Asking to leave is all this does. We move when the server confirms it, which
## is also what happens when somebody else's leaving closes the lobby.
func _on_leave_pressed() -> void:
	if Lobby.is_in_lobby():
		Lobby.leave()
		return
	MenuNavigation.to_lobby_browser(self)
