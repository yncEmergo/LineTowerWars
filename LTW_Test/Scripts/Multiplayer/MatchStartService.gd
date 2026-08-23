class_name MatchStartService
extends Node

## Getting everybody from "the countdown ran out" to "the match exists on every
## machine", and nothing beyond that. **Registered as the autoload
## `MatchStart`**, for the same reason as `Net` and `Lobby`: Godot refuses an
## autoload whose name collides with a global class.
##
## **One object on both machines, branching on who is the server** (D21), so
## the `@rpc` node path matches by construction.
##
## The sequence, which is the whole point of this class existing:
##
##     countdown reaches zero
##       -> Lobby hands the MatchSetup over
##       -> server to each client:  receive_match_starting(setup)
##       -> each client loads the game SCENE, threaded, and reports loaded
##       -> server waits for all of them, or 60 s (D15)
##       -> server to each client:  receive_match_start(final setup)
##       -> everyone builds the world from that final setup
##
## **Nothing builds a world before the last message.** That is not tidiness
## either: D15 lets the server start without a client that never answered, and
## "no player area spawns for a missing player" is only true if no area has
## been placed by the time we know who is missing. So loading means loading the
## PackedScene - the slow part - and the world is created afterwards, from a
## roster that can no longer change.
##
## What it deliberately does NOT do: run the match. Once the scene is open it
## owns only the match's MEMBERSHIP - the initial-world checksum (2.5), who has
## dropped out of it (3.6), and noticing when everybody has gone. What happens
## to a dropped player's world is the match's business, not this object's: it
## says who left and PlayerManager erases the maze (D14).

## Client side: we are in a match's loading phase, for these players.
signal match_starting(setup: MatchSetup)
## Client side: this is who has finished loading, by peer id.
signal readiness_changed(ready_ids: PackedInt32Array)
## Client side: it fell through before starting, and why.
signal match_cancelled(reason: String)
## Server side: a match that was announced is over, or never began, so whoever
## locked a lobby for it may unlock it again.
signal match_abandoned(match_id: String)
## Server side: this player is gone for good and the match carries on without
## them (D13, D14). Fired once the grace period has run out, or at once when
## they said they were leaving.
signal player_dropped(slot: int)

## The match being started, then the match being played. Null when this process
## is in no match at all, which is what makes every entry point below safe to
## call from a single player run.
var _setup: MatchSetup = null

# --- server state, empty on a client --------------------------------------
## Peers this match was announced to, whether or not they have answered.
var _expected: PackedInt32Array = PackedInt32Array()
## True between announcing the match and starting it. The gate, not the match.
var _waiting: bool = false
## True from the announcement until the last player of that match is gone.
var _in_match: bool = false
var _elapsed: float = 0.0
var _timeout_seconds: float = 60.0
var _min_players: int = 2
## Both read while the server entry scene is still up, because References
## belongs to whatever scene is loaded and a match scene knows nothing about
## menus or boot paths. Kept once read, so the trip back works too.
var _server_match_path: String = ""
var _server_entry_path: String = ""
## Whether this process is currently sitting in a match scene rather than in
## the server's entry scene. Only true on a server.
var _match_scene_open: bool = false
## peer id -> the checksum it reported for its initial world (2.5).
## peer id -> seconds left before they are declared gone (3.6). A peer is in
## here exactly while it is being waited for.
var _grace: Dictionary = {}
## Peers that SAID they were leaving. A client that says goodbye is telling us
## it is not coming back, so it skips the hold entirely - which is only
## possible because a deliberate leave and a silent death are distinguishable
## by what arrives, not merely by how fast (14.1).
var _deliberate: Dictionary = {}
var _grace_seconds: float = 10.0
## peer id -> the checksum it reported for its initial world (2.5).
var _reported_checksums: Dictionary = {}
var _reference_checksum: int = 0
var _has_reference: bool = false

# --- both sides -----------------------------------------------------------
var _ready_ids: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	set_process(false)
	Net.peer_left.connect(_on_peer_left)
	Net.status_changed.connect(_on_network_status_changed)


