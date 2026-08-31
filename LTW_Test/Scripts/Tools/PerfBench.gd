class_name PerfBench
extends Node

## What a full match costs to simulate, measured rather than guessed.
##
## Fills every player's maze with towers, keeps a full population of creeps
## walking it, and reports what one simulation tick costs against the budget a
## tick has to fit in. Then it takes the loops this project already suspects
## apart and times each on its own, so a number that is too high says WHICH
## loop spent it rather than only that something did.
##
##   godot --path . --headless res://Scenes/Tools/perf_bench.tscn -- players=10
##   godot --path . res://Scenes/Tools/perf_bench.tscn -- players=2 scene=client
##
## run_bench.ps1 drives the whole matrix and is the way in.
##
## KEPT TOOLING, not scaffolding, for the same reason IconGen3D is: the
## question it answers is asked again every time the roster grows or a scan
## gains a caller. See CLAUDE.md under Project structure.
##
## It builds the world through the game's OWN calls - Builder's placement path
## and SendBuilding's spawn path with the gold, the stock and the unlock clock
## left out - so what it measures is the real simulation rather than a model of
## one. Nothing here is reachable from a match: it is a scene of its own that
## instances a match underneath itself, and no gameplay script knows it exists.
##
## The tick span is taken from SceneTree.physics_frame, which fires before the
## tree is walked, to the end of this node's own _physics_process, which runs
## last because of its priority. So the span is every node's simulation for
## that tick and nothing else.

## Match scene to instance underneath the bench.
##
## Two answers, and the difference is the point: the SERVER scene wires no
## effects root, no camera and no HUD, so it measures what a dedicated server
## really pays. The client scene adds all three and is what a player's machine
## runs. Ten players is a server question; towers on screen is a client one.
const MATCH_SCENES: Dictionary = {
	"server": "res://Scenes/Server/server_match.tscn",
	"client": "res://Scenes/Main.tscn",
}

const TOWER_FOLDER: String = "res://Resources/UnitStats/Towers"
const CREEP_FOLDER: String = "res://Resources/UnitStats/Creeps"

## What a "mix" maze is built out of, one line of the roster at a time.
##
## A mix rather than one tower repeated, because a tick does not cost the same
## for a tower that fires a plain shot and one that leaves burning ground,
## chills, chains or carries an aura. Pass tower=<stem> for a single type when
## the question is a comparison rather than a load.
const TOWER_MIX: Array[String] = [
	"archer_stats",
	"cannon_stats",
	"crusher_stats",
	"fire_lesser_firelord_stats",
	"ice_lesser_crystal_stats",
	"lightning_lesser_orb_keeper_stats",
	"water_lesser_sludge_monstrosity_stats",
	"unholy_lesser_alchemist_stats",
	"holy_lesser_divineshroom_stats",
	"earth_lesser_scorpion_stats",
]

## Every line of the report starts with this, so a driver script can pick the
## numbers out of a boot log that also carries Log.gd's own volume.
const TAG: String = "BENCH"

## How many spots a creep is offered before it is put in the spawn strip
## instead. A dense maze is mostly wall, so a few misses are ordinary.
const SEED_ATTEMPTS: int = 12

## How many times one micro-benchmark repeats. Enough that a single scheduling
## hiccup does not become the answer, few enough that the whole set fits well
## inside the tick it is run from.
const MICRO_REPEATS: int = 50

enum Phase { WARMUP, POPULATE, SETTLE, MEASURE, DONE }

@export_group("Settings")
## Ticks to let the match scene settle before anything is built into it.
@export var _warmup_ticks: int = 10
## Seconds of simulation between populating the world and starting to measure,
## so towers have acquired, creeps have spread and no first-tick cost lands in
## the window.
@export var _settle_seconds: float = 3.0

var _phase: Phase = Phase.WARMUP
var _ticks: int = 0
var _tick_start_usec: int = 0
var _frame_start_usec: int = 0

