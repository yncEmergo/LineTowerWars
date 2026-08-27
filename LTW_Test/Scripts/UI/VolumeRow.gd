class_name VolumeRow
extends HBoxContainer

## One labelled volume slider, bound to a channel of UserSettings.
##
## A prefab rather than six hand-built rows, because this is exactly the element
## that gains behaviour later: the day there is an audio bus layout, the routing
## lands on UserSettings.set_volume() and every row follows without being
## touched. Today moving the slider moves a number in the settings file and
## nothing else - there is no sound in the build yet.
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
