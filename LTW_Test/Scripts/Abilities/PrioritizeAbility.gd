class_name PrioritizeAbility
extends UnitAbility

## Switches a tower between shooting whatever its normal priority picks and
## going for air first.
##
## A TOGGLE rather than a one-shot order: pressing it flips the tower and
## leaves it flipped, which is what makes it worth a permanent square on the
## card. The slot shows which way it is set, see UnitAbility.is_toggled_on().
##
## Only ever offered by a tower that can hit BOTH ground and air. On a
## ground-only tower there is nothing to prefer, and on the anti-air branch
## there is nothing else to shoot - in both cases the button would be a lie, so
## it greys out rather than being authored off each card by hand.
##
## Not local only. Which creep a tower shoots is simulation, so this crosses
## the wire like any other order and the server flips its own copy. A client
## that flipped its own would be describing a fight the server never had.
##
## The setting itself lives on the tower's AttackComponent, because it is per
## tower and this resource is shared by every tower of its type.


func execute(unit: Unit, _target: AbilityTarget) -> void:
	var attack: AttackComponent = _attack_of(unit)
	if attack == null:
		return
	attack.set_prioritize_air(!attack.prioritizes_air())


func can_execute(unit: Unit) -> bool:
	var attack: AttackComponent = _attack_of(unit)
	if attack == null || unit.stats == null || unit.stats.attack == null:
		return false
	# Nothing to choose between unless the tower can really shoot both.
	return unit.stats.attack.can_hit_ground() && unit.stats.attack.can_hit_air()


## Lit while the tower is set to go for air first, so the card answers "which
## way is this one set" without being hovered.
func is_toggled_on(unit: Unit) -> bool:
	var attack: AttackComponent = _attack_of(unit)
	return attack != null && attack.prioritizes_air()


func _attack_of(unit: Unit) -> AttackComponent:
	if unit == null:
		return null
	return unit.attack_component
