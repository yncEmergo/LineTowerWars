class_name PerfProbes
extends RefCounted

## The individual loops PerfBench blames a slow tick on, each timed on its own.
##
## A tick time says the world is expensive; it never says which line made it
## so. These are the calls that are already known to be linear scans - the
## three CLAUDE.md lists under Known weaknesses, plus the two the client pays
## every frame and the one the server pays every tick - measured against the
## world the bench has just built, so the answer is in the same units as the
## tick it has to be compared with.
##
## Every probe is a READ. Nothing here places, spends, damages or moves
## anything, so running the set leaves the world exactly as the measurement
## window left it and a probe can be added without wondering what it disturbs.
##
## Private methods are called on purpose. GDScript has no access modifier and
## the underscore is a convention about who should call a thing in the GAME -
## a tool measuring the game is outside that, and the alternative is a public
## hole in gameplay code that exists only for a benchmark.

## Metres a tower search is given when the probe supplies its own, standing in
## for a real AttackStats.attack_range. Only ever used if no tower in the area
## has an attack to borrow, which no real roster hits.
const FALLBACK_RANGE: float = 4.0


## Times every probe against the world as it stands and returns one flat
## dictionary of microseconds, plus the per-tick estimates those imply.
static func measure(areas: Array[PlayerArea], repeats: int) -> Dictionary:
	var results: Dictionary = {}
	if areas.is_empty():
		return results

	var area: PlayerArea = areas[0]
	var creeps: Array = area.creeps()
	var towers: Array = _towers_of(area)

	results["target_find_us"] = _time_target_find(area, towers, repeats)
	results["separation_us"] = _time_separation(creeps, repeats)
	results["aura_scan_us"] = _time_aura_scan(area, creeps, repeats)
	results["can_place_us"] = _time_can_place(area, repeats)
	results["flow_rebuild_us"] = _time_flow_rebuild(area, repeats)
	results["live_units_us"] = _time_live_units(repeats)
	results["population_us"] = _time_population(repeats)
	_measure_snapshot(results, repeats)
	_estimate(results, areas, towers.size(), creeps.size(), _crowding_count(creeps))
	return results


## Creeps that really do shove their neighbours, which since the roster stopped
## crowding is the attackers and nothing else. Counted rather than assumed,
## because both halves of that rule are config values and either can be turned
## back up - see GameConfig.creep_separation_limit.
static func _crowding_count(creeps: Array) -> int:
	var total: int = 0
	for child: Node in creeps:
		var creep: Creep = child as Creep
		if creep != null && creep._separation_limit() > 0.0:
			total += 1
	return total


# --- Probes -------------------------------------------------------------

## One tower's search for something to shoot. The worst case, and the ordinary
## one for most of a maze: a tower with no target and no cooldown scans its
## area's whole creep list every single tick (AttackComponent._physics_process).
static func _time_target_find(area: PlayerArea, towers: Array, repeats: int) -> float:
	var attack: AttackStats = _any_attack(towers)
	if attack == null || towers.is_empty():
		return 0.0

	var started: int = Time.get_ticks_usec()
	for index: int in range(repeats):
		var tower: Building = towers[index % towers.size()] as Building
		TargetFinder.best_target(area, tower.global_position, attack, false)
	return _per_call(started, repeats)


## One creep's push away from every creep standing too close. Pairwise over the
## whole area, so the area's cost is this times the number of creeps in it.
static func _time_separation(creeps: Array, repeats: int) -> float:
	if creeps.is_empty():
		return 0.0

	var started: int = Time.get_ticks_usec()
	for index: int in range(repeats):
		var creep: Creep = creeps[index % creeps.size()] as Creep
		creep._separation()
	return _per_call(started, repeats)


## One creep's look around for an aura to stand in. The same scan as targeting,
## run by every creep rather than every tower, but only four times a second.
static func _time_aura_scan(area: PlayerArea, creeps: Array, repeats: int) -> float:
	var config: GameConfig = References.game_config
	if config == null || creeps.is_empty():
		return 0.0

	var started: int = Time.get_ticks_usec()
	for index: int in range(repeats):
		var creep: Creep = creeps[index % creeps.size()] as Creep
		TargetFinder.creeps_in_radius(area, creep.global_position, config.creep_aura_radius_cells)
	return _per_call(started, repeats)


