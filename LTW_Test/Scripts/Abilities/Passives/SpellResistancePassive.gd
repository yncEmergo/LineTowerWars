class_name SpellResistancePassive
extends CreepPassive

## Takes less from SPELL damage, the one damage kind that ignores the armour
## matrix and the creep's armour points entirely.
##
## So it is the only defence a creep has against a spell at all: armour does
## nothing there by design, which is what makes a spell worth aiming at a
## heavily armoured Boss and what makes this trait worth carrying. See
## unit_data.md 1.1 and Config/DamageTable.gd.
##
## The source game's spell resistances also shorten harmful spell DURATIONS and
## blunt movement chill. Neither exists yet - nothing in the game applies a
## slow or a timed debuff - so this covers the damage half only, and the rest
## follows the day a tower ability does either.

@export_group("Settings")
## Share of spell damage the creep takes. 0.67 is a third less, which is the
## Lesser resistance; 0.5 is Spell Resistance and 0.34 the Major one.
@export_range(0.0, 1.0, 0.01) var damage_ratio: float = 0.67


func damage_taken_ratio(_is_aoe: bool, is_spell: bool) -> float:
	return damage_ratio if is_spell else 1.0


func effect_text() -> String:
	return "Takes %d%% less spell damage." % roundi((1.0 - damage_ratio) * 100.0)
