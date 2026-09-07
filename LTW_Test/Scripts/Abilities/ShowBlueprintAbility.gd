class_name ShowBlueprintAbility
extends UnitAbility

## One square of the Blueprints card: puts that slot's plan on the ground.
##
## **Local only**, for everything ShowBlueprintsAbility says: it reads a file
## this machine wrote and draws a mesh only this machine sees.
##
## Nine of these exist as nine .tres files, one per slot, each with an id of
## its own - rather than one resource that a card position tells which slot it
## is. An ability is a SHARED resource and must hold no per-unit state, but the
## slot number is not state: it is what this entry IS, the same way a build
## ability is the tower it builds. Authoring nine also means each one owns a
## permanent id, which is what every other command in the game does.

@export_group("Blueprint")
## Which of the library's slots this square shows. Counts from 1, so the number
## in the file name, the number in a log line and this are all the same number.
@export var blueprint_slot: int = 1


## Never a command: a plan is a local file and the overlay is a local mesh.
func is_local_only() -> bool:
	return true


## Shows this slot and hands the card back.
##
## Back to the builder's own commands rather than staying on the list, because
## the list has done its job the moment a plan is up and what the player wants
## next is Build. The one press that puts the plan AWAY again is the Blueprints
## button itself, which is now lit.
func execute(_unit: Unit, _target: AbilityTarget) -> void:
	var overlay: BlueprintOverlay = References.blueprint_overlay
	if overlay == null:
		return

	# Toggle rather than show, so pressing the slot that is already on screen
	# from inside the list means the same thing as pressing the lit Blueprints
	# button - a player who opened the list to switch a plan off should not
	# have to back out of it first.
	overlay.toggle_slot(blueprint_slot)

	var panel: UnitPanel = References.unit_panel
	if panel != null:
		panel.pop_to_root()


## An empty slot cannot be shown. The square stays on the card and stays
## pressable - the panel never hides an unusable one, so the tooltip can say
## why - but it is drawn covered and the press does nothing.
func can_execute(_unit: Unit) -> bool:
	return BlueprintLibrary.has(blueprint_slot) && References.blueprint_overlay != null


## How many towers the plan holds, in the corner of the square, or nothing at
## all for an empty slot. It is the one thing worth knowing about a plan before
## opening it, and the card already draws a number there for a send's reserve.
func charge_count(_unit: Unit) -> int:
	return BlueprintLibrary.entry_count(blueprint_slot)


## Lit while THIS slot is the plan on the ground, so the list says which one is
## up rather than only that something is.
func is_toggled_on(_unit: Unit) -> bool:
	var overlay: BlueprintOverlay = References.blueprint_overlay
	return overlay != null && overlay.shown_slot() == blueprint_slot


func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)
	var count: int = BlueprintLibrary.entry_count(blueprint_slot)
	if count < 0:
		data.add_stat("Saved", "nothing yet")
		return data

	data.add_stat("Towers", str(count))
	# Worth saying, because it is the difference between losing your own work
	# and losing something the game shipped with and can be got back by
	# deleting one file.
	if BlueprintLibrary.is_shipped_default(blueprint_slot):
		data.add_stat("Plan", "shipped default")
	return data
