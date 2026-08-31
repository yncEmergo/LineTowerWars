class_name IceDiscPassive
extends DiscPassive

## Ice's disc: friendly towers in range chill what they hit.
##
## unit_data.md 5.2. An aura that is an ATTACK MODIFIER rather than a stat: the
## disc lends nothing a tower standing idle can use, and everything a tower
## that is shooting can.
##
## The chill is keyed by the DISC and not by the tower carrying it, which is
## what makes the cap mean what the source says. Twelve towers standing in one
## Ultimate Ice disc feed one accumulating chill towards one -36%; twelve caps
## of -36% each would be a stop rather than a slow. See TowerBuffs.

@export_group("Frostbind")
## Share of movement taken per hit, 0.018 for -1.8%.
@export var chill_per_hit: float = 0.01
## The floor those hits accumulate towards, 0.36 for -36%.
@export var chill_cap: float = 0.20


func _reach_towers(disc: Building) -> void:
	for tower: Building in _towers_in_range(disc):
		_lend(tower, TowerBuffs.Kind.CHILL, chill_per_hit)
		_lend(tower, TowerBuffs.Kind.CHILL_CAP, chill_cap)


func effect_text() -> String:
	return ("Attacks by friendly towers within %s cells chill their target"
		+ " %s%% per hit, up to %s%%.") % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(chill_per_hit * 100.0),
		StringUtil.trim_number(chill_cap * 100.0)]
