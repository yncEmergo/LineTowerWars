class_name MatchRecorder
extends Node

## Writes one match to a file: every order every player gave, what came of it,
## and regular pictures of every player's economy and maze.
##
## **Two readers are planned and neither exists yet.** One is a REPLAY, the other
## is TRAINING the computer opponent on how people actually build and send. The
## file is shaped for both, so neither will need a format change when it arrives.
##
## ## Where it is switched on
##
## Per MACHINE, in the lobby room and on the single player setup screen - the same
## shape as the session log, and for the same reason: a file nobody asked for is
## a file quietly growing on a stranger's disk. It is NOT a match setting. Every
## peer runs the same simulation, so every peer that records a match writes the
## same match; whoever wants the data ticks the box, and nobody else is affected.
##
## **One tick covers ONE match.** The choice is a static, so it outlives the menu
## it was made in and reaches the match that follows - and begin() switches it
## back off as it starts recording, so the next match is not recorded unless the
## box is ticked again. The user's call: a recording is asked for per match.
##
## A tutorial is never recorded, whatever the box says. A relay records nothing
## either: it builds no world, so Main returns before ever reaching begin().
##
## ## What it costs
##
## Nothing when off - every call site is a null check and a bool. When on, every
## line is a player action or a snapshot, never a per-unit or per-tick event, and
## the file is only FLUSHED on a snapshot and at the end: a crash loses at most
## one snapshot interval of events.
##
## **It is not simulation.** It reads the world and never writes to it - no RNG,
## no unit ids, nothing checksummed - so a machine recording plays exactly the
## match a machine not recording plays.
##
## ## The file
##
## `user://recordings/match-<local time>-<mode>-slot<n>.jsonl`. JSON Lines: one
## object per line, so a reader can stream it and a crashed match is still a
## readable file up to its last flush. Every line has `k`, what KIND of line it
## is, and every line but the header has `t`, the MATCH TICK it happened on
## (the header says how many ticks make a second).
##
##   header     once, first. Format version, build, the whole MatchSetup (seed,
##              roster, settings), the grid, the lanes, and TABLES naming every
##              unit type, ability and technology id - so the file still reads
##              after the content has moved on. Also names the columns below.
##   order      one player order, exactly as it was applied: `turn` (lockstep
##              only, -1 otherwise), `n` its place in the whole stream, `slot`,
##              `cmd` the command as Command.to_dict writes it, and `result` -
##              applied, rejected (with `why`) or no_effect.
##   <event>    what an order or the simulation actually DID: build, build_done,
##              build_cancel, upgrade, return, morph_cancel, morphed, sell,
##              sell_cancel, sold, destroyed, layout_build, send, research,
##              research_undo, leak, eliminated, player_left. A leak line is
##              every creep one sender got through one defender on one tick,
##              summed, with `creeps` saying how many.
##   snapshot   every player's gold, income, lives, value, population, lane,
##              technologies and whole maze, on the configured interval. One
##              opening snapshot and one closing one are always written.
##   end        once, last: why the recording stopped, the winner and the
##              standings.
##
## ## What a replay would need, and what it has
##
## **The orders are the replay.** Under lockstep the match is a pure function of
## the setup (seed included) and the orders on each turn, and both are here in
## full; `turn` is the key, not `t`, because a draft holds the clock while turns
## still pass. Offline, an order carries the tick it was applied after, which is
## where a replay would apply it again. Orders from an AI seat are recorded too
## and marked `ai` - a replay can inject them, or run the same AI from the same
## seed, but not both. The build line in the header says which code the file
## needs, since a replay against other code is a desync by construction.
##
## Vectors are written as arrays and the command's packed arrays as plain ones;
## Command.from_dict needs `at` turned back into a Vector3, `units` into a
## PackedInt32Array and a layout's `g` into a Vector2i. Floats are written at
## full precision so that round trip is exact.

