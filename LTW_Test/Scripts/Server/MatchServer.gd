class_name MatchServer
extends Node

## A server process that relays exactly ONE match and then exits (D44).
##
## It is spawned by a lobby process when a countdown begins, handed a match file
## naming its players and a secret per seat, and told which port to listen on.
## It never shows a lobby list, never accepts a stranger, and never goes back to
## listening once its match has ended.
##
##     godot --headless --path <checkout> --log-file <run>/<id>.log --
##           --match-server --match-id <id> --match-file <f> --port <p>
##           --shutdown-file <s>
##
## **The relay code underneath is unchanged.** `LockstepService` finds a
## sender's slot by `network_id` through `MatchStart.running_setup()`, and runs
## here exactly as it does in a single-process server - once the roster carries
## the ids of the connections this process actually has. Getting it to carry them
## is the whole job: see `MatchSeats` for the rules and
## `MatchStartService._roster_of_ready` for the re-key.
##
## The four things that cross the boundary to the lobby - the match file, the
## auth bytes, the RESULT and the exit codes - are fixed in `MatchHandoff`.
##
## See `Docs/multi-match.md` §2 steps 2, 6, 7 and 8.

## Where `/proc/self/oom_score_adj` lives. Linux only; skipped in silence
## anywhere else, because it is protection rather than a precondition.
const OOM_SCORE_PATH: String = "/proc/self/oom_score_adj"

## How long the ordered exit waits for links to close before quitting anyway.
## Only used when `Net`'s own shutdown is not already running one.
const EXIT_CLOSE_SECONDS: float = 5.0

var _seats: MatchSeats = null
var _match_id: String = ""
var _run_base: String = ""
var _port: int = 0
var _countdown_ends: float = 0.0
## When this process wrote READY. D15's clock starts at the LATER of that and the
## countdown's end, so a slow boot never shortens anybody's load window.
var _ready_at: float = 0.0
var _heartbeat_clock: float = 0.0
var _desync_tick: int = -1
var _started_at: float = 0.0
## Announced slot -> the slot that seat actually played as, captured at the go
## signal. The go roster RENUMBERS, so without this a reader of the RESULT
## cannot tell "played as slot 2" from "never got in".
var _go_slots: Dictionary = {}
## Refusals and strangers, counted rather than logged one line at a time: a port
## under a flood would otherwise empty the journal's rate-limit bucket for every
## other match on the box.
var _refusals: Dictionary = {}
var _exiting: bool = false
var _exit_clock: float = 0.0
var _exit_code: int = MatchHandoff.EXIT_OK
var _result_written: bool = false

var _config: NetworkConfig:
	get:
		return References.network_config


func _ready() -> void:
	# The socket does not stop because the world is held still, and this node
	# runs the exit clock as well.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cap_frame_rate()
	Log.info("Match process starting", {
		"pid": OS.get_process_id(),
		"display": DisplayServer.get_name(),
	})

	var config: NetworkConfig = _config
	if config == null:
		Log.err("Match process found no NetworkConfig, it cannot listen")
		_quit_now(MatchHandoff.EXIT_BAD_MATCH_FILE)
		return

	# 2. **Refuses to boot under replication.** The replication comparison runs
	#    in a single process, as it does today; a match process is a lockstep
	#    relay and nothing else.
	if !config.lockstep_enabled:
		Log.err("A match process needs lockstep, which is switched off in NetworkConfig")
		_quit_now(MatchHandoff.EXIT_LOCKSTEP_OFF)
		return

	# 3. Before anything can grow: every match dies before the lobby does.
	_raise_oom_score(config)

	# 4. The match file, read and then DELETED - a token must not sit on disk any
	#    longer than it takes to read it, and the run directory is only as
	#    private as its mode.
	if !_load_match_file(config):
		_quit_now(MatchHandoff.EXIT_BAD_MATCH_FILE)
		return

	# 5. Authentication, armed BEFORE the peer is assigned. A callback installed
	#    afterwards would miss every connection made in the meantime.
	_arm_authentication(config)

	# 6/7. The port, and a shutdown file that is HONOURED rather than cleared.
	if !_listen(config):
		_quit_now(MatchHandoff.EXIT_PORT_TAKEN)
		return

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_authentication_failed.connect(_on_auth_failed)
	MatchStart.match_abandoned.connect(_on_match_over)
	MatchStart.desync_detected.connect(_on_desync)

	MatchStart.begin_seated(_seats)

	# 9. Only now: a lobby that sees READY may announce this port to its players.
	_write_ready_file()


