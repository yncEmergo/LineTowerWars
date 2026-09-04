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

## Lit tint for a TOGGLE that is currently switched on, so a card answers
## "which way is this set" at a glance rather than only when hovered.
## Above 1 on purpose: it brightens the square rather than recolouring it, so
## it still reads once real icons replace the placeholder squares.
const TOGGLED_MODULATE: Color = Color(1.4, 1.25, 0.7, 1.0)

## Charge count no ability can ever report, so the first refresh after a slot
## is filled always redraws the corner. Without it a slot refilled from a send
## to a tower kept the send's number on screen, because an ability with no
## charges reports -1 and so compared equal to the count already drawn.
const CHARGES_UNKNOWN: int = -2

## Countdown no ability can ever report, so the middle of a freshly filled slot
## is always redrawn once. Same trap the charge corner had, for the same
## reason: "nothing to wait for" is a real value an ability answers with.
const LOCKOUT_UNKNOWN: int = -2

@export_group("References")
## Hotkey letter in the top left corner, WC3 style, so it stays out of the way
## of the icon that fills the middle of the slot.
@export var _hotkey_label: Label
## Count in the bottom right corner, e.g. the sends left in the reserve.
@export var _charge_label: Label
## Countdown across the middle, shown only while the ability is still waiting
## on a clock to become available at all - a creep that has not unlocked yet.
## In the middle rather than in a corner because it is the whole reason the
## square is covered, so it is what the player is looking for.
@export var _lockout_label: Label
## Sweep shown while the next charge is on its way.
@export var _cooldown: RadialCooldown
## Rich hover tooltip built fresh per hover. Owned by this node, so it stays a
## plain export rather than going through References.
@export var _tooltip_scene: PackedScene

var ability: UnitAbility

var _presentation: PresentationConfig:
	get:
		return References.presentation_config

## Unit the ability would run on. Availability and charges are per unit, so the
## slot has to remember whose card it is showing.
var _unit: Unit = null
var _charges: int = CHARGES_UNKNOWN
## Whole seconds currently drawn in the middle, or -1 for nothing.
var _lockout: int = LOCKOUT_UNKNOWN
## Letter this square answers to, blank for a passive that cannot be pressed.
var _hotkey: String = ""
## The tooltip currently open over this square, or null when none is.
##
## Kept because Godot builds a tooltip ONCE when the cursor arrives and never
## asks again while it stays. That is fine for a square whose meaning is fixed,
## and wrong for one that answers to a press: the Alter Armor cycle changes
## nothing on screen except its own tooltip, so without this it reads as a dead
## button until the cursor leaves the square and comes back. The node is the
## viewport's and is freed when it hides, so every read of it is guarded.
var _tooltip: AbilityTooltip = null


func _ready() -> void:
	# **On PRESS, not on release, and that is an input-latency fix rather than a
	# preference.** Godot's default is ACTION_MODE_BUTTON_RELEASE, so a card
	# square sat on the order for as long as the player held the mouse down -
	# 60-120 ms of pure delay added to every build and every send, and paid
	# before the order even reached the turn scheduler. Hotkeys never had it,
	# which is why the two felt different for no visible reason.
	#
	# Nothing is lost by pressing early: an order is refused by the simulation
	# rather than by this button, so there is no half-committed state to back
	# out of if the player was wrong.
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
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
	# The prefab sets expand_icon, without which a Button grows to fit whatever
	# it is given and one 256 pixel icon blows the whole command card apart -
	# custom_minimum_size is a MINIMUM and does not hold it back.
	icon = ability.icon_texture()
	# A passive has nothing to press, so it draws no letter however good a
	# square it happened to land in.
	_hotkey = "" if ability.targeting == UnitAbility.Targeting.PASSIVE else hotkey
	# The rich tooltip replaces this, but Godot only offers a tooltip at all
	# while the text is non-empty, so it doubles as the fallback.
	tooltip_text = ability.tooltip_text(_hotkey)
	_apply_hotkey_label(_hotkey)

	_charges = CHARGES_UNKNOWN
	_lockout = LOCKOUT_UNKNOWN
	_refresh_state()
	# The card is rebuilt whenever what a square says could have changed, so
	# this is the one place that has to rewrite a tooltip already on screen.
	_refresh_open_tooltip()


