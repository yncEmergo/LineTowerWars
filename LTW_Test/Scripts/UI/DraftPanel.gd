class_name DraftPanel
extends Control

## The screen a DRAFT match opens on: three Ultimates, the same three for
## everybody, and the world held still until every player has taken one.
##
## **It runs while the tree is paused**, which is what its PROCESS_MODE_ALWAYS
## is for. Everything else on the HUD stops - the command card, the send bar,
## the Research Center - so a player being held here cannot spend, build or
## send their way past the choice, and the only two things that answer a click
## are this and the menu that lets them leave.
##
## It owns nothing and decides nothing. Which three are offered and who is
## still to choose is StartingTech's, on the authority, and arrives at a client
## in the snapshot; a press goes to `Commands` and comes back as world state
## like every other player order.

@export_group("References")
## Everything that is hidden between drafts, which is all of it. Separate from
## this node so the node itself can stay in the tree answering the signal.
@export var _panel: Control
## Parent for the option buttons, refilled whenever the offer changes.
@export var _option_row: HBoxContainer
## Says what is being waited for: your choice, or somebody else's.
@export var _status_label: Label

@export_group("Settings")
@export var _option_scene: PackedScene

var _draft: StartingTech:
	get:
		return References.starting_tech

var _tech: TechManager:
	get:
		return References.tech_manager


func _ready() -> void:
	# The one screen that must answer while the world is held still, along with
	# the menu that lets a player leave. See MatchSession.set_paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _panel != null:
		_panel.hide()

	var draft: StartingTech = _draft
	if draft == null:
		# A HUD with no StartingTech is a scene run on its own, not a broken
		# match: there is simply never a draft to show.
		Log.warn("DraftPanel found no StartingTech, no draft can be shown")
		return
	draft.draft_changed.connect(_refresh)
	_refresh()


## Redrawn whole on every change rather than diffed. It changes a handful of
## times in a match - opened, once per player choosing, closed - so there is
## nothing here worth being clever about.
func _refresh() -> void:
	var draft: StartingTech = _draft
	if _panel == null || draft == null:
		return

	if !draft.is_drafting():
		_panel.hide()
		return

	_panel.show()
	_build_options(draft)
	_draw_status(draft)


func _build_options(draft: StartingTech) -> void:
	if _option_row == null || _option_scene == null:
		Log.err("DraftPanel cannot build options, the row or the option prefab is missing")
		return

	for child in _option_row.get_children():
		_option_row.remove_child(child)
		child.queue_free()

	var choosing: bool = draft.needs_local_pick()
	for tech in draft.options():
		var option: DraftOption = _option_scene.instantiate() as DraftOption
		if option == null:
			Log.err("DraftPanel option prefab root does not have a DraftOption script")
			return
		_option_row.add_child(option)
		option.show_tech(tech, _requirement_text(tech))
		# Dead once this player has chosen: the three stay on screen so they
		# can see what they took, but there is nothing left to press.
		option.disabled = !choosing
		option.chosen.connect(_on_option_chosen)


func _draw_status(draft: StartingTech) -> void:
	if _status_label == null:
		return
	if draft.needs_local_pick():
		_status_label.text = "Choose the Ultimate you will open on."
		return
	_status_label.text = "Waiting for %d more player%s..." % [
		draft.pending_count(), "" if draft.pending_count() == 1 else "s",
	]


## What one Ultimate comes with: the four technologies it needs, which at the
## start of a match is exactly the free allowance. Asked of TechManager, so the
## line under a button cannot disagree with what the pick actually grants.
func _requirement_text(tech: TechDefinition) -> String:
	var manager: TechManager = _tech
	if manager == null:
		return ""

	var names: PackedStringArray = PackedStringArray()
	for needed in manager.ultimate_requirement(tech):
		names.append(needed.short_name())
	return ", ".join(names)


## The press goes down the road every player order takes. Nothing is drawn
## differently here in reply: the screen changes when the server says this
## player is no longer one of the ones being waited for.
func _on_option_chosen(tech_id: int) -> void:
	Commands.submit_player_action(Command.PlayerAction.PICK_DRAFT_TECH, tech_id)
