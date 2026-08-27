class_name BurstingLightPassive
extends TowerPassive

## Holy base towers, and the shared half of the Titan Vault above them: one
## attack that strikes several creeps at once.
##
## unit_data.md 4.4 states the Holy line by how many creeps one attack HITS
## rather than by a radius, and that is the whole identity of the element -
## Light Flies hit five creeps for eleven damage each while everything else its
## price hits one for more. It is multishot rather than splash, so a creep that
## resists area damage gets no help from it (game_rules.md).
##
## The count here is "ADDITIONAL", matching the wording of the source and of
## TowerPassive.extra_targets: a tower hitting six in total authors five.

@export_group("Bursting Light")
## Creeps struck alongside the primary target.
@export var additional_targets: int = 4


func extra_targets(_tower: Building) -> int:
	return additional_targets


func effect_text() -> String:
	return "Each attack strikes %d additional creeps, for %d in total." % [
		additional_targets, additional_targets + 1]