## What happened to one BUILDING, which is most of what a maze is. One enum and
## one entry point rather than a method each, because they all write the same
## few facts about the same kind of thing.
enum BuildingEvent {
	## A builder started a tower: gold paid, foundation down.
	STARTED,
	FINISHED,
	CANCELLED,
	UPGRADE_STARTED,
	## A morph back down to an Elemental Core started.
	RETURN_STARTED,
	MORPH_CANCELLED,
	SELL_STARTED,
	SELL_CANCELLED,
	SOLD,
	## Brought down by an attacker creep.
	DESTROYED,
	## Put down free and finished by the layout cheat.
	LAYOUT_PLACED,
}

## What a tower in a snapshot is doing, as the number in its `phase` column.
enum Phase { BUILT, CONSTRUCTING, UPGRADING, RETURNING, SELLING }

## Bumped whenever a reader would have to change to keep up.
const FORMAT_VERSION: int = 1

## Where recordings go. user:// rather than res://, which is read-only in an
## export. On Windows that is %APPDATA%\Godot\app_userdata\<project>\recordings.
const DIRECTORY: String = "user://recordings"

## How each BuildingEvent is spelled in the file, in enum order. Spelled out so
## renaming an enum value never renames a line a reader already looks for.
const BUILDING_EVENT_KEYS: Array[String] = [
	"build", "build_done", "build_cancel", "upgrade", "return", "morph_cancel",
	"sell", "sell_cancel", "sold", "destroyed", "layout_build",
]

## How each Phase is spelled in the header, in enum order.
const PHASE_KEYS: Array[String] = [
	"built", "constructing", "upgrading", "returning", "selling",
]
## The columns of one tower in a snapshot's maze. An array per tower rather than
## an object, because a long match writes hundreds of thousands of them and the
## header names the columns once.
const MAZE_COLUMNS: Array[String] = ["unit", "type", "x", "y", "phase", "into", "hp"]

## The player's choice, for the process. See the note on where it is switched on.
static var _armed: bool = false

var _file: FileAccess = null
var _path: String = ""
var _snapshot_every: int = 0
var _next_snapshot: int = 0
## Lockstep's current turn, or -1 off lockstep. Taken from turn_ready, which
## fires just before that turn's orders are applied.
var _turn: int = -1
var _order_count: int = 0
## The order being applied right now, and what the command road has said about
## it so far. Applying is synchronous, so there is only ever one.
var _open_order: Command = null
var _open_applied: bool = false
var _open_reasons: Array[String] = []
## Leaks not written yet, as [lives, creeps] per (sender, defender), and the tick
## they all happened on. See record_leak.
var _leaks: Dictionary = {}
var _leak_tick: int = -1

var _session: MatchSession:
	get:
		return References.match_session

var _players: PlayerManager:
	get:
		return References.player_manager


func _ready() -> void:
	set_physics_process(false)


## Whether the next match this machine plays will be recorded.
static func is_armed() -> bool:
	return _armed


## Switched from the lobby room or the single player setup screen.
static func set_armed(on: bool) -> void:
	_armed = on


## The folder recordings land in, as a path somebody can open.
static func folder_path() -> String:
	return ProjectSettings.globalize_path(DIRECTORY)


## Starts recording this match, if this machine asked for it. Called by Main once
## the areas, the builders and the registries exist, and BEFORE the opening
## technology is dealt, so a grant made at tick 0 is already in the file.
func begin(setup: MatchSetup, areas: Array[PlayerArea]) -> void:
	if !_armed || setup == null || _file != null:
		return
	# Spent by the match it was ticked for, whatever happens below.
	_armed = false
	if setup.mode == MatchSetup.Mode.TUTORIAL || !MatchSession.is_authority():
		return
	if !_open_file(setup):
		return

	var config: RecordingConfig = References.recording_config
	if config == null:
		Log.warn("MatchRecorder found no RecordingConfig, only the opening and closing snapshot")
	else:
		_snapshot_every = config.snapshot_interval_ticks(MatchSession.tick_seconds())
	_next_snapshot = 0
	_turn = -1
	_order_count = 0

	_write(_header(setup, areas))
	_listen(true)
	set_physics_process(true)
	Log.info("Recording this match", {"path": ProjectSettings.globalize_path(_path)})