## The scenario, read off the command line in _ready.
var _players: int = 2
var _towers_wanted: int = 0
var _creeps_wanted: int = 100
var _measure_seconds: float = 15.0
var _scene_key: String = "server"
var _tower_key: String = "mix"
var _creep_key: String = "forest_troll_stats"
var _out_path: String = ""
## Diagnostic only: switches the match's own sun shadow off before measuring.
## A shadowed directional light re-submits the visible geometry once per split,
## so this is how much of the draw call count is the shadow pass rather than
## the world. Nothing is saved and no scene is touched - it is set on the node
## in this process and dies with it.
var _shadows: bool = true
## Diagnostic only, and the more interesting half of the one above: how far
## the sun casts shadows at all. Godot's default reaches far enough to cover
## this whole map, so every cascade redraws all twelve lanes however few of
## them the camera can see. 0 leaves whatever the scene authored.
var _shadow_distance: float = 0.0

var _tick_samples: PackedFloat64Array = PackedFloat64Array()
var _frame_samples: PackedFloat64Array = PackedFloat64Array()
## What the RENDERER spends, as opposed to what the scripts on a render frame
## spend. Both are zero headless, where there is no renderer to ask.
var _render_cpu_samples: PackedFloat64Array = PackedFloat64Array()
var _render_gpu_samples: PackedFloat64Array = PackedFloat64Array()
var _elapsed: float = 0.0
var _populate_ms: float = 0.0
var _towers_built: int = 0
var _creeps_spawned: int = 0
var _tower_stats: Array[BuildingStats] = []
var _creep_stats: CreepStats = null
var _areas: Array[PlayerArea] = []


func _ready() -> void:
	_read_arguments()
	# Last in the tick, so the span opened by physics_frame closes only after
	# every other node has simulated. BOTH properties, because Godot orders the
	# two callbacks separately: process_priority is the render frame's order and
	# process_physics_priority is the tick's. Setting only the first left this
	# node running BEFORE the match it is timing, and the whole world came back
	# as costing thirty microseconds a tick.
	process_priority = 100000
	process_physics_priority = 100000
	get_tree().physics_frame.connect(_on_physics_frame)
	get_tree().process_frame.connect(_on_process_frame)
	# Off by default because it costs a GPU timer query per frame. The whole
	# question of what DRAWING costs, as opposed to what simulating costs, is
	# unanswerable without it: frame_ms only ever covers the scripts.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_start_match()


func _on_physics_frame() -> void:
	_tick_start_usec = Time.get_ticks_usec()


func _on_process_frame() -> void:
	_frame_start_usec = Time.get_ticks_usec()


# --- Scenario -----------------------------------------------------------

## Command line arguments, as key=value pairs after the "--" separator.
##
## Every one has a default, so a bare run is a legal scenario rather than an
## error, which is what keeps the scene runnable straight from the editor.
func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.split("=", true, 1)
		if parts.size() != 2:
			continue
		_apply_argument(parts[0].strip_edges(), parts[1].strip_edges())


func _apply_argument(key: String, value: String) -> void:
	match key:
		"players":
			_players = maxi(1, int(value))
		"towers":
			_towers_wanted = maxi(0, int(value))
		"creeps":
			_creeps_wanted = maxi(0, int(value))
		"seconds":
			_measure_seconds = maxf(1.0, float(value))
		"scene":
			_scene_key = value
		"tower":
			_tower_key = value
		"creep":
			_creep_key = value
		"out":
			_out_path = value
		"shadows":
			_shadows = value != "off"
		"shadow_distance":
			_shadow_distance = maxf(0.0, float(value))
		_:
			push_warning("PerfBench ignored an argument it does not know: " + key)


## Stands a match up underneath the bench, exactly the way the lobby does: park
## a setup, then let the match scene take it.
func _start_match() -> void:
	var path: String = String(MATCH_SCENES.get(_scene_key, ""))
	if path.is_empty():
		push_error("PerfBench has no match scene for scene=" + _scene_key)
		_quit()
		return

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("PerfBench could not load the match scene: " + path)
		_quit()
		return

	var setup: MatchSetup = MatchSetup.new()
	for slot: int in range(1, _players + 1):
		setup.players.append(MatchPlayer.create(slot, "Bench %d" % slot))
	# A client scene wants a slot to draw from; the server scene sets this to 0
	# itself, so one setup serves both.
	setup.local_slot = 1
	setup.rng_seed = 1
	MenuNavigation.pending_match = setup

	var world: Node = packed.instantiate()
	add_child(world)
	if !_shadows || _shadow_distance > 0.0:
		_tune_shadows(world)


