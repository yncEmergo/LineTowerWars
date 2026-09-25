class_name MatchSupervisor
extends Node

## The LOBBY process's half of the handoff (D44): it spawns a match process per
## match, watches it, and reaps it.
##
## Owned by `Lobby`, which is where the countdown lives. The split is by
## SUBJECT rather than by size: everything here is about CHILD PROCESSES - ports,
## tokens, files, liveness, the cap - and nothing here knows what a lobby is
## beyond its id.
##
## The life of one start:
##
##     countdown begins (D24)    the setup is final, so: tokens, a port, a match
##                               file, and a child. Or a place in the queue.
##     READY                     the child says a player may be sent to it
##     announced                 `Lobby` tells the players the port and their
##                               own token, and closes the lobby
##     reaped                    the RESULT is logged, the port goes back
##
## **Nothing here simulates and nothing here authenticates.** The child does
## both. See `MatchServer` for the other side and `MatchHandoff` for the four
## contracts between them.
##
## See `Docs/multi-match.md` §2 steps 1 to 4, §4 and §5.

## A child that has been asked for, and how far it has got.
signal child_ready(lobby_id: String, match_id: String, port: int)
## It will never be ready: the boot failed, the port was taken twice, or the
## ceiling ran out. The start is cancelled, with this sentence.
signal child_failed(lobby_id: String, reason: String)

enum State {
	## Waiting for another child to finish booting. **It holds a cap slot** from
	## the moment its countdown began, so a queue cannot overshoot the cap.
	QUEUED,
	BOOTING,
	READY,
	ANNOUNCED,
}

## How often the run directory is looked at. A file test a few times a second is
## nothing next to a relay's tick, and it is what decides how fast a start feels.
const POLL_SECONDS: float = 0.25

## One match, from the moment its countdown began until its child is reaped.
class Child extends RefCounted:
	var lobby_id: String = ""
	var match_id: String = ""
	var setup: MatchSetup = null
	var tokens: Dictionary = {}
	## The address that hosted the lobby, for the per-source limit. Counted by
	## the HOST rather than by any member: players behind one NAT share it, which
	## is accepted.
	var host_address: String = ""
	var port: int = 0
	var pid: int = 0
	var run_base: String = ""
	var state: State = State.QUEUED
	## Seconds since the SPAWN, not since the queue: a queued child must never be
	## killed by a ceiling that started before it existed.
	var booting_for: float = 0.0
	var countdown_ends: float = 0.0
	## Whether this match has already been respawned once, on the next port. A
	## taken port is worth one retry; twice is a broken pool.
	var respawned: bool = false
	## The newest heartbeat ever SEEN for this child, which is not the same as
	## the newest one on disk right now. See `_heartbeat_is_stale`.
	var last_beat: float = 0.0


var _children: Dictionary = {}
## Ports free to hand out, LEAST RECENTLY FREED FIRST. A port that has just been
## released may still be held by the OS for a moment, so the far end of the queue
## is the safer one to take from.
var _free_ports: Array[int] = []
var _poll_clock: float = 0.0
var _run_dir: String = ""

var _config: NetworkConfig:
	get:
		return References.network_config


func _ready() -> void:
	# A child booting does not stop because a match is holding the world still.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	var config: NetworkConfig = _config
	if config != null:
		_free_ports.assign(config.match_ports())
	_run_dir = _resolve_run_dir()
	DirAccess.make_dir_recursive_absolute(_run_dir)
	Log.info("Match supervisor ready", {
		"run_dir": _run_dir,
		"ports": _free_ports.size(),
	})


## **Why this server cannot start another match right now**, or empty if it can.
##
## Nothing about the lobby asking - only about the process it would run in. The
## cap counts a START from the moment its countdown began, queued or booting or
## running, so a queue can never overshoot it and "the server is full" is decided
## at Start rather than after a countdown has already run.
func refusal(host_address: String) -> String:
	var config: NetworkConfig = _config
	if config == null:
		return "This server has no network configuration."
	if _free_ports.is_empty():
		return "The server is full."
	if _children.size() >= maxi(1, config.match_cap):
		return "The server is full."
	if _count_for(host_address) >= maxi(1, config.match_per_source_limit):
		return "You already have as many matches running as this server allows."
	return ""