func is_recording() -> bool:
	return _file != null


# --- orders ---------------------------------------------------------------

## An order is about to be applied. CommandService calls this and end_order
## around every application, on every road an order can take.
func begin_order(command: Command) -> void:
	if _file == null || command == null:
		return
	if _open_order != null:
		end_order()
	_open_order = command
	_open_applied = false
	_open_reasons.clear()


func end_order() -> void:
	if _file == null || _open_order == null:
		return
	var command: Command = _open_order
	_open_order = null

	var result: String = "no_effect"
	if _open_applied:
		result = "applied"
	elif !_open_reasons.is_empty():
		result = "rejected"

	var line: Dictionary = _line("order")
	line["turn"] = _turn
	line["n"] = _order_count
	line["slot"] = command.player_slot
	line["ai"] = _is_ai(command.player_slot)
	line["cmd"] = _plain(command.to_dict())
	line["result"] = result
	if !_open_reasons.is_empty():
		line["why"] = _open_reasons.duplicate()
	_order_count += 1
	_write(line)


# --- events ---------------------------------------------------------------

## Something happened to a building. `gold` is what moved with it - the price of
## a build or an upgrade, the refund of a sale or a cancel - and 0 otherwise.
func record_building(event: BuildingEvent, building: Building, gold: int = 0) -> void:
	if _file == null || building == null:
		return
	var line: Dictionary = _line(BUILDING_EVENT_KEYS[event])
	line["slot"] = building.owner_player_id
	line["unit"] = building.unit_id
	line["type"] = _type_of(building.stats)
	line["cell"] = [building.cell.x, building.cell.y]
	if event == BuildingEvent.STARTED || event == BuildingEvent.LAYOUT_PLACED:
		var size: Vector2i = building.footprint()
		line["size"] = [size.x, size.y]
	if building.is_upgrading():
		line["into"] = _type_of(building.upgrade_target())
	if gold != 0:
		line["gold"] = gold
	_write(line)


## A morph finished: the tower at that cell was `from` and is now `type`, under
## the same unit id.
##
## Its own call because the tower that started the morph is gone by the time it
## finishes, so what it WAS has to be handed over. `converted` marks a Void
## conversion, which nobody paid for and nobody ordered.
func record_morphed(building: Building, from_type: int, returned: bool,
		converted: bool) -> void:
	if _file == null || building == null:
		return
	var line: Dictionary = _line("morphed")
	line["slot"] = building.owner_player_id
	line["unit"] = building.unit_id
	line["from"] = from_type
	line["type"] = _type_of(building.stats)
	line["cell"] = [building.cell.x, building.cell.y]
	line["value"] = building.invested_gold
	if returned:
		line["returned"] = true
	if converted:
		line["converted"] = true
	_write(line)


## One send that went through: which creep, into whose lane, and for how much.
func record_send(slot: int, creep_stats: CreepStats, into_slot: int) -> void:
	if _file == null || creep_stats == null:
		return
	var line: Dictionary = _line("send")
	line["slot"] = slot
	line["type"] = _type_of(creep_stats)
	line["into"] = into_slot
	line["gold"] = creep_stats.gold_cost
	line["count"] = creep_stats.pack_creep_count()
	_write(line)


## One research press or one undo of it, with every technology it moved.
func record_research(slot: int, tech_ids: PackedInt32Array, gold: int,
		undone: bool = false) -> void:
	if _file == null:
		return
	var line: Dictionary = _line("research_undo" if undone else "research")
	line["slot"] = slot
	line["techs"] = Array(tech_ids)
	line["gold"] = gold
	_write(line)


