class_name VoidDiscPassive
extends DiscPassive

## Void's disc: friendly towers in range deal more damage, and how much more
## depends on how VARIED the maze around the disc is.
##
## unit_data.md 5.2 calls it the "reward a varied maze" disc, and it is the one
## effect in the roster whose strength is a question about the player's own
## building rather than about the disc: a fixed share per DISTINCT tower type
## standing inside the radius, up to a cap.
##
## Distinct by unit_type_id, which is the game's own answer to "what kind of
## thing is this" and is what makes a Lesser Archer and an Archer two types
## while two Lesser Archers are one. So a wall of one tower repeated gets the
## first step and nothing more, and a mixed maze gets the lot.
##
## NON-DISC is structural rather than filtered. The count comes from
## TargetFinder, which finds only attackable buildings, and a disc is
## invulnerable - so a player cannot feed one Void disc by surrounding it with
## other discs, and nothing here has to say so.

@export_group("Emptiness")
## Share added to attack damage per distinct tower type in range, 0.03 for +3%.
@export var damage_per_type: float = 0.02
## The most it can reach however varied the maze is, 0.24 for +24%.
@export var damage_cap: float = 0.08


func _reach_towers(disc: Building) -> void:
	var towers: Array[Building] = _towers_in_range(disc)
	var bonus: float = minf(damage_per_type * float(_distinct_types(towers)),
		damage_cap)
	if bonus <= 0.0:
		return
	for tower: Building in towers:
		_lend(tower, TowerBuffs.Kind.DAMAGE, bonus)


## How many different KINDS of tower are standing in the radius.
##
## A tower with no stats at all counts as nothing rather than as a type of its
## own: that is a content bug reported elsewhere, and letting it quietly raise
## a Void disc would hide it.
func _distinct_types(towers: Array[Building]) -> int:
	var seen: Dictionary = {}
	for tower: Building in towers:
		if tower.stats != null:
			seen[tower.stats.unit_type_id] = true
	return seen.size()


func effect_text() -> String:
	return ("Friendly towers within %s cells deal %s%% more damage for each"
		+ " different type of tower standing in that radius, up to %s%%.") % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(damage_per_type * 100.0),
		StringUtil.trim_number(damage_cap * 100.0)]
