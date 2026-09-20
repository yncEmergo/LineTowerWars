class_name VolumeRow
extends HBoxContainer

## One labelled volume slider, bound to a channel of UserSettings.
##
## A prefab rather than six hand-built rows, because this is exactly the element
## that gains behaviour later - and it already has. It was written when moving
## the slider moved a number in a settings file and nothing else; the routing
## landed on UserSettings.set_volume(), which pushes the level onto the named
## AudioServer bus, and every row followed without being touched.
##
## APPLIED AS IT MOVES, with no Apply button: the level is pushed onto the bus
## and written to disk by the setter, so a player hears the change while they
## are still dragging. That is what makes a volume slider usable at all, and it
## is why there is nothing here to roll back.
##
## NO FOCUS, like every other control in the game - the prefab carries
## focus_behavior_recursive on its root. A slider is dragged with the mouse and
## Godot needs no focus for that. See FocusPolicy.
##
## The row's NAME is not authored here. It is read off UserSettings from the
## channel, so renaming a channel has one place to happen rather than six.

@export_group("References")
@export var _name_label: Label
@export var _slider: HSlider
@export var _value_label: Label

@export_group("Settings")
## Which channel this row moves.
@export var channel: UserSettings.AudioChannel = UserSettings.AudioChannel.MASTER

## True while the slider is being written FROM the settings rather than to
## them, so a refresh cannot be mistaken for the player dragging it.
var _syncing: bool = false


func _ready() -> void:
	if _slider == null:
		Log.err("VolumeRow has no slider assigned in its prefab", name)
		return

	if _name_label != null:
		_name_label.text = UserSettings.audio_channel_name(channel)

	_slider.value_changed.connect(_on_slider_changed)
	refresh()


## Pulls the stored level back onto the slider.
func refresh() -> void:
	if _slider == null:
		return
	_syncing = true
	_slider.value = UserSettings.volume(channel)
	_syncing = false
	_update_value_label(_slider.value)


func _on_slider_changed(value: float) -> void:
	_update_value_label(value)
	if _syncing:
		return
	UserSettings.set_volume(channel, value)


func _update_value_label(value: float) -> void:
	if _value_label != null:
		_value_label.text = "%d%%" % roundi(value * 100.0)
