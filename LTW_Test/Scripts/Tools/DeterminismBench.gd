class_name DeterminismBench
extends Node

## Proves - or disproves - that the simulation is deterministic, by running the
## same match twice and comparing what the world looked like along the way.
##
## **Why this has to exist before lockstep.** Under lockstep every peer runs the
## whole simulation and the only thing crossing the wire is player input, so a
## single divergence anywhere compounds forever and the match is dead. A desync
## reported from a real game is close to undebuggable: nobody can say which tick
## it started on, and nothing reproduces it. This turns that into a number.
##
## **What it actually tests, stated plainly.** Two runs of the SAME BINARY on
## the SAME MACHINE from the same seed. That catches the whole family of
## iteration-order and unseeded-randomness bugs, which is what the determinism
## inventory taken before the cutover went looking for. It does NOT catch
## cross-machine float divergence, because there is only one machine here - that
## needs two boxes running `replay=` against the same trace, which this supports
## and which is the next step up.
##
## Three modes, one scene:
##
##     record=res://... seed=1 ticks=400   ->  run and write a trace
##     replay=<trace>                      ->  run again, feeding the RECORDED
##                                             commands rather than generating
##                                             them, and write a second trace
##     compare=<a>,<b>                     ->  report the first differing tick
##
## `perturb=<tick>` deliberately corrupts the world on that tick, which is how
## the harness is shown to FAIL when it should. A harness nobody has watched
## fail is not evidence.
##
## KEPT, not scaffolding - which is why it sits in `Scripts/Tools` beside
## `PerfBench` rather than in `Scripts/Dev`, the folder that gets deleted. It is
## run again every time the simulation grows something new, on the same footing
## as the performance bench: a determinism claim goes stale the moment somebody
## adds a feature, so the tool that checks it has to outlive the migration.

const MATCH_SCENE: String = "res://Scenes/Server/server_match.tscn"

## How the world is sampled: cheap enough to take often, since the whole value
## of the trace is LOCATING a divergence rather than merely noticing one.
const DEFAULT_EVERY: int = 10

var _seed: int = 1
var _players: int = 2
var _ticks: int = 400
var _every: int = DEFAULT_EVERY
var _out: String = "user://determinism_a.json"
var _replay_path: String = ""
var _compare: String = ""
var _perturb: int = -1

var _tick: int = 0
var _started: bool = false
var _setup: MatchSetup = null
var _areas: Array[PlayerArea] = []
var _samples: Array = []
var _recorded: Array = []
var _replay_by_tick: Dictionary = {}
var _sent_this_run: int = 0
var _rejected: int = 0

## Seeded from the match seed so the driver is reproducible, but kept SEPARATE
## from the simulation's own stream - see _send_from.
var _driver_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_read_arguments()

	if !_compare.is_empty():
		_run_compare()
		return

	if !_replay_path.is_empty():
		_load_replay(_replay_path)

	_start_match()


# --- arguments ------------------------------------------------------------

func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.split("=", true, 1)
		if pair.size() == 2:
			_apply_argument(pair[0].strip_edges(), pair[1].strip_edges())


func _apply_argument(key: String, value: String) -> void:
	match key:
		"seed":
			_seed = int(value)
		"players":
			_players = maxi(1, int(value))
		"ticks":
			_ticks = maxi(1, int(value))
		"every":
			_every = maxi(1, int(value))
		"out":
			_out = value
		"replay":
			_replay_path = value
		"compare":
			_compare = value
		"perturb":
			_perturb = int(value)
		_:
			push_warning("DeterminismBench ignored an argument: " + key)


# --- running a match ------------------------------------------------------

func _start_match() -> void:
	var packed: PackedScene = load(MATCH_SCENE) as PackedScene
	if packed == null:
		push_error("DeterminismBench could not load " + MATCH_SCENE)
		_quit()
		return

	_setup = MatchSetup.new()
	for slot: int in range(1, _players + 1):
		_setup.players.append(MatchPlayer.create(slot, "Det %d" % slot))
	_setup.local_slot = 1
	_setup.rng_seed = _seed
	_driver_rng.seed = _seed
	MenuNavigation.pending_match = _setup

	add_child(packed.instantiate())

	# Every command the authority accepts, which IS the input stream a replay
	# has to reproduce. Connected rather than hooked into CommandService, so
	# nothing in the shipping path knows this file exists.
	if Commands != null:
		Commands.command_applied.connect(_on_command_applied)
		Commands.command_rejected.connect(_on_command_rejected)

	_started = true


