class_name NetworkService
extends Node

## Owns the one ENetMultiplayerPeer this process has, and is the only thing that
## ever assigns multiplayer.multiplayer_peer.
##
## **Registered as the autoload `Net`**, not as `NetworkService`: Godot refuses
## an autoload whose name collides with a global class, and CLAUDE.md wants the
## class named after its file. So the type is NetworkService and the singleton
## is `Net`, which is also how it reads at a call site - `Net.join()`.
##
## It is an autoload rather than a References entry because it has to OUTLIVE
## scene changes (D10). The menus change scenes with change_scene_to_file, and
## References is per-scene, so anything holding a socket there would die on
## every transition - which is exactly what a connection must not do.
##
## Every entry point returns a Result rather than a bare bool, which is the one
## genuinely good idea in the reference template (multiplayer.md 13). What went
## wrong there is not copied: it kept an `is_busy` flag that a failed host never
## cleared, so one failure bricked the object for the rest of the session. There
## is no such flag here. `_status` is the only state, every failure path puts it
## back to OFFLINE, and the guards read it directly.
##
## It knows nothing about lobbies. That is the `Lobby` autoload in 1.4 (D21);
## this layer only answers "is there a connection, and who is on it".

## Fires on every state change, for a UI that just wants to redraw.
signal status_changed(new_status: Status)
## Server side: the listen socket is open.
signal hosting_started()
## Client side: the server accepted us.
signal connected_to_server()
## Client side: it did not, or never answered. Carries why.
signal connection_failed(result: Result)
## Client side: a new address is being dialled, and which one of how many it is.
##
## Its own signal rather than another status_changed, because the status does
## NOT change while the list is walked - it is CONNECTING from the first address
## to the last - and a screen showing the first address for the whole walk is a
## screen that stops telling the truth on the second one.
signal attempting_address(address: String, index: int, of: int)
## Client side: we were connected and now are not.
signal disconnected_from_server()
## Server side: somebody arrived / left. The peer id is their identity on the
## wire, and 1.6 makes it their player id.
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

enum Status {
	OFFLINE,
	CONNECTING,
	CONNECTED,
	HOSTING,
}

enum Result {
	OK,
	ALREADY_ONLINE,
	NO_CONFIG,
	BAD_CONFIG,
	HOST_FAILED,
	CLIENT_FAILED,
	REFUSED,
	TIMED_OUT,
	VERSION_MISMATCH,
}

## The server is always peer 1 in Godot's high-level multiplayer. Named so the
## number stops being a magic 1 scattered through rpc_id calls.
const SERVER_PEER_ID: int = 1

## How long the server waits after refusing a build before hanging up on it.
##
## It exists because **an rpc is not sent when it is called.** Godot queues it
## and flushes at the end of the frame, so disconnecting the peer in the same
## frame destroys the channels the queued packet still has to go out on, and it
## dies at flush time with "Unable to send packet on channel 0, max channels: 0"
## - on the SERVER, where nobody is looking, while the client simply sees the
## connection close with no reason given. Which is precisely the silent failure
## this whole handshake was built to replace.
##
## One frame would be enough. A second is used because the cost of being wrong
## about that is the same silent failure, and the cost of waiting is a socket
## held open a moment longer for a peer that is already leaving.
const REFUSAL_FLUSH_SECONDS: float = 1.0

var _status: Status = Status.OFFLINE
var _peer: ENetMultiplayerPeer = null
## Seconds left before THIS attempt is given up on and the next address tried.
var _connect_countdown: float = 0.0
## The addresses this join is walking, and how far along it is. Empty unless a
## join is in progress or has just failed - it is the record of what was tried,
## which is the only useful thing to say when none of them answered.
var _candidates: PackedStringArray = PackedStringArray()
var _candidate_index: int = 0
## Held for the whole walk, because every candidate is dialled on the same port.
var _port: int = 0
## Server side: peer id -> seconds left to state a protocol version. A peer
## leaves this the moment it states one, whether or not the number was right.
var _awaiting_version: Dictionary = {}
## Server side: peer id -> seconds left before hanging up on a refused build.
## Separate from the above because these peers have already answered; what they
## are waiting on is the refusal reaching them.
var _closing: Dictionary = {}
## Why the last attempt was refused, when the Result alone cannot say. Only the
## version mismatch fills it in, because only that failure has a detail worth
## putting in front of a player: which build each end is on.
var _refusal_detail: String = ""


