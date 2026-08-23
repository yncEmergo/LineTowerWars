@abstract
class_name CreepPassive
extends UnitAbility

## Something a creep simply HAS, rather than something a player presses.
##
## A UnitAbility on purpose. A passive is an entry on the command card, and it
## is what a send tooltip lists under the creep's stats, so it wants the same
## name, description and icon every other card entry has. It differs only in
## never activating, which its PASSIVE targeting already says - so it needs no
## flag and no separate widget.
##
## Shared like every resource, so a passive holds NO per-creep state. A revive
## that may only fire once records having fired on the CREEP, see
## Creep.spend(), because this one .tres is every skeleton on the field at once.
##
## The hooks below are separate questions with neutral defaults, so each
## passive overrides only the one it answers. Deliberately not one "modify the
## damage" call: the order the damage pipeline applies things in is a rule (see
## game_rules.md) and must not depend on the order somebody happened to list
## the passives in. Ratios multiply, blocks add, auras take the best - all
## order independent.


## Passives are never activated. The card greys them out and their square
## carries no hotkey letter, so there is nothing to run.
func execute(_unit: Unit, _target: AbilityTarget) -> void:
	pass


## Share of incoming damage the creep takes, applied after the damage matrix
## and before its armour points. Multiplied together across every passive.
func damage_taken_ratio(_is_aoe: bool) -> float:
	return 1.0


## Flat points taken off a hit last of all, after every multiplier. Summed
## across every passive.
func damage_block() -> int:
	return 0


## Armour points granted to every creep inside the shared creep aura radius,
## this one included. The best aura in range wins; they do not add up.
func aura_armor_bonus() -> int:
	return 0


## Multiplier on how fast this creep's reserve refills in the send building.
## Above 1 is faster. Multiplied together across every passive.
func stock_regen_ratio() -> float:
	return 1.0


## Health restored per second while the creep is alive and hurt.
func health_regen() -> float:
	return 0.0


## Runs the moment the creep's health reaches zero, before it is removed and
## before any bounty is paid. Return true to report the creep is still alive,
## which calls the death off entirely - so a revived creep pays no bounty,
## because it did not die.
func on_death(_creep: Creep) -> bool:
	return false


## One line describing what this passive does, built from its OWN numbers so
## nothing can quote a figure the passive does not use. Subclasses fill this in
## rather than writing the sentence into their .tres by hand.
func effect_text() -> String:
	return ""


## What gets shown wherever this passive is listed: the generated line if it
## has one, and the authored description otherwise.
func passive_text() -> String:
	var text: String = effect_text()
	return text if !text.is_empty() else description


## The generated line replaces the authored description, for the same reason
## it does everywhere else: one number, one place.
func tooltip_data(hotkey_label: String = "") -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label)
	data.description = passive_text()
	return data
