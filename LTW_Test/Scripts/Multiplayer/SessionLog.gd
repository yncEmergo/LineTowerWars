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
## **ON by default in a windowed client, and switchable from the lobby.** It
## used to be opt-in, and playtest 8 paid for that: one player's third match and
## everything from a third player were never written, because nobody ticked a box
## in a process they had just restarted. A file quietly growing on a stranger's
## disk is still the right worry, and the answer to it is that the folder is
## PRUNED to `NetworkConfig.session_logs_kept` whenever a new file is opened, the
## way Godot's own logs are. Headless runs - the server, the probes, the benches -
## never open one by default. See `start_by_default`.
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
##   lockstep health   stalls with who was missing and how long they held, and a
##                     periodic sample of the link and of this machine's frames
##   the machine       hardware and display, and every frame long enough to feel,
##                     with whether shaders were compiled around it
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

## Godot's shader cache for the Compatibility renderer: one folder per kind of
## shader - scene, canvas, particles and the rest - each holding a folder per
## shader, each holding a file per variant compiled. So a count that rose across
## a long frame IS a compile around that frame. The same trick as `ShaderProbe`,
## which counts only the scene kind; this counts every kind, since a particle or
## a canvas shader compiles on first draw just the same.
const SHADER_CACHE_DIR: String = "user://shader_cache"

## How long a burst of hitch lines may run before the cap resets, in
## milliseconds. See `_on_frame`.
const HITCH_WINDOW_MSEC: int = 5000

static var _file: FileAccess = null
static var _path: String = ""
static var _started_msec: int = 0
static var _stalls: int = 0
static var _wrote_config: bool = false

## Frame timing, all wall clock. The threshold and the cap are read from the
## config when it can be reached and stay at these fallbacks until then.
static var _last_frame_usec: int = 0
static var _hitch_ms: float = 100.0
static var _hitch_lines_cap: int = 10
static var _worst_frame_ms: float = 0.0
static var _hitches: int = 0
static var _hitch_lines: int = 0
static var _hitch_window_msec: int = 0
static var _shader_files: int = 0


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


## Opens the log for this process if the configuration says a session is logged
## unless somebody turns it off. Called once, by `Boot`, for a client.
##
## **Never for a headless process.** The server writes no session log - the
## journal is its log - and the probes and benches that run headless open their
## own when they want one. Opening one there would put a file write into every
## benchmark, measured with it whether anybody meant to or not.
static func start_by_default() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var config: NetworkConfig = References.network_config
	if config == null || !config.session_log_on_by_default:
		return
	enable(true)


## Whether this turn gets an input hash of its own. Same cadence as the health
## line, so the two read together.
static func _input_hash_every(turn: int) -> bool:
	return turn % SAMPLE_EVERY_TURNS == 0


# --- opening and closing ---------------------------------------------------

static func _open() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	_prune_old_files()
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
	_last_frame_usec = 0
	_worst_frame_ms = 0.0
	_hitches = 0
	_hitch_lines = 0
	_shader_files = _count_shader_files()
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


## Deletes the oldest session logs so that, with the one about to be opened,
## no more than `NetworkConfig.session_logs_kept` remain. The names sort by when
## they were made, so the oldest are simply the first.
static func _prune_old_files() -> void:
	var config: NetworkConfig = References.network_config
	var kept: int = 20 if config == null else config.session_logs_kept
	if kept <= 0:
		return
	var logs: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(DIRECTORY):
		if file.begins_with("session-") && file.ends_with(".log"):
			logs.append(file)
	logs.sort()
	for index: int in range(logs.size() - (kept - 1)):
		DirAccess.remove_absolute(DIRECTORY.path_join(logs[index]))


## What was true at the start, so a line further down can be read against it.
## Every one of these has been the answer to a confusing report at least once.
##
## `process_msec` is what lines this file up with the Godot log beside it: that
## one is stamped in milliseconds since the process began (`Boot`), and every
## line here is seconds since THIS number.
static func _write_header() -> void:
	note("session.begin", {
		"utc": Time.get_datetime_string_from_system(true),
		"process_msec": _started_msec,
		"platform": OS.get_name(),
		"engine": Engine.get_version_info().get("string", "?"),
		"debug_build": OS.is_debug_build(),
		"build": _build_text(),
	})
	_write_machine()
	_write_config()