func _ready() -> void:
	# The socket does not stop because the world is held still. Every other
	# network autoload says the same thing, and this is the one they all sit
	# on top of - see StartingTech's draft.
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	set_process(false)


## Opens the listen socket. Server only.
func host(port_override: int = 0) -> Result:
	if _status != Status.OFFLINE:
		return _refuse(Result.ALREADY_ONLINE, "host")

	var config: NetworkConfig = _config()
	if config == null:
		return _refuse(Result.NO_CONFIG, "host")
	if !config.validate():
		return _refuse(Result.BAD_CONFIG, "host")

	var port: int = port_override if port_override > 0 else config.resolved_port()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, config.max_peers)
	if error != OK:
		# Almost always the port already being in use - a second server started
		# without changing it, or the last one not yet released by the OS.
		Log.err("Could not open the server port", {"port": port, "error": error})
		return _refuse(Result.HOST_FAILED, "host")

	_peer = peer
	multiplayer.multiplayer_peer = peer
	# Running from here on, so a peer that connects and then says nothing is
	# eventually dropped rather than left sitting there looking connected.
	set_process(true)
	_set_status(Status.HOSTING)
	Log.info("Listening", {"port": port, "max_peers": config.max_peers})
	hosting_started.emit()
	return Result.OK


## Dials the server. Client only.
##
## Returning OK means the attempt STARTED, not that it succeeded - ENet reports
## an unreachable address by never answering, so the real answer arrives later
## on connected_to_server or connection_failed. Callers must show a connecting
## state rather than assuming they are in.
func join(address_override: String = "", port_override: int = 0) -> Result:
	if _status != Status.OFFLINE:
		return _refuse(Result.ALREADY_ONLINE, "join")

	var config: NetworkConfig = _config()
	if config == null:
		return _refuse(Result.NO_CONFIG, "join")
	if !config.validate():
		return _refuse(Result.BAD_CONFIG, "join")

	_refusal_detail = ""
	# An address named by the caller is an instruction to dial THAT machine, so
	# it replaces the list rather than joining the front of it.
	var single: String = address_override.strip_edges()
	if single.is_empty():
		_candidates = config.resolved_addresses()
	else:
		_candidates = PackedStringArray([single])
	_port = port_override if port_override > 0 else config.resolved_port()

	if !_dial_from(0):
		return _refuse(Result.CLIENT_FAILED, "join")
	return Result.OK


## Hangs up, from either end. Safe to call when already offline, because the
## caller usually cannot know - a Back button does not care whether the
## connection failed a moment ago.
func leave() -> void:
	if _status == Status.OFFLINE:
		return
	Log.info("Closing the connection", {"was": Status.keys()[_status]})
	_teardown()


func status() -> Status:
	return _status


func is_online() -> bool:
	return _status == Status.CONNECTED || _status == Status.HOSTING


## Whether this process is the authority. False while offline, which is the
## honest answer: a machine with no peer is not the server.
func is_server() -> bool:
	return _status == Status.HOSTING


## This machine's id on the wire, or 0 when offline.
func peer_id() -> int:
	if !is_online():
		return 0
	return multiplayer.get_unique_id()


## Everyone connected to us, server side. Empty on a client.
func peer_ids() -> PackedInt32Array:
	if _status != Status.HOSTING:
		return PackedInt32Array()
	return multiplayer.get_peers()