# --- server: starting a match ---------------------------------------------

## Whether this process already has a match. One process runs the lobby and the
## matches for now (D19), and a process can run one match, so the honest answer
## to a second Start is a sentence rather than a quiet overwrite. Splitting the
## two is an address change (D16).
func is_busy() -> bool:
	return _in_match


## Announces a match to everyone in it and starts waiting for them to load.
## Called by `Lobby` when the countdown reaches zero; the setup is already
## built, with its match id and its seed.
func begin(match_setup: MatchSetup) -> void:
	if !multiplayer.is_server():
		Log.err("MatchStart.begin was called on a machine that is not the server")
		return
	if _in_match:
		Log.err("MatchStart.begin was called while a match is already running")
		return
	if match_setup == null || !match_setup.validate():
		Log.err("MatchStart.begin was given a setup that is not a usable match")
		return

	_setup = match_setup
	_in_match = true
	_waiting = true
	_elapsed = 0.0
	_ready_ids = PackedInt32Array()
	_reported_checksums.clear()
	_has_reference = false
	_read_server_settings()

	_expected = PackedInt32Array()
	for player in match_setup.players:
		if player != null && player.network_id != 0:
			_expected.append(player.network_id)

	Log.info("Match announced", {
		"match": match_setup.match_id,
		"players": _expected.size(),
		"timeout": _timeout_seconds,
	})
	for peer_id in _expected:
		receive_match_starting.rpc_id(peer_id, _payload_for(match_setup, peer_id))
	_broadcast_readiness()
	set_process(true)


# --- client: the loading screen's side ------------------------------------

## The match this machine is loading, or playing, or null for neither.
func setup() -> MatchSetup:
	return _setup


## Who has finished loading, by peer id. What the loading screen lists.
func ready_ids() -> PackedInt32Array:
	return _ready_ids


## Said by the loading screen once it holds the match scene. Not "my world is
## built" - the world is built from the setup that comes back, which is the
## point of the gate.
func report_loaded() -> void:
	if _setup == null:
		return
	report_ready.rpc_id(NetworkService.SERVER_PEER_ID, _setup.match_id)


## The initial-world checksum (2.5), reported by `Main` once it has built.
##
## Both roles call this same method: on the server it becomes the answer every
## client is checked against, on a client it is sent there. Offline, or in a
## match nobody else is in, it does nothing at all.
func report_world_checksum(checksum: int) -> void:
	if _setup == null || !Net.is_online():
		return
	if multiplayer.is_server():
		_reference_checksum = checksum
		_has_reference = true
		Log.info("Initial world checksum", {"match": _setup.match_id, "sum": checksum})
		_compare_checksums()
		return
	report_checksum.rpc_id(NetworkService.SERVER_PEER_ID, _setup.match_id, checksum)


