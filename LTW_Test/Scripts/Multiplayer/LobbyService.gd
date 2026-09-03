class_name LobbyService
extends Node

## The lobby registry, and the only thing that speaks about lobbies over the
## wire. **Registered as the autoload `Lobby`**, for the same reason
## NetworkService is `Net`: an autoload may not share a name with a global class.
##
## **One object, present on both machines, branching on who is the server**
## (D21). That is not tidiness, it is a requirement: Godot routes an `@rpc` by
## NODE PATH, so the receiving node must sit at the same path on the sender and
## the receiver. A `LobbyService` on the server and a `LobbyClient` on the client
## would be two different paths, and every call would silently go nowhere. One
## autoload makes the paths match by construction.
##
## Read it in three parts:
##   1. requests   - what a client calls; sent to the server
##   2. server     - what the server does with them; @rpc("any_peer")
##   3. pushes     - what the server tells clients; @rpc("authority")
##
## It also runs the start countdown (D24), which is a lobby rule rather than a
## match one: it locks the lobby, it is cancelled by anybody leaving, and if it
## runs out it hands a MatchSetup to `MatchStart` and stops being involved.
## Everything after that message is MatchStartService's.
##
## **The server trusts nothing a client sends.** A request carries no identity:
## the sender is `multiplayer.get_remote_sender_id()`, which the transport
## supplies and the client cannot forge. A display name is decoration, sanitised
## on arrival and never used as a key (1.6).

## Client side: the browser's list changed.
signal lobby_list_changed(lobbies: Array[LobbyInfo])
## Client side: the lobby WE are in changed, or null when we are in none.
signal current_lobby_changed(lobby: LobbyInfo)
## Client side: a request was refused, with something showable.
signal request_refused(reason: String)
## Client side: the lobby we were in went away, and why.
signal lobby_closed(reason: String)
## Client side: the start countdown is at this many whole seconds (D24).
signal countdown_changed(seconds_left: int)
## Client side: the countdown stopped without starting anything, and why.
signal countdown_cancelled(reason: String)

## Lobby ids are strings (see LobbyInfo), but ours are a plain counter. Prefixed
## so a stray id is obviously ours in a log rather than looking like a number.
const ID_PREFIX: String = "lobby-"

# --- server state, empty on a client --------------------------------------
var _lobbies: Dictionary = {}
## peer id -> lobby id, so a leaving peer can be found without scanning.
var _lobby_of_peer: Dictionary = {}
## peer id -> sanitised display name, learned when they connect.
var _names_of_peer: Dictionary = {}
var _next_lobby_number: int = 1
## lobby id -> seconds left on its start countdown. A lobby is in here exactly
## while it is counting down, so this doubles as the list to advance and the
## answer to "is that lobby counting down".
var _countdowns: Dictionary = {}
## lobby id -> the whole second last announced, so a push only goes out when
## the number on screen actually changes rather than fifty times a second.
var _announced: Dictionary = {}
var _next_match_number: int = 1
## match id -> the lobby that started it, so a match that ends can put its
## lobby back to something a browser can make sense of.
var _lobby_of_match: Dictionary = {}

# --- client state, empty on a server --------------------------------------
var _known_lobbies: Array[LobbyInfo] = []
var _current: LobbyInfo = null


func _ready() -> void:
	# Unaffected by the world being held still - a lobby is not part of any
	# match, and a countdown must not stop because somebody else's match is
	# waiting on a draft.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Only ever running while a countdown is, which on a client is never.
	set_process(false)
	MatchStart.match_abandoned.connect(_on_match_abandoned)
	Net.peer_left.connect(_on_peer_left)
	Net.connected_to_server.connect(_on_connected_to_server)
	Net.disconnected_from_server.connect(_on_lost_server)
	Net.connection_failed.connect(_on_connection_failed)


# --- client: what the screens call ----------------------------------------

## Everything the browser should currently list.
func lobbies() -> Array[LobbyInfo]:
	return _known_lobbies


