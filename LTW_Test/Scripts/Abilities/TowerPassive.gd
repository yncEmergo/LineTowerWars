@abstract
class_name TowerPassive
extends UnitAbility

## Something a TOWER simply has, rather than something a player presses. Every
## elemental tower's named ability is one of these.
##
## The mirror of CreepPassive, and for the same reasons: a passive is an entry
## on the command card, so it wants the name, the description and the icon
## every other entry has, and it differs only in never activating - which its
## PASSIVE targeting already says.
##
## **Shared, so it holds NO per-tower state.** One lesser_lich_frost_blast.tres
## is every Lesser Lich on the field at once. Anything a tower has to REMEMBER
## - its mana, a damage bonus it has eaten, which target it was ramping up on -
## lives on the tower, in `Building.ability_state`, keyed by this passive.
##
## The hooks are separate questions with neutral defaults, so a passive
## overrides only what it answers. They are called in a fixed order, which is a
## rule rather than an accident of listing:
##
##   on_tick        every simulation tick, for regeneration, auras and the
##                  abilities that cast on a timer of their own
##   bonus_damage   added to the roll BEFORE the armour matrix, so a bonus is
##                  worth what the matchup says it is worth
##   damage_type_for  lets an attack be dealt as something other than its own
##                  type this once - "every other attack is Spell Damage"
##   extra_targets  further creeps this attack strikes alongside its primary
##   on_hit         once per creep actually struck, after it has taken the
##                  damage. Where slows, poison, armour erosion and the rest go
##
## AUTHORITY. Every hook runs on both machines, exactly as the attack that
## calls them does - a client fires, flies and lands its own shots as
## presentation. What must not happen twice is a CHANGE to the world, and that
## is refused at the door by the things a passive calls rather than here:
## take_damage, StatusEffects and Building.gain_mana all stand aside on a
## client. A passive that reaches past those and writes something itself has to
## check MatchSession.is_authority() for itself.

## How often an aura re-reads the creeps standing in it, in seconds.
##
## The same beat a creep re-reads the auras around IT on, and for the same
## reason: nothing an aura grants can change fast enough for a quarter second
## to show, and running one every tick would have each aura tower walk the
## whole creep list twenty times a second.
const AURA_REFRESH_SECONDS: float = 0.25

## How long an aura's effect is applied for each time it is refreshed.
##
## Comfortably longer than the gap between refreshes, so a creep standing still
## inside an aura never flickers out of it. What it costs is that a creep
## walking OUT keeps the effect for the rest of the window, which is a fraction
## of a second and is the cheap half of the trade.
const AURA_HOLD_SECONDS: float = 1.0


## Passives are never activated. The card greys them out and their square
## carries no hotkey letter, so there is nothing to run.
func execute(_unit: Unit, _target: AbilityTarget) -> void:
	pass


## Mana this tower regenerates per second, which the tower applies rather than
## the passive - so two passives that both regenerate simply add up and neither
## has to know about the other.
##
## NEGATIVE drains, which is what the Doom Guard line's decaying mana is.
func mana_per_second(_tower: Building) -> float:
	return 0.0


## Runs every simulation tick on a tower that is finished and able to act.
##
## For anything on a clock of its own: an Ignite that picks a creep every 2.1
## seconds, an aura that reaches the creeps standing around it, a Harbinger
## counting down to a rift. Nothing here is tied to the tower attacking.
func on_tick(_tower: Building, _delta: float) -> void:
	pass


## Raised when the tower COMMITS to an attack, before any damage exists.
##
## The place for anything measured per ATTACK rather than per creep hit: mana
## gained by attacking, a ramp that resets when the target changes, the idle
## bonus a Scorpion has been banking.
func on_attack(_tower: Building, _target: Unit) -> void:
	pass


## Damage to add to the roll, before the armour matrix sees it.
##
## Whole points rather than a share, so a passive that wants "+50%" reads the
## base roll it is handed and answers with half of it. Both shapes exist in
## unit_data.md and turning one into the other here would mean the caller
## deciding which a passive meant.
func bonus_damage(_tower: Building, _target: Unit, _rolled: int) -> int:
	return 0


