class_name BlazingInfernoPassive
extends TowerPassive

## Fire 1, Lesser and Greater Doom Guard: the tower that is at its strongest
## the moment it is built and is worth less every second afterwards.
##
## unit_data.md 4.3: it starts at full mana, loses a fixed share of it per
## second and **can never regain it**. Its attacks are scaled by what is left,
## and while any is left every attack also explodes around the creep it hit.
##
## The decay is the whole design, so it is a NEGATIVE mana_per_second rather
## than a countdown of its own - Building.gain_mana already clamps at zero, and
## nothing anywhere refills a Doom Guard.

@export_group("Blazing Inferno")
## Share of MAXIMUM mana lost per second. 0.0083 is the 0.83%/sec of the
## source, which empties a tower over about two minutes.
@export var decay_per_second: float = 0.0083
## Extra damage at FULL mana, as a share of the roll. 3.0 is the +300% the
## source states, scaled down linearly as the mana drains.
@export var max_bonus_share: float = 3.0
## Share of the damage dealt that the tower explodes for, as Spell Damage.
@export var explosion_share: float = 0.66
## Radius of that explosion, in player cells.
@export var explosion_cells: float = 1.56


func mana_per_second(tower: Building) -> float:
	return -decay_per_second * float(tower.max_mana)


func bonus_damage(tower: Building, _target: Unit, rolled: int) -> int:
	return int(round(float(rolled) * max_bonus_share * tower.mana_ratio()))


## Only the creep that was aimed at brings the explosion. A multishot picking
## up three more would otherwise set off three more blasts from one attack,
## which is not what the source describes and would be worth far more than the
## ability it is written as.
func on_hit(tower: Building, target: Unit, dealt: int, is_primary: bool) -> void:
	if !is_primary || tower.current_mana <= 0 || target == null:
		return
	spell_burst(tower.area, target.global_position, explosion_cells,
		int(round(float(dealt) * explosion_share)))


func effect_text() -> String:
	return ("Built at full mana and loses %s%% of it per second, never"
		+ " regaining any. Attacks deal up to +%d%% damage scaled by the mana"
		+ " left. While any remains, each attack explodes for %d%% of the"
		+ " damage dealt as Spell Damage within %s cells.") % [
		StringUtil.trim_number(decay_per_second * 100.0),
		int(round(max_bonus_share * 100.0)),
		int(round(explosion_share * 100.0)),
		StringUtil.trim_number(explosion_cells),
	]