## Takes a slot, a port and a child for a countdown that has just begun.
##
## D24 froze the roster, the seats, the colours and the settings when the
## countdown started, so the setup is final NOW - which is why the boot happens
## during the countdown rather than after it, and hides inside it.
func begin_start(
	lobby_id: String,
	setup: MatchSetup,
	tokens: Dictionary,
	host_address: String
) -> bool:
	if setup == null || _children.has(setup.match_id):
		Log.err("Match supervisor was asked to start a match it cannot", lobby_id)
		return false

	var child: Child = Child.new()
	child.lobby_id = lobby_id
	child.match_id = setup.match_id
	child.setup = setup
	child.tokens = tokens
	child.host_address = host_address
	child.countdown_ends = Time.get_unix_time_from_system() + _countdown_left()
	_children[child.match_id] = child
	set_process(true)

	# **Serialised.** A boot costs whole CPU-seconds and every running relay
	# needs its tick on time, so one child boots at a time until P5 measures
	# whether the box's cores can take more.
	if _booting_child() != null:
		Log.info("Match start queued behind a booting child", {"match": child.match_id})
		return true
	return _spawn(child)


## The start is off: a member left, the host cancelled, or the server is going
## down. The child is KILLED rather than asked to stop - it may not be listening
## yet, and nobody has been told to move.
func cancel_start(lobby_id: String, reason: String) -> void:
	for match_id: String in _children.keys():
		var child: Child = _children[match_id]
		if child.lobby_id != lobby_id:
			continue
		Log.info("Cancelling a start", {"match": match_id, "why": reason})
		_kill_and_reap(child, "cancelled")


## The players have been told. From here the child owns the match, and a D45
## shutdown asks it to stop rather than killing it.
func mark_announced(match_id: String) -> void:
	var child: Child = _children.get(match_id)
	if child != null:
		child.state = State.ANNOUNCED


## How many matches this process is responsible for, queued and booting and
## running. The "Matches running" line, and the cap's own count.
func child_count() -> int:
	return _children.size()


## Every match id this supervisor holds, for the log line and for a deploy that
## wants to say how many players it is about to disturb.
func match_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for match_id: String in _children:
		ids.append(match_id)
	return ids


## D45: asks every ANNOUNCED child to stop, and kills the rest.
##
## The announced ones have players in them, so they get the shutdown file and
## tell their own players; a child nobody has been sent to has nothing to say and
## is killed. Created at the START of the lobby's notice phase, so the children's
## notices and closes run alongside the lobby's rather than after them.
func begin_shutdown_of_all() -> void:
	for match_id: String in _children.keys():
		var child: Child = _children[match_id]
		if child.state == State.ANNOUNCED:
			var file: FileAccess = FileAccess.open(child.run_base + ".shutdown", FileAccess.WRITE)
			if file != null:
				file.close()
			Log.info("Asked a match to shut down", {"match": match_id})
		else:
			_kill_and_reap(child, "cancelled")


## Whether every child has gone, which is what the lobby's own quit waits for.
func all_gone() -> bool:
	return _children.is_empty()


func _process(delta: float) -> void:
	_poll_clock += delta
	if _poll_clock < POLL_SECONDS:
		return
	var elapsed: float = _poll_clock
	_poll_clock = 0.0

	for match_id: String in _children.keys():
		var child: Child = _children.get(match_id)
		if child != null:
			_poll_child(child, elapsed)
	_drain_queue()
	if _children.is_empty():
		set_process(false)


## **READY first, then liveness, then the ceiling**, and the order is the point.
##
## A child that wrote READY in the same poll as its ceiling ran out has started
## successfully, and killing it because the clock says so would throw away a
## match that was about to work. A child that exited on its own is handled before
## the ceiling for the same reason: its exit CODE says more than the clock does.
func _poll_child(child: Child, delta: float) -> void:
	if child.state == State.QUEUED:
		return

	if child.state == State.BOOTING:
		child.booting_for += delta
		if FileAccess.file_exists(child.run_base + ".ready"):
			_accept_ready(child)
			return
		if !OS.is_process_running(child.pid):
			_handle_early_exit(child)
			return
		if child.booting_for >= _ready_ceiling():
			Log.err("A match process never became ready", {
				"match": child.match_id, "seconds": child.booting_for,
			})
			_kill_and_reap(child, "never_ready")
		return

	# Ready or announced: it is running its own match now.
	if !OS.is_process_running(child.pid):
		_reap(child)
		return
	if _heartbeat_is_stale(child):
		Log.err("A match process wedged, killing it", {"match": child.match_id})
		_kill_and_reap(child, "wedged")


func _accept_ready(child: Child) -> void:
	# The pid in the READY file is what tells this child's READY from one its
	# own failed predecessor left behind on the same match id.
	var stated: Dictionary = MatchHandoff.read_json(child.run_base + ".ready")
	if int(stated.get("pid", 0)) != child.pid:
		Log.warn("Ignoring a READY file from another process", {
			"match": child.match_id, "says": stated.get("pid", 0), "expected": child.pid,
		})
		return
	child.state = State.READY
	Log.info("Match process is ready", {
		"match": child.match_id, "port": child.port, "pid": child.pid,
		"seconds": snappedf(child.booting_for, 0.01),
	})
	child_ready.emit(child.lobby_id, child.match_id, child.port)


