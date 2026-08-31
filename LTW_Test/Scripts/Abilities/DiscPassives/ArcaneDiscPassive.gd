class_name ArcaneDiscPassive
extends DiscPassive

## Arcane's disc: whatever walks over it takes more spell damage and stops
## hearing the auras of its own pack.
##
## unit_data.md 5.2, reworked in 10.0a. An ON-STEP trigger, and one of the two
## effects in the game that exist only because a disc is something creeps walk
## OVER rather than around. See DiscPassive and game_rules.md.
##
## Both halves land as one effect with one duration, applied as two calls
## because they are already two pieces of machinery: an amplification is a
## share of incoming damage, and hearing no aura is a creep not listening to
## its neighbours. See StatusEffects.deny_auras.
##
## The gate is the DISC's, not the creep's - "can trigger once per second" -
## so a pack crossing one disc gets one touch a second between all of them
## rather than one each. That is what the source says and it is also what keeps
## a wave of ninety creeps from being ninety touches on one tick.

@export_group("Null Field")
## How long both halves last on a creep the disc has touched.
@export var duration_seconds: float = 12.0
## Extra share of SPELL damage the touched creep takes, 0.10 for +10%.
@export var spell_amp: float = 0.10
## How often this disc may fire at all.
@export var trigger_seconds: float = 1.0

## What the gate is counted under in the disc's own ability_state.
const GATE: String = "arcane_disc_trigger"


func _reach_creeps(disc: Building) -> void:
	var standing: Array[Creep] = _creeps_on(disc)
	if standing.is_empty():
		return
	if !_gate_ready(disc, GATE, trigger_seconds):
		return

	# Every creep on the square, not one of them. The gate is how often the
	# disc FIRES; what it catches when it does is whatever is standing on it.
	for creep: Creep in standing:
		var status: StatusEffects = creep.status()
		status.amplify_spell(self, spell_amp, duration_seconds)
		status.deny_auras(self, duration_seconds)


func _gate_keys() -> Array[String]:
	var keys: Array[String] = [GATE]
	return keys


func effect_text() -> String:
	return ("A ground creep that steps on this disc takes %s%% more spell"
		+ " damage and can benefit from no friendly aura for %ss."
		+ " Triggers at most once every %ss.") % [
		StringUtil.trim_number(spell_amp * 100.0),
		StringUtil.trim_number(duration_seconds),
		StringUtil.trim_number(trigger_seconds)]
