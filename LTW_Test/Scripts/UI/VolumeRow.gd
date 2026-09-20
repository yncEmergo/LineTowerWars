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

## Shortest gap between two previews while a slider is being dragged. Long
## enough to read as a tick per step rather than a tone, short enough that a
## slow drag is never silent.
const PREVIEW_GAP_SECONDS: float = 0.09

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
	_preview()


## Plays a short sound on THIS row's own bus, so the player hears what they
## just set while they are still setting it.
##
## **Four of the six channels are otherwise silent on this screen.** SFX, Music,
## Speech and Atmo have nothing playing through them in a menu, so moving those
## sliders changes a number, writes a file, moves the bus - and produces no
## evidence whatsoever that any of it happened. That is indistinguishable from
## a broken slider, and it is what "the audio options do nothing" turned out to
## describe.
##
## MASTER and UI are the two that already had feedback, because the click of
## the button that opened the screen goes through them. They get the preview
## too rather than being special-cased: one rule is easier to trust than two,
## and hearing the same sound on every row is what makes the six comparable.
##
## Rate limited, because a drag emits value_changed on every frame it moves.
## The gap is AudioHub's own same-sound gap, which turns a drag into a tick
## rather than a tearing noise - and it is keyed by PATH, so dragging one
## slider cannot machine-gun another row's preview either.
func _preview() -> void:
	var config: AudioConfig = References.audio_config
	if config == null:
		return
	var bus: StringName = UserSettings.AUDIO_BUS_NAMES[int(channel)]
	AudioHub.play_preview(config.ui_click_path, bus, PREVIEW_GAP_SECONDS)


func _update_value_label(value: float) -> void:
	if _value_label != null:
		_value_label.text = "%d%%" % roundi(value * 100.0)
