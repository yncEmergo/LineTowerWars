class_name ControlGroupSlot
extends Button

## One numbered control group's square on the control group bar.
##
## Laid out like a CommandSlot on purpose - the key in the top left, the count
## in the bottom right, the icon filling the middle - because it answers the
## same question in the same corner of the eye. It is not one, though: a
## command card square stands for an ABILITY and polls it, while this stands
## for a SELECTION and only ever redraws when told to. Nothing about a group
## changes between the moments something is added to it or dies out of it, so
## there is nothing worth polling for.
##
## Pressing it selects the group, and pressing it twice snaps the camera there,
## because it hands the press straight to the same code the number key runs.

## Emitted when the square is pressed. The bar decides what that means.
signal group_activated(index: int)

@export_group("References")
## The number that recalls this group, in the top left corner.
@export var _hotkey_label: Label
## How many units the group holds, in the bottom right corner.
@export var _count_label: Label

## Which group this square stands for. 1-based, matching the key. Set once,
## when the bar builds its row, and never again: a square keeps its number
## whether or not the group behind it holds anything.
var group_index: int = 0


func _ready() -> void:
	pressed.connect(_on_pressed)


## Draws a group that holds something. The icon is the FIRST unit's, which is
## also the unit a double tap centres the camera on, so the picture and the
## camera agree about what the group is "of".
func show_group(units: Array) -> void:
	visible = true
	disabled = false
	if _hotkey_label != null:
		_hotkey_label.text = OS.get_keycode_string((int(KEY_1) + group_index - 1) as Key)
	if _count_label != null:
		_count_label.text = str(units.size())
	# The prefab sets expand_icon, without which a Button grows to fit whatever
	# it is given - the same trap CommandSlot and UnitTile both document.
	icon = _icon_of(units[0])
	tooltip_text = _tooltip(units)


## An empty group is hidden rather than drawn blank: the bar is meant to say
## what the player has made, and a row of empty squares says the opposite.
func clear() -> void:
	visible = false
	disabled = true
	icon = null
	tooltip_text = ""
	if _count_label != null:
		_count_label.text = ""


## A group holds whatever was selected, so this asks rather than assumes: a
## square with no picture still draws its number and its count.
func _icon_of(unit: Variant) -> Texture2D:
	var node: Unit = unit as Unit
	if node == null || !is_instance_valid(node) || node.stats == null:
		return null
	return node.stats.icon


## Names the group by its first unit, which is what the icon shows, and says
## how many there are so a mixed group is not silently described as one type.
func _tooltip(units: Array) -> String:
	var first: Unit = units[0] as Unit
	var name_text: String = "Units"
	if first != null && first.stats != null:
		name_text = first.stats.display_name
	if units.size() == 1:
		return "%s\n1 unit" % name_text
	return "%s\n%d units" % [name_text, units.size()]


func _on_pressed() -> void:
	if group_index <= 0:
		return
	group_activated.emit(group_index)
