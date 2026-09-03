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
##
## WELL OVER gdlint's public-method ceiling, and knowingly. Tiers 3 and 4 are
## where the roster stops being "the same question with a different number" and
## starts asking new ones: whether a creep walks through towers, whether it
## dodges, what its maximum health really is, what armour type it counts as.
## Each of those is one line here and a neutral default for every passive that
## does not care. The alternative - a hook object per family of question - is a
## .tres and a layer of indirection for the one or two that would hold one.


## Passives are never activated. The card greys them out and their square
## carries no hotkey letter, so there is nothing to run.
func execute(_unit: Unit, _target: AbilityTarget) -> void:
	pass


## Share of incoming damage the creep takes, applied after the damage matrix
## and before its armour points. Multiplied together across every passive.
##
## Takes the DAMAGE TYPE rather than a pair of booleans, because two of the
## roster's resistances care which type it actually was - Elemental Warding
## resists whichever one has hurt it most - and "is it a spell" is one call on
## DamageTable away from the type. `is_aoe` cannot be derived and stays.
##
## Takes the creep for the same reason armor_delta() does: two of these answer
## with a number read off that creep's own mana or health.
func damage_taken_ratio(_creep: Creep, _damage_type: DamageTable.DamageType,
		_is_aoe: bool) -> float:
	return 1.0


## Flat points taken off a hit last of all, after every multiplier. Summed
## across every passive.
func damage_block() -> int:
	return 0


## Share of a hit that reaches this creep once its own bands have run, asked on
## the damage that ACTUALLY LANDED rather than on the attacker's roll.
##
## A separate question from damage_taken_ratio() because Reactive Armor states
## its thresholds in what the creep really takes, so a band read off the roll
## would fire on a hit that arrived as a scratch. Multiplied across passives.
func landed_damage_ratio(_creep: Creep, _landed: float) -> float:
	return 1.0


## Share of a harmful timed effect's DURATION this creep actually serves.
## 1.0 is the full window, 0.1 is a tenth of it. Multiplied across passives.
##
## A separate question from damage_taken_ratio() because the source game states
## it separately: every spell resistance in the roster shortens durations by a
## different amount than it blunts damage, and the Major one is the case that
## proves they are not the same knob - it takes a third off the damage and half
## off the clock. See unit_data.md 6.6.
func harmful_duration_ratio() -> float:
	return 1.0


## The longest a harmful timed effect may run on this creep whatever it asked
## for, in seconds, or 0 for no ceiling at all. The smallest cap across every
## passive wins, applied after the ratio above.
##
## A CEILING rather than a share, because Regenerative Flesh states both: two
## thirds off, and never more than a second and a half. A ratio alone cannot
## say the second half.
func harmful_duration_cap() -> float:
	return 0.0


## Share of a movement chill's MAGNITUDE that lands on this creep. 1.0 takes
## the full slow, 0.5 is the "50% immune to movement chill" the spell
## resistances carry, 0.0 is outright immunity. Multiplied across passives.
##
## The MAGNITUDE rather than the duration, which is the question above: the
## source game blunts how far a slow goes and shortens how long it lasts as two
## separate numbers, and a creep can carry one without the other.
func chill_taken_ratio() -> float:
	return 1.0


## The most this creep may ever be slowed, as a share of its speed, whatever
## has accumulated on it. 1.0 is no ceiling; 0.25 is Goblin Engineering's
## "cannot be chilled or slowed by more than 25%". The smallest wins.
##
## A CAP on the total rather than a share of each application, which is the
## difference between it and chill_taken_ratio() above: one blunts every chill
## as it lands, this one refuses to let the pile go past a line however many
## towers are stacking on it.
func max_slow_share() -> float:
	return 1.0


## Armour points granted to every creep inside the shared creep aura radius,
## this one included. The best aura in range wins; they do not add up.
##
## Every aura hook takes the creep CARRYING the aura, never the one receiving
## it: one of them is switched on by its own creep's health, and the answer is
## then the same for everything standing in range.
func aura_armor_bonus(_creep: Creep) -> int:
	return 0


## Armour points this passive adds to or takes off the creep CARRYING it,
## summed across every passive on that creep.
##
## A different question to the aura above, which is what this creep hands to
## everything standing near it: this one never leaves the creep and so adds
## rather than taking the best. Hardened Skin is the loudest thing that answers
## it, with a negative number that grows as the creep is worn down.
##
## Takes the creep because the answer is about THAT one, and a shared resource
## may hold no state of its own - the same reason on_death() does.
func armor_delta(_creep: Creep) -> int:
	return 0


## The armour TYPE this creep counts as, or -1 to leave it its own. The FIRST
## passive to name one wins, since two disagreeing is an authoring mistake
## rather than something to resolve on every hit.
func armor_type_override(_creep: Creep) -> int:
	return -1


## Multiplier on this creep's MAXIMUM health. Multiplied across passives.
##
## Here rather than in the stats file because one trait in the roster converts
## something else into health - Bone Shield turns every point of base armour
## into 4% more of it - so the creep's real ceiling is not a number anybody
## could have authored next to the other stats.
func max_health_ratio(_creep: Creep) -> float:
	return 1.0


## Multiplier on the MOVEMENT speed of every creep inside the shared aura
## radius, this one included. Above 1 is faster, and the best aura in range
## wins exactly as it does for armour.
func aura_move_speed_ratio(_creep: Creep) -> float:
	return 1.0


## Multiplier on the ATTACK speed of every creep inside the shared aura radius,
## which matters only to the attacker creeps - everything else in a pack has no
## attack for it to act on.
func aura_attack_speed_ratio(_creep: Creep) -> float:
	return 1.0


