class_name ControlGroupBar
extends Control

## The row of numbered control groups in the top left corner.
##
## Shows only the groups that hold something, so it costs the corner nothing
## until the player makes one and disappears again when the last unit of the
## last group dies. That is why the option below it exists at all: hiding a bar
## that already hides itself is a preference rather than a fix.
##
## It shares the corner with the Research Center, which is drawn AFTER it in
## the HUD and so covers it while it is open. That is the intended reading -
## the screen the player deliberately opened wins over the bar they did not.
##
## PRESENTATION ONLY, like the rest of the HUD. A press goes to
## SelectionController and comes back as a selection; nothing here decides what
## a group holds.
##
## It redraws when told rather than every frame: a group changes only when
## something is assigned to it, upgraded inside it or dies out of it, and
## ControlGroups announces all three.

## Told when the option that hides this bar is changed, the same way the health
## bars and the sun are told about theirs.
const GROUP: String = "control_group_bars"

@export_group("References")
## Parent for the squares. Filled at runtime, because how many groups exist is
## authored on ControlsConfig and this bar should not hold a second copy.
@export var _slot_row: BoxContainer
@export var _slot_scene: PackedScene

var _slots: Array[ControlGroupSlot] = []

var _controls: ControlsConfig:
	get:
		return References.controls_config

var _selection: SelectionController:
	get:
		return References.selection_controller


func _ready() -> void:
	add_to_group(GROUP)
	hide()

	var selection: SelectionController = _selection
	if selection == null:
		Log.err("ControlGroupBar found no SelectionController on References, it will stay empty")
		return

	selection.control_groups().changed.connect(_on_group_changed)
	_build_slots()
	refresh()


## Redraws every square from what the groups currently hold, and hides the
## whole bar when they hold nothing between them - or when the option that
## hides it outright has been turned off.
##
## Also what the options screen broadcasts to GROUP, because "draw what is
## true now" is the same answer to a group changing and to the option changing.
##
## Whole rather than only the group that changed: there are at most nine
## squares and each is one dictionary lookup, so diffing would buy nothing but
## a second way to be wrong.
func refresh() -> void:
	var selection: SelectionController = _selection
	if selection == null:
		hide()
		return

	if !UserSettings.show_control_groups:
		hide()
		return

	var groups: ControlGroups = selection.control_groups()
	var any: bool = false
	for slot: ControlGroupSlot in _slots:
		var units: Array = groups.recall(slot.group_index)
		if units.is_empty():
			slot.clear()
			continue
		slot.show_group(units)
		any = true

	visible = any


## One square per group the controls define, built once. A build with no
## controls config wired draws no bar rather than guessing at a count.
func _build_slots() -> void:
	var config: ControlsConfig = _controls
	if _slot_row == null || _slot_scene == null:
		Log.err("ControlGroupBar is missing its row or its slot scene, it will be empty")
		return
	if config == null:
		Log.err("ControlGroupBar found no ControlsConfig, it will be empty")
		return

	for index: int in range(1, config.control_group_count + 1):
		var slot: ControlGroupSlot = _slot_scene.instantiate() as ControlGroupSlot
		if slot == null:
			Log.err("Control group slot scene does not have a ControlGroupSlot script")
			return
		_slot_row.add_child(slot)
		slot.group_index = index
		slot.clear()
		slot.group_activated.connect(_on_group_activated)
		_slots.append(slot)


func _on_group_changed(_index: int) -> void:
	refresh()


func _on_group_activated(index: int) -> void:
	var selection: SelectionController = _selection
	if selection != null:
		selection.recall_control_group(index)
