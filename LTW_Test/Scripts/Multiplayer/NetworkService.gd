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
}

## The server is always peer 1 in Godot's high-level multiplayer. Named so the
## number stops being a magic 1 scattered through rpc_id calls.
const SERVER_PEER_ID: int = 1

var _status: Status = Status.OFFLINE
var _peer: ENetMultiplayerPeer = null
## Seconds left before an unanswered connection attempt is given up on.
var _connect_countdown: float = 0.0


func _ready() -> void:
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

	var address: String = address_override.strip_edges()
	if address.is_empty():
		address = config.resolved_address()
	var port: int = port_override if port_override > 0 else config.resolved_port()

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port)
	if error != OK:
		Log.err("Could not start a connection", {
			"address": address,
			"port": port,
			"error": error,
		})
		return _refuse(Result.CLIENT_FAILED, "join")

	_peer = peer
	multiplayer.multiplayer_peer = peer
	_connect_countdown = config.connect_timeout_seconds
	set_process(true)
	_set_status(Status.CONNECTING)
	Log.info("Connecting", {"address": address, "port": port})
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
	return "Unknown error"


## Only ever running while a connection attempt is outstanding.
##
## Deliberately _process and not _physics_process, against the usual rule: this
## is a wall-clock timeout on a socket, not simulation. It has to keep counting
## on a machine whose match has not started and whose physics tick is therefore
## carrying nothing.
func _process(delta: float) -> void:
	if _status != Status.CONNECTING:
		set_process(false)
		return

	_connect_countdown -= delta
	if _connect_countdown > 0.0:
		return

	Log.warn("The server did not answer in time, giving up")
	_teardown()
	connection_failed.emit(Result.TIMED_OUT)


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
	Log.info("Connected to the server", {"peer_id": multiplayer.get_unique_id()})
	connected_to_server.emit()


func _on_connection_failed() -> void:
	Log.warn("The server refused the connection")
	_teardown()
	connection_failed.emit(Result.REFUSED)


func _on_server_disconnected() -> void:
	Log.warn("The server closed the connection")
	_teardown()
	disconnected_from_server.emit()


## Fires on a client too, where the first "peer" to appear is the server
## itself. Saying so beats a line reading "Peer joined 1" on a machine that
## just connected to peer 1.
func _on_peer_connected(id: int) -> void:
	if id == SERVER_PEER_ID && !is_server():
		Log.info("The server is on the line")
	else:
		Log.info("Peer joined", id)
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	Log.info("Peer left", id)
	peer_left.emit(id)


## Back to a clean offline state from anywhere, so no failure path can leave a
## half-open peer behind for the next attempt to trip over.
func _teardown() -> void:
	set_process(false)
	_connect_countdown = 0.0
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	_set_status(Status.OFFLINE)


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


## Read at call time rather than held, because References belongs to whatever
## scene is currently up and this object outlives all of them.
func _config() -> NetworkConfig:
	var config: NetworkConfig = References.network_config
	if config == null:
		Log.err("No NetworkConfig on References, this process cannot reach the network")
	return config
