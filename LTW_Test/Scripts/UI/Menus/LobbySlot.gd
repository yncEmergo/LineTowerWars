class_name LobbySlot
extends PanelContainer

## One player slot in the lobby room.
##
## A prefab rather than a label built in code, because a slot is going to grow
## behaviour: a kick button for the host, a ready tick. Free for all only, so
## there is no team to pick - see game_rules.md.
##
## THE COLOUR IS TWO CONTROLS. Every row shows a SWATCH, in the same column at
## the same size, because the colour is what the players read each other by and
## it has to be the same shape on every line. Only your OWN row also shows a
## dropdown, because a colour is yours to choose and nobody else's - which is
## also why nothing in this file asks who hosts the lobby.
##
## Nothing here decides anything. The dropdown reports the choice upwards and
## the row is redrawn from whatever the SERVER pushes back, so a colour that
## was refused - somebody else took it half a second earlier - snaps back to
## what this player really has rather than showing what they clicked.

signal color_chosen(color_index: int)

@export_group("References")
@export var _index_label: Label
@export var _name_label: Label
@export var _state_label: Label
## Shown on this machine's OWN row and on no other. Lists the whole palette as
## SWATCHES rather than as names, with the colours other players hold disabled
## rather than left out - a colour missing from a menu reads as a bug, a greyed
## one reads as taken. The name rides along as each item's tooltip, so it is
## still sayable out loud without spending a column on it.
@export var _color_option: OptionButton
## The colour itself, on every row. Blank on a seat nobody is sitting in.
@export var _color_swatch: ColorRect

@export_group("Settings")
@export var _host_color: Color = Color(1.0, 0.85, 0.35, 1.0)
@export var _player_color: Color = Color(0.86, 0.88, 0.92, 1.0)
@export var _open_color: Color = Color(0.45, 0.47, 0.54, 1.0)
## What the swatch shows for a seat nobody is sitting in.
@export var _empty_swatch_color: Color = Color(0.16, 0.17, 0.22, 1.0)

## Side of the square drawn in each dropdown item, in pixels before the
## control scales it. Small: it is an icon in a menu row, not a swatch.
const ITEM_SWATCH_PX: int = 14

## One texture per colour, built once and shared by every row in every lobby.
##
## Godot has no "solid colour" texture and an OptionButton item takes a
## Texture2D rather than a Color, so the square has to come from somewhere.
## Built rather than shipped as a PNG per colour, because these are not ART -
## they are the palette itself, and a file per entry would be twelve assets
## that have to be redrawn the moment somebody edits one hue in the config.
##
## STATIC, because the rows are rebuilt on every push the server makes and
## rebuilding twelve images each time would be work for nothing.
static var _swatches: Dictionary = {}

## Set while the dropdown is being filled in from the lobby, so the change that
## writing to it raises is not reported back as a player choosing something.
var _writing: bool = false


func _ready() -> void:
	if _color_option != null:
		_color_option.item_selected.connect(_on_color_selected)


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
	show_color(MatchPlayer.NO_COLOR, false, [])


## Draws this row's colour.
##
## `is_own` decides whether the dropdown appears at all; the swatch is drawn
## either way. `taken` is the colours other members hold.
func show_color(color_index: int, is_own: bool, taken: Array) -> void:
	var presentation: PresentationConfig = References.presentation_config
	var known: bool = presentation != null && color_index != MatchPlayer.NO_COLOR
	if _color_swatch != null:
		_color_swatch.color = (
			presentation.player_color(color_index) if known else _empty_swatch_color
		)

	if _color_option == null:
		return
	_color_option.visible = is_own && presentation != null
	if !_color_option.visible:
		return

	_writing = true
	_color_option.clear()
	for index in range(presentation.color_count()):
		# No text at all: the square IS the entry. The name is the tooltip, for
		# a player who wants to say which one they took.
		_color_option.add_icon_item(_swatch_for(presentation.player_color(index)),
			"", index)
		var item: int = _color_option.item_count - 1
		_color_option.set_item_disabled(item, taken.has(index))
		_color_option.set_item_tooltip(item, presentation.player_color_name(index))
	if known:
		_color_option.select(_color_option.get_item_index(color_index))
	_writing = false


## The square for one colour, made on first use and kept.
static func _swatch_for(color: Color) -> ImageTexture:
	if _swatches.has(color):
		return _swatches[color]

	var image: Image = Image.create_empty(
		ITEM_SWATCH_PX, ITEM_SWATCH_PX, false, Image.FORMAT_RGBA8
	)
	image.fill(color)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_swatches[color] = texture
	return texture


func _on_color_selected(item: int) -> void:
	if _writing || _color_option == null:
		return
	color_chosen.emit(_color_option.get_item_id(item))


func _set_index(index: int) -> void:
	if _index_label != null:
		_index_label.text = "%d." % index