## The lobby this client is in, or null.
func current() -> LobbyInfo:
	return _current


func is_in_lobby() -> bool:
	return _current != null


## Whether this client created the lobby it is in - the only one who may Start.
func is_host() -> bool:
	return _current != null && _current.host_id == Net.peer_id()


func create(lobby_name: String, max_players: int) -> void:
	if !_require_connection():
		return
	request_create.rpc_id(NetworkService.SERVER_PEER_ID, lobby_name, max_players)


func join(lobby_id: String) -> void:
	if !_require_connection():
		return
	request_join.rpc_id(NetworkService.SERVER_PEER_ID, lobby_id)


func leave() -> void:
	if !_require_connection() || _current == null:
		return
	request_leave.rpc_id(NetworkService.SERVER_PEER_ID)


## Asks for the start countdown (D24). The host's button, and the server
## checks that claim rather than believing it.
func start() -> void:
	if !_require_connection():
		return
	request_start.rpc_id(NetworkService.SERVER_PEER_ID)


## Stops a countdown the host started. The same button, because there is
## nothing else the host can usefully do for those five seconds.
func cancel_start() -> void:
	if !_require_connection():
		return
	request_cancel_start.rpc_id(NetworkService.SERVER_PEER_ID)


## Asks for the match rules to be changed (8.2). The host's panel, and the
## server checks that claim rather than believing it - exactly as it does for
## Start, and for the same reason: the panel is on the other machine.
##
## The whole settings block travels every time rather than one changed field.
## It is ten values on a cold path, and sending the lot means the server never
## has to merge two half-states and a client can never be looking at a mixture
## of what it asked for and what was allowed.
func set_settings(settings: MatchSettings) -> void:
	if !_require_connection() || settings == null:
		return
	request_settings.rpc_id(NetworkService.SERVER_PEER_ID, settings.to_dict())


## Tells the server this machine is now called something else.
##
## The same rpc arrival uses, because it is the same claim: a client states its
## name and the server sanitises it. Sending it again simply overwrites what is
## held against this peer id, which is what a rename IS - there is no separate
## state to keep in step.
func rename_player() -> void:
	if !_require_connection():
		return
	register_player.rpc_id(NetworkService.SERVER_PEER_ID, LobbyIdentity.display_name())


## Asks for this player's colour to be changed. Anybody may, for THEMSELVES -
## unlike the settings, which are the host's alone - because a colour is that
## player's own identity and nobody else's business.
##
## The server owns the answer: it refuses one somebody else already holds, and
## the dropdown draws what comes back rather than what was clicked. Two players
## reaching for the same colour in the same second is exactly the case that
## makes that worth the round trip.
func set_color(color_index: int) -> void:
	if !_require_connection():
		return
	request_color.rpc_id(NetworkService.SERVER_PEER_ID, color_index)


# --- server: requests arriving from clients -------------------------------

## Sent on connecting, and again whenever this player changes their name. The
## name is a courtesy, not a credential: it is sanitised here and the peer id
## remains the identity.
##
## A RENAME is the same message rather than one of its own, because the whole
## of it is "this is what I am called now" - so the second one overwrites the
## first and there is no second path to keep in step. What it costs is that a
## player already sitting in a lobby has to have that roster corrected too,
## which is the block below: their `MatchPlayer` carries the name every other
## client is drawing, and the browser rows carry the host's.
@rpc("any_peer", "reliable")
func register_player(display_name: String) -> void:
	if !multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	_names_of_peer[peer_id] = LobbyIdentity.sanitise(display_name)
	Log.info("Player registered", {"peer": peer_id, "name": _names_of_peer[peer_id]})
	_push_list_to(peer_id)

	var lobby: LobbyInfo = _lobbies.get(_lobby_of_peer.get(peer_id, ""), null) as LobbyInfo
	if lobby == null:
		return
	var player: MatchPlayer = lobby.member_for(peer_id)
	if player == null:
		return
	player.display_name = _names_of_peer[peer_id]
	_push_lobby(lobby)
	_broadcast_list()


