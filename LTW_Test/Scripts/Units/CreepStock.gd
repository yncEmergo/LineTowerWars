class_name CreepStock
extends RefCounted

## The reserve of sends held for one creep type.
##
## It starts part full rather than empty or full: the source game hands a creep
## half its maximum the moment it unlocks, and the attacker creeps exactly one.
## CreepStats.starting_stock() is where that is decided, so this only ever asks.
##
## One of these per creep type per send building. Spending a send takes one,
## and they refill on their own timer, so a player cannot pour a single creep
## type out faster than it regenerates however much gold they have.
##
## The timer only runs while the reserve is below full. Letting it accumulate
## at full would bank an instant refill for anyone who simply waited, which
## would defeat the point of the limit.

var stats: CreepStats
var count: int = 0

var _elapsed: float = 0.0
## Seconds one stock takes, with the creep's own passives already folded in.
## Worked out once in setup() rather than per frame, since neither the stats
## nor the passives on them can change while a match runs.
var _interval: float = 0.0


func setup(creep_stats: CreepStats) -> void:
	stats = creep_stats
	count = 0 if creep_stats == null else creep_stats.starting_stock()
	_elapsed = 0.0
	_interval = _compute_interval()


func max_count() -> int:
	if stats == null:
		return 0
	return maxi(0, stats.max_stock)


func is_full() -> bool:
	return count >= max_count()


func has_stock() -> bool:
	return count > 0


## Takes one send, reporting whether there was one to take.
func consume() -> bool:
	if count <= 0:
		return false
	count -= 1
	return true


## How far along the current stock is, 0 to 1. Full reserves read as 1, so a
## cooldown drawn from this is simply absent when there is nothing to wait for.
func regen_progress() -> float:
	if is_full() || _regen_seconds() <= 0.0:
		return 1.0
	return clampf(_elapsed / _regen_seconds(), 0.0, 1.0)


## Advances the timer. Returns true when the count changed, so the UI only
## refreshes on a real change rather than every frame.
func advance(delta: float) -> bool:
	if is_full():
		_elapsed = 0.0
		return false

	var interval: float = _regen_seconds()
	if interval <= 0.0:
		count = max_count()
		return true

	_elapsed += delta
	var gained: bool = false
	while _elapsed >= interval && !is_full():
		_elapsed -= interval
		count += 1
		gained = true

	if is_full():
		_elapsed = 0.0
	return gained


func _regen_seconds() -> float:
	return _interval


## The creep's base rate, sped up by any passive that says so. A passive acts
## on the rate rather than replacing it, so the base stays one number in
## game_rules.md and a creep only states how much it beats it by.
func _compute_interval() -> float:
	if stats == null:
		return 0.0

	var ratio: float = 1.0
	for entry in stats.abilities:
		var passive: CreepPassive = entry as CreepPassive
		if passive != null:
			ratio *= passive.stock_regen_ratio()

	return stats.stock_regen_seconds / maxf(0.01, ratio)
