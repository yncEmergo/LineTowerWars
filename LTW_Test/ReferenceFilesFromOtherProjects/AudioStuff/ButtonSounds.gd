## Add as child of any button to play button sounds
@tool
class_name ButtonSounds
extends Control

@export var resize: bool = false:
	set(value):
		resize_disabled_button()
		resize = false
	
@export_group("Settings")
@export var use_click_sound: bool = true
@export var use_hover_sound: bool = true
@export var use_disabled_sound: bool = true

var target_button: Button
var disabled_sound_button: Button:
	get:
		if has_node("DisabledSoundButton"):
			return get_node("DisabledSoundButton")
		return null
func _ready() -> void:
	var parent: Node = get_parent()
	if parent is not Button:
		Log.err("ButtonSounds has no button as Parent. Parent: " + parent.name)
		queue_free()
		return
	else:
		target_button = parent as Button

	if use_hover_sound:
		target_button.mouse_entered.connect(on_target_button_mouse_entered)
	if use_click_sound:
		target_button.pressed.connect(on_target_button_pressed)
	if use_disabled_sound:
		disabled_sound_button.pressed.connect(on_disabled_button_pressed)
		
	resize_disabled_button()

## Makes this node and its disabled catcher cover the button exactly.
##
## Anchoring beats assigning a size: the node then follows the button for the rest of its life
## instead of matching it once, and nothing has to be re-run when the button is resized.
##
## Assigning size was also the source of "Nodes with non-equal opposite anchors will have their
## size overridden after _ready()". set_deferred does not avoid that warning, because Control
## only clears the warning flag on a deferred call of its own that is queued after this one.
func resize_disabled_button() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if disabled_sound_button != null:
		disabled_sound_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func on_target_button_mouse_entered() -> void:
	if !target_button.disabled:
		AudioHub.play_sound(AudioHub.audio_config.menu_click_hover, AudioHub.Bus.UI)

func on_target_button_pressed() -> void:
	AudioHub.play_sound(AudioHub.audio_config.menu_click, AudioHub.Bus.UI)
	
func on_disabled_button_pressed() -> void:
	AudioHub.play_sound(AudioHub.audio_config.menu_click_disabled, AudioHub.Bus.UI)

## Has to be called externally, because there is no inherent button.on_disabled signal
func enable_disable_button() -> void:
	disabled_sound_button.mouse_filter = Control.MOUSE_FILTER_STOP
	await get_tree().process_frame
	resize_disabled_button()

## Has to be called externally, because there is no inherent button.on_disabled signal
func disable_disable_button() -> void:
	disabled_sound_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