@rpc("any_peer", "reliable")
func request_create(lobby_name: String, max_players: int) -> void:
	if !multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()

	if _lobby_of_peer.has(peer_id):
		_refuse(peer_id, "You are already in a lobby.")
		return

	var lobby: LobbyInfo = LobbyInfo.new()
	lobby.lobby_id = ID_PREFIX + str(_next_lobby_number)
	_next_lobby_number += 1
	lobby.lobby_name = LobbyIdentity.sanitise(lobby_name, _max_lobby_name_length())
	lobby.max_players = _clamp_size(max_players)
	lobby.host_id = peer_id
	# The defaults, which is a ranked match on whatever GameConfig says. The
	# host edits this copy; the file it came from is never touched.
	lobby.settings = MatchSettings.defaults(References.game_config)
	lobby.add_member(MatchPlayer.create(1, _name_of(peer_id), peer_id))

	_lobbies[lobby.lobby_id] = lobby
	_lobby_of_peer[peer_id] = lobby.lobby_id
	Log.info("Lobby created", {"id": lobby.lobby_id, "name": lobby.lobby_name, "host": peer_id})

	_push_lobby(lobby)
	_broadcast_list()


@rpc("any_peer", "reliable")
func request_join(lobby_id: String) -> void:
	if !multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()

	if _lobby_of_peer.has(peer_id):
		_refuse(peer_id, "You are already in a lobby.")
		return

	var lobby: LobbyInfo = _lobbies.get(lobby_id) as LobbyInfo
	# Every one of these can happen honestly, between the browser drawing a row
	# and the player clicking it.
	if lobby == null:
		_refuse(peer_id, "That lobby no longer exists.")
		return
	if lobby.is_in_progress:
		_refuse(peer_id, "That match has already started.")
		return
	# D24: the countdown exists to make the roster final, so it has to refuse
	# a joiner as flatly as a running match does.
	if lobby.is_starting:
		_refuse(peer_id, "That match is already starting.")
		return
	if lobby.is_full():
		_refuse(peer_id, "That lobby is full.")
		return

	lobby.add_member(MatchPlayer.create(0, _name_of(peer_id), peer_id))
	_lobby_of_peer[peer_id] = lobby.lobby_id
	Log.info("Lobby joined", {"id": lobby.lobby_id, "peer": peer_id})

	_push_lobby(lobby)
	_broadcast_list()


## One player changing their own colour. Refused rather than clamped when it is
## taken, because a clamp would silently hand them a colour they did not ask
## for and the dropdown would then disagree with the row beside it.
##
## The roster is pushed to everybody afterwards, not only to the asker: a
## colour is what the other players read each other by, so all of them have to
## see it move.
@rpc("any_peer", "reliable")
func request_color(color_index: int) -> void:
	if !multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()

	var lobby: LobbyInfo = _lobbies.get(_lobby_of_peer.get(peer_id, ""), null) as LobbyInfo
	if lobby == null:
		_refuse(peer_id, "You are not in a lobby.")
		return
	# The countdown makes the roster final (D24), and a colour is part of it.
	if lobby.is_starting || lobby.is_in_progress:
		_refuse(peer_id, "The match is already starting.")
		return

	var presentation: PresentationConfig = References.presentation_config
	var count: int = 0 if presentation == null else presentation.color_count()
	if color_index < 0 || color_index >= count:
		_refuse(peer_id, "That is not a color.")
		return
	if lobby.is_color_taken(color_index, peer_id):
		_refuse(peer_id, "Somebody already has that color.")
		return

	var player: MatchPlayer = lobby.member_for(peer_id)
	if player == null:
		return
	player.color_index = color_index
	Log.info("Lobby color chosen", {
		"id": lobby.lobby_id, "peer": peer_id, "color": color_index,
	})
	_push_lobby(lobby)