## The address currently being dialled, or the last one dialled once the walk
## has ended. Empty when no join has been attempted.
##
## Different from NetworkConfig.resolved_address(), which is the FIRST address
## that would be tried. Once the list has more than one entry, "where are we
## dialling" and "where would we start" stop being the same question, and a
## status line that answers the second one while doing the first is a status
## line that lies.
func current_address() -> String:
	if _candidates.is_empty():
		return ""
	return _candidates[clampi(_candidate_index, 0, _candidates.size() - 1)]


## Every address the last join attempt walked, so a failure can say what it
## actually tried rather than naming one address out of several.
func attempted_addresses() -> PackedStringArray:
	return _candidates


## Detail behind the last refusal, or empty when the Result says it all. Only a
## version mismatch fills this in.
func refusal_detail() -> String:
	return _refusal_detail


## A Result as something a player can be shown. Kept next to the enum so a new
## case cannot be added without an obvious place to describe it - 1.8 turns
## these into the connection failure states the UI does not have yet.
static func describe(result: Result) -> String:
	match result:
		Result.OK:
			return "OK"
		Result.ALREADY_ONLINE:
			return "Already connected"
		Result.NO_CONFIG:
			return "No network configuration"
		Result.BAD_CONFIG:
			return "The network configuration is unusable"
		Result.HOST_FAILED:
			return "Could not open the server port"
		Result.CLIENT_FAILED:
			return "Could not start the connection"
		Result.REFUSED:
			return "The server refused the connection"
		Result.TIMED_OUT:
			return "The server did not answer"
		Result.VERSION_MISMATCH:
			return "This build cannot play against that server"
	return "Unknown error"


## Two clocks, never both at once: a client's timeout on the address it is
## dialling, and a server's timeout on peers that have not yet said what build
## they are. Offline there is nothing to count and this switches itself off.
##
## Deliberately _process and not _physics_process, against the usual rule: these
## are wall-clock timeouts on a socket, not simulation. They have to keep
## counting on a machine whose match has not started and whose physics tick is
## therefore carrying nothing.
func _process(delta: float) -> void:
	match _status:
		Status.CONNECTING:
			_tick_connect(delta)
		Status.HOSTING:
			_tick_handshakes(delta)
		_:
			set_process(false)


## A client waiting on one address. Running out is not a failure yet - there may
## be another address behind it.
func _tick_connect(delta: float) -> void:
	_connect_countdown -= delta
	if _connect_countdown > 0.0:
		return
	Log.info("No answer in time", {"address": current_address()})
	_advance_candidate()


## A server waiting on peers, for either of the two reasons it ever does: one
## that has not yet said what build it is, and one that has been told its build
## is wrong and is being given time to hear it.
func _tick_handshakes(delta: float) -> void:
	# keys() is a copy, so erasing inside the loop is safe.
	for peer_id in _awaiting_version.keys():
		var left: float = float(_awaiting_version[peer_id]) - delta
		if left > 0.0:
			_awaiting_version[peer_id] = left
			continue
		_awaiting_version.erase(peer_id)
		Log.warn("Peer never said what build it is, dropping it", {"peer": peer_id})
		_disconnect_peer(peer_id)

	for peer_id in _closing.keys():
		var left: float = float(_closing[peer_id]) - delta
		if left > 0.0:
			_closing[peer_id] = left
			continue
		_closing.erase(peer_id)
		_disconnect_peer(peer_id)


## Hanging up politely on the way out, so other players see somebody leave at
## once rather than after ENet's dead-peer timeout - measured at about 5.6 s.
##
## Best effort, and deliberately not relied on: a crash, a kill or a pulled
## cable cannot run this. That is why the server treats a peer that simply stops
## answering as a peer that left (1.9), and why this only makes the common case
## faster rather than making the uncommon one work.
##
## NOT _teardown(): that emits signals, and by this point half the listeners are
## themselves leaving the tree. All that matters here is that the socket says
## goodbye.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST && what != NOTIFICATION_EXIT_TREE:
		return
	if _peer == null:
		return

	Log.info("Closing the connection on the way out")
	_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	_status = Status.OFFLINE


