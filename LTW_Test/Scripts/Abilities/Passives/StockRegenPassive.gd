class_name StockRegenPassive
extends CreepPassive

## Refills this creep's reserve in the send building faster than normal.
##
## It acts on the SEND BUILDING rather than on the creep in the maze, which is
## the odd one out among the passives: it is what a player feels before the
## creep ever exists. Written as a multiplier rather than baked into the
## creep's stock_regen_seconds so the base rate stays one number in
## game_rules.md and the creep only states how much it beats it by.

@export_group("Settings")
## 1.25 is a quarter faster, so a 3 second reserve refills in 2.4.
@export var regen_ratio: float = 1.25


func stock_regen_ratio() -> float:
	return maxf(0.01, regen_ratio)


func effect_text() -> String:
	return "Its reserve in the send building refills %d%% faster." \
		% roundi((maxf(0.01, regen_ratio) - 1.0) * 100.0)