@rpc("any_peer", "reliable")
func request_leave() -> void:
	if !multiplayer.is_server():
		return
	_remove_from_lobby(multiplayer.get_remote_sender_id(), "You left the lobby.")


## Begins the countdown, having checked every claim the request makes by
## implication: that the sender is in a lobby, that they host it, that it is
## not already starting or running, and that there are enough players in it.
##
## The host's own screen has already disabled the button in most of these
## cases. That is a courtesy to the player, not a check - the button is on the
## other machine.
@rpc("any_peer", "reliable")
func request_start() -> void:
	if !multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var lobby: LobbyInfo = _lobby_hosted_by(peer_id)
	if lobby == null:
		_refuse(peer_id, "Only the host can start the match.")
		return
	if lobby.is_in_progress:
		_refuse(peer_id, "That match has already started.")
		return
	if lobby.is_starting:
		_refuse(peer_id, "That match is already starting.")
		return

	var needed: int = _min_players()
	if lobby.player_count() < needed:
		_refuse(peer_id, "%d players are needed to start." % needed)
		return
	# D19: one process runs the lobby and the matches, so it can run one match.
	# Splitting them is an address change (D16), and until then this is a
	# sentence rather than a second match quietly overwriting the first.
	if MatchStart.is_busy():
		_refuse(peer_id, "The server is already running a match.")
		return

	_begin_countdown(lobby)


## The host changing the rules. Refused once the lobby is locked, because the
## roster and the rules become final at the same moment: a countdown that could
## still change what everybody is about to play is not a countdown to anything.
@rpc("any_peer", "reliable")
func request_settings(payload: Dictionary) -> void:
	if !multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var lobby: LobbyInfo = _lobby_hosted_by(peer_id)
	if lobby == null:
		_refuse(peer_id, "Only the host can change the match settings.")
		return
	if lobby.is_in_progress || lobby.is_starting:
		_refuse(peer_id, "The match is already starting.")
		return

	var settings: MatchSettings = MatchSettings.from_dict(payload)
	# Nothing a client states is taken as read: a ranked match is put back onto
	# the defaults here, whatever arrived, and every number is clamped.
	settings.sanitise(References.game_config, References.menu_config)
	lobby.settings = settings
	Log.info("Lobby settings changed", {
		"id": lobby.lobby_id, "settings": settings.describe(),
	})

	# Pushed to the room so every player sees the change, and broadcast to the
	# browser because the list carries the settings too - a lobby row could
	# say "ranked" one day without anything else moving.
	_push_lobby(lobby)
	_broadcast_list()


@rpc("any_peer", "reliable")
func request_cancel_start() -> void:
	if !multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var lobby: LobbyInfo = _lobby_hosted_by(peer_id)
	if lobby == null || !_countdowns.has(lobby.lobby_id):
		_refuse(peer_id, "There is no countdown to cancel.")
		return
	_cancel_countdown(lobby, "The host cancelled the start.")


# --- server: the start countdown (D24) ------------------------------------

## Wall clock, not simulation, which is why this is _process and not
## _physics_process: a lobby has no match and therefore no simulation tick to
## ride on. The same reasoning as NetworkService's connect timeout.
##
## Only ever running while at least one lobby is counting down.
func _process(delta: float) -> void:
	if _countdowns.is_empty():
		set_process(false)
		return
	# Over a copy of the keys: firing or cancelling erases from the dictionary
	# we would otherwise be iterating.
	for lobby_id in _countdowns.keys():
		_advance_countdown(str(lobby_id), delta)


func _begin_countdown(lobby: LobbyInfo) -> void:
	var seconds: float = _countdown_seconds()
	lobby.is_starting = true
	_countdowns[lobby.lobby_id] = seconds
	_announced[lobby.lobby_id] = -1
	set_process(true)
	Log.info("Start countdown", {"lobby": lobby.lobby_id, "seconds": seconds})

	# The roster screen learns the lobby is locked, the browser learns the row
	# now reads "Starting...", and the room gets its first number this frame
	# rather than up to a second later.
	_push_lobby(lobby)
	_broadcast_list()
	_announce_countdown(lobby, ceili(seconds))


