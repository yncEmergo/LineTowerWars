class_name ShowRangesAbility
extends UnitAbility

## Puts every range the selection carries on the ground for a few seconds.
##
## A tower's attack reach in the usual colour, and every ability radius it has
## in a second one - an aura, a heal, a spread. Aiming an Attack already shows
## the first; this is the answer to "and how far does the thing it DOES reach",
## which is the question a player is really asking while deciding where a Titan
## Vault or an Alchemist goes.
##
## **Local only.** It draws two circles on one machine and changes nothing: the
## server has no camera and no selection, and the other players have no
## business being told what you are looking at. So it never becomes a command -
## see UnitAbility.is_local_only(), which is the same line the build ghost, the
## selection and the build grid toggle sit on.
##
## Which abilities answer with a radius is the ability's own question, asked
## through UnitAbility.display_radius() rather than listed here. An attack's
## SPLASH is deliberately not one of them: it lands where the shot lands, so a
## ring around the tower would be describing the wrong thing.
##
## On every tower's card, which is why it is a shared resource rather than one
## per tower: the same square, the same key and the same answer everywhere.

@export_group("Show Ranges")
## How long the circles stay up before they go away again, in seconds.
##
## A duration rather than a toggle: it is READ and then done with, so leaving
## it switched on would mean every player learning to switch it off again, and
## a maze covered in circles is a maze nobody can see the creeps in.
@export var reveal_seconds: float = 5.0


## Never a command. This draws a mesh for a few seconds and nothing else.
func is_local_only() -> bool:
	return true


## Shows the whole SELECTION rather than this one unit, which is what aiming an
## Attack already does - the ranges of the towers you have picked is one
## picture, and drawing it per unit would paint the shared ground twice.
##
## So it does the same thing however many units it is run for, and running it
## once per selected unit - which is what a local ability's execution does -
## simply redraws the same circles and restarts the same clock.
func execute(_unit: Unit, _target: AbilityTarget) -> void:
	var commands: CommandController = References.command_controller
	if commands == null:
		return
	commands.reveal_ranges(reveal_seconds)


## Greyed out on a unit with nothing to draw, rather than offering a button
## that puts nothing on the ground.
func can_execute(unit: Unit) -> bool:
	if unit == null || unit.stats == null:
		return false
	if unit.stats.attack != null && unit.stats.attack.attack_range > 0.0:
		return true
	for ability: UnitAbility in unit.stats.abilities:
		if ability != null && ability.display_radius(unit) > 0.0:
			return true
	return false
