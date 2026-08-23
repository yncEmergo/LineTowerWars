class_name CommandSlot
extends Button

## One slot on a unit's command card.
##
## A prefab rather than a bare panel, because slots carry real behaviour:
## clicking to activate, hotkey letters, hover tooltips, charge counts, the
## cooldown sweep, and later ability icons. Every unit type reuses this same
## slot and only the UnitAbility behind it differs, so a tower's passive and a
## creep's send command need no separate widget.
##
## The slot polls its ability rather than waiting to be told. Availability
## depends on gold, on stock and on whatever a future ability cares about, and
## a signal per source would mean every new ability having to remember to wire
## itself up here. Polling is cheap because the ability answers from cached
## values, never by touching the filesystem.

## Emitted when a filled slot is pressed. The panel decides what that means.
signal ability_activated(ability: UnitAbility)

## Greyed out tint for an ability that exists but cannot be used right now.
const UNAVAILABLE_MODULATE: Color = Color(0.55, 0.55, 0.55, 1.0)

## Charge count no ability can ever report, so the first refresh after a slot
## is filled always redraws the corner. Without it a slot refilled from a send
## to a tower kept the send's number on screen, because an ability with no
## charges reports -1 and so compared equal to the count already drawn.
const CHARGES_UNKNOWN: int = -2

@export_group("References")
## Hotkey letter in the top left corner, WC3 style, so it stays out of the way
## of the icon that fills the middle of the slot.
@export var _hotkey_label: Label
## Count in the bottom right corner, e.g. the sends left in the reserve.
@export var _charge_label: Label
## Sweep shown while the next charge is on its way.
@export var _cooldown: RadialCooldown
## Rich hover tooltip built fresh per hover. Owned by this node, so it stays a
## plain export rather than going through References.
@export var _tooltip_scene: PackedScene

var ability: UnitAbility

## Unit the ability would run on. Availability and charges are per unit, so the
## slot has to remember whose card it is showing.
var _unit: Unit = null
var _charges: int = CHARGES_UNKNOWN
## Letter this square answers to, blank for a passive that cannot be pressed.
var _hotkey: String = ""


func _ready() -> void:
	pressed.connect(_on_pressed)
	clear()


## Fills the slot from an ability, or empties it when given null.
##
## The unit is needed because availability is per unit, not per ability. The
## hotkey letter comes in for a related reason: the card is a grid and the key
## belongs to the SQUARE rather than to what sits in it, so only whoever laid
## the card out knows which letter this one answers to.
func set_ability(new_ability: UnitAbility, unit: Unit, hotkey: String) -> void:
	if new_ability == null:
		clear()
		return

	ability = new_ability
	_unit = unit
	disabled = false
	icon = ability.icon
	# A passive has nothing to press, so it draws no letter however good a
	# square it happened to land in.
	_hotkey = "" if ability.targeting == UnitAbility.Targeting.PASSIVE else hotkey
	# The rich tooltip replaces this, but Godot only offers a tooltip at all
	# while the text is non-empty, so it doubles as the fallback.
	tooltip_text = ability.tooltip_text(_hotkey)
	_apply_hotkey_label(_hotkey)

	_charges = CHARGES_UNKNOWN
	_refresh_state()


## Empties the slot. Empty slots stay in place so the card keeps its shape,
## and stay disabled so they cannot be clicked.
func clear() -> void:
	ability = null
	_unit = null
	_charges = CHARGES_UNKNOWN
	disabled = true
	icon = null
	tooltip_text = ""
	_hotkey = ""
	modulate = Color.WHITE

	_apply_hotkey_label("")
	if _charge_label != null:
		_charge_label.visible = false
	if _cooldown != null:
		_cooldown.set_progress(1.0)


## Availability, charges and the sweep all move on their own: gold is spent
## elsewhere, stock refills on a timer. Re-read every frame so the slot is
## never describing a state the player has already left.
func _process(_delta: float) -> void:
	if ability == null:
		return
	_refresh_state()


func _refresh_state() -> void:
	if ability == null || !is_instance_valid(_unit):
		return

	# Greyed rather than disabled, because a disabled Control is exactly the
	# case where the player most wants the tooltip explaining why.
	var usable: bool = ability.targeting != UnitAbility.Targeting.PASSIVE \
		&& ability.can_execute(_unit)
	modulate = Color.WHITE if usable else UNAVAILABLE_MODULATE

	var count: int = ability.charge_count(_unit)
	if count != _charges:
		_charges = count
		_apply_charge_label(count)

	if _cooldown != null:
		_cooldown.set_progress(ability.charge_progress(_unit))


func _apply_charge_label(count: int) -> void:
	if _charge_label == null:
		return
	_charge_label.visible = count >= 0
	if count >= 0:
		_charge_label.text = str(count)


func _apply_hotkey_label(label: String) -> void:
	if _hotkey_label == null:
		return
	_hotkey_label.visible = !label.is_empty()
	_hotkey_label.text = label


## Rich tooltip laid out like the WC3 original, rather than the plain text
## Godot would otherwise draw. Returning null falls back to that text, which is
## what keeps a slot describable even with the scene unassigned.
func _make_custom_tooltip(_for_text: String) -> Object:
	if ability == null || _tooltip_scene == null:
		return null

	var tooltip: AbilityTooltip = _tooltip_scene.instantiate() as AbilityTooltip
	if tooltip == null:
		Log.err("Ability tooltip scene does not have an AbilityTooltip script")
		return null

	tooltip.show_data(ability.tooltip_data(_hotkey))
	return tooltip


func _on_pressed() -> void:
	if ability == null:
		return
	ability_activated.emit(ability)
