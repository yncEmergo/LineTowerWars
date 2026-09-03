class_name LobbyBrowser
extends Control

## The list of open lobbies, and the way into a new one.
##
## Modelled on the Warcraft III custom game list: rows of name, host, players
## and status, one selected at a time, join or create.
##
## The list is now real. It is pushed by the server through the `Lobby`
## autoload, not polled - create, join and leave anywhere update every browser
## within a frame or two, and Refresh only redraws what was already pushed.
##
## This screen is also where a client meets the network (D20): the connection is
## opened when the browser opens and closed on the way out, so a player who only
## ever presses Play never opens a socket.

@export_group("References")
## Parent for the rows. Emptied and refilled on every list update.
@export var _lobby_list: VBoxContainer
## Shown instead of the list when no lobby came back.
@export var _empty_label: Label
## One line under the list saying what the browser is currently doing.
@export var _status_label: Label
@export var _join_button: Button
@export var _create_button: Button
@export var _refresh_button: Button
@export var _back_button: Button

@export_group("Create Lobby")
## Overlay asking for a name and a player count. Hidden until Create is pressed.
@export var _create_panel: Control
@export var _lobby_name_input: LineEdit
@export var _player_count_spin: SpinBox
@export var _create_confirm_button: Button
@export var _create_cancel_button: Button

@export_group("Settings")
## The row prefab. A node's own prefab stays a PackedScene export.
@export var _entry_scene: PackedScene

var _selected: LobbyInfo = null
var _entry_group: ButtonGroup = ButtonGroup.new()
## Set while a request is outstanding, so a refused create can put the dialog
## back rather than leaving the player looking at a browser that ignored them.
var _pending_action: String = ""

var _config: MenuConfig:
	get:
		return References.menu_config


func _ready() -> void:
	if _config == null:
		Log.err("LobbyBrowser found no MenuConfig on References")
	_connect_buttons()
	_setup_create_panel()
	_connect_network()
	_ensure_connected()
	refresh()

	# Why we are back, if we were thrown out of a lobby rather than having
	# opened the browser ourselves.
	var notice: String = MenuNavigation.take_pending_notice()
	if !notice.is_empty():
		_set_status(notice)


## Puts a list of lobbies on screen, replacing whatever was there.
func set_lobbies(lobbies: Array[LobbyInfo]) -> void:
	_clear_selection()
	_clear_rows()

	for lobby in lobbies:
		_add_row(lobby)

	var is_empty: bool = lobbies.is_empty()
	if _empty_label != null:
		_empty_label.visible = is_empty
	if _lobby_list != null:
		_lobby_list.visible = !is_empty


## Redraws from what the server last pushed. There is nothing to ask for: the
## list arrives unprompted whenever it changes, so this is a repaint, not a
## request.
func refresh() -> void:
	set_lobbies(Lobby.lobbies())
	_update_status()


# --- network --------------------------------------------------------------

func _connect_network() -> void:
	Net.status_changed.connect(_on_network_status_changed)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected_from_server.connect(_on_server_disconnected)
	Net.attempting_address.connect(_on_attempting_address)

	Lobby.lobby_list_changed.connect(_on_lobby_list_changed)
	Lobby.current_lobby_changed.connect(_on_current_lobby_changed)
	Lobby.request_refused.connect(_on_request_refused)


func _ensure_connected() -> void:
	if Net.status() != NetworkService.Status.OFFLINE:
		return
	var result: NetworkService.Result = Net.join()
	if result != NetworkService.Result.OK:
		_set_status("Cannot connect: %s" % NetworkService.describe(result))


func _on_lobby_list_changed(lobbies: Array[LobbyInfo]) -> void:
	set_lobbies(lobbies)
	_update_status()


## Landing in a lobby is what a successful create or join looks like: the server
## does not answer "yes", it simply tells us which lobby we are in.
func _on_current_lobby_changed(lobby: LobbyInfo) -> void:
	if lobby == null:
		return
	_pending_action = ""
	MenuNavigation.to_lobby_room(self, lobby)