## Leaves a match on purpose: says goodbye, then hangs up, IN THAT ORDER and
## with a poll cycle between them.
##
## The wait is the whole point and it is not a guess. An rpc does not travel
## when it is called - it is handed to ENet, which transmits on the multiplayer
## poll at the top of the next frame - so closing the socket in the same frame
## throws the goodbye away. Measured: the server then held the full grace
## period for a player who had said they were going. Two frames is one
## complete poll cycle, which is the smallest wait that actually works.
##
## Best effort by nature: a crash says nothing at all, which is exactly what
## the grace period is there for. This only makes the polite case fast.
func leave_match() -> void:
	if _setup == null || !Net.is_online() || multiplayer.is_server():
		Net.leave()
		return

	report_leaving.rpc_id(NetworkService.SERVER_PEER_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	Net.leave()


# --- server: what clients send --------------------------------------------


@rpc("any_peer", "reliable")
func report_leaving() -> void:
	if !multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	_deliberate[peer_id] = true
	Log.info("Player is leaving deliberately", peer_id)
	# Usually the disconnect follows within a frame or two, but a client that
	# announces and then hangs would otherwise be held for the full grace, so
	# the drop is resolved here rather than waited for.
	_drop_peer(peer_id, "left the match")

## "I have the match scene loaded." Carries the match id so an answer about a
## match that has already been abandoned cannot count towards the next one.
@rpc("any_peer", "reliable")
func report_ready(match_id: String) -> void:
	if !multiplayer.is_server() || !_waiting || _setup == null:
		return
	if match_id != _setup.match_id:
		return

	var peer_id: int = multiplayer.get_remote_sender_id()
	if !_expected.has(peer_id) || _ready_ids.has(peer_id):
		return

	_ready_ids.append(peer_id)
	Log.info("Client loaded", {
		"peer": peer_id,
		"ready": _ready_ids.size(),
		"of": _expected.size(),
	})
	_broadcast_readiness()


@rpc("any_peer", "reliable")
func report_checksum(match_id: String, checksum: int) -> void:
	if !multiplayer.is_server() || _setup == null || match_id != _setup.match_id:
		return
	_reported_checksums[multiplayer.get_remote_sender_id()] = checksum
	_compare_checksums()


# --- client: what the server sends ----------------------------------------

@rpc("authority", "reliable")
func receive_match_starting(payload: Dictionary) -> void:
	_setup = MatchSetup.from_dict(payload)
	_ready_ids = PackedInt32Array()
	Log.info("Match starting", {
		"match": _setup.match_id,
		"slot": _setup.local_slot,
		"players": _setup.player_count(),
	})
	match_starting.emit(_setup)
	MenuNavigation.to_match_loading(self)


@rpc("authority", "reliable")
func receive_readiness(ready: PackedInt32Array) -> void:
	_ready_ids = ready
	readiness_changed.emit(_ready_ids)


## The go signal. The setup that comes with it is FINAL - it can be shorter
## than the one announced, if somebody never loaded (D15) - so the world is
## built from this one and never from the earlier copy.
@rpc("authority", "reliable")
func receive_match_start(payload: Dictionary) -> void:
	_setup = MatchSetup.from_dict(payload)
	Log.info("Match start", {
		"match": _setup.match_id,
		"slot": _setup.local_slot,
		"players": _setup.player_count(),
	})
	MenuNavigation.to_game(self, _setup)


@rpc("authority", "reliable")
func receive_match_cancelled(reason: String) -> void:
	Log.warn("Match cancelled", reason)
	_setup = null
	_ready_ids = PackedInt32Array()
	match_cancelled.emit(reason)
	# The reason is handed across the scene change, as every other one is.
	MenuNavigation.pending_notice = reason
	# Usually still in the lobby, so that is where this goes back to. If the
	# lobby went away too, the browser is the only place left.
	var lobby: LobbyInfo = Lobby.current()
	if lobby == null:
		MenuNavigation.to_lobby_browser(self)
		return
	MenuNavigation.to_lobby_room(self, lobby)


# --- server: the gate -----------------------------------------------------

## Wall clock, not simulation: this counts while there is no match to tick.
func _process(delta: float) -> void:
	_advance_grace(delta)

	if !_waiting:
		set_process(_grace.is_empty() == false)
		return

	if _ready_ids.size() >= _expected.size():
		_start_match(_setup)
		return

	_elapsed += delta
	if _elapsed < _timeout_seconds:
		return

	# D15. A client that has not answered in a minute has not been slow, it has
	# crashed - the scene is a second or two of loading. Everyone else has
	# waited long enough.
	if _ready_ids.size() < _min_players:
		_abort("Not enough players finished loading.")
		return
	Log.warn("Starting without players who never loaded", {
		"match": _setup.match_id,
		"missing": _expected.size() - _ready_ids.size(),
	})
	_start_match(_roster_of_ready())


## Everyone who reported loaded, renumbered into a legal match.
##
## Slots move, and that is correct: a missing player was never in the match
## rather than in it and instantly dead, so nothing downstream should be able
## to tell somebody was dropped. Starting lives follow the smaller count, which
## is the one visible consequence (§14.2).
func _roster_of_ready() -> MatchSetup:
	var reduced: MatchSetup = MatchSetup.new()
	reduced.match_id = _setup.match_id
	reduced.rng_seed = _setup.rng_seed
	reduced.local_slot = 0
	var slot: int = 1
	for player in _setup.players:
		if player == null || !_ready_ids.has(player.network_id):
			continue
		var copy: MatchPlayer = MatchPlayer.from_dict(player.to_dict())
		copy.slot = slot
		slot += 1
		reduced.players.append(copy)
	return reduced


func _start_match(final_setup: MatchSetup) -> void:
	_waiting = false
	set_process(false)
	_setup = final_setup

	Log.info("Match start", {
		"match": final_setup.match_id,
		"players": final_setup.player_count(),
	})
	var started: PackedInt32Array = PackedInt32Array()
	for player in final_setup.players:
		if player == null || player.network_id == 0:
			continue
		started.append(player.network_id)
		receive_match_start.rpc_id(
			player.network_id, _payload_for(final_setup, player.network_id)
		)

	# Anybody announced to but not started is being left behind (D15). Told so
	# rather than left watching a loading bar that will never finish - a client
	# that hung long enough to be dropped may well come back.
	for peer_id in _expected:
		if !started.has(peer_id):
			receive_match_cancelled.rpc_id(peer_id, "You did not finish loading in time.")
	_expected = started

	# The server builds the same world from the same setup, headless (2.3). Its
	# own copy plays no slot, which is what local_slot 0 means.
	var server_view: MatchSetup = MatchSetup.from_dict(final_setup.to_dict())
	server_view.local_slot = 0
	_match_scene_open = true
	MenuNavigation.to_server_scene(self, _server_match_path, server_view)


## Nothing was started, so everybody goes back to the lobby they were in.
func _abort(reason: String) -> void:
	Log.warn("Match abandoned before it started", {
		"match": _setup.match_id,
		"reason": reason,
	})
	for peer_id in _expected:
		receive_match_cancelled.rpc_id(peer_id, reason)
	_finish_match()


## Going offline ends any claim this object has about a match, in either role.
## A client that left a match keeps no stale match id to answer about, and a
## server whose socket closed has nothing to run.
func _on_network_status_changed(new_status: NetworkService.Status) -> void:
	if new_status != NetworkService.Status.OFFLINE || _setup == null:
		return
	Log.info("Offline, forgetting the match", _setup.match_id)
	_finish_match()


## A match with nobody left in it is over. There is no reconnect (D13), so the
## last player leaving ends it - and that is what frees this process to host
## the next one, which matters more while testing than anywhere else.
func _on_peer_left(peer_id: int) -> void:
	if !multiplayer.is_server() || !_in_match:
		return
	# Already gone. A polite leave arrives twice - the goodbye, then the socket
	# closing - and both describe one player leaving once.
	if !_expected.has(peer_id):
		return

	# A peer that ANNOUNCED it was leaving is already gone as far as the match
	# is concerned; one that simply went quiet gets the hold (D13, 14.1).
	if !_deliberate.has(peer_id) && _grace_seconds > 0.0 && !_grace.has(peer_id):
		_grace[peer_id] = _grace_seconds
		set_process(true)
		Log.info("Player went quiet, holding", {
			"peer": peer_id,
			"seconds": _grace_seconds,
		})
		return

	_drop_peer(peer_id, "disconnected")


## Counts down every hold. Wall clock, like everything else in this class:
## there is a simulation running now, but a grace period is a fact about a
## socket rather than about the world.
func _advance_grace(delta: float) -> void:
	if _grace.is_empty():
		return

	for key in _grace.keys():
		var peer_id: int = int(key)
		var left: float = float(_grace[peer_id]) - delta
		if left > 0.0:
			_grace[peer_id] = left
			continue
		_grace.erase(peer_id)
		Log.info("Player did not come back", peer_id)
		_drop_peer(peer_id, "timed out")


## Declares a player gone for good. **No reconnect, out is out** (D13), so
## there is nothing to keep for them.
##
## What happens to their world is deliberately NOT decided here: this says who
## left, and the match erases their maze (D14). The rest needs no new rule at
## all - with no maze every creep in that lane walks straight through, each
## leak steals a life for whoever sends into it, and they are eliminated the
## ordinary way.
func _drop_peer(peer_id: int, reason: String) -> void:
	if !_in_match:
		return

	_grace.erase(peer_id)
	_deliberate.erase(peer_id)

	var still_here: PackedInt32Array = PackedInt32Array()
	for id in _expected:
		if id != peer_id:
			still_here.append(id)
	if still_here.size() == _expected.size():
		# Already dropped; a leave announcement followed by the disconnect
		# itself arrives as two events about one player.
		return
	_expected = still_here

	var slot: int = _slot_of(peer_id)
	Log.info("Player dropped from the match", {
		"peer": peer_id,
		"slot": slot,
		"why": reason,
		"left_in_match": _expected.size(),
	})
	if slot != 0:
		player_dropped.emit(slot)

	if !_expected.is_empty():
		return
	Log.info("Match over, everybody has left", "" if _setup == null else _setup.match_id)
	_finish_match()


func _slot_of(peer_id: int) -> int:
	if _setup == null:
		return 0
	for player in _setup.players:
		if player != null && player.network_id == peer_id:
			return player.slot
	return 0


func _finish_match() -> void:
	var finished_id: String = "" if _setup == null else _setup.match_id
	_waiting = false
	_in_match = false
	_setup = null
	_expected = PackedInt32Array()
	_ready_ids = PackedInt32Array()
	_reported_checksums.clear()
	_grace.clear()
	_deliberate.clear()
	_has_reference = false
	set_process(false)
	match_abandoned.emit(finished_id)

	# Back to listening. Without this the process would sit in a finished match
	# for ever, with no status line and no way to host the next one.
	if _match_scene_open:
		_match_scene_open = false
		MenuNavigation.to_server_scene(self, _server_entry_path)


# --- server: helpers ------------------------------------------------------

## The one field whose value differs per machine is which slot it plays, so the
## payload is built per peer rather than broadcast.
func _payload_for(source: MatchSetup, peer_id: int) -> Dictionary:
	var payload: Dictionary = source.to_dict()
	payload["local_slot"] = 0
	for player in source.players:
		if player != null && player.network_id == peer_id:
			payload["local_slot"] = player.slot
			break
	return payload


func _broadcast_readiness() -> void:
	for peer_id in _expected:
		receive_readiness.rpc_id(peer_id, _ready_ids)


## Read once, while the server's entry scene is still the current one: after
## the match scene opens, References answers with the match's own node and
## knows nothing about menus or boot paths.
func _read_server_settings() -> void:
	var menus: MenuConfig = References.menu_config
	if menus != null:
		_timeout_seconds = maxf(1.0, menus.load_timeout_seconds)
		_min_players = menus.min_players
		_grace_seconds = maxf(0.0, menus.disconnect_grace_seconds)

	# Assigned only when the configs are actually there, so the paths read
	# during the first match survive into the second one - by which point
	# References is answering for a match scene rather than for the menus.
	var boot: BootConfig = References.boot_config
	if boot != null:
		_server_match_path = boot.server_match_scene_path
		_server_entry_path = boot.server_scene_path
	if _server_match_path.is_empty():
		Log.err("MatchStart has no server match scene path, the server cannot load a match")


## 2.5: the same world, built twice from the same setup, must hash the same.
## A mismatch is not a crash - the match carries on and diverges - so it has to
## be said loudly here or it will be found by a player instead.
func _compare_checksums() -> void:
	if !_has_reference:
		return

	for peer_id in _reported_checksums.keys():
		var reported: int = int(_reported_checksums[peer_id])
		if reported == _reference_checksum:
			Log.info("Initial world agrees", {"peer": peer_id, "sum": reported})
		else:
			Log.err("Initial world DIFFERS from the server", {
				"peer": peer_id,
				"client": reported,
				"server": _reference_checksum,
			})
	_reported_checksums.clear()