## Applies whichever shadow diagnostic was asked for to every directional light
## in the match scene. Walks the tree rather than naming a node, because the two
## match scenes do not have the same one and a server scene has none at all.
func _tune_shadows(node: Node) -> void:
	var light: DirectionalLight3D = node as DirectionalLight3D
	if light != null:
		if !_shadows:
			light.shadow_enabled = false
		if _shadow_distance > 0.0:
			light.directional_shadow_max_distance = _shadow_distance
	for child: Node in node.get_children():
		_tune_shadows(child)


# --- The run ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_ticks += 1
	match _phase:
		Phase.WARMUP:
			if _ticks >= _warmup_ticks:
				_phase = Phase.POPULATE
		Phase.POPULATE:
			_populate()
			_elapsed = 0.0
			_phase = Phase.SETTLE
		Phase.SETTLE:
			_top_up_creeps()
			_elapsed += delta
			if _elapsed >= _settle_seconds:
				_elapsed = 0.0
				_phase = Phase.MEASURE
		Phase.MEASURE:
			_top_up_creeps()
			_sample()
			_elapsed += delta
			if _elapsed >= _measure_seconds:
				_phase = Phase.DONE
				_finish()
		Phase.DONE:
			pass


func _sample() -> void:
	if _tick_start_usec > 0:
		_tick_samples.append(float(Time.get_ticks_usec() - _tick_start_usec) * 0.001)


func _process(_delta: float) -> void:
	if _phase != Phase.MEASURE || _frame_start_usec <= 0:
		return
	_frame_samples.append(float(Time.get_ticks_usec() - _frame_start_usec) * 0.001)

	# Already in milliseconds, and already the previous frame's - the GPU is
	# asked for a timer it has finished with rather than stalled on.
	var view: RID = get_viewport().get_viewport_rid()
	_render_cpu_samples.append(RenderingServer.viewport_get_measured_render_time_cpu(view))
	_render_gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(view))


# --- Populating ---------------------------------------------------------

## Fills every area, then reports what filling them cost. That number is worth
## having on its own: it is a flood fill per placement and a flow field rebuild
## per placement, which is the most expensive thing a build order does.
func _populate() -> void:
	_collect_areas()
	_load_content()
	var started: int = Time.get_ticks_usec()
	for area: PlayerArea in _areas:
		_fill_maze(area)
		_seed_creeps(area)
	_populate_ms = float(Time.get_ticks_usec() - started) * 0.001


func _collect_areas() -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		push_error("PerfBench found no PlayerManager, the match did not start")
		return
	for slot: int in range(1, _players + 1):
		var area: PlayerArea = manager.area_for(slot)
		if area != null:
			_areas.append(area)


func _load_content() -> void:
	var keys: Array[String] = TOWER_MIX
	if _tower_key != "mix":
		keys = [_tower_key]
	for key: String in keys:
		var stats: BuildingStats = load("%s/%s.tres" % [TOWER_FOLDER, key]) as BuildingStats
		if stats == null:
			push_error("PerfBench could not load tower stats: " + key)
			continue
		_tower_stats.append(stats)

	_creep_stats = load("%s/%s.tres" % [CREEP_FOLDER, _creep_key]) as CreepStats
	if _creep_stats == null:
		push_error("PerfBench could not load creep stats: " + _creep_key)