func _on_request_refused(reason: String) -> void:
	_set_status(reason)
	# A refused create means the dialog was dismissed for nothing. Put it back
	# with what they typed still in it.
	if _pending_action == "create" && _create_panel != null:
		_create_panel.show()
	_pending_action = ""


func _on_network_status_changed(_new_status: NetworkService.Status) -> void:
	_update_status()


## Says what was actually TRIED, not where we would have started. With more than
## one address in the list, "is the server running at 127.0.0.1?" would be true
## of one attempt out of several and misleading about the rest.
func _on_connection_failed(result: NetworkService.Result) -> void:
	var detail: String = Net.refusal_detail()
	if !detail.is_empty():
		_set_status(detail)
		return

	var tried: PackedStringArray = Net.attempted_addresses()
	if tried.size() > 1:
		_set_status("%s - tried %s on port %d." % [
			NetworkService.describe(result), ", ".join(tried), _server_port(),
		])
		return
	_set_status("%s - is the server running at %s?" % [
		NetworkService.describe(result), _server_text(),
	])


func _on_attempting_address(address: String, index: int, of: int) -> void:
	if of <= 1:
		_set_status("Connecting to %s:%d..." % [address, _server_port()])
		return
	_set_status("Looking for a server: %s (%d of %d)..." % [
		address, index, of,
	])


func _on_server_disconnected() -> void:
	_set_status("The server closed the connection.")


func _update_status() -> void:
	_update_buttons()
	match Net.status():
		NetworkService.Status.CONNECTING:
			_set_status("Connecting to %s..." % _server_text())
		NetworkService.Status.CONNECTED:
			_set_status(_connected_text())
		NetworkService.Status.HOSTING:
			_set_status("This process is the server.")
		_:
			_set_status("Not connected.")


func _connected_text() -> String:
	var count: int = Lobby.lobbies().size()
	if count == 0:
		return "Connected to %s. No open lobbies - create one." % _server_text()
	return "Connected to %s. %d open %s." % [
		_server_text(), count, "lobby" if count == 1 else "lobbies",
	]


## The address this screen should NAME right now: the one being dialled while a
## walk is in progress, and the one that would be dialled first before any has
## been. Net is asked first because only it knows how far along the list we are.
func _server_text() -> String:
	var config: NetworkConfig = References.network_config
	if config == null:
		return "the server"
	var address: String = Net.current_address()
	if address.is_empty():
		address = config.resolved_address()
	return "%s:%d" % [address, config.resolved_port()]


func _server_port() -> int:
	var config: NetworkConfig = References.network_config
	if config == null:
		return 0
	return config.resolved_port()


# --- buttons --------------------------------------------------------------

func _connect_buttons() -> void:
	if _join_button != null:
		_join_button.pressed.connect(_on_join_pressed)
	if _create_button != null:
		_create_button.pressed.connect(_on_create_pressed)
	if _refresh_button != null:
		_refresh_button.pressed.connect(_on_refresh_pressed)
	if _back_button != null:
		_back_button.pressed.connect(_on_back_pressed)
	if _create_confirm_button != null:
		_create_confirm_button.pressed.connect(_on_create_confirmed)
	if _create_cancel_button != null:
		_create_cancel_button.pressed.connect(_on_create_cancelled)


func _setup_create_panel() -> void:
	if _create_panel != null:
		_create_panel.hide()
	if _config == null:
		return

	if _player_count_spin != null:
		_player_count_spin.min_value = _config.min_players
		_player_count_spin.max_value = _config.max_players
		_player_count_spin.value = _config.default_lobby_size
	if _lobby_name_input != null:
		_lobby_name_input.max_length = _config.max_lobby_name_length


func _on_join_pressed() -> void:
	if _selected == null:
		return
	_pending_action = "join"
	_set_status("Joining %s..." % _selected.lobby_name)
	Lobby.join(_selected.lobby_id)


## Refresh while connected is a repaint. Offline it is a retry, which is the
## only thing worth doing at that point.
func _on_refresh_pressed() -> void:
	if Net.status() == NetworkService.Status.OFFLINE:
		_set_status("Connecting to %s..." % _server_text())
		_ensure_connected()
		return
	refresh()


