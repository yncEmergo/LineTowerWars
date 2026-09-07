class_name SaveBlueprintAbility
extends UnitAbility

## One square of the Save Blueprint card: writes the maze standing right now
## into that slot.
##
## **Local only**, on the same terms as everything else in the blueprint
## family: it reads the buildings in the player's own area and writes a file on
## this machine. Nothing about a match changes, so nothing crosses the wire.
##
## **Overwriting asks first, and saving into an empty slot does not.** That is
## the whole of the difference between the two presses: a slot with something
## in it is somebody's saved work, and the one press that can destroy it is
## this one - so it goes through a modal box that blocks the rest of the game
## until it is answered. An empty slot has nothing to lose and a confirmation
## on it would only teach the player to click through the one that matters.
##
## A shipped default counts as occupied and asks like any other, because from
## where the player is sitting it is a plan in a slot. What the box tells them
## is which of the two it is, since only one of them can be got back.

@export_group("Blueprint")
## Which of the library's slots this square writes to. Counts from 1, and is
## the same numbering the Show card uses - slot 4 here is slot 4 there.
@export var blueprint_slot: int = 1

@export_group("Overwrite warning")
## Title on the confirmation box.
@export var overwrite_title: String = "Overwrite this blueprint?"
## What it says, with {slot} and {towers} standing for the slot number and how
## many towers are in the plan that is about to go.
##
## Placeholders rather than a sentence built in code, for the reason
## UnitAbility.description_text exists: the wording is authored data, and a
## number typed into it here would be a second copy of something the library
## already knows.
@export_multiline var overwrite_message: String = (
	"Blueprint {slot} already holds {towers} towers.\n"
	+ "Saving over it cannot be undone."
)
## Line added instead when the plan being replaced is one that shipped with the
## game, since that one CAN be got back.
@export_multiline var overwrite_default_message: String = (
	"Blueprint {slot} still holds the plan that came with the game, "
	+ "{towers} towers.\nSaving over it replaces it for good on this machine."
)
@export var overwrite_confirm_text: String = "Overwrite"


## Never a command: it reads local nodes and writes a local file.
func is_local_only() -> bool:
	return true


func execute(unit: Unit, _target: AbilityTarget) -> void:
	if unit == null || unit.area == null:
		return

	# Captured BEFORE the question is asked, so the plan that gets written is
	# the maze the player was looking at when they pressed the button rather
	# than whatever it has become by the time they answer. A tower can finish,
	# or be destroyed by a leak, while the box is up.
	var plan: TowerLayout = TowerLayout.capture(unit.area)
	if plan.entry_count() <= 0:
		Log.info("There is nothing standing to save as a blueprint",
			{"slot": blueprint_slot})
		return

	if !BlueprintLibrary.has(blueprint_slot):
		_store(plan)
		return

	var prompt: ConfirmPrompt = References.confirm_prompt
	if prompt == null:
		Log.err("There is no ConfirmPrompt on References, the overwrite was refused")
		return
	prompt.ask(overwrite_title, _warning_text(), _store.bind(plan),
		overwrite_confirm_text)


## Every square is pressable: the slot it writes to is decided by the square
## rather than by anything about the unit, and the two things that can refuse a
## save - an empty maze and a slot somebody says no to - are both answered
## after the press.
func can_execute(unit: Unit) -> bool:
	return unit != null && unit.area != null && BlueprintLibrary.is_slot(blueprint_slot)


## How many towers the slot already holds, in the corner of the square, so the
## save card says at a glance which slots are spoken for. Nothing at all on an
## empty one, which is what makes the free slots findable.
func charge_count(_unit: Unit) -> int:
	return BlueprintLibrary.entry_count(blueprint_slot)


func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)
	var count: int = BlueprintLibrary.entry_count(blueprint_slot)
	if count < 0:
		data.add_stat("Holds", "nothing yet")
		return data

	data.add_stat("Holds", "%d towers" % count)
	data.add_stat("Saving", "asks before overwriting")
	return data


## Writes the plan and hands the card back.
##
## Bound to the confirmation box on the overwrite path and called straight on
## the empty one, so both roads end in exactly the same call - there is no
## second way to write a slot that could drift from the first.
func _store(plan: TowerLayout) -> void:
	if !BlueprintLibrary.store(blueprint_slot, plan):
		return
	var panel: UnitPanel = References.unit_panel
	if panel != null:
		panel.pop_to_root()


## The warning, with the numbers filled in and the right one of the two
## sentences chosen.
func _warning_text() -> String:
	var shipped: bool = BlueprintLibrary.is_shipped_default(blueprint_slot)
	var text: String = overwrite_default_message if shipped else overwrite_message
	return text.replace("{slot}", str(blueprint_slot)).replace(
		"{towers}", str(BlueprintLibrary.entry_count(blueprint_slot))
	)
