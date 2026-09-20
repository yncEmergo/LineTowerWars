class_name TutorialGuide
extends RefCounted

## Which of the player's units a lesson is walking them to, and whether they
## have got there - the one question both tutorial arrows ask.
##
## The UI arrow (TutorialPointer) and the world arrows (TutorialWorldArrows)
## both change what they point at on the answer: while the unit a lesson wants
## is NOT selected they point at the unit and the button that selects it, and
## once it is they move on to the button on its card. Asked of the selection
## every frame rather than remembered, because a player can click away from the
## builder at any moment and the arrow has to come back to it.
##
## PRESENTATION, local from end to end.

## The HUD name of the button that selects each guide unit, as authored on the
## TutorialPointer in match_hud.tscn.
const BUILDER_BUTTON_KEY: StringName = &"builder_button"
const FIRST_SENDER_BUTTON_KEY: StringName = &"send_tier_1"


## Whether the lesson on screen still wants a unit selected that is not. False
## for a lesson that names no unit.
##
## **A task that both builds and upgrades stops guiding to the builder the
## moment there is something to upgrade.** One task can be "build a Core and
## raise it to a Greater Annihilation Glyph", and the builder is the answer for
## exactly the first press of that: afterwards the player wants the tower
## selected, and an arrow calling them back to the builder between every rung
## is pointing at the wrong thing. The towers a task puts arrows over are what
## it is working ON, so one of them standing is the handover.
static func needs_selecting(step: TutorialStep) -> bool:
	if step == null || step.guide_unit == TutorialStep.Select.NONE:
		return false
	if _has_arrow_tower(step):
		return false
	return !is_selected(step.guide_unit)


## Whether the player owns a tower of any type this task points arrows at.
static func _has_arrow_tower(step: TutorialStep) -> bool:
	var wanted: Array[BuildingStats] = step.arrow_towers()
	if wanted.is_empty():
		return false
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return false
	var area: PlayerArea = manager.area_for(manager.local_player_id())
	if area == null:
		return false
	for child in area.get_children():
		var building: Building = child as Building
		if building != null && building.stats in wanted:
			return true
	return false


## Whether a guide unit is in the player's selection right now.
static func is_selected(which: TutorialStep.Select) -> bool:
	var selection: SelectionController = References.selection_controller
	var unit: Unit = unit_for(which)
	return selection != null && unit != null && unit in selection.get_selection()


## The player's own unit a guide names, or null.
static func unit_for(which: TutorialStep.Select) -> Unit:
	var manager: PlayerManager = References.player_manager
	var session: MatchSession = References.match_session
	if manager == null || session == null:
		return null
	var mine: int = manager.local_player_id()
	match which:
		TutorialStep.Select.BUILDER:
			for unit: Unit in session.live_units():
				var builder: Builder = unit as Builder
				if builder != null && builder.owner_player_id == mine:
					return builder
		TutorialStep.Select.FIRST_SENDER:
			var area: PlayerArea = manager.area_for(mine)
			if area != null:
				for sender in area.send_buildings():
					if sender.send_tier == 1 && !sender.is_sudden_death_tier:
						return sender
	return null


## The HUD key of the button that selects a guide unit.
static func button_key(which: TutorialStep.Select) -> StringName:
	match which:
		TutorialStep.Select.BUILDER:
			return BUILDER_BUTTON_KEY
		TutorialStep.Select.FIRST_SENDER:
			return FIRST_SENDER_BUTTON_KEY
	return &""