## The maze-blocking test: a flood fill over the whole internal grid. Paid once
## per build order on the server, and once PER RENDER FRAME on the client for
## as long as a build ghost is armed (CommandController._update_preview).
static func _time_can_place(area: PlayerArea, repeats: int) -> float:
	var cell: Vector2i = Vector2i(0, area.build_zone_first_row())
	var footprint: Vector2i = area.cells_to_internal(Vector2i.ONE)
	var started: int = Time.get_ticks_usec()
	for index: int in range(repeats):
		area.can_place(cell, footprint)
	return _per_call(started, repeats)


## The route every creep in the area reads, swept once per grid change. Paid on
## every placement and every sale.
static func _time_flow_rebuild(area: PlayerArea, repeats: int) -> float:
	var started: int = Time.get_ticks_usec()
	for index: int in range(repeats):
		area._rebuild_flow_field()
	return _per_call(started, repeats)


## The array of every live unit the minimap builds to draw its dots, which it
## does on every render frame (Minimap._process calls queue_redraw
## unconditionally).
static func _time_live_units(repeats: int) -> float:
	var session: MatchSession = References.match_session
	if session == null:
		return 0.0

	var started: int = Time.get_ticks_usec()
	for index: int in range(repeats):
		session.live_units()
	return _per_call(started, repeats)


## One player's population, which walks the SORTED id list of every unit in the
## match. Read by the status bar on its own refresh clock and by every send.
static func _time_population(repeats: int) -> float:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return 0.0

	var started: int = Time.get_ticks_usec()
	for index: int in range(repeats):
		manager.population_for(1)
	return _per_call(started, repeats)


## Building the whole-world snapshot, and how big it is. The server pays both
## every tick, per connected client for the bytes.
##
## Measured even offline, where the service does not run: the question is what
## a networked match of this size WOULD cost, and the work is identical.
static func _measure_snapshot(results: Dictionary, repeats: int) -> void:
	var started: int = Time.get_ticks_usec()
	var snapshot: Dictionary = {}
	for index: int in range(repeats):
		snapshot = Replication._build_snapshot()
	results["snapshot_us"] = _per_call(started, repeats)

	var floats: int = 0
	for key: String in ["u", "e"]:
		floats += (snapshot.get(key, PackedFloat32Array()) as PackedFloat32Array).size()
	var ints: int = 0
	for key: String in ["p", "s", "r"]:
		ints += (snapshot.get(key, PackedInt32Array()) as PackedInt32Array).size()
	results["snapshot_kb"] = float(floats + ints) * 4.0 / 1024.0


# --- Estimates ----------------------------------------------------------

## What those per-call numbers add up to over a whole tick of a whole match.
##
## Worst case on purpose, and it is a real case rather than a pessimistic one:
## a tower only skips its search while it HAS a target, and most of a full maze
## has nothing in range at any moment.
## The creep count here is the CROWDING one, not the population: separation is
## timed on a real creep either way, but only the creeps that actually pay it
## belong in what a tick costs.
static func _estimate(results: Dictionary, areas: Array[PlayerArea], towers: int,
		creeps: int, crowding: int) -> void:
	var lanes: float = float(areas.size())
	var rate: float = float(Engine.physics_ticks_per_second)
	results["crowding_creeps_per_lane"] = float(crowding)
	results["est_targeting_ms_per_tick"] = \
		float(results["target_find_us"]) * float(towers) * lanes / 1000.0
	results["est_separation_ms_per_tick"] = \
		float(results["separation_us"]) * float(crowding) * lanes / 1000.0
	# Four times a second rather than every tick, so its share of an average
	# tick is that fraction of the whole sweep.
	results["est_aura_ms_per_tick"] = \
		float(results["aura_scan_us"]) * float(creeps) * lanes * 4.0 / (rate * 1000.0)
	results["est_snapshot_ms_per_tick"] = float(results["snapshot_us"]) / 1000.0
	results["est_snapshot_kb_per_sec"] = float(results["snapshot_kb"]) * rate


# --- Helpers ------------------------------------------------------------

static func _towers_of(area: PlayerArea) -> Array:
	var towers: Array = []
	for child: Node in area.get_children():
		var building: Building = child as Building
		if building != null:
			towers.append(building)
	return towers


## An attack to run the target search with, borrowed from a real tower so the
## range and the air/ground rules are the roster's rather than invented.
static func _any_attack(towers: Array) -> AttackStats:
	for tower: Building in towers:
		if tower.stats != null && tower.stats.attack != null:
			return tower.stats.attack

	var stand_in: AttackStats = AttackStats.new()
	stand_in.attack_range = FALLBACK_RANGE
	return stand_in


static func _per_call(started_usec: int, repeats: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / float(maxi(1, repeats))
