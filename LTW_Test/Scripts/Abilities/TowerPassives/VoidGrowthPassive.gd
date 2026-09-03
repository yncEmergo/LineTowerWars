class_name VoidGrowthPassive
extends VoidSpreadPassive

## Void base towers: a Voidling that has been shooting long enough turns one of
## its neighbours into another Voidling, free, ONCE.
##
## unit_data.md 4.9: it fills a mana bar by regenerating and by attacking, and
## the moment that bar is full the conversion happens. A lane seeded with one
## Void tower and left alone grows into a row of them, which is the whole
## identity of the element and the reason it is worth its low damage.
##
## THE MANA IS A CLOCK, NOT A COST. It is never spent and never resets - a
## Voidling that has grown stands there with a full bar for the rest of the
## match, which is exactly what a player should be able to read off it: this
## one is done. What stops it firing twice is the spent flag, and the bar is
## the countdown to the one time it fires.
##
## AND THE ATTEMPT IS SPENT WHETHER OR NOT IT LANDS. A tower that fills its bar
## with nothing eligible standing near it has missed its chance and does not
## get another - it does not sit waiting for a neighbour to be built next to it
## later. That makes WHERE a Void tower is placed a real decision rather than
## something that sorts itself out eventually.

## Key the once-only flag is kept under.
const SPENT_KEY: String = "void_growth_spent"

@export_group("Void Growth")
## Mana regenerated per second.
@export var regen_per_second: float = 1.0
## Mana gained per attack, on top of the regeneration.
@export var mana_per_attack: float = 1.0


func mana_per_second(_tower: Building) -> float:
	return regen_per_second


func on_attack(tower: Building, _target: Unit) -> void:
	tower.gain_mana(mana_per_attack)


func on_tick(tower: Building, _delta: float) -> void:
	if bool(tower.ability_state.get(SPENT_KEY, false)) || !tower.has_full_mana():
		return
	if !MatchSession.is_authority():
		return

	# Marked BEFORE the attempt rather than after it, and deliberately not
	# conditional on the result: a full bar is one chance, spent on whatever
	# was standing there at the moment it filled.
	tower.ability_state[SPENT_KEY] = true
	spread(tower)


func effect_text() -> String:
	var becomes: String = _becomes_name()
	return ("Regenerates %s mana per second and gains %s per attack. The"
		+ " moment its mana fills it transforms one tower within %s into"
		+ " %s %s, at no cost. It does this once: if there is no tower it can"
		+ " take in range at that moment, nothing happens and it does not"
		+ " try again.") % [
		StringUtil.trim_number(regen_per_second),
		StringUtil.trim_number(mana_per_attack),
		StringUtil.trim_number(reach_cells),
		StringUtil.article(becomes), becomes,
	]