## Multiplier on how hard every creep inside the shared aura radius HITS, which
## again only the attacker creeps have anything for. War Stance is the only
## thing in the roster that grants one, and only once its own creep is hurt.
func aura_attack_damage_ratio(_creep: Creep) -> float:
	return 1.0


## Health restored per second to every creep inside the shared aura radius,
## this one included. Separate from health_regen() below, which is the creep
## healing only ITSELF: an aura reaches the pack, and the two are added rather
## than one hiding the other.
func aura_health_regen(_creep: Creep) -> float:
	return 0.0


## Whether this creep is deaf to every friendly aura standing over it, its own
## included. One creep in the roster is - unit_data.md 6.6, Unfathomable Power
## - and it is the whole reason a Demon cannot be made faster or tougher by
## walking it inside a pack.
func ignores_auras() -> bool:
	return false


## Multiplier on how hard this creep's OWN attack lands. Multiplied across
## passives, and only the attacker creeps have an attack for it to act on.
func attack_damage_ratio(_creep: Creep) -> float:
	return 1.0


## Whether the creep never draws a tower's attention and is always shot at
## last. Read once when the creep collects its passives, not per scan, since a
## creep cannot gain or lose a passive while it walks.
func is_skittering() -> bool:
	return false


## Whether the creep walks THROUGH towers rather than around them, which is
## half of what Ethereal means. Read once with the rest, for the same reason.
##
## An ethereal creep reads none of the occupancy grid and goes straight down
## the lane exactly as a flyer does - and unlike a flyer it stays on the floor,
## so every tower may still shoot it.
func is_ethereal() -> bool:
	return false


## Chance from 0 to 1 that an attack from a tower reaching this far simply
## misses. The best chance across every passive wins rather than the sum, so
## two dodges could never make a creep untouchable.
##
## Takes the attacker's REACH because that is what the one dodge in the roster
## is written against: Quickness only works against towers that shoot from far
## enough away, which is what stops a Huntress being immune to a short ranged
## maze as well as to a long one.
func dodge_chance(_attack_range: float) -> float:
	return 0.0


## Multiplier on how fast this creep's reserve refills in the send building.
## Above 1 is faster. Multiplied together across every passive.
func stock_regen_ratio() -> float:
	return 1.0


## Health restored per second while the creep is alive and hurt.
##
## Takes the creep because one of them scales with how hurt it already is,
## which is a reading of that creep and not of this resource.
func health_regen(_creep: Creep) -> float:
	return 0.0


## Runs once, the moment the creep is placed in its first maze and before it
## has taken a step.
##
## What a trait that is true FROM SPAWN gets - a shield converted out of
## maximum health, a pool primed - rather than a first tick that would have to
## remember whether it had already run.
func on_spawn(_creep: Creep) -> void:
	pass


## Runs the moment the creep's health reaches zero, before it is removed and
## before any bounty is paid. Return true to report the creep is still alive,
## which calls the death off entirely - so a revived creep pays no bounty,
## because it did not die.
func on_death(_creep: Creep) -> bool:
	return false


## Runs after a hit has actually landed, with the health the creep really lost
## and what kind of damage took it.
##
## The LANDED figure rather than the attacker's roll, for the same reason
## Hardened Skin counts that one: everything on the defender has already been
## applied, so a passive here is reading what the player watched leave the
## health bar. Nothing is called on a client, on an invulnerable unit or on a
## creep already down, because in all three cases no health moved.
##
## Takes the creep because the answer is about THAT one, the same reason
## on_death() does: this resource is every creep of its type at once.
func on_damage_taken(_creep: Creep, _lost: float,
		_damage_type: DamageTable.DamageType) -> void:
	pass


## Runs once per simulation tick, for a passive that is on a clock of its own
## rather than being asked a question when something happens.
##
## The clock itself lives on the CREEP - see Creep.advance_passive_clock() -
## because this resource is shared and may remember nothing. A passive that
## only answers questions never overrides this and pays nothing for it.
##
## Authority only: it is called from the creep's own _physics_process, which a
## client leaves at the door (multiplayer.md 3.4).
func on_tick(_creep: Creep, _delta: float) -> void:
	pass


## What counts as a HEAVY hit on this creep, in damage actually landed, or 0
## for a creep that does not care - which is every one of them but the Ancient
## Wendigo. The creep counts the hits that reach it and an ability reads the
## count back, so nothing here has to remember anything per creep.
##
## Asked once when the creep collects its passives, so it must be a plain
## reading of an @export and never depend on the creep's state.
func heavy_hit_threshold() -> float:
	return 0.0


## One line describing what this passive does, built from its OWN numbers so
## nothing can quote a figure the passive does not use. Subclasses fill this in
## rather than writing the sentence into their .tres by hand.
func effect_text() -> String:
	return ""


## What gets shown wherever this passive is listed: the generated line if it
## has one, and the authored description - placeholders filled - otherwise.
##
## Takes the creep's STATS rather than the creep, because everything a trait
## description quotes is a property of the TYPE, and the two places that ask
## for this have one of those and not always the other: the send tooltip is
## describing a creep nobody has spawned yet.
func passive_text(context: UnitStats = null) -> String:
	var text: String = effect_text()
	return text if !text.is_empty() else description_text(context)


## The generated line replaces the authored description, for the same reason
## it does everywhere else: one number, one place.
func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)
	data.description = passive_text(null if unit == null else unit.stats)
	return data


## The shared creep aura radius in cells, which EVERY aura in the roster uses -
## a player learns the size of an aura once and it holds for all of them. See
## GameConfig.creep_aura_radius_cells and game_rules.md.
##
## Here rather than copied into the several aura passives that quote it in
## their own sentence, so the text and the search can never disagree.
static func aura_radius() -> float:
	var config: GameConfig = References.game_config
	return 0.0 if config == null else config.creep_aura_radius_cells