## The child exited before it was ready. A TAKEN PORT is worth exactly one
## respawn on the next free one; anything else cancels the start.
func _handle_early_exit(child: Child) -> void:
	var code: int = OS.get_process_exit_code(child.pid)
	if code == MatchHandoff.EXIT_PORT_TAKEN && !child.respawned:
		Log.warn("A match port was taken, respawning on the next one", {
			"match": child.match_id, "port": child.port,
		})
		child.respawned = true
		_release_port(child.port)
		# **Every file the failed spawn left goes first, and the match file is
		# written again**: the first child deleted it on reading, and both spawns
		# share one match id, so a heartbeat or log left behind would be read as
		# the new child's.
		_remove_run_files(child)
		if _spawn(child):
			return
	Log.err("A match process died before it was ready", {
		"match": child.match_id, "code": code,
	})
	_finish(child, "died", code)
	child_failed.emit(child.lobby_id, "The match could not be started.")


## A child that exited on its own. Its RESULT says how the match went; a child
## with none is logged as having died, with its code.
func _reap(child: Child) -> void:
	var code: int = OS.get_process_exit_code(child.pid)
	_finish(child, "died", code)


## Kills a child and reaps it in the same breath.
##
## **On Linux `OS.kill` reaps the process itself and never updates Godot's
## table**, so a later `is_process_running` on that pid logs an engine error and
## reads 0 - which looks exactly like a clean exit. So a killed child leaves
## supervision here, in this call, rather than being noticed later.
func _kill_and_reap(child: Child, how: String) -> void:
	if child.pid > 0:
		OS.kill(child.pid)
	_finish(child, how, -1)


## The one exit: the RESULT becomes a log line, the files go, the port comes back
## and the slot is freed.
##
## **The RESULT is logged rather than kept.** Tools read the journal with `-o cat`
## and there is nothing to read a file with, so the line carries the match id and
## the file is deleted with the rest. A child that left no RESULT gets a line
## written here instead, which is what makes "died" visible at all.
func _finish(child: Child, fallback: String, code: int) -> void:
	var result: Dictionary = MatchHandoff.read_json(child.run_base + ".result")
	if result.is_empty():
		result = {"match": child.match_id, "ended": fallback}
	if code >= 0:
		result["exit_code"] = code
	Log.info("Match result", result)

	_remove_run_files(child)
	_release_port(child.port)
	_children.erase(child.match_id)
	Log.info("Matches running", {"count": _children.size()})


## Makes the next queued start, if nothing is booting. Serialised spawns mean a
## queue, and a queue means something has to drain it.
func _drain_queue() -> void:
	if _booting_child() != null:
		return
	for match_id: String in _children:
		var child: Child = _children[match_id]
		if child.state == State.QUEUED:
			_spawn(child)
			return


# --- spawning -------------------------------------------------------------

## Writes the match file and starts the child.
##
## *Why a file and not arguments:* Boot logs its arguments, `/proc/<pid>/cmdline`
## is readable by every local user, and journald records each writer's command
## line. A token must reach none of them.
func _spawn(child: Child) -> bool:
	var binary: String = OS.get_executable_path()
	# **A Godot upgrade under a running lobby.** The kernel marks a replaced
	# binary's path " (deleted)", and spawning from it would either fail or run
	# the old code against a new checkout.
	if binary.ends_with(" (deleted)"):
		Log.err("This server's binary has been replaced, no match can be spawned", binary)
		_children.erase(child.match_id)
		child_failed.emit(child.lobby_id, "The server is being updated. Try again shortly.")
		return false

	var port: int = _take_port()
	if port == 0:
		Log.err("No match port is free", child.match_id)
		_children.erase(child.match_id)
		child_failed.emit(child.lobby_id, "The server is full.")
		return false
	child.port = port
	child.run_base = _run_dir.path_join(child.match_id)

	if !MatchHandoff.write_match_file(
		child.run_base + ".match", child.setup, child.tokens,
		child.countdown_ends, OS.get_process_id()
	):
		_release_port(port)
		_children.erase(child.match_id)
		child_failed.emit(child.lobby_id, "The match could not be started.")
		return false

	var arguments: PackedStringArray = PackedStringArray([
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--log-file", child.run_base + ".log",
		"--",
		"--match-server",
		"--match-id", child.match_id,
		"--match-file", child.run_base + ".match",
		"--port", str(port),
		"--shutdown-file", child.run_base + ".shutdown",
	])
	var pid: int = OS.create_process(binary, arguments)
	if pid <= 0:
		Log.err("Could not spawn a match process", {"match": child.match_id})
		_remove_run_files(child)
		_release_port(port)
		_children.erase(child.match_id)
		child_failed.emit(child.lobby_id, "The match could not be started.")
		return false

	child.pid = pid
	child.state = State.BOOTING
	child.booting_for = 0.0
	Log.info("Match process spawned", {
		"match": child.match_id, "pid": pid, "port": port,
	})
	Log.info("Matches running", {"count": _children.size()})
	return true