## The damage type this one attack should be dealt as, or -1 to leave it alone.
##
## Exists for the Arcane Orb line, which deals every other attack as Spell
## Damage, and for Water 1, whose every third attack turns Chaos. Only the
## FIRST passive that answers is used, because two passives fighting over the
## type of one attack is an authoring mistake rather than something to resolve.
func damage_type_for(_tower: Building, _target: Unit) -> int:
	return -1


## Further creeps this attack strikes alongside its primary target.
##
## Summed across every passive, so a tower with two of them hits the total.
## unit_data.md states these as "hits N additional targets", which is exactly
## this number - a Holy Lantern hitting 6 in total answers 5.
func extra_targets(_tower: Building) -> int:
	return 0


## How far from the primary target a further creep may stand, in cells, or 0 to
## use the game's shared multishot reach. The Beastmaster names its own.
func extra_target_range(_tower: Building) -> float:
	return 0.0


## Runs once per creep actually struck, after that creep has taken the damage.
##
## `dealt` is what the hit cost the creep AFTER the whole pipeline, which is
## what every "20% of the damage dealt" in unit_data.md means. `is_primary`
## separates the creep that was aimed at from the ones caught alongside it.
func on_hit(_tower: Building, _target: Unit, _dealt: int, _is_primary: bool) -> void:
	pass


## Runs when a creep this tower struck dies, whoever finished it. The permanent
## damage the Alchemist and the Leviathan eat is bought here.
func on_kill(_tower: Building, _target: Unit) -> void:
	pass


## Damage this passive has permanently added to the tower's attack, on top of
## whatever its stats say. Read by the UI so a card can show what a tower has
## grown into, and by bonus_damage() implementations that grant it.
func permanent_bonus(_tower: Building) -> int:
	return 0


## One line describing what this passive does, built from its OWN numbers, so
## nothing can quote a figure the passive does not use. Same contract
## CreepPassive.effect_text() has.
func effect_text() -> String:
	return ""


## What gets shown wherever this passive is listed: the generated line if it
## has one, and the authored description otherwise.
func passive_text() -> String:
	var text: String = effect_text()
	return text if !text.is_empty() else description


## The generated line replaces the authored description, one number in one
## place, exactly as it does for a creep passive.
func tooltip_data(hotkey_label: String = "") -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label)
	data.description = passive_text()
	return data


# --- helpers every passive ends up wanting ---------------------------------

## Whether this tower's aura is due to be re-read, counting the time towards it
## along the way. `key` is what it counts under, so a tower carrying two auras
## keeps two clocks.
static func aura_due(tower: Building, key: String, delta: float) -> bool:
	var left: float = float(tower.ability_state.get(key, 0.0)) - delta
	if left > 0.0:
		tower.ability_state[key] = left
		return false
	tower.ability_state[key] = AURA_REFRESH_SECONDS
	return true


## The status effects on a struck unit, or null when it is not a creep at all.
## A tower can be shooting nothing but creeps, so this is only ever null when
## the target died on the way.
static func status_of(target: Unit) -> StatusEffects:
	var creep: Creep = target as Creep
	return null if creep == null else creep.status()


## Deals Spell Damage to every creep within `radius` cells of a point, and
## answers how many were struck.
##
## The shape almost every elemental ability's burst has, written once: it
## ignores armour entirely by being Spell Damage, and it counts what it hit
## because half of these abilities refund mana when they hit too few.
static func spell_burst(area: PlayerArea, at: Vector3, radius: float,
		damage: int) -> int:
	if area == null || damage <= 0 || radius <= 0.0:
		return 0

	var struck: int = 0
	for creep: Creep in TargetFinder.creeps_in_radius(area, at, radius):
		creep.take_damage(damage, DamageTable.DamageType.SPELL, true)
		struck += 1
	return struck
