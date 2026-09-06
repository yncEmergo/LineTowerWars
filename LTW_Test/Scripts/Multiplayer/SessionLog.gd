class_name SessionLog
extends RefCounted

## An opt-in record of one play session, written to a file the player can send
## back after a test.
##
## **For a playtest on somebody else's machine, where nobody is watching a
## console.** `Log.gd` writes everything to stdout, which is perfect while a
## developer is looking at a terminal and worthless once a build is on itch and
## the tester is a friend two countries away. This writes the networking half of
## that to `user://logs/`, which on Windows is
## `%APPDATA%\Godot\app_userdata\<project>\logs\`.
##
## **OFF by default and turned on per session from the lobby.** A log nobody
## asked for is a file that quietly grows on a stranger's disk, and a tester who
## has not been asked to reproduce anything does not need one.
##
## ## Why this is a static class and not an autoload
##
## It has to outlive the lobby it is switched on in - the whole point is to cover
## the match that follows - and statics live for the process, so it does. An
## autoload would do the same and would also mean editing `[autoload]` in
## `project.godot`, which cannot be done safely while the editor is open
## (`CLAUDE.md`). There is nothing here that needs a node: no drawing, no
## `_process`, and the periodic sampling rides a signal that is already firing.
##
## ## What it records, and why those
##
## It listens to signals that already exist rather than being called from
## everywhere, so it cannot drift out of step with the code it watches:
##
##   the connection    connected, failed, dropped, peers joining and leaving
##   the match         starting, players dropping out, divergence
##   lockstep health   stalls with who was missing, and a periodic sample of the
##                     chosen input delay and the measured round trip
##
## Anything genuinely unusual also calls `note()` directly - a desync, an order
## running late - because those are the lines somebody reading this afterwards
## is actually looking for.
##
## ## The turn stream, and why it is the whole point
##
## **A checksum says WHICH TURN two worlds parted on. It says nothing about why,
## and a desync a tester reports is otherwise unreproducible.** The turn stream is
## the replay format: the same orders on the same turns from the same seed rebuild
## the same match, because that is what determinism means. So every turn that
## carried an order is written here, and `MatchSetup`'s seed is already in the
## header.
##
## Two hashes are kept rather than one, which costs a line and answers a question
## the state hash cannot. The INPUT hash covers the orders a turn carried; the
## state hash covers the world they produced. If the inputs match and the states
## diverge it is the SIMULATION - two machines computed differently from the same
## orders. If the inputs diverge it is the NETWORK - they were not given the same
## orders to begin with. Without the split those two are indistinguishable, and
## they want completely different investigations.

## Where session logs are written.
const DIRECTORY: String = "user://logs"

## How often the periodic health line is written, in TURNS. Every 100 turns is
## once every five seconds at one turn per tick - often enough to see the shape
## of a connection over a match, rare enough that the file stays readable.
const SAMPLE_EVERY_TURNS: int = 100

static var _file: FileAccess = null
static var _path: String = ""
static var _started_msec: int = 0
static var _stalls: int = 0
static var _wrote_config: bool = false


## Whether this session is being written to a file.
static func is_enabled() -> bool:
	return _file != null


## The file being written, or "" when logging is off. Shown to the player so
## they know what to send back.
static func path() -> String:
	return _path


## Starts or stops recording. Safe to call with the value it already has.
static func enable(on: bool) -> void:
	if on == is_enabled():
		return
	if on:
		_open()
	else:
		_close()


## One line in the log. `data` is written as-is, so a Dictionary reads as one.
##
## Costs a single comparison when logging is off, which is the normal case, so
## call sites do not need to guard themselves.
static func note(event: String, data: Variant = null) -> void:
	if _file == null:
		return
	var seconds: float = float(Time.get_ticks_msec() - _started_msec) / 1000.0
	var line: String = "[%9.3f] %s" % [seconds, event]
	if data != null:
		line += "  " + str(data)
	_file.store_line(line)
	# Flushed every line on purpose: the sessions worth reading are the ones that
	# ended in a crash, and a buffered tail is exactly the part that would be
	# lost.
	_file.flush()


## Whether this turn gets an input hash of its own. Same cadence as the health
## line, so the two read together.
static func _input_hash_every(turn: int) -> bool:
	return turn % SAMPLE_EVERY_TURNS == 0


# --- opening and closing ---------------------------------------------------

static func _open() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	# Sortable, and unique enough that two runs a minute apart cannot collide.
	# LOCAL time here so the file sorts alongside Godot's own logs in the same
	# folder, and UTC in the header so two testers in different timezones can
	# still line their logs up against each other.
	var stamp: String = Time.get_datetime_string_from_system(false, false)
	stamp = stamp.replace(":", "-").replace("T", "_")
	_path = "%s/session-%s.log" % [DIRECTORY, stamp]

	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		Log.warn("Session logging could not open its file", {
			"path": _path, "error": FileAccess.get_open_error(),
		})
		_path = ""
		return

	_started_msec = Time.get_ticks_msec()
	_stalls = 0
	_wrote_config = false
	_write_header()
	_listen(true)
	Log.info("Session logging on", {"path": ProjectSettings.globalize_path(_path)})


static func _close() -> void:
	if _file == null:
		return
	_listen(false)
	note("session.end", {"stalls": _stalls})
	_file.close()
	_file = null
	Log.info("Session logging off", {"path": _path})


