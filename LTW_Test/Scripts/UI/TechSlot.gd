class_name TechSlot
extends Button

## One square of the Research Center grid: a technology a player can buy.
##
## The command card's CommandSlot with a different subject, and deliberately
## the same shape - a prefab that carries the hotkey letter, the hover tooltip
## and the greyed-out state, so the two grids look and behave alike and neither
## has to know how the other draws.
##
## Not a CommandSlot subclass, because what one shows is a UnitAbility on a
## unit and what this shows is a technology owned by a player, and almost every
## line of the two differs on exactly that. Sharing the LOOK is the tooltip
## scene and the style, both of which are shared already.
##
## The square polls its technology rather than waiting to be told. Whether it
## can be bought moves with gold as much as with what is owned, and a signal
## per source would mean every future caller having to remember to wire itself
## up here. Polling is cheap: the answer is a dictionary lookup and a compare.

## Emitted when a square that holds a technology is pressed. The panel decides
## what that means, and nothing here spends anything.
signal tech_activated(tech: TechDefinition)

## Greyed tint for a technology that cannot be bought right now - the element
## it needs is not owned, or there is not enough gold.
const UNAVAILABLE_MODULATE: Color = Color(0.55, 0.55, 0.55, 1.0)
## Lit tint for one already researched. Above 1 on purpose, the same way a
## command card marks a toggle that is switched on: it brightens the square
## rather than recolouring it, so it still reads once icons replace the text.
const RESEARCHED_MODULATE: Color = Color(1.4, 1.25, 0.7, 1.0)

@export_group("References")
## Hotkey in the top left corner, WC3 style. "Q", or "S+Q" on the rows that
## are pressed with Shift held.
@export var _hotkey_label: Label
## Two-character label across the middle, e.g. "F1". Placeholder for the icon
## this square will carry once there is art - thirty blank squares would be
## unreadable - and deliberately terse, because the colour behind it is doing
## most of the work.
@export var _name_label: Label
## The element's own hue, filling the square behind everything else. Also a
## placeholder standing in for the icon, and the reason the labels can be as
## short as they are: a row reads as one element before a letter is read.
##
## Under the labels rather than a stylebox on the button, so the greyed and lit
## tints keep working - modulate reaches a child and would not reach a theme
## override.
@export var _background: ColorRect
## Rich hover tooltip, built fresh per hover. The command card's own scene,
## because a technology has exactly the blocks it draws: a title, a price, some
## stats and a note.
@export var _tooltip_scene: PackedScene

var tech: TechDefinition

## Whose Research Center this is. Availability is per player, and the resource
## behind the square is shared by every player in the match.
var _player_id: int = 0
## Label this square answers to, kept for the tooltip.
var _hotkey: String = ""

var _manager: TechManager:
	get:
		return References.tech_manager


func _ready() -> void:
	pressed.connect(_on_pressed)
	clear()


## Fills the square from a technology, or empties it when given null.
func set_tech(new_tech: TechDefinition, player_id: int, hotkey: String) -> void:
	if new_tech == null:
		clear()
		return

	tech = new_tech
	_player_id = player_id
	_hotkey = hotkey
	disabled = false
	icon = tech.icon
	# Godot only offers a tooltip at all while the text is non-empty, so this
	# doubles as the fallback for a missing tooltip scene.
	tooltip_text = tech.display_name
	_apply_label(_hotkey_label, _hotkey)
	_apply_label(_name_label, "" if tech.icon != null else tech.grid_label())
	if _background != null:
		_background.color = tech.element_color()
	_refresh_state()


## Empties the square. Empty squares stay in place so the grid keeps its shape,
## and stay disabled so they cannot be pressed.
func clear() -> void:
	tech = null
	_player_id = 0
	_hotkey = ""
	disabled = true
	icon = null
	tooltip_text = ""
	modulate = Color.WHITE
	if _background != null:
		_background.color = Color.TRANSPARENT
	_apply_label(_hotkey_label, "")
	_apply_label(_name_label, "")


## Availability moves on its own: gold is spent elsewhere, and the element this
## rests on can be bought from another square of this very grid. Re-read every
## frame so a square never describes a state the player has already left.
##
## A hidden square costs nothing: a Godot node goes on processing while it is
## invisible, so the visibility is asked for rather than assumed, and a closed
## Research Center is thirty squares doing one compare each.
func _process(_delta: float) -> void:
	if tech != null && is_visible_in_tree():
		_refresh_state()


func _refresh_state() -> void:
	var manager: TechManager = _manager
	if manager == null:
		return

	# Greyed rather than disabled, because a disabled Control is exactly the
	# case where the player most wants the tooltip explaining why.
	if manager.owns(_player_id, tech.tech_id):
		modulate = RESEARCHED_MODULATE
	elif manager.can_research(_player_id, tech):
		modulate = Color.WHITE
	else:
		modulate = UNAVAILABLE_MODULATE


func _apply_label(label: Label, text: String) -> void:
	if label == null:
		return
	label.visible = !text.is_empty()
	label.text = text


## Everything the hover card says about this technology, built here rather than
## on the resource because half of it is about the PLAYER: what it would cost
## them now, and why it is refused if it is.
func _make_custom_tooltip(_for_text: String) -> Object:
	if tech == null || _tooltip_scene == null:
		return null

	var tooltip: AbilityTooltip = _tooltip_scene.instantiate() as AbilityTooltip
	if tooltip == null:
		Log.err("Technology tooltip scene does not have an AbilityTooltip script")
		return null

	tooltip.show_data(_tooltip_data())
	return tooltip


func _tooltip_data() -> AbilityTooltipData:
	var data: AbilityTooltipData = AbilityTooltipData.new()
	data.title = tech.display_name
	data.hotkey = _hotkey
	data.description = tech.description

	var manager: TechManager = _manager
	if manager == null:
		return data

	_add_ultimate(data)
	_add_price(data, manager)
	return data


## The Ultimate this path leads to and the one other element-path it also
## needs, which together are the only reason a player picks one path over the
## other this early (unit_data.md 2.3).
##
## Silent about the element's own Basic on purpose: that is the square
## immediately to the left, and the refusal names it when it is missing, so a
## third line would only repeat the grid.
func _add_ultimate(data: AbilityTooltipData) -> void:
	if !tech.is_path() || tech.ultimate_name.is_empty():
		return
	data.add_stat("Ultimate", tech.ultimate_name)

	var session: MatchSession = References.match_session
	if session == null:
		return
	var cross: TechDefinition = session.techs().tech_for(tech.ultimate_cross_tech_id)
	if cross != null:
		data.add_stat("Also needs", cross.short_name())


## What it would cost this player right now, or why they cannot have it. Both
## come off TechManager rather than being worked out here, so the card cannot
## quote a price the server would not charge or allow what it would refuse.
func _add_price(data: AbilityTooltipData, manager: TechManager) -> void:
	if manager.owns(_player_id, tech.tech_id):
		data.add_special("Researched", "")
		return

	var cost: int = manager.cost_of_next(_player_id)
	if cost > 0:
		data.gold_cost = cost
	else:
		data.add_stat("Cost", "Free (%d left)" % manager.free_left(_player_id))

	var reason: String = manager.refusal_for(_player_id, tech)
	if reason != TechManager.ALLOWED:
		data.add_special("Not yet", reason)


func _on_pressed() -> void:
	if tech != null:
		tech_activated.emit(tech)