func _collect_areas() -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return
	_areas.clear()
	for slot: int in range(1, _players + 1):
		var area: PlayerArea = manager.area_for(slot)
		if area != null:
			_areas.append(area)


func _physics_process(_delta: float) -> void:
	if !_started:
		return

	if _areas.is_empty():
		_collect_areas()
		if _areas.is_empty():
			return

	_drive_tick()

	if _tick == _perturb:
		_apply_perturbation()

	if _tick % _every == 0:
		_sample()

	_tick += 1
	if _tick > _ticks:
		_finish()


## What makes the two runs worth comparing: a world that just sits there proves
## nothing, so the match is driven hard enough to exercise spawning, pathing,
## targeting and damage.
##
## The stream is derived from the SEED rather than from the wall clock, so a
## second run generates the identical stream without needing the trace - which
## is what lets `record` twice be a valid test on its own.
func _drive_tick() -> void:
	if !_replay_by_tick.is_empty():
		_replay_tick()
		return

	# Two cheats first, and they are not a shortcut past the thing being tested:
	# they travel the same Commands road every other order does, and without
	# them a fresh match has 40 gold and every creep still behind its unlock
	# delay, so nothing sends and the world barely moves. Re-issued on a slow
	# beat so the driver never stalls on an empty purse.
	if _tick % 40 == 2:
		for area: PlayerArea in _areas:
			_cheat(Command.PlayerAction.CHEAT_GOLD, area.player_id)
			_cheat(Command.PlayerAction.CHEAT_UNLOCK_CREEPS, area.player_id)
		return

	# Every player holds the send key, which is the heaviest ordinary load the
	# game produces and the one the stutter was reported in.
	if _tick < 6 || _tick % 4 != 0:
		return
	for area: PlayerArea in _areas:
		_send_from(area)


func _cheat(action: Command.PlayerAction, slot: int) -> void:
	var command: Command = Command.create_player_action(action)
	command.tick = _tick
	command.player_slot = slot
	Commands.call("_queue", command)
	_sent_this_run += 1


func _send_from(area: PlayerArea) -> void:
	var buildings: Array = area.send_buildings()
	if buildings.is_empty():
		return
	var building: SendBuilding = buildings[0] as SendBuilding
	if building == null || building.stats == null:
		return

	# The SEND abilities only. The card also carries submenus and settings, and
	# ordering one of those is a no-op that would quietly make the driver do
	# nothing while still looking busy.
	var abilities: Array = []
	for entry: Variant in building.stats.abilities:
		if entry is SendCreepAbility:
			abilities.append(entry)
	if abilities.is_empty():
		return

	# The DRIVER's own generator, never MatchSession.match_rng().
	#
	# This is not a style preference, it is the difference between the harness
	# working and lying. A real player's choice of creep is not drawn from the
	# match RNG, and if the driver draws from it then RECORD and REPLAY consume
	# different numbers of rolls - replay does not generate, so it does not draw
	# - and every gameplay roll afterwards is handed a different number. The
	# replay would then diverge from the recording for a reason that is entirely
	# the test's own fault, which is the worst possible failure for a tool whose
	# only job is to say whether a divergence is real.
	var index: int = _driver_rng.randi_range(0, abilities.size() - 1)
	var ability: UnitAbility = abilities[index] as UnitAbility
	if ability == null:
		return

	var command: Command = Command.create(
		ability.ability_id, [building], null, false
	)
	command.tick = _tick
	command.player_slot = area.player_id

	Commands.call("_queue", command)
	_sent_this_run += 1


func _replay_tick() -> void:
	var entries: Variant = _replay_by_tick.get(_tick)
	if entries == null:
		return
	for entry: Variant in entries as Array:
		var command: Command = Command.from_dict(_from_json_safe(entry as Dictionary))
		if command == null:
			push_error("DeterminismBench could not rebuild a command from the trace")
			continue
		Commands.call("_queue", command)
		_sent_this_run += 1


## Rejections are counted rather than printed one by one: a driver holding the
## send key produces the same refusal hundreds of times, and the first few say
## everything the rest would.
func _on_command_rejected(command: Command, reason: String) -> void:
	_rejected += 1
	if _rejected <= 3:
		print("DET rejected (ability=%d slot=%d units=%d): %s" % [
			command.ability_id, command.player_slot, command.unit_ids.size(), reason,
		])


