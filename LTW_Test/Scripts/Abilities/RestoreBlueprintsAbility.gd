class_name RestoreBlueprintsAbility
extends UnitAbility

## A square on the Save Blueprint card that puts every slot back the way a fresh
## install has it: the plans that ship with the game where there are some, and
## empty everywhere else.
##
## **Local only**, for everything SaveBlueprintAbility says: it deletes files on
## this machine and nothing about a match changes.
##
## **Always asks first**, through the same modal box an overwrite uses, because
## it is the one press that can throw away every plan the player saved at once.
## A press with nothing to throw away does not ask - there is no question to put
## to anybody - and says so in the log instead.

@export_group("Warning")
## Title on the confirmation box.
@export var confirm_title: String = "Restore default blueprints?"
## What it says, with {saved} standing for how many plans the player saved that
## are about to go. Placeholder rather than a sentence built in code, for the
## reason SaveBlueprintAbility.overwrite_message gives.
@export_multiline var confirm_message: String = (
	"This erases all {saved} of your saved blueprints and brings back the plans "
	+ "that came with the game.\nIt cannot be undone."
)
@export var confirm_text: String = "Restore"


## Never a command: it deletes local files.
func is_local_only() -> bool:
	return true


func execute(_unit: Unit, _target: AbilityTarget) -> void:
	var prompt: ConfirmPrompt = References.confirm_prompt
	if prompt == null:
		Log.err("There is no ConfirmPrompt on References, the reset was refused")
		return
	# A local ability runs once per selected unit, so a second builder in the
	# selection would ask the same question over the one already open.
	if prompt.is_open():
		return

	var saved: int = BlueprintLibrary.user_saved_count()
	if saved <= 0:
		Log.info("Blueprints are already the defaults, there is nothing to restore")
		_back_to_root()
		return

	prompt.ask(confirm_title, confirm_message.replace("{saved}", str(saved)),
		_restore, confirm_text)


## Same condition as the slots beside it: only a builder standing in an area
## has a Save card to be on.
func can_execute(unit: Unit) -> bool:
	return unit != null && unit.area != null


func _restore() -> void:
	BlueprintLibrary.restore_defaults()
	_back_to_root()


func _back_to_root() -> void:
	var panel: UnitPanel = References.unit_panel
	if panel != null:
		panel.pop_to_root()