## Lives moving from a defender to the sender whose creep got through.
##
## **Merged, not written per creep.** A leak is a PER-UNIT event - in Sudden Death
## a lane can leak dozens a tick - so leaks are summed per tick per sender and
## defender and written as one line with a `creeps` count once the tick has
## moved on. It saves less than it sounds: an AI endgame measured on 2026-09-14
## went from one line per creep to about five in six, because leaks spread over
## ticks rather than bunching on one. What keeps it affordable is that a line is
## a buffered write with no stack capture - the whole recorded match ran within
## noise of the same seed's earlier run.
func record_leak(sender_slot: int, defender_slot: int, lives: int) -> void:
	if _file == null:
		return
	var session: MatchSession = _session
	var tick: int = 0 if session == null else session.tick()
	if tick != _leak_tick:
		_flush_leaks()
		_leak_tick = tick
	var key: Vector2i = Vector2i(sender_slot, defender_slot)
	var sums: Vector2i = _leaks.get(key, Vector2i.ZERO)
	_leaks[key] = sums + Vector2i(lives, 1)


## Writes the leaks summed so far, stamped with the tick they happened on.
func _flush_leaks() -> void:
	if _leaks.is_empty():
		return
	for key: Vector2i in _leaks:
		var sums: Vector2i = _leaks[key]
		_file.store_line(JSON.stringify({
			"k": "leak", "t": _leak_tick, "slot": key.x, "from": key.y,
			"lives": sums.x, "creeps": sums.y,
		}, "", false, true))
	_leaks.clear()


# --- the clock ------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _file == null:
		set_physics_process(false)
		return
	if !MatchSession.is_authority():
		return
	var session: MatchSession = _session
	if session == null:
		return
	# A later tick has begun, so no more leaks can join the ones summed so far.
	# Written here as well as on the next leak, so a burst that ends is not held
	# back until somebody else leaks.
	if _leak_tick < session.tick():
		_flush_leaks()
	if session.tick() < _next_snapshot:
		return
	_write_snapshot()
	if _snapshot_every <= 0:
		# Only the opening one; the closing one is written by _finish.
		_next_snapshot = 1 << 62
	else:
		_next_snapshot = session.tick() + _snapshot_every


## Leaving mid-match, or quitting. A match that ended properly has already closed
## the file, which makes this a no-op.
##
## **This node sits AFTER References in the match scene, and that is what makes
## this work.** Siblings leave the tree last-first, and References clears its
## static handle as it leaves - so a recorder above it would find no
## PlayerManager to take its closing snapshot from.
func _exit_tree() -> void:
	_finish("left", 0)


func _on_turn_ready(turn: int, _orders: Array) -> void:
	_turn = turn


func _on_command_applied(command: Command) -> void:
	if command == _open_order:
		_open_applied = true


func _on_command_rejected(command: Command, reason: String) -> void:
	if command == _open_order:
		_open_reasons.append(reason)


func _on_player_eliminated(slot: int) -> void:
	var line: Dictionary = _line("eliminated")
	line["slot"] = slot
	var manager: PlayerManager = _players
	var state: PlayerState = null if manager == null else manager.state_for(slot)
	if state != null:
		line["placement"] = state.placement
	_write(line)


func _on_player_dropped(slot: int) -> void:
	var line: Dictionary = _line("player_left")
	line["slot"] = slot
	_write(line)


func _on_match_ended(winner_slot: int) -> void:
	_finish("match_over", winner_slot)


# --- writing --------------------------------------------------------------

func _open_file(setup: MatchSetup) -> bool:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	# Local time so the files sort the way the player remembers playing them.
	# The header carries UTC for lining two machines' files up.
	var stamp: String = Time.get_datetime_string_from_system(false, false)
	stamp = stamp.replace(":", "-").replace("T", "_")
	var mode: String = str(MatchSetup.Mode.keys()[setup.mode]).to_lower()
	_path = "%s/match-%s-%s-slot%d.jsonl" % [DIRECTORY, stamp, mode, setup.local_slot]

	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		Log.warn("Match recording could not open its file", {
			"path": _path, "error": FileAccess.get_open_error(),
		})
		_path = ""
		return false
	return true