func _process(delta: float) -> void:
	_note_started()
	_advance_exit(delta)
	_touch_heartbeat(delta)


## Notices the moment the match really began.
##
## Asked of `running_setup()`, which is null until the go signal, rather than
## taken from a signal: the server side of a start emits nothing, and adding a
## signal for one reader would put a second thing to keep in step next to a
## question that already answers itself. It is what tells `aborted` from
## `all_left` in the RESULT.
func _note_started() -> void:
	if _started_at > 0.0:
		return
	var started: MatchSetup = MatchStart.running_setup()
	if started == null:
		return
	_started_at = Time.get_unix_time_from_system()
	# **The renumbering is captured HERE, not at the end.** `_finish_match`
	# clears the running setup BEFORE it emits the signal that makes the RESULT
	# get written, so asking for it then gives null and every seat records a go
	# slot of 0 - which reads as "never got in" for players who played the whole
	# match.
	for player: MatchPlayer in started.players:
		if player != null && player.network_id != 0:
			_go_slots[_seats.slot_of(player.network_id)] = player.slot
	Log.info("Match under way", {"match": _match_id, "go_slots": _go_slots})


# --- boot -----------------------------------------------------------------

## Reads the match file, builds the seat table, and CLEARS every seat's
## `network_id`.
##
## Clearing them is not tidying. Those ids were chosen by the clients on their
## LOBBY connections, on another process; here they name nothing, and a roster
## that still carried them would make the gate wait for connections that can
## never arrive. Until a seat is claimed it is identified by its token alone.
func _load_match_file(config: NetworkConfig) -> bool:
	var path: String = MatchHandoff.normalise(config.match_file_path())
	if path.is_empty():
		Log.err("A match process was given no --match-file")
		return false

	var data: Dictionary = MatchHandoff.read_match_file(path)
	if data.is_empty():
		return false

	var setup: MatchSetup = MatchSetup.from_dict(data.get("setup", {}))
	if setup == null || !setup.validate():
		Log.err("The match file does not hold a usable match", path)
		return false
	for player: MatchPlayer in setup.players:
		if player != null:
			player.network_id = 0

	_match_id = config.match_id()
	if _match_id.is_empty():
		_match_id = setup.match_id
	# Two names for one match is a trap rather than a feature: the run files are
	# named by the id on the command line, and `report_ready` is checked against
	# the id in the SETUP. The lobby writes both, so they can only differ through
	# a bug in the lobby - and if they do, every client's readiness is silently
	# refused and the match dies at the load timeout with nothing to look at.
	if _match_id != setup.match_id:
		Log.err("The match file and the command line name different matches", {
			"argument": _match_id, "setup": setup.match_id,
		})
	_run_base = path.get_base_dir().path_join(_match_id)
	_countdown_ends = float(data.get("countdown_ends", 0.0))

	_seats = MatchSeats.new()
	_seats.build(setup, MatchHandoff.tokens_from(data), _hold_seconds())

	# The token map is the reason. `/proc/<pid>/cmdline` is readable by every
	# local user and journald records each writer's command line, which is why
	# the tokens travel in a file rather than as arguments - and why the file
	# does not outlive the reading.
	DirAccess.remove_absolute(path)
	Log.info("Match process read its match", {
		"match": _match_id,
		"seats": setup.player_count(),
		"lobby_pid": data.get("lobby_pid", 0),
	})
	return true