func _on_connected_to_server() -> void:
	set_process(false)
	_set_status(Status.CONNECTED)
	Log.info("Connected to the server", {
		"peer_id": multiplayer.get_unique_id(),
		"address": current_address(),
	})
	# BEFORE the signal, and it matters: Lobby answers that signal by registering
	# this player, and both calls are reliable on the same channel, so sending
	# ours first is what puts the build number ahead of everything else this
	# client will ever say. A server that refuses us then does so before it has
	# been asked for anything.
	state_protocol_version.rpc_id(SERVER_PEER_ID, _protocol_version())
	connected_to_server.emit()


## ENet gave up on this address. To a client hunting for whichever machine is
## hosting today, that means the same thing a silence does - not this one - so
## it walks on rather than ending the attempt.
func _on_connection_failed() -> void:
	if _status != Status.CONNECTING:
		return
	Log.info("Refused", {"address": current_address()})
	_advance_candidate()


func _on_server_disconnected() -> void:
	# A refused build tears itself down and says why; the server hanging up
	# afterwards is the same event arriving a second time, with less to say.
	if _status == Status.OFFLINE:
		return
	Log.warn("The server closed the connection")
	_teardown()
	disconnected_from_server.emit()


## Fires on a client too, where the first "peer" to appear is the server
## itself. Saying so beats a line reading "Peer joined 1" on a machine that
## just connected to peer 1.
func _on_peer_connected(id: int) -> void:
	if is_server():
		Log.info("Peer joined", id)
		# On the clock from here until it says what build it is.
		_awaiting_version[id] = _handshake_timeout()
	elif id == SERVER_PEER_ID:
		Log.info("The server is on the line")
	else:
		Log.info("Peer joined", id)
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	Log.info("Peer left", id)
	_awaiting_version.erase(id)
	_closing.erase(id)
	peer_left.emit(id)


## Back to a clean offline state from anywhere, so no failure path can leave a
## half-open peer behind for the next attempt to trip over.
func _teardown() -> void:
	set_process(false)
	_connect_countdown = 0.0
	_awaiting_version.clear()
	_closing.clear()
	_close_peer()
	_set_status(Status.OFFLINE)


## The socket alone, with the status left where it is. What the walk between two
## addresses needs: closing one attempt must not announce that we are offline,
## because a moment later we are dialling the next one and every listener would
## have redrawn twice for nothing.
func _close_peer() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null


func _set_status(new_status: Status) -> void:
	if _status == new_status:
		return
	_status = new_status
	status_changed.emit(new_status)


## Logs and returns a refusal in one line, so every guard above stays one line
## and no early return can forget to say why.
func _refuse(result: Result, action: String) -> Result:
	Log.warn("Network request refused", {
		"action": action,
		"reason": describe(result),
		"status": Status.keys()[_status],
	})
	return result


# --- the protocol version handshake ---------------------------------------
#
# The first thing a client says and the first thing the server checks. It exists
# because two machines running different builds of this project cannot be told
# apart by anything else until they have already gone wrong together: the server
# simulates and the clients draw, so a disagreement about what an authored id
# means, or about the shape of a command, surfaces as rejected orders or a world
# that quietly differs - never as "you need to update".
#
# It lives HERE rather than on Lobby, though Lobby already has a first-message
# of its own in register_player, because this gates the CONNECTION rather than
# the lobby. A peer refused here never reaches Lobby at all, and anything added
# later that talks before Lobby does is covered without being changed.

