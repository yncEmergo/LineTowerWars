class_name HudActionButton
extends Button

## One square of the ActionBar: a picture, a hotkey letter in the corner, and a
## lit state. It knows nothing about what it does.
##
## The same square as SendTierButton - same size, same styleboxes, same press
## behaviour - because the row of buttons over the unit panel has to read as one
## row whether a square selects a sender, selects the builder or opens a screen.
## Not a subclass of it, because a SendTierButton IS a sender and this is not:
## what they share is a look, and a look is shared by the prefab.
##
## Deliberately empty of behaviour. The bar above it wires each square to what
## it does, so a square that later selects something else is one line changed
## rather than a second script.

## Tint for the square whose thing is currently on screen or selected, so the
## button and what it opened agree at a glance. Above 1 on purpose: it brightens
## rather than recolours, exactly as a toggled command slot does.
const ACTIVE_MODULATE: Color = Color(1.45, 1.3, 0.75, 1.0)

@export_group("References")
## The picture. A TextureRect rather than the Button's own `icon` for the reason
## every other square in this HUD uses one: it can then be laid out against the
## hotkey letter rather than centred by the theme.
@export var _icon_rect: TextureRect
## Hotkey in the top left corner, WC3 style. Empty on a square with no key.
@export var _hotkey_label: Label


func _ready() -> void:
	# **On PRESS, not on release.** Godot's default sits on the order for as
	# long as the player holds the mouse down, which is 60-120 ms of pure delay
	# added to every click. See SendTierButton, where this was measured.
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	set_active(false)


## The picture this square carries, or null to leave it blank.
func show_icon(picture: Texture2D) -> void:
	if _icon_rect == null:
		return
	_icon_rect.texture = picture
	_icon_rect.visible = picture != null


## The letter drawn in the corner. Passed in rather than read here, because
## which key opens what is ControlsConfig's answer and a player can change it.
func show_hotkey(text: String) -> void:
	if _hotkey_label == null:
		return
	_hotkey_label.visible = !text.is_empty()
	_hotkey_label.text = text


## Lights the square while whatever it opens is on screen.
func set_active(value: bool) -> void:
	modulate = ACTIVE_MODULATE if value else Color.WHITE