## Empties the slot. Empty slots stay in place so the card keeps its shape,
## and stay disabled so they cannot be clicked.
func clear() -> void:
	ability = null
	_unit = null
	_charges = CHARGES_UNKNOWN
	_lockout = LOCKOUT_UNKNOWN
	disabled = true
	icon = null
	tooltip_text = ""
	_hotkey = ""
	modulate = Color.WHITE

	_apply_hotkey_label("")
	if _charge_label != null:
		_charge_label.visible = false
	if _lockout_label != null:
		_lockout_label.visible = false
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

	# Never disabled, because a disabled Control is exactly the case where the
	# player most wants the tooltip explaining why. The square stays pressable
	# and the order is refused by the simulation, which had to refuse it anyway.
	#
	# Nothing TINTS an unusable square either, any more: the icon stays lit and
	# the cooldown fill says "not ready" on its own. See _sweep_progress().
	var passive: bool = ability.targeting == UnitAbility.Targeting.PASSIVE
	var usable: bool = !passive && ability.can_execute(_unit)
	if ability.is_toggled_on(_unit):
		modulate = TOGGLED_MODULATE
	else:
		modulate = Color.WHITE

	var count: int = ability.charge_count(_unit)
	if count != _charges:
		_charges = count
		_apply_charge_label(count)

	# Asked once and used twice: the number in the middle and the fill over it
	# are two readings of the same wait and must never disagree by a frame.
	var lockout: float = ability.lockout_seconds(_unit)
	var seconds: int = -1 if lockout <= 0.0 else ceili(lockout)
	if seconds != _lockout:
		_lockout = seconds
		_apply_lockout_label(seconds)

	if _cooldown != null:
		_cooldown.set_progress(_sweep_progress(lockout, usable, passive))


func _apply_charge_label(count: int) -> void:
	if _charge_label == null:
		return
	_charge_label.visible = count >= 0
	if count >= 0:
		_charge_label.text = str(count)


## How ready the square is, 0 to 1, driving the dark fill over it: 1 covers
## nothing and 0 covers it whole.
##
## Answered in priority order, which is also the order of how much each answer
## KNOWS. A wait that is running beats one that is not, every time, because the
## flat cover says only "no" where a sweep says "no, and this much longer".
##
## So a one-off lockout comes first, then a charge on its way - being out of
## stock IS the reason the square cannot be pressed, and the reserve coming
## back is the answer to how long, which a flat cover would throw away. The
## cover is what is left for a square with nothing moving behind it at all: a
## tower there is no gold for, an upgrade whose technology is not researched.
## Those read as a wait that has not started, which is what they are.
##
## A passive is excluded rather than covered: it is never unusable, only ever
## read, so a card of auras would otherwise be a card of black squares.
func _sweep_progress(lockout: float, usable: bool, passive: bool) -> float:
	if lockout > 0.0:
		return _lockout_progress(lockout)

	var progress: float = ability.charge_progress(_unit)
	if progress < 1.0:
		return progress

	if !usable && !passive:
		return 0.0
	return 1.0


## How far a one-off wait has come, over the last stretch of it rather than
## over the whole thing.
##
## PresentationConfig.card_lockout_sweep_seconds is that stretch. A wait longer
## than the window reads as 0 - covered whole - and starts unwinding once it
## comes inside, so a five minute wait is not a fill that never visibly moves.
func _lockout_progress(lockout: float) -> float:
	var config: PresentationConfig = _presentation
	if config == null || config.card_lockout_sweep_seconds <= 0.0:
		return 0.0
	return clampf(1.0 - lockout / config.card_lockout_sweep_seconds, 0.0, 1.0)


func _apply_lockout_label(seconds: int) -> void:
	if _lockout_label == null:
		return
	_lockout_label.visible = seconds > 0
	if seconds > 0:
		_lockout_label.text = str(seconds)


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

	tooltip.show_data(ability.tooltip_data(_hotkey, _unit))
	_tooltip = tooltip
	return tooltip


## Rewrites the tooltip hanging over this square, if one is up. Does nothing
## the rest of the time, which is nearly always.
func _refresh_open_tooltip() -> void:
	if _tooltip == null || !is_instance_valid(_tooltip):
		_tooltip = null
		return
	if !_tooltip.is_inside_tree():
		return
	if ability == null || !is_instance_valid(_unit):
		return

	_tooltip.show_data(ability.tooltip_data(_hotkey, _unit))
	# The popup Godot wrapped the tooltip in was sized when it opened, so a
	# line that has grown would be clipped by a box a frame out of date.
	# Deferred, because the panel has not laid the new text out yet.
	_resize_tooltip.call_deferred()


func _resize_tooltip() -> void:
	if _tooltip == null || !is_instance_valid(_tooltip) || !_tooltip.is_inside_tree():
		return
	var wrapper: Window = _tooltip.get_parent() as Window
	if wrapper != null:
		wrapper.reset_size()


func _on_pressed() -> void:
	if ability == null:
		return
	ability_activated.emit(ability)
