class_name SpellResistancePassive
extends CreepPassive

## Takes less from SPELL damage, serves less of a harmful effect's clock, and
## shrugs off part of a movement chill. The roster's four resistances are all
## this one script at four settings - see unit_data.md 6.6.
##
## Spell damage is the one damage kind that ignores the armour matrix and the
## creep's armour points entirely, so this is the only defence a creep has
## against it at all. That is what makes a spell worth aiming at a heavily
## armoured Boss, and what makes this trait worth carrying. See unit_data.md
## 1.1 and Config/DamageTable.gd.
##
## THREE SETTINGS RATHER THAN ONE, because the source game really does state
## them separately and they do not move together: the Major resistance takes
## two thirds off the damage and only half off the clock, where the ordinary
## one takes half the damage and nine tenths of the clock. A single "strength"
## number could not say that.
##
## The duration and chill halves were written down long before anything in the
## game applied either. They do something now: the elemental roster brought
## Combat/StatusEffects.gd, which asks the creep for both.

## All three default to NO resistance at all, and every resource states its own
## three. A default carrying one tier's figure would be quietly stripped out of
## any .tres that matched it when the editor next saved the file, moving that
## creep's data into this script - the trap CLAUDE.md records under writing
## resources by hand.

@export_group("Settings")
## Share of spell damage the creep takes. 0.67 is a third less, which is the
## Lesser resistance; 0.5 is Spell Resistance and 0.34 the Major one.
@export_range(0.0, 1.0, 0.01) var damage_ratio: float = 1.0
## Share of a harmful timed effect's window the creep serves. 0.25 is "harmful
## spell durations -75%", which is the Lesser resistance's figure.
@export_range(0.0, 1.0, 0.01) var duration_ratio: float = 1.0
## Share of a movement chill's magnitude that lands. 0.5 is the "50% immune to
## movement chill" every one of the resistances but the Major one carries.
@export_range(0.0, 1.0, 0.05) var chill_ratio: float = 1.0


func damage_taken_ratio(_is_aoe: bool, is_spell: bool) -> float:
	return damage_ratio if is_spell else 1.0


func harmful_duration_ratio() -> float:
	return duration_ratio


func chill_taken_ratio() -> float:
	return chill_ratio


## Built from its own three numbers, so the card can never quote a resistance
## the creep does not have. The chill clause is left off entirely when nothing
## is resisted rather than reading "0% immune", which is the one part of this a
## player would misread.
func effect_text() -> String:
	var parts: PackedStringArray = PackedStringArray([
		"Takes %d%% less spell damage" % roundi((1.0 - damage_ratio) * 100.0),
		"harmful effects last %d%% less" % roundi((1.0 - duration_ratio) * 100.0),
	])
	if chill_ratio < 1.0:
		parts.append("%d%% immune to movement chill" % roundi((1.0 - chill_ratio) * 100.0))
	return "%s." % ", ".join(parts)