## Stated by a client the moment it connects. Server side.
@rpc("any_peer", "reliable")
func state_protocol_version(version: int) -> void:
	if !multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	# Off the clock whatever the answer: it has spoken, so the silence timeout in
	# _tick_handshakes is no longer the thing that applies to it.
	_awaiting_version.erase(sender)

	var expected: int = _protocol_version()
	if version == expected:
		Log.info("Peer is on our build", {"peer": sender, "build": version})
		return

	Log.warn("Refusing a peer on another build", {
		"peer": sender,
		"theirs": version,
		"ours": expected,
	})
	refuse_protocol_version.rpc_id(sender, expected)
	# NOT disconnected here - see _closing and REFUSAL_FLUSH_SECONDS.
	_closing[sender] = REFUSAL_FLUSH_SECONDS


## The server saying no, with its own number so the client can say which way
## round the mismatch is. Client side.
@rpc("authority", "reliable")
func refuse_protocol_version(server_version: int) -> void:
	if multiplayer.is_server():
		return
	var ours: int = _protocol_version()
	_refusal_detail = "The server is on build %d and this game is build %d." % [
		server_version, ours,
	]
	Log.warn("The server refused this build", {"theirs": server_version, "ours": ours})
	# A wrong build is wrong at every address, so the walk stops here rather than
	# carrying the same refusal to the next machine on the list.
	_candidates = PackedStringArray([current_address()])
	_teardown()
	connection_failed.emit(Result.VERSION_MISMATCH)


# --- walking the address list ---------------------------------------------

## Starts the first attempt at or after `index` that ENet is willing to open,
## and says whether there was one.
##
## A create_client that fails outright - a malformed address, almost always - is
## SKIPPED rather than ending the walk. One unusable row in the inspector must
## not hide the good addresses sitting behind it.
func _dial_from(index: int) -> bool:
	_candidate_index = index
	while _candidate_index < _candidates.size():
		if _try_candidate():
			return true
		_candidate_index += 1
	return false


func _try_candidate() -> bool:
	var address: String = _candidates[_candidate_index]
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, _port)
	if error != OK:
		Log.err("Could not start a connection", {
			"address": address,
			"port": _port,
			"error": error,
		})
		return false

	_peer = peer
	multiplayer.multiplayer_peer = peer
	_connect_countdown = _connect_timeout()
	set_process(true)
	_set_status(Status.CONNECTING)
	Log.info("Connecting", {
		"address": address,
		"port": _port,
		"candidate": _candidate_index + 1,
		"of": _candidates.size(),
	})
	attempting_address.emit(address, _candidate_index + 1, _candidates.size())
	return true


## On to the next address, or the end of the road. The only place a join
## actually fails, so it is the only place that has to say what was tried.
func _advance_candidate() -> void:
	_close_peer()
	if _dial_from(_candidate_index + 1):
		return

	Log.warn("No server answered", {"tried": _candidates, "port": _port})
	_teardown()
	connection_failed.emit(Result.TIMED_OUT)


## Hangs up on one peer, server side.
##
## now = false on purpose: anything already queued for that peer - the refusal
## just sent, in particular - still goes out before the socket closes. Dropping
## it immediately would refuse the build without ever saying so.
func _disconnect_peer(id: int) -> void:
	if _peer == null:
		return
	_peer.disconnect_peer(id, false)


# --- config, with a usable answer when there is none ----------------------

func _protocol_version() -> int:
	var config: NetworkConfig = _config()
	if config == null:
		return 0
	return config.protocol_version


func _handshake_timeout() -> float:
	var config: NetworkConfig = _config()
	if config == null:
		return 5.0
	return config.handshake_timeout_seconds


func _connect_timeout() -> float:
	var config: NetworkConfig = _config()
	if config == null:
		return 3.0
	return config.connect_timeout_seconds


## Read at call time rather than held, because References belongs to whatever
## scene is currently up and this object outlives all of them.
func _config() -> NetworkConfig:
	var config: NetworkConfig = References.network_config
	if config == null:
		Log.err("No NetworkConfig on References, this process cannot reach the network")
	return config