func _finish(reason: String, winner_slot: int) -> void:
	if _file == null:
		return
	end_order()
	_flush_leaks()
	_write_snapshot()

	var line: Dictionary = _line("end")
	line["reason"] = reason
	line["winner"] = winner_slot
	var standings: Array = []
	var manager: PlayerManager = _players
	if manager != null:
		for state in manager.states_in_slot_order():
			standings.append({
				"slot": state.player_id, "placement": state.placement, "value": state.value,
			})
	line["standings"] = standings
	_write(line)

	_listen(false)
	set_physics_process(false)
	_file.close()
	_file = null
	Log.info("Match recording closed", {
		"path": ProjectSettings.globalize_path(_path), "reason": reason,
	})


func _write(line: Dictionary) -> void:
	if _file == null:
		return
	# Leaks from an earlier tick go first, so `t` never runs backwards down the
	# file. A leak line of THIS tick may still follow, which is the same tick.
	if !_leaks.is_empty() && int(line.get("t", 0)) != _leak_tick:
		_flush_leaks()
	# Unsorted, so `k` and `t` stay at the front where a person reads them, and
	# at full precision, so a position read back is the position that was used.
	_file.store_line(JSON.stringify(line, "", false, true))


func _line(kind: String) -> Dictionary:
	var session: MatchSession = _session
	return {"k": kind, "t": 0 if session == null else session.tick()}


func _listen(on: bool) -> void:
	var manager: PlayerManager = _players
	_bind(Commands.command_applied, _on_command_applied, on)
	_bind(Commands.command_rejected, _on_command_rejected, on)
	_bind(Lockstep.turn_ready, _on_turn_ready, on)
	_bind(MatchStart.player_dropped, _on_player_dropped, on)
	if manager != null:
		_bind(manager.player_eliminated, _on_player_eliminated, on)
		_bind(manager.match_ended, _on_match_ended, on)


func _bind(source: Signal, target: Callable, on: bool) -> void:
	if on:
		if !source.is_connected(target):
			source.connect(target)
	elif source.is_connected(target):
		source.disconnect(target)


# --- what a line says -----------------------------------------------------

func _header(setup: MatchSetup, areas: Array[PlayerArea]) -> Dictionary:
	var session: MatchSession = _session
	var network: NetworkConfig = References.network_config
	var info: BuildInfo = References.build_info
	var line: Dictionary = _line("header")
	line["format"] = FORMAT_VERSION
	line["utc"] = Time.get_datetime_string_from_system(true)
	line["build"] = "" if info == null else info.label_text()
	line["engine"] = str(Engine.get_version_info().get("string", "?"))
	line["platform"] = OS.get_name()
	line["protocol"] = 0 if network == null else network.protocol_version
	line["rpc_signature"] = Net.rpc_signature() if Net.is_online() else ""
	line["lockstep"] = MatchSession.is_lockstep()
	line["ticks_per_second"] = roundi(1.0 / MatchSession.tick_seconds())
	line["ticks_per_turn"] = 1 if network == null else maxi(1, network.ticks_per_turn)
	line["setup"] = _plain(setup.to_dict())
	line["settings_text"] = setup.settings.describe()
	line["grid"] = _grid(areas)
	line["maze_columns"] = MAZE_COLUMNS
	line["phases"] = PHASE_KEYS
	# What an order's `act` number means, since it is written as the enum's value.
	line["player_actions"] = Command.PlayerAction.keys()
	if session != null:
		line["unit_types"] = _unit_type_table(session.unit_types())
		line["abilities"] = _ability_table(session.abilities())
		line["techs"] = _tech_table(session.techs())
	return line


## What every area's grid looks like. Cells in every other line are INTERNAL,
## area-local and anchored top-left - the numbers Building.cell carries - so a
## maze reads the same whichever lane it was built in.
func _grid(areas: Array[PlayerArea]) -> Dictionary:
	for area in areas:
		if area == null:
			continue
		return {
			"width": area.internal_width(),
			"depth": area.internal_depth(),
			"cell_size": area.internal_cell_size(),
			"build_rows": [area.build_zone_first_row(), area.build_zone_row_end()],
		}
	return {}


