class_name FrostAttackPassive
extends TowerPassive

## The chill the whole Ice element is built on: Obelisk, Runic Monolith, and
## the Lich line above them.
##
## unit_data.md 4.5 states every one of them the same way - "-X% movement speed
## per hit, up to -Y%" - so this is one script and five .tres files. The Lich
## tiers add a duration bonus on top and the Ultimate adds Frostbitten, which
## is what Chilling Death is for.
##
## Every chill in the game ACCUMULATES towards its own cap and each source
## keeps its own, which is what "up to 25%" means at all. The source key below
## is what decides who shares one, and the whole Ice line shares a single key:
## an Obelisk, a Runic Monolith and every Lich above them feed ONE chill that
## climbs to whichever of their caps is highest, so upgrading a line replaces
## its slow rather than stacking a second copy of it. See StatusEffects.chill.

@export_group("Frost Attack")
## Movement taken per hit, as a share. 0.0375 is the -3.75% of the source.
@export var slow_per_hit: float = 0.0375
## The most this tower's chill may ever reach, as a share.
@export var slow_cap: float = 0.20
## How long a chill lasts before it wears off entirely. unit_data.md 1.3 says
## the base is 4 seconds; the Lich line authors more.
@export var slow_seconds: float = 4.0
## The key this tower's chill accumulates under. Every tower sharing it shares
## one cap, which is why every tier of the line authors the same one.
@export var chill_source: String = "ice"


func on_hit(_tower: Building, target: Unit, _dealt: int, _is_primary: bool) -> void:
	var status: StatusEffects = status_of(target)
	if status != null:
		status.chill(self, chill_source, slow_per_hit, slow_cap, slow_seconds, true)


func effect_text() -> String:
	return ("Each hit slows the target by %s%% movement speed, stacking up to"
		+ " %s%% and lasting %ss.") % [
		StringUtil.trim_number(slow_per_hit * 100.0),
		StringUtil.trim_number(slow_cap * 100.0),
		StringUtil.trim_number(slow_seconds),
	]
