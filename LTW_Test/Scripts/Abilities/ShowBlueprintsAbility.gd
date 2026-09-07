class_name ShowBlueprintsAbility
extends UnitAbility

## The builder's Blueprints button: opens the list of saved plans, or takes the
## one on screen away.
##
## **Local only.** A blueprint is a note the player wrote to themselves on this
## machine and the overlay it puts up changes nothing - the server has no plans
## and the other players have no business seeing yours. Same line the build
## grid toggle and Show Ranges sit on, see UnitAbility.is_local_only().
##
## **One square, two meanings, and which one depends on what is on the ground.**
## With no plan up it opens the list; with one up it switches that plan off and
## does not open anything. That is what makes the square honest as a toggle: it
## lights while a plan is showing, and pressing a lit button turns the thing it
## is lit for off, rather than reopening a menu the player is already done with.
##
## Which is also why it is IMMEDIATE rather than SUBMENU. A SUBMENU ability is
## pure card navigation the panel performs for it, and there is no way for one
## to say "not this time" - so this pushes the card itself, on the one press
## that means to open it. Everything else about it is an ordinary card entry.

@export_group("Blueprints")
## The nine slots, in card order. Every entry should be a ShowBlueprintAbility.
##
## Authored here rather than generated from BlueprintLibrary.SLOT_COUNT,
## because each one is a .tres with an id of its own - and an id has to be
## authored, never derived from a position in a list. See CLAUDE.md.
@export var slots: Array[UnitAbility] = []


## Never a command: it reads a local file and shows a mesh.
func is_local_only() -> bool:
	return true


func execute(_unit: Unit, _target: AbilityTarget) -> void:
	var overlay: BlueprintOverlay = References.blueprint_overlay
	if overlay == null:
		Log.err("There is no BlueprintOverlay on References, blueprints cannot be shown")
		return

	if overlay.is_showing():
		overlay.hide_blueprint()
		return

	var panel: UnitPanel = References.unit_panel
	if panel == null:
		return
	# A local ability runs once per selected unit, and a card only wants
	# pushing once. Guarded rather than left to there being one builder,
	# because "there is one of those" is the kind of thing that stops being
	# true quietly.
	if panel.is_in_submenu():
		return
	panel.push_card(slots)


## Pointless on a card with no slots behind it, and on a machine with nowhere
## to draw one.
func can_execute(unit: Unit) -> bool:
	return unit != null && !slots.is_empty() && References.blueprint_overlay != null


## Lit while any plan is on the ground, which is the whole of what the second
## press means. The unit is ignored: a plan belongs to the machine rather than
## to the builder that opened it, and it stays up after that builder is
## deselected.
func is_toggled_on(_unit: Unit) -> bool:
	var overlay: BlueprintOverlay = References.blueprint_overlay
	return overlay != null && overlay.is_showing()


## The card this opens. Not read by the panel - this ability pushes its own -
## but it is how the registry's walk reaches nine abilities that are otherwise
## named by nothing else on the builder's card.
func submenu_abilities() -> Array[UnitAbility]:
	return slots


## Its own emptiness check, because the one on the base class only covers a
## SUBMENU and this is deliberately IMMEDIATE - see the note at the top. Same
## failure it is guarding against, and the same reason it must be loud.
func validate(seen: Dictionary) -> bool:
	var complete: bool = super(seen)
	if slots.is_empty():
		Log.err("Blueprints ability has no slots, its card would open empty",
			{"id": ability_id})
		complete = false

	for entry in slots:
		var ability: UnitAbility = entry as UnitAbility
		if ability != null && !ability.validate(seen):
			complete = false
	return complete
