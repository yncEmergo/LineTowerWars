class_name AbyssalCarapacePassive
extends CreepPassive

## Converts nearly the whole creep into a shield before it takes a step.
##
## The Behemoth trait, and the reason its numbers in unit_data.md 6.4 look
## wrong at first reading: "on spawn, 90% of maximum health is converted into a
## damage absorption shield", so a creep with 546,865 health walks the lane
## showing a tenth of that with the rest standing in front of it.
##
## What it CHANGES is what "hurt" means to a Behemoth. Every point of the
## shield stops a point of damage flat, wherever it came from and whatever the
## armour matrix said about it - so the creep takes the same total punishment
## either way, and nothing that heals, mends or revives it can touch the nine
## tenths of it that are gone. A Behemoth is a wall exactly once.
##
## Both halves come out of ONE number. The share below is what the health bar
## keeps, and the shield is everything else expressed against it, so the two
## can never add up to more or less than the creep.
##
## The shield lives in the creep StatusEffects, which is what already owns
## every timed and stored thing on a creep - and is what gets it a row on the
## panel and onto the wire for free. See StatusEffects.absorb.

@export_group("Settings")
## Share of the creep authored health that stays as health. The rest becomes
## the shield.
@export_range(0.01, 1.0, 0.01) var health_share: float = 0.10


func max_health_ratio(_creep: Creep) -> float:
	return health_share


## Converted at SPAWN rather than on the first tick, so a Behemoth is never
## briefly a creep with a tenth of its health and no shield - which for one
## sent into a lane of towers is a creep that could die in the gap.
func on_spawn(creep: Creep) -> void:
	if creep == null || health_share <= 0.0 || health_share >= 1.0:
		return
	# Expressed against what the creep has LEFT rather than against what it was
	# authored with, so the two halves are read off one number: a tenth on the
	# bar and nine times that in front of it.
	creep.status().absorb(self,
		float(creep.max_health()) * (1.0 - health_share) / health_share)


func effect_text() -> String:
	return ("Converts %d%% of its maximum health into a shield that absorbs"
		+ " damage before any of it reaches the creep.") \
		% roundi((1.0 - health_share) * 100.0)
