class_name LobbySlot
extends PanelContainer

## One player slot in the lobby room.
##
## A prefab rather than a label built in code, because a slot is going to grow
## behaviour: a kick button for the host, a ready tick, a player colour. Free
## for all only, so there is no team to pick - see game_rules.md.

@export_group("References")
@export var _index_label: Label
@export var _name_label: Label
@export var _state_label: Label

@export_group("Settings")
@export var _host_color: Color = Color(1.0, 0.85, 0.35, 1.0)
@export var _player_color: Color = Color(0.86, 0.88, 0.92, 1.0)
@export var _open_color: Color = Color(0.45, 0.47, 0.54, 1.0)


## Fills the slot in for a player who is in the lobby.
func show_player(index: int, player_name: String, is_host: bool) -> void:
	show_status(index, player_name, "Host" if is_host else "Ready", is_host)


## The same row with the state spelled out, which is what the loading screen
## needs: it says whether that player's match scene is loaded yet, not whether
## they host the lobby.
func show_status(index: int, player_name: String, state: String, highlight: bool) -> void:
	_set_index(index)
	if _name_label != null:
		_name_label.text = player_name
		_name_label.add_theme_color_override(
			"font_color", _host_color if highlight else _player_color
		)
	if _state_label != null:
		_state_label.text = state


## Fills the slot in as an empty seat nobody has taken.
func show_open(index: int) -> void:
	_set_index(index)
	if _name_label != null:
		_name_label.text = "Open slot"
		_name_label.add_theme_color_override("font_color", _open_color)
	if _state_label != null:
		_state_label.text = "-"


func _set_index(index: int) -> void:
	if _index_label != null:
		_index_label.text = "%d." % index
