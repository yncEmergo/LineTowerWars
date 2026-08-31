class_name ReactiveArmorPassive
extends CreepPassive

## The harder it is hit, the less of the hit gets through.
##
## The Goblin Shredder trait. unit_data.md 6.6: "damage above 1,000 reduced by
## 75%; damage above 300 reduced by 95%."
##
## `?` READ AS BANDS, which is a CHOICE this project made rather than a
## reading. The source states two thresholds with the SMALLER one carrying the
## HARSHER reduction, which cannot both be a whole-hit multiplier - a 1,001
## damage hit would then land for more than a 999 one. Read as bands it is
## coherent and matches how armour like this behaves everywhere else: every
## point up to the first threshold lands in full, everything between the two
## is cut by 95%, and everything past the second by 75%.
##
## Which makes it enormously good against a maze of medium hits and merely good
## against one enormous one - so a Goblin Shredder is walked into a lane of
## many towers and avoided by a lane of one big one. That reading is the whole
## character of the creep, so it is authored as a table rather than hard coded:
## the bands are three exports and can be re-read without touching this file.
##
## It is asked on the damage that ACTUALLY LANDED rather than on the attacker
## roll, which is what landed_damage_ratio() exists for - the thresholds are
## stated in what a creep takes, so a hit that is huge on paper and arrives
## through the armour matrix as a scratch must not trip the top band.

@export_group("Bands")
## Damage in one hit below which nothing is reduced at all.
@export var first_threshold: float = 300.0
## Share of the damage BETWEEN the two thresholds that still lands.
@export_range(0.0, 1.0, 0.01) var middle_ratio: float = 0.05
## Damage in one hit above which the second band takes over.
@export var second_threshold: float = 1000.0
## Share of the damage ABOVE the second threshold that still lands.
@export_range(0.0, 1.0, 0.01) var top_ratio: float = 0.25


func landed_damage_ratio(_creep: Creep, landed: float) -> float:
	if landed <= first_threshold || landed <= 0.0:
		return 1.0

	var kept: float = first_threshold
	var middle: float = minf(landed, second_threshold) - first_threshold
	kept += maxf(0.0, middle) * middle_ratio
	kept += maxf(0.0, landed - second_threshold) * top_ratio
	return clampf(kept / landed, 0.0, 1.0)


func effect_text() -> String:
	return ("Takes the first %s damage of any hit in full, %d%% less of"
		+ " everything up to %s, and %d%% less of everything past that.") % [
		StringUtil.trim_number(first_threshold),
		roundi((1.0 - middle_ratio) * 100.0),
		StringUtil.trim_number(second_threshold),
		roundi((1.0 - top_ratio) * 100.0),
	]