func _advance_countdown(lobby_id: String, delta: float) -> void:
	# The keys were a snapshot taken before the first lobby was advanced, so
	# this one may already have been fired or cancelled by then.
	if !_countdowns.has(lobby_id):
		return

	var lobby: LobbyInfo = _lobbies.get(lobby_id) as LobbyInfo
	if lobby == null:
		# The lobby went away under it. Nothing to announce to nobody.
		_countdowns.erase(lobby_id)
		_announced.erase(lobby_id)
		return

	var left: float = float(_countdowns[lobby_id]) - delta
	if left <= 0.0:
		_fire_countdown(lobby)
		return

	_countdowns[lobby_id] = left
	var whole: int = ceili(left)
	if int(_announced[lobby_id]) != whole:
		_announce_countdown(lobby, whole)


## The countdown ran out. From here it is the start handshake's problem.
func _fire_countdown(lobby: LobbyInfo) -> void:
	_clear_countdown(lobby)

	# Re-checked rather than assumed: five seconds is long enough for another
	# lobby's countdown to have fired first.
	if MatchStart.is_busy():
		_announce_countdown_cancelled(lobby, "The server is already running a match.")
		_push_lobby(lobby)
		_broadcast_list()
		return

	var setup: MatchSetup = lobby.to_match_setup(_next_match_id(), randi())
	lobby.is_in_progress = true
	_lobby_of_match[setup.match_id] = lobby.lobby_id
	Log.info("Match starting", {
		"lobby": lobby.lobby_id,
		"match": setup.match_id,
		"players": setup.player_count(),
		"seed": setup.rng_seed,
	})

	_push_lobby(lobby)
	_broadcast_list()
	MatchStart.begin(setup)


## Puts the lobby straight back to ordinary and open. A cancelled countdown is
## not a state to recover from - it never happened, and the host may press
## Start again immediately.
func _cancel_countdown(lobby: LobbyInfo, reason: String) -> void:
	if !_countdowns.has(lobby.lobby_id):
		return
	_clear_countdown(lobby)
	Log.info("Start countdown cancelled", {"lobby": lobby.lobby_id, "reason": reason})

	_announce_countdown_cancelled(lobby, reason)
	_push_lobby(lobby)
	_broadcast_list()


func _clear_countdown(lobby: LobbyInfo) -> void:
	_countdowns.erase(lobby.lobby_id)
	_announced.erase(lobby.lobby_id)
	lobby.is_starting = false


## Every player in the lobby sees the same number, because it is this one
## (D24). Nobody counts on their own clock.
func _announce_countdown(lobby: LobbyInfo, seconds_left: int) -> void:
	_announced[lobby.lobby_id] = seconds_left
	for player in lobby.members:
		if player != null:
			receive_countdown.rpc_id(player.network_id, seconds_left, "")


func _announce_countdown_cancelled(lobby: LobbyInfo, reason: String) -> void:
	for player in lobby.members:
		if player != null:
			receive_countdown.rpc_id(player.network_id, -1, reason)


func _next_match_id() -> String:
	var id: String = "match-%d" % _next_match_number
	_next_match_number += 1
	return id


func _lobby_hosted_by(peer_id: int) -> LobbyInfo:
	if !_lobby_of_peer.has(peer_id):
		return null
	var lobby: LobbyInfo = _lobbies.get(_lobby_of_peer[peer_id]) as LobbyInfo
	if lobby == null || lobby.host_id != peer_id:
		return null
	return lobby


# --- server: bookkeeping --------------------------------------------------

