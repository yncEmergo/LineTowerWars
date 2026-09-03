class_name UnholyDiscPassive
extends DiscPassive

## Unholy's disc: attacks by friendly towers in range eat armour permanently.
##
## unit_data.md 5.2, reworked in 11.0a into what it is now. An attack modifier
## like Ice's, and the erosion stops at 0 rather than carrying on into the
## negatives - the disc says "down to 0", where the Divineshroom line, which is
## the one thing in the game that goes past it, says so explicitly.
##
## The steps are tiny on purpose: a twentieth of an armour point a hit. What
## makes it worth a cell is that it is PERMANENT and that every tower in the
## radius is eating at the same creep, so a maze built around one is worth more
## the longer a wave has been walking through it.

@export_group("Corrosion")
## Armour points eaten per hit, permanently.
@export var armor_per_hit: float = 0.05


func _reach_towers(disc: Building) -> void:
	for tower: Building in _towers_in_range(disc):
		_lend(tower, TowerBuffs.Kind.EROSION, armor_per_hit)


func effect_text() -> String:
	return ("Attacks by friendly towers within %s permanently reduce"
		+ " the target's armor by %s, down to 0.") % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(armor_per_hit, 3)]
