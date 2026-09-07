class_name UltimateButton
extends Button

## One square of the Show Ultimates row: an Ultimate tower a player can take
## as their opening, and the four technologies it is made of.
##
## The same shape as TechSlot and for the same reasons - a prefab carrying its
## own picture, tooltip and greyed state - but it stands for a TOWER rather
## than for a technology, and it is pressed for a set of four rather than for
## one. See unit_data.md 2.3 for why an Ultimate costs four technologies and
## why exactly one of them is a Basic of somebody else's element.
##
## **It gives no order and it knows no rule.** Hovering it says which four
## squares light up; pressing it says which Ultimate was pressed. The screen
## above hands that to `Commands`, and TechManager refuses it if it is not
## allowed - so a click the rules refuse simply changes nothing, exactly as a
## refused build does.
##
## The square is named by the PATH technology that leads to the Ultimate,
## never by the tower: the tower is a picture and a name, and the path is the
## thing a command can name (TechDefinition.ultimate_cross_tech_id).

## The mouse is over this square, or has left it. What the Research Center
## frames the four technologies on.
signal hovered(tech: TechDefinition)
signal unhovered(tech: TechDefinition)
## This square was pressed. The screen above decides what that means.
signal chosen(tech: TechDefinition)

## Greyed tint for an Ultimate that cannot be taken - the free allowance has
## been spent, or this one is already owned.
const UNAVAILABLE_MODULATE: Color = Color(0.5, 0.5, 0.5, 1.0)
## Lit tint for one the player already has all four technologies of. Above 1 on
## purpose, the same way every other lit square in this HUD is.
const OWNED_MODULATE: Color = Color(1.4, 1.25, 0.7, 1.0)

@export_group("References")
## The Ultimate tower's own picture, over the element hue. A TextureRect rather
## than the Button's `icon` for the reason TechSlot's is one: a Button draws its
## icon before its children, so a coloured child would cover it.
@export var _icon_rect: TextureRect
## Fallback for a build with no art for this tower: the element and its path
## number, e.g. "F1".
@export var _name_label: Label
## The element's own hue behind everything else, so the row reads as ten pairs
## rather than twenty strangers.
@export var _background: ColorRect
## Rich hover tooltip, the command card's own scene. An Ultimate has exactly
## the blocks it draws: a title, a list of what it needs, and a refusal.
@export var _tooltip_scene: PackedScene

## The path technology this square stands for, which is what a command names.
var tech: TechDefinition

## Whose Research Center this is. What can be taken is per player.
var _player_id: int = 0

var _manager: TechManager:
	get:
		return References.tech_manager


func _ready() -> void:
	# On PRESS rather than release, the same input-latency fix every other
	# square in this HUD carries. See SendTierButton.
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	clear()


## Fills the square from the path technology that leads to one Ultimate.
func set_tech(new_tech: TechDefinition, player_id: int) -> void:
	if new_tech == null || !new_tech.is_path():
		clear()
		return

	tech = new_tech
	_player_id = player_id
	# Godot only offers a tooltip while the text is non-empty, so this doubles
	# as the fallback for a missing tooltip scene.
	tooltip_text = tech.ultimate_name

	var picture: Texture2D = tech.ultimate_icon()
	if _icon_rect != null:
		_icon_rect.texture = picture
		_icon_rect.visible = picture != null
	if _name_label != null:
		_name_label.visible = picture == null
		_name_label.text = tech.grid_label()
	if _background != null:
		_background.color = tech.element_color()
	_refresh_state()


## Empties the square. It keeps its place so the row holds its shape.
func clear() -> void:
	tech = null
	_player_id = 0
	tooltip_text = ""
	modulate = Color.WHITE
	if _icon_rect != null:
		_icon_rect.texture = null
		_icon_rect.visible = false
	if _name_label != null:
		_name_label.visible = false
	if _background != null:
		_background.color = Color.TRANSPARENT


## What can be taken moves on its own - every technology researched by hand
## spends part of the allowance this row needs whole - so it is re-read while
## the row is on screen, exactly as a grid square is. A hidden row costs
## nothing, because the visibility is asked for rather than assumed.
func _process(_delta: float) -> void:
	if tech != null && is_visible_in_tree():
		_refresh_state()


## Greyed rather than disabled, because a square the player cannot press is
## precisely the one whose tooltip they want to read.
func _refresh_state() -> void:
	var manager: TechManager = _manager
	if manager == null:
		return

	var reason: String = manager.refusal_for_ultimate(_player_id, tech)
	if reason == TechManager.ALLOWED:
		modulate = Color.WHITE
	elif _owns_all(manager):
		modulate = OWNED_MODULATE
	else:
		modulate = UNAVAILABLE_MODULATE


func _owns_all(manager: TechManager) -> bool:
	for needed in manager.ultimate_requirement(tech):
		if !manager.owns(_player_id, needed.tech_id):
			return false
	return true


func _make_custom_tooltip(_for_text: String) -> Object:
	if tech == null || _tooltip_scene == null:
		return null

	var tooltip: AbilityTooltip = _tooltip_scene.instantiate() as AbilityTooltip
	if tooltip == null:
		Log.err("Ultimate tooltip scene does not have an AbilityTooltip script")
		return null

	tooltip.show_data(_tooltip_data())
	return tooltip


## What this Ultimate is made of and whether it can be taken. Both come off
## TechManager rather than being worked out here, so the card cannot promise
## something the server would refuse.
func _tooltip_data() -> AbilityTooltipData:
	var data: AbilityTooltipData = AbilityTooltipData.new()
	data.title = tech.ultimate_name

	var manager: TechManager = _manager
	if manager == null:
		return data

	var names: PackedStringArray = PackedStringArray()
	for needed in manager.ultimate_requirement(tech):
		names.append(needed.short_name())
	data.add_stat("Needs", ", ".join(names))

	var reason: String = manager.refusal_for_ultimate(_player_id, tech)
	if reason == TechManager.ALLOWED:
		data.add_special("Free", "spends the opening allowance")
	else:
		data.add_special("Not yet", reason)
	return data


func _on_pressed() -> void:
	if tech != null:
		chosen.emit(tech)


func _on_mouse_entered() -> void:
	if tech != null:
		hovered.emit(tech)


func _on_mouse_exited() -> void:
	if tech != null:
		unhovered.emit(tech)