## A match that never started, or that everybody has left, leaves its lobby
## marked "In progress" with nothing running in it. This is the only way that
## flag is ever cleared - a lobby whose match ended normally has usually lost
## its host by then and closed itself.
func _on_match_abandoned(match_id: String) -> void:
	if !_lobby_of_match.has(match_id):
		return
	var lobby: LobbyInfo = _lobbies.get(_lobby_of_match[match_id]) as LobbyInfo
	_lobby_of_match.erase(match_id)
	if lobby == null:
		return

	lobby.is_in_progress = false
	Log.info("Lobby is open again", {"id": lobby.lobby_id, "match": match_id})
	_push_lobby(lobby)
	_broadcast_list()


## A peer that vanished is a peer that left, whether it meant to or not (1.9).
func _on_peer_left(peer_id: int) -> void:
	if !multiplayer.is_server():
		return
	_names_of_peer.erase(peer_id)
	_remove_from_lobby(peer_id, "")


## Takes a peer out of whatever lobby it is in.
##
## **The host leaving closes the lobby** (D23): everyone else is sent back to
## the browser with a reason. The alternative was promoting somebody, and the
## user chose the Warcraft III rule.
func _remove_from_lobby(peer_id: int, own_reason: String) -> void:
	if !_lobby_of_peer.has(peer_id):
		return

	var lobby_id: String = _lobby_of_peer[peer_id]
	_lobby_of_peer.erase(peer_id)
	var lobby: LobbyInfo = _lobbies.get(lobby_id) as LobbyInfo
	if lobby == null:
		return

	var was_host: bool = lobby.host_id == peer_id
	var leaver: MatchPlayer = lobby.member_for(peer_id)
	var leaver_name: String = "A player" if leaver == null else leaver.display_name
	lobby.remove_member(peer_id)

	if !own_reason.is_empty():
		receive_closed.rpc_id(peer_id, own_reason)

	if was_host || lobby.members.is_empty():
		_close_lobby(lobby, "The host left the lobby.")
		_broadcast_list()
		return

	# D24: ANY player leaving cancels the countdown, a joiner exactly as much
	# as the host. That is what makes the roster final by the time the
	# handshake starts. _cancel_countdown pushes and broadcasts for itself.
	if _countdowns.has(lobby.lobby_id):
		_cancel_countdown(lobby, "%s left the lobby." % leaver_name)
		return

	_push_lobby(lobby)
	_broadcast_list()


func _close_lobby(lobby: LobbyInfo, reason: String) -> void:
	# Silently: everyone in it is about to be told the lobby is gone, which is
	# a bigger piece of news than the countdown that was running in it.
	_clear_countdown(lobby)

	for player in lobby.members:
		if player == null:
			continue
		_lobby_of_peer.erase(player.network_id)
		receive_closed.rpc_id(player.network_id, reason)

	_lobbies.erase(lobby.lobby_id)
	Log.info("Lobby closed", {"id": lobby.lobby_id, "reason": reason})


# --- server: pushes out ---------------------------------------------------

## The list goes to everyone. It is a handful of small dictionaries on a cold
## path, so filtering it per peer would cost more thought than it saves.
func _broadcast_list() -> void:
	receive_list.rpc(_list_payload())


func _push_list_to(peer_id: int) -> void:
	receive_list.rpc_id(peer_id, _list_payload())


func _push_lobby(lobby: LobbyInfo) -> void:
	var payload: Dictionary = lobby.to_dict()
	for player in lobby.members:
		if player != null:
			receive_lobby.rpc_id(player.network_id, payload)


func _list_payload() -> Array:
	var payload: Array = []
	for lobby in _lobbies.values():
		payload.append((lobby as LobbyInfo).to_dict())
	return payload


func _refuse(peer_id: int, reason: String) -> void:
	Log.info("Lobby request refused", {"peer": peer_id, "reason": reason})
	receive_refusal.rpc_id(peer_id, reason)


# --- client: pushes arriving ----------------------------------------------