## Installs the auth callback and its timeout on the ONE SceneMultiplayer this
## process has, before `Net.host()` assigns the peer.
##
## The timeout is the backstop for a client that reads a refusal and does not
## hang up, and it is the only thing that ever closes a connection which sends
## no token at all.
func _arm_authentication(config: NetworkConfig) -> void:
	var scene_multiplayer: SceneMultiplayer = multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		Log.err("Match process has no SceneMultiplayer, it cannot authenticate anybody")
		return
	scene_multiplayer.auth_callback = _on_auth
	scene_multiplayer.auth_timeout = maxf(1.0, config.match_auth_timeout_seconds)


## Opens the port this process was given. A failure is almost always the port
## already being held, which the lobby turns into one respawn on the next free
## one - so it exits at once rather than logging NOT LISTENING and waiting.
func _listen(config: NetworkConfig) -> bool:
	_port = config.resolved_port()
	var result: NetworkService.Result = Net.host(_port, true, config.match_max_peers)
	if result != NetworkService.Result.OK:
		Log.err("Match process could not open its port", {
			"port": _port,
			"why": NetworkService.describe(result),
		})
		return false
	Log.info("Match process listening", {"match": _match_id, "port": _port})
	return true


## Raises this process's own out-of-memory badness, so the kernel takes a MATCH
## before it takes the lobby.
##
## `OOMPolicy=continue` on the unit keeps the lobby up when a child is killed for
## memory; it does not choose which process dies. The kernel picks mostly by
## size, and the lobby boots to about the size of a match - so without this a
## slimmer match process would make the LOBBY the likeliest victim, which is the
## one outcome the whole arrangement exists to avoid.
##
## Needs no privilege to raise. A read-back that differs is an error LINE and the
## boot carries on: it is protection, not a precondition.
func _raise_oom_score(config: NetworkConfig) -> void:
	if !FileAccess.file_exists(OOM_SCORE_PATH):
		return
	var wanted: int = clampi(config.match_oom_score_adj, 0, 1000)
	var writer: FileAccess = FileAccess.open(OOM_SCORE_PATH, FileAccess.WRITE)
	if writer == null:
		Log.err("Match process could not raise its oom_score_adj", {
			"error": FileAccess.get_open_error(),
		})
		return
	writer.store_string(str(wanted))
	writer.close()

	var reader: FileAccess = FileAccess.open(OOM_SCORE_PATH, FileAccess.READ)
	var found: int = -1 if reader == null else int(reader.get_as_text().strip_edges())
	if reader != null:
		reader.close()
	if found != wanted:
		Log.err("oom_score_adj did not read back as it was set", {
			"wanted": wanted, "found": found,
		})
		return
	Log.info("Match process raised its oom_score_adj", {"value": found})


func _cap_frame_rate() -> void:
	var config: NetworkConfig = _config
	if config != null && config.server_max_fps > 0:
		Engine.max_fps = config.server_max_fps


# --- the seats ------------------------------------------------------------

## **The token check.** Every rule it applies lives in `MatchSeats.check_token`;
## this is the wire around it.
##
## A refusal is answered THROUGH AUTH and the connection is left alone. Hanging
## up in the same breath delivered the reason zero times in six when it was
## measured, which is CLAUDE.md's message-before-disconnect trap reached through
## authentication. The client hangs up once it has read the status, and
## `auth_timeout` closes the connection if it does not.
##
## **Every refusal is decided and sent inside this call.** The client sends its
## token and calls `complete_auth` at once, so once its completion has arrived
## the server's `send_auth` fails - a status decided a frame later never leaves.
func _on_auth(peer_id: int, data: PackedByteArray) -> void:
	var scene_multiplayer: SceneMultiplayer = multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		return

	var status: int = MatchHandoff.AUTH_SHUTTING_DOWN if Net.is_shutting_down() \
		else _seats.check_token(peer_id, data)
	if status == 0:
		scene_multiplayer.complete_auth(peer_id)
		return

	_count_refusal(status)
	scene_multiplayer.send_auth(peer_id, MatchHandoff.status_bytes(status))