## What was true at the start, so a line further down can be read against it.
## Every one of these has been the answer to a confusing report at least once.
static func _write_header() -> void:
	note("session.begin", {
		"utc": Time.get_datetime_string_from_system(true),
		"platform": OS.get_name(),
		"engine": Engine.get_version_info().get("string", "?"),
		"debug_build": OS.is_debug_build(),
		"build": _build_text(),
	})
	_write_config()


## Which build wrote this file, as the menu corner states it.
##
## **This is what ties a log somebody sends back to a commit.** The label is on
## screen too, but that relies on a tester reading it out and copying it
## correctly into a message; this rides along with the evidence by itself.
##
## Empty rather than absent when the resource is not wired into the scene that
## opened the log, so the key is always there to be searched for.
static func _build_text() -> String:
	var info: BuildInfo = References.build_info
	if info == null:
		return ""
	return info.label_text()


## The configuration this session is running, written as soon as it can be.
##
## **Not necessarily at the moment logging is switched on.** `References` is a
## node in whatever scene is loaded, so on the main menu there is no
## NetworkConfig to read at all - the first version of this wrote
## "config.missing" and nothing else, which is exactly the line a reader needs
## and never got. So it is attempted at the start and again when a match begins,
## and written the first time it succeeds.
static func _write_config() -> void:
	if _wrote_config:
		return
	var config: NetworkConfig = References.network_config
	if config == null:
		return
	_wrote_config = true
	note("config", {
		"protocol": config.protocol_version,
		"lockstep": config.lockstep_enabled,
		"ticks_per_turn": config.ticks_per_turn,
		"adaptive_delay": config.adaptive_delay,
		"delay_range": [config.min_delay_turns, config.max_delay_turns],
		"jitter_margin_ms": config.jitter_margin_ms,
		"address": config.resolved_address(),
		"port": config.resolved_port(),
	})


# --- what it watches -------------------------------------------------------

## Connects or disconnects every signal at once, so the two can never drift.
static func _listen(on: bool) -> void:
	_bind(Net.connected_to_server, _on_connected, on)
	_bind(Net.connection_failed, _on_connect_failed, on)
	_bind(Net.disconnected_from_server, _on_server_lost, on)
	_bind(Net.peer_joined, _on_peer_joined, on)
	_bind(Net.peer_left, _on_peer_left, on)
	_bind(MatchStart.match_starting, _on_match_starting, on)
	_bind(MatchStart.player_dropped, _on_player_dropped, on)
	_bind(MatchStart.desync_detected, _on_desync, on)
	_bind(Lockstep.turn_stalled, _on_stalled, on)
	_bind(Lockstep.turn_ready, _on_turn_ready, on)


## One connect or disconnect, guarded both ways. Called twice with the same
## value it would otherwise error or silently double up.
static func _bind(source: Signal, target: Callable, on: bool) -> void:
	if on:
		if !source.is_connected(target):
			source.connect(target)
		return
	if source.is_connected(target):
		source.disconnect(target)


static func _on_connected() -> void:
	note("net.connected", {"as_peer": Net.peer_id(), "address": Net.current_address()})


static func _on_connect_failed(result: NetworkService.Result) -> void:
	note("net.connect_failed", {"result": result})


static func _on_server_lost() -> void:
	note("net.server_lost", "the connection to the server ended")


static func _on_peer_joined(peer_id: int) -> void:
	note("net.peer_joined", peer_id)


static func _on_peer_left(peer_id: int) -> void:
	note("net.peer_left", peer_id)


static func _on_match_starting(setup: MatchSetup) -> void:
	# The scene now HAS a References, so the configuration can finally be read.
	_write_config()
	if setup == null:
		note("match.starting", "no setup")
		return
	note("match.starting", {
		"match": setup.match_id,
		"players": setup.player_count(),
		"seed": setup.rng_seed,
		"local_slot": setup.local_slot,
	})


static func _on_player_dropped(slot: int) -> void:
	note("match.player_dropped", {"slot": slot})


static func _on_desync(tick: int, detail: String) -> void:
	note("MATCH DIVERGED", {"tick": tick, "detail": detail})


static func _on_stalled(turn: int, missing: PackedInt32Array) -> void:
	_stalls += 1
	note("lockstep.stalled", {"turn": turn, "missing": missing, "stalls_so_far": _stalls})


## The periodic health line. Rides a signal that is already firing rather than
## keeping a timer, which is what lets this be a class with no node.
static func _on_turn_ready(turn: int, commands: Array) -> void:
	# The stream itself. Empty turns are the overwhelming majority and are left
	# out - a replay can assume "no orders" for any turn it does not name, which
	# is what makes this affordable to keep for a whole match.
	if !commands.is_empty():
		note("turn", {"n": turn, "in": hash(commands), "orders": commands})
	elif _input_hash_every(turn):
		# A periodic input hash even on empty turns, so a divergence in what the
		# peers were GIVEN is caught rather than inferred from its consequences.
		note("turn.inputs", {"n": turn, "in": hash(commands)})

	if turn % SAMPLE_EVERY_TURNS != 0:
		return
	note("lockstep.health", {
		"turn": turn,
		"delay_turns": Lockstep.delay_turns(),
		"rtt_ms": Net.round_trip_ms(NetworkService.SERVER_PEER_ID),
		"rtt_var_ms": Net.round_trip_variance_ms(NetworkService.SERVER_PEER_ID),
		"stalls": _stalls,
	})