func _on_back_pressed() -> void:
	# The connection was opened for the lobby list and nothing behind this
	# screen wants it, so leaving the browser hangs up.
	Net.leave()
	MenuNavigation.to_main_menu(self)


func _on_create_pressed() -> void:
	if _create_panel == null:
		return
	if _lobby_name_input != null && _config != null:
		_lobby_name_input.text = _config.default_lobby_name(LobbyIdentity.display_name())
	_create_panel.show()
	if _lobby_name_input != null:
		_lobby_name_input.grab_focus()


func _on_create_cancelled() -> void:
	if _create_panel != null:
		_create_panel.hide()


## Asks the server to make one. It decides the id, checks the size and answers
## by telling us which lobby we are now in - so there is nothing to navigate to
## from here.
func _on_create_confirmed() -> void:
	if _create_panel != null:
		_create_panel.hide()

	_pending_action = "create"
	_set_status("Creating lobby...")
	Lobby.create(_entered_lobby_name(LobbyIdentity.display_name()), _entered_player_count())


func _entered_lobby_name(host_name: String) -> String:
	var entered: String = ""
	if _lobby_name_input != null:
		entered = _lobby_name_input.text.strip_edges()
	if !entered.is_empty():
		return entered
	if _config != null:
		return _config.default_lobby_name(host_name)
	return host_name


func _entered_player_count() -> int:
	if _player_count_spin != null:
		return int(_player_count_spin.value)
	if _config != null:
		return _config.default_lobby_size
	return 2


# --- rows -----------------------------------------------------------------

func _add_row(lobby: LobbyInfo) -> void:
	if _lobby_list == null || _entry_scene == null:
		Log.err("LobbyBrowser cannot build rows, the list or the row prefab is missing")
		return

	var entry: LobbyListEntry = _entry_scene.instantiate() as LobbyListEntry
	if entry == null:
		Log.err("LobbyBrowser row prefab root does not have a LobbyListEntry script")
		return

	_lobby_list.add_child(entry)
	entry.button_group = _entry_group
	entry.lobby_chosen.connect(_on_entry_chosen)
	entry.lobby_confirmed.connect(_on_entry_confirmed)
	entry.setup(lobby)


func _clear_rows() -> void:
	if _lobby_list == null:
		return
	# Out of the tree first, then freed. queue_free alone leaves the old rows
	# visible and still in the ButtonGroup for the rest of the frame, so a
	# refresh would briefly show both lists at once.
	for child in _lobby_list.get_children():
		var row: LobbyListEntry = child as LobbyListEntry
		if row != null:
			row.button_group = null
		_lobby_list.remove_child(child)
		child.queue_free()


func _clear_selection() -> void:
	_selected = null
	_update_buttons()


## Every button that needs a server is disabled without one, rather than left
## clickable so the player can discover the problem by pressing it. The status
## line says what is wrong; the buttons say what is possible.
func _update_buttons() -> void:
	var status: NetworkService.Status = Net.status()
	var online: bool = status == NetworkService.Status.CONNECTED
	var dialling: bool = status == NetworkService.Status.CONNECTING

	if _create_button != null:
		_create_button.disabled = !online
	if _join_button != null:
		_join_button.disabled = !online || _selected == null

	# Refresh has nothing to refresh while offline, so it becomes the way back
	# in. Without this a failed connection is a dead end short of leaving the
	# screen and coming back.
	if _refresh_button != null:
		_refresh_button.text = "Refresh" if online else "Reconnect"
		_refresh_button.disabled = dialling


func _set_status(text_value: String) -> void:
	if _status_label != null:
		_status_label.text = text_value


func _on_entry_chosen(entry: LobbyListEntry) -> void:
	_selected = entry.lobby
	_update_buttons()


## Double clicking a row is pressing Join on it, so it goes through the same
## path rather than a second copy of it - including every reason a join can be
## refused, and the greyed-out Join button that says so.
func _on_entry_confirmed(entry: LobbyListEntry) -> void:
	_on_entry_chosen(entry)
	if _join_button != null && _join_button.disabled:
		return
	_on_join_pressed()