func _unit_type_table(registry: UnitTypeRegistry) -> Dictionary:
	var table: Dictionary = {}
	if registry == null:
		return table
	for id in registry.ids():
		var stats: UnitStats = registry.stats_for(id)
		if stats == null:
			continue
		var entry: Dictionary = {"name": stats.display_name, "class": _class_name(stats)}
		var building: BuildingStats = stats as BuildingStats
		if building != null:
			entry["gold"] = building.gold_cost
			entry["total_gold"] = building.total_gold_cost
			entry["footprint"] = [building.footprint_cells.x, building.footprint_cells.y]
		var creep: CreepStats = stats as CreepStats
		if creep != null:
			entry["gold"] = creep.gold_cost
			entry["income"] = creep.income_gain
			entry["count"] = creep.pack_creep_count()
		table[str(id)] = entry
	return table


func _ability_table(registry: AbilityRegistry) -> Dictionary:
	var table: Dictionary = {}
	if registry == null:
		return table
	for id in registry.ids():
		var ability: UnitAbility = registry.ability_for(id)
		if ability != null:
			table[str(id)] = {"name": ability.display_name, "class": _class_name(ability)}
	return table


func _tech_table(registry: TechRegistry) -> Dictionary:
	var table: Dictionary = {}
	if registry == null:
		return table
	for tech in registry.all():
		table[str(tech.tech_id)] = {
			"name": tech.display_name,
			"element": str(TechDefinition.Element.keys()[tech.element]),
			"kind": str(TechDefinition.Kind.keys()[tech.kind]),
		}
	return table


func _write_snapshot() -> void:
	var manager: PlayerManager = _players
	if _file == null || manager == null:
		return
	var players: Array = []
	for state in manager.states_in_slot_order():
		var slot: int = state.player_id
		var area: PlayerArea = manager.area_for(slot)
		players.append({
			"slot": slot,
			"gold": state.gold,
			"income": state.income,
			"lives": state.lives,
			"value": manager.value_for(slot),
			"population": manager.population_for(slot),
			"placement": state.placement,
			"out": state.is_eliminated(),
			"into": manager.sends_into(slot),
			"creeps": 0 if area == null else area.creeps().size(),
			"techs": Array(state.tech.owned_ids()),
			"maze": _maze(area),
		})
	var line: Dictionary = _line("snapshot")
	line["players"] = players
	_write(line)
	# The one place a flush is paid for, so a crash loses one interval at most.
	_file.flush()


func _maze(area: PlayerArea) -> Array:
	var maze: Array = []
	if area == null:
		return maze
	for child: Node in area.get_children():
		var building: Building = child as Building
		if building == null || building.cell.x < 0 || building.is_queued_for_deletion():
			continue
		maze.append([
			building.unit_id,
			_type_of(building.stats),
			building.cell.x,
			building.cell.y,
			_phase_of(building),
			_type_of(building.upgrade_target()),
			roundi(building.current_health),
		])
	return maze


func _phase_of(building: Building) -> Phase:
	if building.is_under_construction():
		return Phase.CONSTRUCTING
	if building.is_selling():
		return Phase.SELLING
	if building.is_returning():
		return Phase.RETURNING
	if building.is_upgrading():
		return Phase.UPGRADING
	return Phase.BUILT


func _is_ai(slot: int) -> bool:
	var session: MatchSession = _session
	if session == null || session.setup() == null:
		return false
	var player: MatchPlayer = session.setup().player_for(slot)
	return player != null && player.is_ai()


static func _type_of(stats: UnitStats) -> int:
	return UnitTypeRegistry.NO_TYPE if stats == null else stats.unit_type_id


static func _class_name(resource: Resource) -> String:
	var script: Script = resource.get_script() as Script
	return "" if script == null else str(script.get_global_name())


## A value JSON can hold without losing its shape: vectors become arrays, packed
## arrays become plain ones, and containers are walked. JSON.stringify would
## otherwise write a Vector3 as the STRING "(1, 2, 3)".
static func _plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_DICTIONARY:
			var source: Dictionary = value as Dictionary
			var result: Dictionary = {}
			for key: Variant in source:
				result[str(key)] = _plain(source[key])
			return result
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
				TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, \
				TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(_plain(item))
			return items
	return value