## Serpentine, which is the maze a player actually builds: every row full but
## one cell, and the gap alternating sides so a creep walks the whole width of
## every row. Densest legal layout and longest walk, worst case for both.
##
## Every placement still goes through can_place, so a row that would seal the
## area is refused by the world rather than trusted to be legal here.
func _fill_maze(area: PlayerArea) -> void:
	if _tower_stats.is_empty():
		return

	var footprint: Vector2i = area.cells_to_internal(_tower_stats[0].footprint_cells)
	if footprint.x <= 0 || footprint.y <= 0:
		return

	var columns: int = area.internal_width() / footprint.x
	var row: int = 0
	var iz: int = area.build_zone_first_row()
	while iz + footprint.y <= area.build_zone_row_end():
		var gap: int = columns - 1 if row % 2 == 0 else 0
		for column: int in range(columns):
			if column == gap:
				continue
			if _towers_wanted > 0 && _towers_built >= _towers_wanted * _areas.size():
				return
			_place_tower(area, Vector2i(column * footprint.x, iz), footprint)
		row += 1
		iz += footprint.y


func _place_tower(area: PlayerArea, cell: Vector2i, footprint: Vector2i) -> void:
	if !area.can_place(cell, footprint):
		return

	var stats: BuildingStats = _tower_stats[_towers_built % _tower_stats.size()]
	var scene: PackedScene = stats.scene()
	if scene == null:
		return
	var building: Building = scene.instantiate() as Building
	if building == null:
		return

	area.add_child(building)
	# Already standing: a maze of towers still rising would measure the
	# construction clock rather than the fight.
	building.place(area.player_id, area, cell, stats.gold_cost, true)
	_towers_built += 1


## Creeps spread over the whole walkable area rather than piled at the spawn,
## which is what a maze under pressure looks like. The cost is the same either
## way - every scan in the project walks the whole list whatever it holds - but
## a pile at the spawn would all leak in the same second and empty the world
## halfway through the measurement.
##
## Every spot is checked for a ROUTE, not only for being free. can_place only
## promises a way out from the SPAWN STRIP, so a dense maze legally leaves free
## pockets nothing can reach, and a creep dropped into one warns that it has
## nowhere to go on every tick for the rest of the run. That is a hundred
## thousand log lines and a measurement of Log.gd rather than of the game.
func _seed_creeps(area: PlayerArea) -> void:
	if _creep_stats == null:
		return
	var scene: PackedScene = _creep_stats.scene()
	if scene == null:
		return

	var rng: RandomNumberGenerator = MatchSession.match_rng()
	for index: int in range(_creeps_wanted):
		_spawn_creep(area, scene, _walkable_point(area, rng))


## A spot in the maze a creep can actually walk out of, or the spawn strip when
## enough tries have missed. The spawn strip is always routed: the maze test
## every placement went through is exactly the promise that it is.
func _walkable_point(area: PlayerArea, rng: RandomNumberGenerator) -> Vector3:
	var bounds: Rect2 = area.local_bounds()
	for attempt: int in range(SEED_ATTEMPTS):
		var local: Vector3 = Vector3(
			rng.randf_range(0.0, bounds.size.x), 0.0, rng.randf_range(0.0, bounds.size.y)
		)
		var point: Vector3 = area.nearest_free_point(area.to_global(local))
		if area.has_route_from(point):
			return point
	return area.random_spawn_point(_creep_stats.body_radius, rng)


func _spawn_creep(area: PlayerArea, scene: PackedScene, at: Vector3) -> void:
	var creep: Creep = scene.instantiate() as Creep
	if creep == null:
		return
	area.creeps_root().add_child(creep)
	creep.spawn(area.player_id, area, at)
	_creeps_spawned += 1


## Keeps every area at its target population, replacing what the towers killed
## and what walked off the end. Without it the measurement window would drain
## and report the cost of an emptying maze.
func _top_up_creeps() -> void:
	if _creep_stats == null:
		return
	var scene: PackedScene = _creep_stats.scene()
	if scene == null:
		return

	var rng: RandomNumberGenerator = MatchSession.match_rng()
	for area: PlayerArea in _areas:
		var missing: int = _creeps_wanted - area.creeps_root().get_child_count()
		for index: int in range(missing):
			_spawn_creep(area, scene, area.random_spawn_point(_creep_stats.body_radius, rng))


# --- The report ---------------------------------------------------------

