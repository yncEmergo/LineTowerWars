class_name FireDiscPassive
extends DiscPassive

## Fire's disc: whatever walks over it explodes for a share of its own maximum
## health.
##
## unit_data.md 5.2. The second ON-STEP trigger, and the one that makes the
## walkable rule pay for itself: a share of MAXIMUM health is the only kind of
## damage in the game that is worth the same against a Sheep and against a
## Behemoth, so a Fire disc is what a maze puts down against the wave it cannot
## otherwise hurt.
##
## TWO GATES, and they are deliberately different questions:
##
##   the DISC's own cooldown, which is how often this square can go off at all
##   the CREEP's immunity, which is shared by EVERY Fire disc on the field - so
##   a lane of them is worth one explosion per creep per window, not one each
##
## The immunity is what stops a wall of Fire discs being an instant kill on
## anything that walks into it, and it is keyed by a shared string for exactly
## that reason. See StatusEffects.set_immune.
##
## The damage is Spell Damage, so it ignores armour entirely. A percentage of
## maximum health that was then reduced by the target's armour would not be a
## percentage of maximum health, and the whole point of the number is that it
## is the same share whatever it lands on.

@export_group("Detonate")
## Share of the creep's MAXIMUM health dealt, 0.33 for 33%.
@export var max_health_share: float = 0.20
## How long this disc waits before it can fire again.
@export var cooldown_seconds: float = 30.0
## How long the creep is then immune to every Fire disc in the game.
@export var creep_immunity_seconds: float = 5.0

## What the disc counts its own cooldown under, in its ability_state.
const GATE: String = "fire_disc_cooldown"
## What a creep counts its immunity under. ONE key for the whole element, which
## is what makes it an immunity to Fire discs rather than to this disc.
const IMMUNITY: String = "fire_disc"


func _reach_creeps(disc: Building) -> void:
	var standing: Array[Creep] = _creeps_on(disc)
	if standing.is_empty():
		return

	# The creeps are found and filtered BEFORE the cooldown is spent, so a disc
	# whose whole catch is already immune does not burn its thirty seconds on
	# an explosion that would have hurt nothing.
	var caught: Array[Creep] = []
	for creep: Creep in standing:
		if !creep.status().is_immune(IMMUNITY):
			caught.append(creep)
	if caught.is_empty() || !_gate_ready(disc, GATE, cooldown_seconds):
		return

	for creep: Creep in caught:
		creep.status().set_immune(IMMUNITY, creep_immunity_seconds)
		creep.take_damage(maxi(1, int(round(float(creep.max_health())
			* max_health_share))), DamageTable.DamageType.SPELL, false)


func _gate_keys() -> Array[String]:
	var keys: Array[String] = [GATE]
	return keys


func effect_text() -> String:
	return ("A ground creep that steps on this disc takes %s%% of its maximum"
		+ " health as spell damage, and is then immune to every Fire disc for"
		+ " %ss. The disc itself waits %ss.") % [
		StringUtil.trim_number(max_health_share * 100.0),
		StringUtil.trim_number(creep_immunity_seconds),
		StringUtil.trim_number(cooldown_seconds)]