## The hardware, once. **Playtest 8 had to fetch a player's graphics card from
## the first line of a different file**, and whether a freeze is a shader compile
## is a question about the card and its driver.
##
## The driver query can be slow on Windows, which is why this is paid once when
## the file opens rather than anywhere near a match.
static func _write_machine() -> void:
	var memory: Dictionary = OS.get_memory_info()
	note("machine", {
		"os": OS.get_version(),
		"cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
		"ram_mb": int(memory.get("physical", 0)) / 1048576,
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": OS.get_video_adapter_driver_info(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"renderer": RenderingServer.get_current_rendering_method(),
		# Zero is a machine that has compiled nothing yet: the player whose first
		# match pays for every shader. See `ShaderWarmup`.
		"shader_cache_files": _shader_files,
	})


## How the game is being drawn right now. At match start rather than in the
## header, because every one of these can be changed from the options screen in
## between.
static func _display() -> Dictionary:
	var screen: int = DisplayServer.window_get_current_screen()
	return {
		"window_mode": DisplayServer.window_get_mode(),
		"window": DisplayServer.window_get_size(),
		"screen": DisplayServer.screen_get_size(screen),
		"refresh_hz": snappedf(DisplayServer.screen_get_refresh_rate(screen), 0.1),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
	}


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
	_hitch_ms = float(config.hitch_threshold_ms)
	_hitch_lines_cap = config.hitch_lines_per_window
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
	_bind(Lockstep.turn_resumed, _on_resumed, on)
	_bind(Lockstep.turn_ready, _on_turn_ready, on)
	# The frame clock. A signal the tree emits anyway, so the class still needs
	# no node of its own.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		_bind(tree.process_frame, _on_frame, on)


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
	# **The roster, so a slot is a person.** Every other line names players by
	# slot or by peer id, and playtest 8 had to go to the relay's journal to learn
	# who "slot 3" was.
	var roster: Array = []
	for player: MatchPlayer in setup.players:
		if player != null:
			roster.append({
				"slot": player.slot, "name": player.display_name,
				"peer": player.network_id, "ai": player.is_ai(),
			})
	_shader_files = _count_shader_files()
	note("match.starting", {
		"match": setup.match_id,
		"players": setup.player_count(),
		"seed": setup.rng_seed,
		"local_slot": setup.local_slot,
		"roster": roster,
		"display": _display(),
		"shader_cache_files": _shader_files,
	})


static func _on_player_dropped(slot: int) -> void:
	note("match.player_dropped", {"slot": slot})


static func _on_desync(tick: int, detail: String) -> void:
	note("MATCH DIVERGED", {"tick": tick, "detail": detail})


static func _on_stalled(turn: int, missing: PackedInt32Array) -> void:
	_stalls += 1
	note("lockstep.stalled", {"turn": turn, "missing": missing, "stalls_so_far": _stalls})


## The end of a stall, with what it cost. See `LockstepService.turn_resumed` for
## why the backlog is the number that matters.
static func _on_resumed(turn: int, held_ms: int, backlog: int) -> void:
	note("lockstep.resumed", {"turn": turn, "held_ms": held_ms, "backlog": backlog})


## Every frame: how long the last one took, in wall clock.
##
## **This is the per-frame path, so it is one clock read and one comparison
## unless the frame was long.** Everything else - the line, the shader count -
## happens only on a hitch, and the count is a directory listing that is cheap
## next to a frame that already took a tenth of a second.
##
## **Capped, because the machine this matters most on is the one that would
## flood it.** A player running at eight frames a second hitches on every frame,
## so after `hitch_lines_per_window` lines in `HITCH_WINDOW_MSEC` the rest are
## only counted, and the health line still reports them.
static func _on_frame() -> void:
	var now: int = Time.get_ticks_usec()
	var previous: int = _last_frame_usec
	_last_frame_usec = now
	if previous == 0:
		return
	var frame_ms: float = float(now - previous) / 1000.0
	_worst_frame_ms = maxf(_worst_frame_ms, frame_ms)
	if frame_ms < _hitch_ms:
		return

	_hitches += 1
	var msec: int = now / 1000
	if msec - _hitch_window_msec > HITCH_WINDOW_MSEC:
		_hitch_window_msec = msec
		_hitch_lines = 0
	if _hitch_lines >= _hitch_lines_cap:
		return
	_hitch_lines += 1

	var shaders: int = _count_shader_files()
	var in_match: bool = References.match_session != null
	note("frame.hitch", {
		"ms": int(frame_ms),
		"turn": Lockstep.current_turn() if in_match else -1,
		"in_match": in_match,
		# Held by the warm-up on purpose, so a long frame there is expected.
		"warming": in_match && !ShaderWarmup.is_done(),
		# Variants compiled since the last count - at the last hitch, the match
		# start or the file opening. Not proof this frame compiled them, but a
		# long frame with a rise here, against long frames without one, is as
		# close as a log can get.
		"new_shaders": shaders - _shader_files,
		"focused": DisplayServer.window_is_focused(),
	})
	_shader_files = shaders


