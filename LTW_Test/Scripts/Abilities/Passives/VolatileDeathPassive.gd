class_name VolatileDeathPassive
extends CreepPassive

## Goes off when it dies and damages the towers around it.
##
## The Phoenix trait. unit_data.md 6.6: "on death, deals 1,000 Physical Damage
## to towers within 250 AoE."
##
## The other half of what makes a Phoenix worth 3,000,000 gold: it is an
## attacker, so it is already standing on a tower when it dies, and the blast
## lands on whatever else the defender packed in beside it. Killing one on top
## of a maze is worse for the maze than letting it chew.
##
## Ordinary damage through the ordinary pipeline, so the defending tower armour
## type and the damage matrix both apply exactly as they would to any hit. It
## is stated as PHYSICAL rather than as spell for that reason - what it is
## worth depends on what it lands on.

@export_group("Settings")
## How far the blast reaches, in player cells. The source states 250, which
## snaps to 2 at the quarter every reach is stated in - unit_data.md 3.
@export var radius_cells: float = 2.0
## Damage dealt to each tower caught.
@export var damage: int = 1000
## What kind of damage it is, which decides how the defender armour reads it.
@export var damage_type: DamageTable.DamageType = DamageTable.DamageType.NORMAL


## Runs on death and does not call it off. Returning false is what says so.
func on_death(creep: Creep) -> bool:
	if creep.area == null || damage <= 0:
		return false

	for tower: Building in TargetFinder.buildings_in_radius(
			creep.area, creep.global_position, radius_cells):
		# is_aoe, because it is: a tower with area resistance should read this
		# the way it reads any other blast.
		tower.take_damage(damage, damage_type, true)
	return false


func effect_text() -> String:
	return "As it dies, deals %d %s damage to every tower within %s." % [
		damage, DamageTable.damage_type_text(damage_type),
		StringUtil.trim_number(radius_cells),
	]