func _on_command_applied(command: Command) -> void:
	if command == null:
		return
	var data: Dictionary = command.to_dict()
	data["tick"] = command.tick
	_recorded.append(_to_json_safe(data))


## `Command.to_dict()` is the WIRE format, and it is right for the wire: Godot
## encodes a Vector3 as twelve bytes and a PackedInt32Array as itself. JSON can
## do neither - it turns the vector into the STRING "(0, 0, 0)" and the packed
## array into floats - and `from_dict` then reads a String where it wants a
## Vector3 and hands back something unusable.
##
## Cost an hour: the replay ran, reported no error, injected nothing, and looked
## exactly like a determinism failure at the first sampled tick. The trace is a
## FILE format and needs its own encoding; it is not the wire and should not
## pretend to be.
static func _to_json_safe(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate()
	var at: Variant = data.get("at", Vector3.ZERO)
	if at is Vector3:
		out["at"] = [(at as Vector3).x, (at as Vector3).y, (at as Vector3).z]
	var units: Array = []
	for id: int in PackedInt32Array(data.get("units", PackedInt32Array())):
		units.append(id)
	out["units"] = units
	return out


static func _from_json_safe(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate()
	var at: Variant = data.get("at", null)
	if at is Array && (at as Array).size() == 3:
		var parts: Array = at as Array
		out["at"] = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	else:
		out["at"] = Vector3.ZERO
	var units: PackedInt32Array = PackedInt32Array()
	for id: Variant in data.get("units", []) as Array:
		units.append(int(id))
	out["units"] = units
	return out


# --- sampling -------------------------------------------------------------

## Two numbers per sample, on purpose.
##
## `world` is `WorldChecksum.of(...)`, which is what the game ALREADY computes
## and compares at match start - so a divergence it sees is a divergence the
## shipping code would also see.
##
## `deep` is this harness's own, and it exists because `WorldChecksum` covers
## identity and POSITION but not health, gold, lives or mana. A desync that
## moved only a creep's health would be invisible to the first number and is
## caught by the second. **`WorldChecksum` was deliberately not widened**: it is
## shipping code with a shipping cost, and whether it should carry more is a
## design question rather than something a test harness gets to decide.
func _sample() -> void:
	var session: MatchSession = References.match_session
	_samples.append({
		"tick": _tick,
		"world": WorldChecksum.of(_setup, _areas, session),
		"deep": _deep_hash(session),
	})


func _deep_hash(session: MatchSession) -> int:
	var parts: PackedStringArray = PackedStringArray()

	if session != null:
		for id: Variant in session.unit_ids():
			var unit: Unit = session.unit_for(int(id))
			if unit == null:
				parts.append("u%d:gone" % id)
				continue
			# Health is a float and is quantised for the same reason a position
			# is: two machines that agree to a thousandth agree, and hashing
			# raw bit patterns would call that a desync.
			parts.append("u%d:%d/%d:%s" % [
				id,
				roundi(unit.current_health * WorldChecksum.SCALE),
				unit.max_health(),
				_point(unit.global_position),
			])

	var manager: PlayerManager = References.player_manager
	if manager != null:
		for slot: int in range(1, _players + 1):
			var state: PlayerState = manager.state_for(slot)
			if state == null:
				parts.append("s%d:none" % slot)
				continue
			parts.append("s%d:%d/%d/%d" % [slot, state.gold, state.income, state.lives])

	return "|".join(parts).hash()


static func _point(position: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(position.x * WorldChecksum.SCALE),
		roundi(position.y * WorldChecksum.SCALE),
		roundi(position.z * WorldChecksum.SCALE),
	]


## Moves one creep by a millimetre. The point is to prove the harness REPORTS a
## divergence at the right tick - a checker that has only ever been seen to pass
## is not evidence that it can fail.
func _apply_perturbation() -> void:
	for area: PlayerArea in _areas:
		var creeps: Array = area.creeps()
		if creeps.is_empty():
			continue
		var creep: Creep = creeps[0] as Creep
		if creep == null:
			continue
		creep.global_position += Vector3(0.001, 0.0, 0.0)
		print("DET perturbed a creep at tick %d" % _tick)
		return
	print("DET perturb at tick %d found no creep to move" % _tick)


# --- output ---------------------------------------------------------------

func _finish() -> void:
	var trace: Dictionary = {
		"seed": _seed,
		"players": _players,
		"ticks": _ticks,
		"every": _every,
		"mode": "replay" if !_replay_path.is_empty() else "record",
		"commands_sent": _sent_this_run,
		"commands_applied": _recorded.size(),
		"samples": _samples,
		"commands": _recorded,
	}

	var file: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		push_error("DeterminismBench could not write " + _out)
	else:
		file.store_string(JSON.stringify(trace, "  "))
		file.close()

	print("DET wrote %s" % _out)
	print("DET seed=%d players=%d ticks=%d every=%d" % [
		_seed, _players, _ticks, _every,
	])
	print("DET commands sent=%d applied=%d rejected=%d samples=%d" % [
		_sent_this_run, _recorded.size(), _rejected, _samples.size(),
	])
	_quit()


func _load_replay(path: String) -> void:
	var trace: Dictionary = _read_trace(path)
	if trace.is_empty():
		return
	_seed = int(trace.get("seed", _seed))
	_players = int(trace.get("players", _players))
	for entry: Variant in trace.get("commands", []) as Array:
		var data: Dictionary = entry as Dictionary
		var tick: int = int(data.get("tick", 0))
		if !_replay_by_tick.has(tick):
			_replay_by_tick[tick] = []
		(_replay_by_tick[tick] as Array).append(data)
	print("DET replaying %d commands over %d ticks from %s" % [
		(trace.get("commands", []) as Array).size(), _replay_by_tick.size(), path,
	])


static func _read_trace(path: String) -> Dictionary:
	if !FileAccess.file_exists(path):
		push_error("DeterminismBench found no trace at " + path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if !(parsed is Dictionary):
		push_error("DeterminismBench could not parse " + path)
		return {}
	return parsed as Dictionary


# --- comparing ------------------------------------------------------------

## The whole point of the tool: not "do these differ" but "WHERE". A divergence
## located to a tick is something a probe can be pointed at; one that is merely
## detected is a bug report nobody can act on.
func _run_compare() -> void:
	var paths: PackedStringArray = _compare.split(",")
	if paths.size() != 2:
		push_error("DeterminismBench wants compare=<a.json>,<b.json>")
		_quit()
		return

	var a: Dictionary = _read_trace(paths[0].strip_edges())
	var b: Dictionary = _read_trace(paths[1].strip_edges())
	if a.is_empty() || b.is_empty():
		_quit()
		return

	var left: Array = a.get("samples", []) as Array
	var right: Array = b.get("samples", []) as Array

	print("DET compare %s (%d samples) vs %s (%d samples)" % [
		paths[0], left.size(), paths[1], right.size(),
	])
	if int(a.get("seed", 0)) != int(b.get("seed", 1)):
		print("DET WARNING seeds differ: %d vs %d - of course they diverge" % [
			int(a.get("seed", 0)), int(b.get("seed", 1)),
		])

	var count: int = mini(left.size(), right.size())
	for index: int in range(count):
		var one: Dictionary = left[index] as Dictionary
		var two: Dictionary = right[index] as Dictionary
		var world_same: bool = int(one.get("world", 0)) == int(two.get("world", 1))
		var deep_same: bool = int(one.get("deep", 0)) == int(two.get("deep", 1))
		if world_same && deep_same:
			continue

		var which: String = "world+deep"
		if world_same:
			which = "deep only - health, gold or lives moved but positions did not"
		elif deep_same:
			which = "world only"
		print("DET DIVERGED first at tick %d (%s)" % [int(one.get("tick", -1)), which])
		print("DET   a world=%d deep=%d" % [
			int(one.get("world", 0)), int(one.get("deep", 0)),
		])
		print("DET   b world=%d deep=%d" % [
			int(two.get("world", 0)), int(two.get("deep", 0)),
		])
		_quit()
		return

	if left.size() != right.size():
		print("DET DIVERGED in LENGTH: %d samples vs %d, identical up to tick %d" % [
			left.size(), right.size(), count * int(a.get("every", 1)),
		])
		_quit()
		return

	print("DET IDENTICAL across %d samples, %d ticks" % [
		count, count * int(a.get("every", 1)),
	])
	_quit()


func _quit() -> void:
	get_tree().quit()