# --- files and ports ------------------------------------------------------

## Where the per-match files live.
##
## `/run/ltw-server` on the box, which the unit's `RuntimeDirectory` creates with
## mode 0700 - **the match file is private because its directory is**, since the
## defaults are 0755 for a directory and 0644 for a file. `user://run` on Windows,
## where the dev loop is the only reader.
func _resolve_run_dir() -> String:
	var config: NetworkConfig = _config
	var named: String = "" if config == null else config.shutdown_file_path()
	if !named.is_empty():
		return MatchHandoff.normalise(named).get_base_dir()
	if OS.get_name() == "Linux":
		return "/run/ltw-server"
	return ProjectSettings.globalize_path("user://run")


func _remove_run_files(child: Child) -> void:
	if child.run_base.is_empty():
		return
	# **The LOG is deliberately kept.** On Windows it is a child's only output,
	# and it is what the dev loop and every proof read; deleting it at reap would
	# take it away before the harness could check its positive control.
	for suffix: String in [".match", ".ready", ".result", ".heartbeat", ".shutdown"]:
		DirAccess.remove_absolute(child.run_base + suffix)


func _take_port() -> int:
	if _free_ports.is_empty():
		return 0
	return _free_ports.pop_front()


func _release_port(port: int) -> void:
	if port > 0 && !(port in _free_ports):
		# To the BACK, so the least recently freed port is the next one handed
		# out: a port released a moment ago may still be held by the OS.
		_free_ports.push_back(port)


## Whether a child has stopped touching its heartbeat file.
##
## **Read as a MODIFICATION TIME, never as the file's contents.** The first
## version parsed a timestamp out of the file, and a healthy match was killed
## mid-play for being wedged: the child writes by opening the file for WRITE,
## which TRUNCATES it, so a reader landing in that window gets an empty string -
## which parses as 0, which is infinitely stale. The file being TOUCHED is the
## whole signal, so there was never a reason to look inside it.
##
## Judged only after READY, which is all the caller asks about: the boot is
## synchronous and writes no heartbeat, so judging a booting child would kill
## slow but healthy boots. Before READY the ceiling is the only bound.
func _heartbeat_is_stale(child: Child) -> bool:
	var config: NetworkConfig = _config
	if config == null:
		return false
	var bound: float = maxf(2.0, config.match_heartbeat_stale_seconds)
	# **The newest beat ever SEEN, kept on the child.** A missing file is "no new
	# reading", never "no reading at all": whatever writes it has a moment when
	# it is not there - a truncating write, a rename, a filesystem being a
	# filesystem - and a poll landing in that moment must not be able to condemn
	# a match. This exact fallback, reading the READY stamp instead, killed a
	# healthy match the first time it was tried.
	var path: String = child.run_base + ".heartbeat"
	if FileAccess.file_exists(path):
		child.last_beat = maxf(child.last_beat, float(FileAccess.get_modified_time(path)))
	# Until the first beat lands there is the READY stamp to measure from, so
	# there is never a moment with nothing to measure against at all.
	var at: float = maxf(child.last_beat, _ready_stamp(child))
	return Time.get_unix_time_from_system() - at > bound


## When this child said it was ready, or NOW if it has stopped saying so.
##
## "Now" for a missing file rather than zero, because this is only ever the
## floor under a heartbeat reading: a child that has cleaned its files up on the
## way out must not read as infinitely stale in the moment before the supervisor
## notices it has gone.
func _ready_stamp(child: Child) -> float:
	var path: String = child.run_base + ".ready"
	if FileAccess.file_exists(path):
		return float(FileAccess.get_modified_time(path))
	return Time.get_unix_time_from_system()


func _booting_child() -> Child:
	for match_id: String in _children:
		var child: Child = _children[match_id]
		if child.state == State.BOOTING:
			return child
	return null


func _count_for(host_address: String) -> int:
	if host_address.is_empty():
		return 0
	var count: int = 0
	for match_id: String in _children:
		if _children[match_id].host_address == host_address:
			count += 1
	return count


func _ready_ceiling() -> float:
	var config: NetworkConfig = _config
	return 45.0 if config == null else maxf(5.0, config.match_ready_ceiling_seconds)


func _countdown_left() -> float:
	var menus: MenuConfig = References.menu_config
	return 5.0 if menus == null else maxf(0.0, menus.start_countdown_seconds)