## A pending entry becomes a claim, and the link is stretched HERE rather than
## at the go signal (D41).
##
## The cost of stretching at the claim is real and worth knowing: a claimed
## loader that crashes is then noticed only once the stretched timeout runs out,
## past the relay's silence allowance, and D26's hold starts from there. The
## others wait longer for that seat than they would have.
func _on_peer_connected(peer_id: int) -> void:
	var slot: int = _seats.admit(peer_id)
	if slot == 0:
		# `check_token` says this cannot happen. If it does, whoever holds the
		# seat keeps it and the newcomer goes.
		Log.err("A connection was admitted with no seat pending for it", peer_id)
		_count_refusal(MatchHandoff.AUTH_SEAT_HELD)
		var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet != null:
			var link: ENetPacketPeer = enet.get_peer(peer_id)
			if link != null:
				link.peer_disconnect_later()
		return
	Log.info("Seat claimed", {"slot": slot, "peer": peer_id})
	MatchStart.stretch_link(peer_id)


## A connection that passed the check but was never admitted raises ONLY this,
## never `peer_disconnected`. It discards the pending entry and changes no seat
## state - a pending entry is not a claim.
func _on_auth_failed(peer_id: int) -> void:
	if _seats == null:
		return
	var slot: int = _seats.release(peer_id, false, -1)
	if slot != 0:
		Log.info("A pending claim was discarded", {"slot": slot, "peer": peer_id})


func _hold_seconds() -> float:
	var menus: MenuConfig = References.menu_config
	return 10.0 if menus == null else maxf(0.0, menus.disconnect_grace_seconds)


func _count_refusal(status: int) -> void:
	_refusals[status] = int(_refusals.get(status, 0)) + 1


# --- the files ------------------------------------------------------------

## Says this process is up, and is the last thing the boot does. A lobby that
## sees this may announce the port to its players.
##
## It carries the pid so the lobby can tell a READY written by the child it is
## waiting for from one left by a respawned predecessor.
func _write_ready_file() -> void:
	_ready_at = Time.get_unix_time_from_system()
	MatchHandoff.write_json(_run_base + ".ready", {
		"pid": OS.get_process_id(),
		"port": _port,
		"at": _ready_at,
	})
	Log.info("Match process ready", {"match": _match_id, "port": _port})


## Touched from the main loop, FROM READY ON.
##
## The boot is synchronous and writes nothing, so a lobby judging staleness from
## the spawn would kill slow but healthy boots. Before READY the ceiling is the
## only bound, and it is a different question with a different answer.
func _touch_heartbeat(delta: float) -> void:
	if _ready_at <= 0.0 || _exiting:
		return
	var config: NetworkConfig = _config
	if config == null:
		return
	_heartbeat_clock += delta
	if _heartbeat_clock < maxf(0.5, config.match_heartbeat_seconds):
		return
	_heartbeat_clock = 0.0
	# **Just touched.** Truncation does not matter, because the lobby reads the
	# file's MODIFICATION TIME and never its contents - the file being written at
	# all is the whole signal.
	#
	# It was briefly written whole and renamed into place, like the other handoff
	# files, and that was WORSE: a rename has to remove the target first, so
	# there is a window with no file there at all, and a lobby polling into it
	# killed a healthy match for being wedged. A truncated file still has a
	# modification time; a missing one does not.
	var file: FileAccess = FileAccess.open(_run_base + ".heartbeat", FileAccess.WRITE)
	if file != null:
		file.store_string(str(Time.get_unix_time_from_system()))
		file.close()