## How many files Godot's shader cache holds. See `SHADER_CACHE_DIR`.
static func _count_shader_files() -> int:
	var total: int = 0
	for kind: String in DirAccess.get_directories_at(SHADER_CACHE_DIR):
		var kind_dir: String = SHADER_CACHE_DIR.path_join(kind)
		for shader: String in DirAccess.get_directories_at(kind_dir):
			total += DirAccess.get_files_at(kind_dir.path_join(shader)).size()
	return total


## This machine's frames since the last health line, and what it is drawing.
## Resets the window it reports.
static func _frame_sample() -> Dictionary:
	var sample: Dictionary = {
		"fps": int(Engine.get_frames_per_second()),
		"worst_ms": int(_worst_frame_ms),
		"hitches": _hitches,
		"draw_calls": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"mem_mb": int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		"vram_mb": int(Performance.get_monitor(
			Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
	}
	_worst_frame_ms = 0.0
	_hitches = 0
	return sample


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
		"rtt_ms": Net.round_trip_ms(NetworkService.SERVER_PEER_ID),
		"rtt_var_ms": Net.round_trip_variance_ms(NetworkService.SERVER_PEER_ID),
		# What THIS machine's own frame times are costing, which the two figures
		# above cannot show. Playtest 1 was diagnosed the long way round for want
		# of it: the connection was clean on both sides and one machine was
		# simply not finishing its ticks on time.
		"local_jitter_ms": Lockstep.local_jitter_ms(),
		# How far behind the relay this machine is playing. It is the peer's
		# input delay in turns, and the number the catch-up servo drives back
		# down - see LockstepService._pace_engine.
		"sealed_held": Lockstep.sealed_held(),
		# [recovered, deliberately dropped]. On a clean link both are zero; the
		# first going up on a real connection is REAL PACKET LOSS being repaired
		# by the unreliable echo, and is the only place this build reports it.
		"echo": Lockstep.echo_recovery(),
		# [asked, repaired]: seals this machine asked the relay for again because
		# they had not come, and how many of those arrived that nothing else had
		# delivered. Zero on a healthy link; climbing when the reliable channel is
		# the thing that is late. See LockstepService._repair_missing_seals.
		"repair": Lockstep.repair_counts(),
		# ENet's own figures for the link to the relay: round trip, the share of
		# this machine's reliable sends it had to resend, and its throttle. See
		# NetworkService.link_quality for what those can and cannot say.
		"link": Net.link_quality(NetworkService.SERVER_PEER_ID),
		# **What a word actually COST, which nothing above can show.** Every
		# figure beside it is an ESTIMATE of the wire - a mean round trip, its
		# smoothed variance, this machine's frame times - and the same problem
		# was diagnosed wrongly twice from those estimates alone. This is the
		# measurement: `arrived - due` per peer, positive meaning late.
		"arrival_ms": Lockstep.arrival_leads(),
		"stalls": _stalls,
		# **A stall COUNT is not a stall COST**, and `stalls` above is a count.
		# Two configurations with the same number of stalls can differ by an
		# order of magnitude in time actually held, and every tuning decision
		# taken against the count alone is taken blind. See `CLAUDE.md`.
		"stalled_s": snappedf(Lockstep.stalled_seconds(), 0.01),
		# **What this machine's frames looked like since the last line.** A stall
		# on a clean link beside a worst frame of a second is a machine that
		# stopped, and playtest 8 had to infer that from backlogs.
		"frame": _frame_sample(),
	})
