class_name StatusIcon
extends Control

## One square in the unit panel's debuff row.
##
## The sibling of CommandSlot and deliberately built like one: an icon that
## fills the square, a count in a corner, a sweep over the top and a rich
## tooltip on hover. It is not a Button, because there is nothing to press - a
## debuff is something a player READS.
##
## The picture is the SOURCE ABILITY's, so a chill shows the tower that chilled
## and a stun shows the tower that stunned. That costs no art of its own and
## answers the question a player actually has about a debuff, which is usually
## "what is doing this to me" rather than "what kind of thing is it". The kind
## is what the tooltip leads with.
##
## The tooltip is REBUILT while it is open, unlike a command slot's, because
## half of what it says is a countdown. Godot builds a custom tooltip once per
## hover and would otherwise freeze the duration at the moment the cursor
## arrived, which reads as a debuff that has stopped running.

## Drawn in the middle when the source ability has no picture to show - a
## debuff nothing authored applied, or one whose ability has no icon. The
## square still has to say something, and the first letter of its name says more
## than an empty box.
@export_group("References")
@export var _icon: TextureRect
@export var _letter: Label
## Stacks in the bottom right corner, WC3 style, hidden for anything that does
## not stack.
@export var _stacks_label: Label
## Dark wedge closing over the square as the debuff runs out. See
## StatusEntry.expiry_progress for why it is a window rather than a fraction of
## the whole duration.
@export var _sweep: RadialCooldown
@export var _tooltip_scene: PackedScene

## What this square is showing, or null while it is empty.
var entry: StatusEntry = null

## The tooltip currently on screen for this square, so its countdown can be
## kept honest. Godot owns and frees it; this is only borrowed.
var _tooltip: AbilityTooltip = null

var _presentation: PresentationConfig:
	get:
		return References.presentation_config


## Fills the square from one debuff, or empties it when given null.
func show_entry(new_entry: StatusEntry) -> void:
	if new_entry == null:
		clear()
		return

	entry = new_entry
	visible = true

	var ability: UnitAbility = entry.source_ability()
	var texture: Texture2D = null if ability == null else ability.icon_texture()
	if _icon != null:
		_icon.texture = texture
		_icon.visible = texture != null
	if _letter != null:
		_letter.visible = texture == null
		_letter.text = entry.title().left(1)

	# Non-empty or Godot offers no tooltip at all, and it doubles as the plain
	# fallback when the rich one cannot be built.
	tooltip_text = "%s\n%s" % [entry.title(), entry.text()]
	_apply_stacks()
	_apply_sweep()
	_refresh_tooltip()


func clear() -> void:
	entry = null
	visible = false
	tooltip_text = ""
	if _icon != null:
		_icon.texture = null
	if _stacks_label != null:
		_stacks_label.visible = false
	if _sweep != null:
		_sweep.set_progress(1.0)


func _apply_stacks() -> void:
	if _stacks_label == null:
		return
	_stacks_label.visible = entry.stacks > 0
	if entry.stacks > 0:
		# The count alone rather than "3 / 5", which does not fit a square this
		# size. The ceiling is in the tooltip, where there is room to say it.
		_stacks_label.text = str(entry.stacks)


func _apply_sweep() -> void:
	if _sweep == null:
		return
	var config: PresentationConfig = _presentation
	var window: float = 0.0 if config == null else config.status_expiry_sweep_seconds
	# The wedge GROWS as the debuff runs out, which is the opposite of a command
	# slot's: there it counts down to being usable, here it counts down to being
	# gone. RadialCooldown draws nothing at 1, so the progress is inverted.
	_sweep.set_progress(1.0 - entry.expiry_progress(window))


## Keeps an open tooltip's countdown moving. Called from the same refresh that
## fills the square, so it runs on the panel's beat rather than per frame.
func _refresh_tooltip() -> void:
	if _tooltip == null:
		return
	if !is_instance_valid(_tooltip):
		_tooltip = null
		return
	_tooltip.show_data(tooltip_data())


## Everything the hover tooltip says about this debuff: what it is, what it is
## doing, how long is left, how many stacks it holds, and which ability applied
## it. Public so the tooltip can be refilled from outside as the clock runs.
func tooltip_data() -> AbilityTooltipData:
	var data: AbilityTooltipData = AbilityTooltipData.new()
	if entry == null:
		return data

	data.title = entry.title()
	data.description = entry.text()

	var duration: String = entry.duration_text()
	if !duration.is_empty():
		data.add_stat("Duration", duration)
	var stacks: String = entry.stacks_text()
	if !stacks.is_empty():
		data.add_stat("Stacks", stacks)

	var ability: UnitAbility = entry.source_ability()
	if ability != null:
		# In the block a card uses for a unit's own passives, because that is
		# what this is: the named ability behind the effect.
		data.add_special(ability.display_name, "")
	return data


func _make_custom_tooltip(_for_text: String) -> Object:
	if entry == null || _tooltip_scene == null:
		return null

	var tooltip: AbilityTooltip = _tooltip_scene.instantiate() as AbilityTooltip
	if tooltip == null:
		Log.err("Status tooltip scene does not have an AbilityTooltip script")
		return null

	tooltip.show_data(tooltip_data())
	_tooltip = tooltip
	return tooltip