## What a relay can honestly know about the match it just ran.
##
## **It carries NO winner.** Under lockstep no server process computes the
## outcome: the relay stamps orders and seals turns and simulates nothing. A
## trusted result would need the turn log replayed on a server, or the clients'
## own reports cross-checked.
func _write_result(ended: String) -> void:
	if _result_written || _seats == null:
		return
	_result_written = true

	var rows: Array = _seats.result_rows()
	# The go slot, which only the started roster knows. An announced seat that
	# was not started with keeps 0, so a reader can tell "played as slot 2" from
	# "never got in" without comparing two lists.
	#
	# Matched through the PEER ID rather than the display name, which two players
	# are perfectly entitled to share - and captured at the START rather than
	# read here, because by now the running setup has already been cleared.
	for row: Dictionary in rows:
		row["go_slot"] = int(_go_slots.get(int(row["slot"]), 0))

	MatchHandoff.write_json(_run_base + ".result", {
		"match": _match_id,
		"ended": ended,
		"seats": rows,
		"started": _started_at,
		"ended_at": Time.get_unix_time_from_system(),
		"desync_tick": _desync_tick,
		"refusals": _refusals,
	})
	Log.info("Match result written", {"match": _match_id, "ended": ended})


# --- ending ---------------------------------------------------------------

func _on_desync(tick: int, _detail: String) -> void:
	if _desync_tick < 0:
		_desync_tick = tick


## Every road out of a match arrives here, and the process **exits** on all of
## them. It never goes back to listening: one process, one match.
func _on_match_over(_match_id_over: String) -> void:
	if _exiting:
		return
	# **A D45 shutdown is recorded as one even when it caught the match before it
	# began.** "aborted" means D15 gave up on the players; a deploy that arrived
	# during loading is a different thing entirely, and a reader of the RESULT
	# who cannot tell them apart will blame the players for a restart.
	var ended: String = "all_left"
	if Net.is_shutting_down():
		ended = "shutdown"
	elif _started_at <= 0.0:
		ended = "aborted"
	_write_result(ended)

	# **On the D45 road, `Net`'s own shutdown already does the notice, the close
	# and the quit**, and it is halfway through doing them right now - this
	# signal reached us from inside its NOTICE phase. Starting a second ordered
	# exit on top of it would close the links underneath the sentence it is busy
	# delivering.
	if Net.is_shutting_down():
		return
	_begin_exit(MatchHandoff.EXIT_OK)


## **Exiting is ordered, and is never a `quit()` in the frame of the last
## notice.**
##
## `_abort` sends `receive_match_cancelled` and calls `_finish_match` in the same
## call, so a quit hooked straight onto the end of a match destroys the socket in
## the very frame that D15's sentence was written to it - and CLAUDE.md's
## message-before-disconnect trap loses it at the receiver. Which is exactly the
## silent failure the sentence exists to replace.
##
## So: close every link with `peer_disconnect_later`, which ENet completes only
## once what was already sent has been acknowledged, and quit when they have all
## gone or the bound has passed.
func _begin_exit(code: int) -> void:
	if _exiting:
		return
	_exiting = true
	_exit_code = code
	_exit_clock = 0.0
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null:
		for peer_id: int in multiplayer.get_peers():
			var link: ENetPacketPeer = enet.get_peer(peer_id)
			if link != null:
				link.peer_disconnect_later()
	Log.info("Match process is leaving", {
		"match": _match_id, "open": multiplayer.get_peers().size(), "code": code,
	})


func _advance_exit(delta: float) -> void:
	if !_exiting:
		return
	_exit_clock += delta
	if multiplayer.get_peers().is_empty() || _exit_clock >= EXIT_CLOSE_SECONDS:
		_quit_now(_exit_code)


## The one place this process ends, and the only place an exit CODE is chosen.
##
## Between 65 and 126 for everything but success: a death by signal comes back as
## the raw wait status, which without a core dump is the signal number itself,
## and Linux signals run to 64. A lower code would be ambiguous between "this
## process decided" and "the kernel killed it" - which is the one distinction the
## lobby actually needs.
func _quit_now(code: int) -> void:
	set_process(false)
	_cleanup_files()
	get_tree().quit(code)


## The READY and heartbeat files go; the RESULT stays for the lobby to read.
## The match file was deleted when it was read.
func _cleanup_files() -> void:
	if _run_base.is_empty():
		return
	DirAccess.remove_absolute(_run_base + ".ready")
	DirAccess.remove_absolute(_run_base + ".heartbeat")