@rpc("authority", "reliable")
func receive_list(payload: Array) -> void:
	_known_lobbies.clear()
	for entry in payload:
		if entry is Dictionary:
			_known_lobbies.append(LobbyInfo.from_dict(entry as Dictionary))
	Log.info("Lobby list received", {"lobbies": _known_lobbies.size()})
	lobby_list_changed.emit(_known_lobbies)


@rpc("authority", "reliable")
func receive_lobby(payload: Dictionary) -> void:
	_current = LobbyInfo.from_dict(payload)
	Log.info("In lobby", {
		"id": _current.lobby_id,
		"name": _current.lobby_name,
		"players": _current.player_count(),
		"host": is_host(),
	})
	current_lobby_changed.emit(_current)


@rpc("authority", "reliable")
func receive_closed(reason: String) -> void:
	_current = null
	Log.info("Out of the lobby", reason)
	# Reason FIRST. The screen listening to current_lobby_changed reacts by
	# changing scene, so anything it needs to carry along has to already be in
	# hand by the time that fires.
	lobby_closed.emit(reason)
	current_lobby_changed.emit(null)


## One message says everything there is to say about the countdown: how many
## whole seconds are left, or - with a negative count - that there are none
## left because it was stopped, and why. A negative sentinel rather than a
## second rpc, for the same reason LobbyInfo.ping_ms uses one: there is a
## single fact here, not two events.
@rpc("authority", "reliable")
func receive_countdown(seconds_left: int, reason: String) -> void:
	if seconds_left < 0:
		Log.info("Start countdown cancelled", reason)
		countdown_cancelled.emit(reason)
		return
	countdown_changed.emit(seconds_left)


@rpc("authority", "reliable")
func receive_refusal(reason: String) -> void:
	Log.warn("Lobby request refused by the server", reason)
	request_refused.emit(reason)


# --- shared helpers -------------------------------------------------------

func _on_connected_to_server() -> void:
	# The server learns our name the moment we arrive, so it never has to ask
	# and no later request has to carry it.
	register_player.rpc_id(NetworkService.SERVER_PEER_ID, LobbyIdentity.display_name())


func _on_lost_server() -> void:
	_forget_everything("Lost connection to the server.")


func _on_connection_failed(result: NetworkService.Result) -> void:
	_forget_everything(NetworkService.describe(result))


## Losing the connection means losing every claim about lobbies, including the
## one we thought we were in. Anything else leaves a stale roster on screen that
## looks live.
##
## Being dropped is told exactly like being thrown out - same signals, same
## order, reason before the change of lobby - so a screen sitting in a lobby
## needs no separate handling for the server going away than for the host
## leaving. It is one case, not two.
func _forget_everything(reason: String) -> void:
	_known_lobbies.clear()
	var had_lobby: bool = _current != null
	_current = null
	lobby_list_changed.emit(_known_lobbies)
	if had_lobby:
		lobby_closed.emit(reason)
		current_lobby_changed.emit(null)


func _require_connection() -> bool:
	if Net.is_online():
		return true
	request_refused.emit("Not connected to a server.")
	return false


func _name_of(peer_id: int) -> String:
	if _names_of_peer.has(peer_id):
		return str(_names_of_peer[peer_id])
	# A peer that never registered still gets a name rather than a blank row.
	return "Player %d" % peer_id


func _clamp_size(requested: int) -> int:
	var config: MenuConfig = References.menu_config
	if config == null:
		return maxi(2, requested)
	return clampi(requested, config.min_players, config.max_players)


func _min_players() -> int:
	var config: MenuConfig = References.menu_config
	if config == null:
		return 2
	return config.min_players


func _countdown_seconds() -> float:
	var config: MenuConfig = References.menu_config
	if config == null:
		return 5.0
	return maxf(1.0, config.start_countdown_seconds)


func _max_lobby_name_length() -> int:
	var config: MenuConfig = References.menu_config
	if config == null:
		return LobbyIdentity.MAX_NAME_LENGTH
	return config.max_lobby_name_length
