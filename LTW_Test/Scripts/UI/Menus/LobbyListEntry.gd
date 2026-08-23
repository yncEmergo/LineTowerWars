class_name LobbyListEntry
extends Button

## One row in the lobby browser.
##
## A prefab rather than labels built in code, because a row is going to grow
## behaviour: a lock icon for password lobbies, a region. It is a Button in
## toggle mode so the browser can put every row in one ButtonGroup and get
## single selection for free.

## One click: this row is now the selected one.
signal lobby_chosen(entry: LobbyListEntry)
## Two clicks: join it, without the trip to the Join button. The row only
## reports the gesture - whether a join is possible is the browser's to answer,
## and it already answers it for the button.
signal lobby_confirmed(entry: LobbyListEntry)

@export_group("References")
@export var _name_label: Label
@export var _host_label: Label
@export var _players_label: Label
@export var _status_label: Label
@export var _ping_label: Label

@export_group("Settings")
@export var _open_color: Color = Color(0.44, 0.89, 0.46, 1.0)
@export var _full_color: Color = Color(0.85, 0.6, 0.3, 1.0)
@export var _in_progress_color: Color = Color(0.55, 0.58, 0.66, 1.0)
## A countdown is the one status worth looking at, so it gets the accent colour
## rather than the greyed-out one a running match gets.
@export var _starting_color: Color = Color(1.0, 0.85, 0.35, 1.0)

## Which lobby this row is showing. Null until setup() runs.
var lobby: LobbyInfo = null


func _ready() -> void:
	toggled.connect(_on_toggled)


## Double click, taken from the event rather than timed by hand: Godot already
## decides what counts as one, using the player's own system setting.
##
## _gui_input rather than _unhandled_input, because the click belongs to this
## row - a Control only sees a press that landed on it. The first click of the
## pair still selects through toggled(), so a double click both selects and
## joins, which is what makes it feel like one gesture rather than two.
func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null || button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed && button.double_click && !disabled:
		lobby_confirmed.emit(self)
		accept_event()


## Fills the row in and greys it out when the lobby cannot be joined.
func setup(info: LobbyInfo) -> void:
	lobby = info
	if lobby == null:
		Log.err("LobbyListEntry was set up with no LobbyInfo")
		return

	_set_label(_name_label, lobby.lobby_name)
	_set_label(_host_label, lobby.host_name())
	_set_label(_players_label, lobby.players_text())
	_set_label(_status_label, lobby.status_text())
	_set_label(_ping_label, lobby.ping_text())
	if _status_label != null:
		_status_label.add_theme_color_override("font_color", _status_color())

	# Still listed, so a player can see the game exists, but not selectable.
	disabled = !lobby.is_joinable()
	modulate.a = 1.0 if lobby.is_joinable() else 0.55


## Green only when the lobby can actually be joined, so the column reads at a
## glance rather than having to be spelled out.
func _status_color() -> Color:
	if lobby.is_in_progress:
		return _in_progress_color
	if lobby.is_starting:
		return _starting_color
	if lobby.is_full():
		return _full_color
	return _open_color


func _set_label(label: Label, text_value: String) -> void:
	if label != null:
		label.text = text_value


func _on_toggled(toggled_on: bool) -> void:
	if toggled_on:
		lobby_chosen.emit(self)
