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
## It owns nothing and decides nothing. Which three are offered, who is still to
## choose and how long they have are StartingTech's; a press goes to `Commands`
## and comes back as world state like every other player order.
##
## **The clock is POLLED rather than pushed**, and only while the screen is up.
## It moves every tick and is drawn to the second, so a signal per tick would be
## twenty redraws a second of a number that changes once - and `_process` on a
## hidden Control costs a bool test.

@export_group("References")
## Parent for the option buttons, refilled whenever the offer changes.
@export var _option_row: HBoxContainer
## Says what is being waited for: your choice, or somebody else's.
@export var _status_label: Label
## Seconds until the match chooses for whoever has not. Hidden entirely when the
## match was set up with no deadline, rather than drawn frozen at zero.
@export var _timer_label: Label

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
	# the menu that lets a player leave. See MatchSession.hold.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

	var draft: StartingTech = _draft
	if draft == null:
		# A HUD with no StartingTech is a scene run on its own, not a broken
		# match: there is simply never a draft to show.
		Log.warn("DraftPanel found no StartingTech, no draft can be shown")
		return
	draft.opening_changed.connect(_refresh)
	_refresh()


## Redrawn whole on every change rather than diffed. It changes a handful of
## times in a match - opened, once per player choosing, closed - so there is
## nothing here worth being clever about.
func _refresh() -> void:
	var draft: StartingTech = _draft
	if draft == null:
		return

	# **The ROOT is what is shown, not a child of it.** The HUD authors this
	# instance hidden, so a panel that only showed its own contents drew
	# nothing at all - which reads exactly like a draft that never opened.
	if !draft.is_drafting():
		hide()
		return

	show()
	_build_options(draft)
	_draw_status(draft)
	_draw_clock(draft)


## The clock, re-read on a render frame rather than on a signal. See the note at
## the top of the class.
func _process(_delta: float) -> void:
	if visible:
		_draw_clock(_draft)


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
		# Dead once this player has chosen: the three stay on screen so they can
		# see what they took, but there is nothing left to press.
		option.show_tech(tech, _requirement_text(tech), !choosing)
		if !choosing && _owns_whole(tech):
			option.mark_chosen()
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


## The deadline, and what it means. Drawn as a bare countdown rather than a
## sentence, because it is read at a glance by somebody who is already being
## told what to do by the line above it.
func _draw_clock(draft: StartingTech) -> void:
	if _timer_label == null || draft == null:
		return

	var left: float = draft.seconds_left()
	if left <= 0.0:
		_timer_label.hide()
		return
	_timer_label.show()
	_timer_label.text = "%d" % int(ceil(left))


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


## Whether the local player already holds all four of this Ultimate's
## technologies, which after they have chosen is how the screen knows WHICH of
## the three they took.
##
## Worked out from what they own rather than remembered, for the reason
## MatchStats derives the same answer: a pick that arrives in a turn, a deadline
## that chose for them and a snapshot that told them about it all land in the
## same place, and only the record says which.
func _owns_whole(tech: TechDefinition) -> bool:
	var manager: TechManager = _tech
	var session: MatchSession = References.match_session
	if manager == null || session == null:
		return false

	var needed: Array[TechDefinition] = manager.ultimate_requirement(tech)
	if needed.is_empty():
		return false
	for entry in needed:
		if !manager.owns(session.local_slot(), entry.tech_id):
			return false
	return true


## The press goes down the road every player order takes. Nothing is drawn
## differently here in reply: the screen changes when the server says this
## player is no longer one of the ones being waited for.
func _on_option_chosen(tech_id: int) -> void:
	Commands.submit_player_action(Command.PlayerAction.PICK_DRAFT_TECH, tech_id)