func _finish() -> void:
	var budget: float = 1000.0 / float(Engine.physics_ticks_per_second)
	var micro: Dictionary = PerfProbes.measure(_areas, MICRO_REPEATS)
	var report: Dictionary = _build_report(budget, micro)
	_print_report(report)
	if !_out_path.is_empty():
		_write_report(report)
	_quit()


func _build_report(budget: float, micro: Dictionary) -> Dictionary:
	var tick: Dictionary = _statistics(_tick_samples)
	var frame: Dictionary = _statistics(_frame_samples)
	return {
		"players": _players,
		"scene": _scene_key,
		"tower": _tower_key,
		"creep": _creep_key,
		"shadows": _shadows,
		"shadow_distance": _shadow_distance,
		"towers": _towers_built,
		"creeps_alive": _count_creeps(),
		"creeps_spawned": _creeps_spawned,
		"units": _unit_count(),
		"nodes": get_tree().get_node_count(),
		"budget_ms": budget,
		"tick_ms": tick,
		"frame_ms": frame,
		"render_cpu_ms": _statistics(_render_cpu_samples),
		"render_gpu_ms": _statistics(_render_gpu_samples),
		"headroom": budget / maxf(0.001, float(tick.get("p95", 0.0))),
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"populate_ms": _populate_ms,
		"micro": micro,
	}


func _print_report(report: Dictionary) -> void:
	var tick: Dictionary = report["tick_ms"]
	var frame: Dictionary = report["frame_ms"]
	print("%s ---- %s scene, %d players, tower=%s creep=%s ----" % [
		TAG, _scene_key, _players, _tower_key, _creep_key,
	])
	print("%s world towers=%d creeps=%d units=%d nodes=%d" % [
		TAG, report["towers"], report["creeps_alive"], report["units"], report["nodes"],
	])
	print("%s tick_ms avg=%.2f p50=%.2f p95=%.2f max=%.2f budget=%.1f headroom=%.2fx" % [
		TAG, tick["avg"], tick["p50"], tick["p95"], tick["max"],
		report["budget_ms"], report["headroom"],
	])
	print("%s frame_ms avg=%.2f p95=%.2f fps=%.1f draws=%d prims=%d" % [
		TAG, frame["avg"], frame["p95"], report["fps"],
		int(report["draw_calls"]), int(report["primitives"]),
	])
	var render_cpu: Dictionary = report["render_cpu_ms"]
	var render_gpu: Dictionary = report["render_gpu_ms"]
	print("%s render_ms cpu_avg=%.2f cpu_p95=%.2f gpu_avg=%.2f gpu_p95=%.2f" % [
		TAG, render_cpu["avg"], render_cpu["p95"], render_gpu["avg"], render_gpu["p95"],
	])
	print("%s memory_mb=%.1f populate_ms=%.1f creeps_spawned=%d" % [
		TAG, report["memory_mb"], report["populate_ms"], report["creeps_spawned"],
	])
	for key: String in report["micro"]:
		print("%s micro %s=%.3f" % [TAG, key, float(report["micro"][key])])


func _write_report(report: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		push_error("PerfBench could not write its report to " + _out_path)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()


func _statistics(samples: PackedFloat64Array) -> Dictionary:
	if samples.is_empty():
		return {"avg": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0, "count": 0}

	var sorted: Array = Array(samples)
	sorted.sort()
	var total: float = 0.0
	for value: float in sorted:
		total += value
	var last: int = sorted.size() - 1
	return {
		"avg": total / float(sorted.size()),
		"p50": float(sorted[mini(last, int(float(sorted.size()) * 0.50))]),
		"p95": float(sorted[mini(last, int(float(sorted.size()) * 0.95))]),
		"max": float(sorted[last]),
		"count": sorted.size(),
	}


func _count_creeps() -> int:
	var total: int = 0
	for area: PlayerArea in _areas:
		total += area.creeps_root().get_child_count()
	return total


func _unit_count() -> int:
	var session: MatchSession = References.match_session
	return 0 if session == null else session.unit_count()


func _quit() -> void:
	get_tree().quit()
