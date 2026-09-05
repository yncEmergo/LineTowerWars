class_name ShatterArmorPassive
extends TowerPassive

## Earth's armour erosion, shared by the base towers and by the Ancient Warden
## line above them.
##
## unit_data.md 4.2: attacks PERMANENTLY reduce the armour of what they hit, by
## a small step, down to a floor. The Rockfall stops at 1, everything above it
## stops at 0, and the Ultimate takes half a point at a time and heals itself
## out of what it deals.
##
## Permanent is the whole point. Every other armour effect in the game runs on
## a timer; this one is gone for the rest of that creep's life, so an Earth
## tower is worth more the longer a pack has been walking past it - and so it
## is the thing you put in FRONT of everything else.
##
## The "full damage across the whole splash radius" the Ancient Warden line
## carries is not here: a SplashEffect is already flat with no falloff at all
## (game_rules.md), so the tower's own splash already does it.

@export_group("Shatter Armor")
## Armour eaten per hit.
@export var armor_per_hit: float = 0.1
## How far down it may go. 1 on the Rockfall, 0 on everything above it.
@export var armor_floor: float = 1.0

@export_group("Nature's Guidance")
## Share of the damage dealt that the tower heals itself for, or 0 on the tiers
## that heal nothing.
@export var self_heal_share: float = 0.0


func apply_debuffs(_tower: Building, target: Unit) -> void:
	var status: StatusEffects = status_of(target)
	if status != null:
		status.erode_armor(self, armor_per_hit, armor_floor)


## Nature's Guidance: a share of what the shot COST, which for this line is
## everything the blast covered rather than the creep it aimed at.
##
## The Ancient Warden deals FULL damage across its whole splash radius
## (unit_data.md 4.2), so "2.35% of damage dealt" is a share of all of it. Paid
## out of the aimed creep alone it was a share of one twentieth of the tower's
## work, and it shrank exactly when the tower was doing the most - a healing
## tower that read as healing nothing.
##
## Both hooks, and the same line in each: on_hit is the creep it struck, and
## on_area_hit is every creep the blast reached. See TowerPassive.on_area_hit
## for why those stay two hooks.
func on_hit(tower: Building, _target: Unit, dealt: int, _is_primary: bool) -> void:
	_heal(tower, dealt)


func on_area_hit(tower: Building, _target: Unit, dealt: int) -> void:
	_heal(tower, dealt)


## A tower already at full health simply clamps, so the share is worked out and
## thrown away for nearly every Warden nearly all of the time. Guarded on the
## SHARE rather than on the health, because the tiers below the Ultimate author
## no heal at all and that is the case worth costing nothing.
func _heal(tower: Building, dealt: int) -> void:
	if self_heal_share > 0.0:
		tower.heal(int(round(float(dealt) * self_heal_share)))


func effect_text() -> String:
	var text: String = ("Attacks permanently reduce the target's armor by %s,"
		+ " down to %s.") % [
		StringUtil.trim_number(armor_per_hit),
		StringUtil.trim_number(armor_floor)]
	if self_heal_share > 0.0:
		text += " Heals the tower for %s%% of the damage dealt." \
			% StringUtil.trim_number(self_heal_share * 100.0)
	return text
