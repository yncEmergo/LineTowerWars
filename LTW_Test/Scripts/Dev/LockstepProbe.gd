extends Node

## THROWAWAY. Drives a real two-peer networked match headlessly, so the lockstep
## cutover can be proven rather than hoped for.
##
## **Delete this and its scene when the cutover is settled.** `Scripts/Dev` is
## scaffolding (`CLAUDE.md`).
##
## Nothing else in this project can answer the question it answers. A single
## process cannot test lockstep - the whole model is about two machines agreeing
## - and the editor cannot be made to do the same thing twice. So: one server,
## one client, both headless, both driven from a script that reads its role off
## the command line.
##
##     .\Tools\run_server.ps1                     # or godot --headless -- --server
##     godot --path . --headless -- --probe client
##
## The client connects, makes a lobby, starts the match, plays for a while
## issuing orders, and reports what happened. What is being watched for:
##
##   TURNS RUNNING    both peers advance turns and neither stalls forever
##   ORDERS APPLIED   an order given on one machine takes effect on both
##   NO DESYNC        the per-turn checksums agree for the whole run
##
## It also drives the LOADING GATE, which needs more than two machines:
##
##     --players <n>         the host waits for n members before pressing Start
##     --quit-before-ready   die with no goodbye, before reporting loaded
##     --quit-after-ready    die with no goodbye, once the server has counted us
##     --ready-delay <s>     report loaded s seconds late, without going quiet
##
## And the MATCH-PROCESS handoff (D44), with `--probe match`, which skips the
## lobby entirely: it reads a hand-written match file, dials the match port with
## its seat's token and plays.
##
##     --match-port <p>      the port the match process is listening on
##     --match-file <f>      a COPY of the match file, kept for the probes
##     --slot <n>            which announced seat this probe claims
##     --redial-after <s>    drop the link with no goodbye, then claim again
##     --dead-port-first     dial a closed port once, so a retry must happen
##     --bad-token           present sixteen bytes that are nobody's seat
##     --steal-slot <n>      present ANOTHER seat's token, while its owner holds it
##     --late-dial <s>       wait s seconds before dialling at all, so the go
##                           signal has already gone out
##
## Does NOTHING when --probe is absent, so the editor, the server and every
## other run are unaffected by its presence.

const ROLE_ARGUMENT: String = "--probe"

## Long enough for a lobby to exist and the server to notice it.
const SETTLE_SECONDS: float = 2.0
## How long to play before reporting, overridable with --play <seconds> so a
## test that has to outlast the disconnect grace can say so.
const PLAY_SECONDS: float = 25.0

## How long a deliberate hitch blocks the main thread for, in milliseconds.
## Sized on playtest 1, where one machine took 650-900 ms the first time each
## kind of content was spawned.
const HITCH_MSEC: int = 900

var _role: String = ""
var _elapsed: float = 0.0
var _started: bool = false
var _requested: bool = false
var _seat_closed: bool = false
var _in_match: bool = false
var _turns: int = 0
var _stalls: int = 0
var _desyncs: int = 0
var _orders: int = 0
var _last_turn: int = -1
var _sent: int = 0
var _dialled: bool = false
var _browsing: bool = false
var _joining: bool = false
var _corrupted: bool = false
var _wedged: bool = false
var _hitches: int = 0
var _drops: int = 0
var _spoofs: int = 0
var _driven_after_giveup: int = 0
## The PAUSE scenario's readings. The turn each peer saw the world stop on and
## the turn it saw it move again, which is the whole test: two peers reporting
## the same pair agree, and two reporting different ones have desynced their
## clocks whether or not a checksum has noticed yet.
var _pause_turn: int = -1
var _resume_turn: int = -1
var _pauses: int = 0
var _was_paused: bool = false
var _paused_asked: bool = false
var _resume_asked: bool = false
## The LOADING GATE scenario's readings. Whether the server ever counted this
## machine as loaded, and whether a held-back report was finally made - the two
## positive controls for a run that is about to kill peers around the gate and
## claim the survivors were handled correctly.
var _self_ready: bool = false
var _reported_late: bool = false
var _quit_fired: bool = false
var _real_match_id: String = ""
var _ready_delay_left: float = -1.0
## The MATCH-PROCESS scenario's readings (D44). How many times this probe was
## admitted to a seat, what the go signal says its `network_id` is, and how the
## move ended - the three things that tell a handoff that worked from one that
## was never exercised.
var _claims: int = 0
var _go_network_id: int = 0
var _move_reason: String = ""
var _match_started: bool = false
var _redial_left: float = -1.0
var _redialled: bool = false


func _ready() -> void:
	_role = _read_role()
	if _role.is_empty():
		queue_free()
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	Log.warn("LockstepProbe starting", {"role": _role})
	if "--session-log" in OS.get_cmdline_user_args():
		SessionLog.enable(true)

	Lockstep.turn_ready.connect(_on_turn_ready)
	Lockstep.turn_stalled.connect(_on_turn_stalled)
	MatchStart.desync_detected.connect(_on_desync)
	# **The positive control for a player DROP, and its absence is what let a
	# critical bug through.** A wedged peer leaving looks identical from the
	# survivor's side whether or not the survivor actually processed it: the
	# match carries on either way. Only this signal says the leaver's maze was
	# really erased.
	MatchStart.player_dropped.connect(_on_player_dropped)
	Lobby.current_lobby_changed.connect(_on_lobby_changed)
	Lobby.request_refused.connect(_on_refused)
	MatchStart.match_starting.connect(_on_match_starting)
	MatchStart.readiness_changed.connect(_on_readiness_changed)

	Net.connected_to_server.connect(_on_connected)
	Net.connection_failed.connect(_on_connect_failed)
	Net.move_ended.connect(_on_move_ended)
	MatchStart.match_cancelled.connect(_on_cancelled)
	# NOT joined here. References is a NODE in a scene, so it holds nothing at
	# all while an autoload's _ready runs - Net.join() this early is refused
	# with "No network configuration" and the probe never leaves the ground.
	# Waited for in _process instead.


func _play_seconds() -> float:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == "--play" && index + 1 < args.size():
			return maxf(1.0, float(args[index + 1]))
	return PLAY_SECONDS


func _read_role() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == ROLE_ARGUMENT && index + 1 < args.size():
			return args[index + 1]
	return ""


# --- getting into a match --------------------------------------------------

func _on_connected() -> void:
	# The MATCH role's connection is to a match process, which has no lobby and
	# whose `Lobby` endpoints are inert. Registering there would be a packet sent
	# to be ignored, and `create` would look like a bug in the log.
	if _role == "match":
		return
	Log.warn("PROBE connected, registering")
	Lobby.register_player("Probe " + _role)
	# The host makes the lobby. The joiner waits for it to appear in the list,
	# because a lobby that does not exist yet cannot be joined and the two
	# processes are started a second apart at best.
	if _role == "host":
		Lobby.create("Probe match", _players_wanted())
	else:
		Lobby.lobby_list_changed.connect(_on_lobby_list)


## How many members the HOST waits for before pressing Start, from `--players`.
## Two is what every scenario before the loading-gate proof needed, and it is
## also the smallest a match may be (`min_players`).
func _players_wanted() -> int:
	return maxi(2, _int_argument("--players", 2))


func _on_connect_failed(_result: NetworkService.Result) -> void:
	Log.err("PROBE could not reach the server")
	_finish()


## The joiner takes the first lobby it sees that is not full and not already
## playing.
func _on_lobby_list(lobbies: Array[LobbyInfo]) -> void:
	# **The `browse` role connects and then does NOTHING, which is the whole
	# point of it.** Pressing Multiplayer connects a peer to the server (D20)
	# and `SceneMultiplayer.server_relay` announces them to everybody already in
	# a match - so this is the third machine that is NOT in the match, and it is
	# the topology that has broken this project twice: once when
	# `_expected_peers` read the transport's peer list and froze every running
	# match, and once when a bare `rpc()` sent the whole turn stream to it.
	#
	# The sealed seal is a NEW broadcast, so it meets that trap again. Nothing
	# else in any obvious test setup contains this case.
	if _role == "browse" || _role == "spoof":
		return
	if Lobby.is_in_lobby() || _joining:
		return
	for lobby: LobbyInfo in lobbies:
		if lobby == null || lobby.is_in_progress:
			continue
		_joining = true
		Log.warn("PROBE joining", {"id": lobby.lobby_id})
		Lobby.join(lobby.lobby_id)
		return


func _on_lobby_changed(lobby: LobbyInfo) -> void:
	if lobby == null:
		return
	Log.warn("PROBE in lobby", {
		"id": lobby.lobby_id, "players": lobby.player_count(), "host": Lobby.is_host(),
		"max": lobby.max_players, "seats": lobby.seat_count, "closed": lobby.closed_seats,
	})
	# `--close-seat <n>`: the host closes that seat once, as soon as it hosts.
	# The positive control for seat closing is the "max" above dropping by one
	# on EVERY machine in the lobby, not just the host's.
	var close_seat: int = _int_argument("--close-seat", 0)
	if close_seat > 0 && Lobby.is_host() && !_seat_closed:
		_seat_closed = true
		Log.warn("PROBE closing a seat", {"seat": close_seat})
		Lobby.set_seat_state(close_seat, LobbyInfo.SeatState.CLOSED)
	# Only the host may start, and only once the second player is really in -
	# the server refuses a one player match, which is the rule doing its job.
	if Lobby.is_host() && !_requested && lobby.player_count() >= _players_wanted():
		_requested = true
		Log.warn("PROBE starting the match")
		Lobby.start()


func _on_refused(reason: String) -> void:
	Log.err("PROBE refused: " + reason)


## What the GO SIGNAL says this machine's seat is.
##
## **The positive control for the re-key.** A match process gives each seat the
## id of the connection that actually claimed it, so `go_id` equal to `own_id` is
## what proves the roster the relay stamps orders against is the one this socket
## answers to. Different ids mean every order this player sends is about to be
## stamped with somebody else's slot - which no checksum would catch until the
## two worlds had already diverged.
##
## Read off the roster rather than taken from a signal, because the go signal has
## no client-side signal of its own: it opens the match scene and that is all.
func _note_go_roster() -> void:
	var setup: MatchSetup = MatchStart.setup()
	if setup == null || _go_network_id != 0:
		return
	var mine: MatchPlayer = setup.player_for(setup.local_slot)
	if mine != null:
		_go_network_id = mine.network_id


func _on_cancelled(reason: String) -> void:
	_move_reason = reason
	Log.warn("PROBE match cancelled", {"why": reason})


func _on_match_starting(setup: MatchSetup) -> void:
	Log.warn("PROBE match starting")
	_in_match = true

	# **Out with no goodbye, BEFORE this machine has reported loaded.** The gate
	# must keep waiting for it through D26's hold, then start without it and
	# spawn it no area (D15).
	if "--quit-before-ready" in OS.get_cmdline_user_args():
		_hard_exit("before reporting ready")
		return

	var delay: float = float(_int_argument("--ready-delay", 0))
	if delay > 0.0 && setup != null:
		_real_match_id = setup.match_id
		# See _advance_ready_delay. Blanking the id here, before MatchLoading
		# exists, is what makes its automatic report a no-op on the server.
		setup.match_id = "probe-not-loaded-yet"
		_ready_delay_left = delay
		Log.warn("PROBE holding its readiness back", {"seconds": delay})


## The server's own record of who has loaded, echoed to every client. A probe
## watching for ITSELF in it knows its report actually arrived, which is a far
## better moment to die at than "we sent one and hoped".
func _on_readiness_changed(ready_ids: PackedInt32Array) -> void:
	if _self_ready:
		return
	# **A match process sends SLOTS and a lobby process sends PEER IDS**, so what
	# to look for here depends on which kind of server answered. Looking for the
	# wrong one does not fail loudly: it simply never matches, and `self_ready`
	# reads false for a probe the server counted perfectly well - a positive
	# control that quietly reports the opposite of the truth.
	var setup: MatchSetup = MatchStart.setup()
	var mine: int = multiplayer.get_unique_id()
	if _role == "match":
		mine = 0 if setup == null else setup.local_slot
	if mine == 0 || !(mine in ready_ids):
		return
	_self_ready = true
	Log.warn("PROBE counted ready by the server")
	# **Out with no goodbye, AFTER being counted.** This is the half of the
	# loading-gate bug that reads as a pass: the server had a ready flag for a
	# machine that no longer exists, and the count let the start through while
	# somebody else was still loading.
	if "--quit-after-ready" in OS.get_cmdline_user_args():
		_hard_exit("after being counted ready")


## Dies the way a crash does, with nothing said on the wire, so the server
## learns of it from ENet rather than from `report_leaving`. `get_tree().quit()`
## takes the polite road through `Net`, which is a different test entirely.
func _hard_exit(why: String) -> void:
	if _quit_fired:
		return
	_quit_fired = true
	Log.warn("PROBE hard-exiting", {"why": why, "role": _role})
	OS.kill(OS.get_process_id())


# --- the match-process role (D44) ------------------------------------------

## Stands in for the LOBBY's announce, from a file, and then moves.
##
## The real road is: the lobby announces a port and this seat's token, the client
## starts loading and moves at the same time. There is no lobby in this test, so
## the announce is made locally out of the match file - which is exactly the
## dictionary the lobby would have sent - and everything after it is the shipping
## code doing its own job.
##
## **The probes read a COPY of the match file.** The match process deletes its
## own the moment it has read it, so that a token does not sit on disk; a probe
## started afterwards would find nothing.
func _drive_match_role(delta: float) -> void:
	if !_match_started:
		# `--late-dial <s>` waits past the go signal, so what is under test is a
		# dial that arrives when the door is already shut.
		var wait: float = maxf(SETTLE_SECONDS, float(_int_argument("--late-dial", 0)))
		if _elapsed < wait:
			return
		_match_started = true
		_announce_locally()
		return

	_advance_redial(delta)
	# The match role holds its readiness back the same way the lobby roles do.
	# It is not reached by the shared call in `_process`, which the match branch
	# returns before.
	_advance_ready_delay(delta)
	if !_in_match:
		if _elapsed > SETTLE_SECONDS * 25.0:
			Log.err("PROBE never got into the match")
			_finish()
		return

	if !_started:
		_started = true
		_elapsed = 0.0
		Log.warn("PROBE playing", {"own_id": multiplayer.get_unique_id()})
		return

	# Asked every frame until it answers. `_in_match` is set by the ANNOUNCE, so
	# reading the roster at that moment reads the announced setup, whose ids the
	# match process deliberately cleared - which is a zero that looks exactly
	# like a re-key that never happened.
	_note_go_roster()
	_drive()
	if _elapsed >= _play_seconds():
		_finish()


## Plays the announce this probe would have been sent, out of the match file.
func _announce_locally() -> void:
	var data: Dictionary = MatchHandoff.read_match_file(_text_argument("--match-file", ""))
	if data.is_empty():
		Log.err("PROBE could not read its match file")
		_finish()
		return
	var slot: int = _int_argument("--slot", 0)
	var tokens: Dictionary = MatchHandoff.tokens_from(data)
	if !tokens.has(slot):
		Log.err("PROBE has no token for its slot", {"slot": slot})
		_finish()
		return

	var payload: Dictionary = data.get("setup", {})
	payload["local_slot"] = slot
	# **The port and this seat's token ride the announce**, exactly as the lobby
	# will send them in P3. Everything after this is shipping code: MatchStart
	# starts the move itself, keeps the token for a re-claim, and reports ready
	# when both the load and the move are done.
	payload["match_port"] = _int_argument("--match-port", 0)
	payload["match_token"] = MatchHandoff.token_to_hex(_move_token(tokens, slot))
	MatchStart.receive_match_starting(payload)
	Log.warn("PROBE announced to itself", {"slot": slot, "match": payload.get("match_id", "")})


## Which token this probe presents, which is its own unless a flag says
## otherwise.
func _move_token(tokens: Dictionary, slot: int) -> PackedByteArray:
	# `--bad-token`: sixteen bytes of the right SHAPE that are nobody's seat, so
	# the refusal under test is WRONG_TOKEN rather than a length check.
	if "--bad-token" in OS.get_cmdline_user_args():
		var forged: PackedByteArray = PackedByteArray()
		for index: int in range(MatchHandoff.TOKEN_BYTES):
			forged.append((index * 7 + 3) % 256)
		return forged
	# `--steal-slot <n>`: another seat's real token, presented while its owner is
	# sitting in it. The answer must be SEAT_HELD, and the owner must keep the
	# seat - never the eviction that "last claim wins" would give.
	var steal: int = _int_argument("--steal-slot", 0)
	if steal > 0 && tokens.has(steal):
		Log.warn("PROBE presenting another seat's token", {"seat": steal})
		return tokens[steal]
	return tokens.get(slot, PackedByteArray())


## `--redial-after <s>`: closes the link with no goodbye and claims the same seat
## again, which is the owner's re-claim rule (D26) exercised from the client end.
##
## `claims=2` in the result, together with the go signal carrying a DIFFERENT
## `network_id` from the first admission, is what proves the seat was really
## re-keyed rather than the first claim simply never having been lost.
func _advance_redial(delta: float) -> void:
	if _redial_left <= 0.0:
		return
	_redial_left -= delta
	if _redial_left > 0.0:
		return
	_redial_left = -1.0
	# **Closed with no goodbye**, so the server learns of it from ENet rather
	# than from `report_leaving` - a deliberate leave makes the seat `left` at
	# once, which is the opposite of the case under test. MatchStart notices the
	# connection go and claims the seat again with the token it kept.
	Log.warn("PROBE dropping its link, the client should claim again")
	Net.leave()


func _on_move_ended(ok: bool, reason: String) -> void:
	_move_reason = reason
	if !ok:
		Log.warn("PROBE move failed", {"why": reason})
		return
	_claims += 1
	Log.warn("PROBE admitted to the match", {"claims": _claims, "id": multiplayer.get_unique_id()})
	var after: float = float(_int_argument("--redial-after", 0))
	if after > 0.0 && _claims == 1:
		_redial_left = after


func _text_argument(flag: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == flag && index + 1 < args.size():
			return args[index + 1]
	return fallback


## `--ready-delay <s>`: report loaded that many seconds late, WITHOUT going
## quiet.
##
## MatchLoading reports the moment its warm-up finishes and a probe cannot stop
## it, so the setup's match id is blanked first: `report_ready` is refused on
## the server for an id that is not the match's. The id goes back, with a report
## of our own, once the delay has run. The go signal rebuilds the whole setup
## from its payload, so none of this survives into the match.
##
## **Blocking the main thread instead would be a different test.** A peer that
## stops polling stops answering ENet too, so it reads as a SILENT player and
## gets D26's hold - where what is wanted here is a player who is merely still
## LOADING, and whom the gate has to keep waiting for.
func _advance_ready_delay(delta: float) -> void:
	if _ready_delay_left <= 0.0 || _reported_late:
		return
	_ready_delay_left -= delta
	if _ready_delay_left > 0.0:
		return
	var setup: MatchSetup = MatchStart.setup()
	if setup == null:
		Log.err("PROBE had no setup left to report its late load against")
		_ready_delay_left = -1.0
		return
	_reported_late = true
	setup.match_id = _real_match_id
	MatchStart.report_loaded()
	Log.warn("PROBE reporting loaded late", {"match": _real_match_id})


# --- watching it ------------------------------------------------------------

func _on_turn_ready(turn: int, commands: Array) -> void:
	_turns += 1
	_last_turn = turn
	_orders += commands.size()
	# On the turn boundary rather than on a frame, so the numbers two peers
	# report can be compared at all. See _watch_pause.
	_watch_pause(turn)


func _on_turn_stalled(turn: int, missing: PackedInt32Array) -> void:
	_stalls += 1
	if _stalls <= 3:
		Log.warn("PROBE stall", {"turn": turn, "missing": missing})


func _on_player_dropped(slot: int) -> void:
	_drops += 1
	Log.warn("PROBE saw a player dropped", {"slot": slot})


func _on_desync(tick: int, _detail: String) -> void:
	_desyncs += 1
	Log.err("PROBE DESYNC", {"tick": tick})


func _process(delta: float) -> void:
	_elapsed += delta

	# Walk the menus the way a player does, and for a reason worth knowing: the
	# MAIN MENU's References node wires only the menu config, so
	# References.network_config is null there and Net.join() is refused. The
	# network config lives on the LOBBY BROWSER's References - which is exactly
	# right, since D20 says a client connects when Multiplayer is pressed rather
	# than at boot.
	# The MATCH role never goes near a lobby: there is not one. It takes the
	# place the announce would have, from a file, and moves straight to the port.
	if _role == "match":
		_drive_match_role(delta)
		return

	if !_browsing:
		# The JOIN probe deliberately dawdles, so the two peers do NOT start
		# their matches at the same instant. That stagger is what exposed the
		# priming bug and nothing else reproduces it.
		var wait: float = SETTLE_SECONDS * (3.0 if _role == "join" else 1.0)
		if _elapsed < wait:
			return
		_browsing = true
		Log.warn("PROBE opening the lobby browser")
		MenuNavigation.to_lobby_browser(self)
		return

	_apply_faults()
	# Before every early return below: a held-back report is owed whatever else
	# this role is doing, and the roles that hold one back are the ones that
	# otherwise have nothing to do while they wait.
	_advance_ready_delay(delta)

	if !_dialled:
		if References.network_config == null:
			return
		_dialled = true
		# The browser dials on its own as it opens (D20). Only step in if it
		# somehow has not, so this never fights it.
		if !Net.is_online():
			Log.warn("PROBE dialling")
			Net.join()
		return

	# The browser never enters a match on purpose. It just sits there being
	# connected, which is the whole experiment.
	if _role == "browse" || _role == "spoof":
		# **`spoof` is a HOSTILE browser**: connected, in no match, forging a turn
		# checksum every frame across the whole checksum range. It is the test for
		# the 2026-09-10 audit's critical finding - a relay that took a checksum
		# from anybody connected let a lobby browser end any match with one packet.
		# A sweep rather than one turn, so a forgery lands on a turn that really is
		# compared whenever this happens to connect.
		if _role == "spoof" && Net.is_online():
			Lockstep.report_turn_checksum.rpc_id(
				NetworkService.SERVER_PEER_ID, (_spoofs * 10) % 4000, 12345
			)
			# And a forged repair request, which must be refused the same way:
			# answered, it would make the relay send a match's orders to a peer
			# that is in no match at all.
			Lockstep.request_seals.rpc_id(
				NetworkService.SERVER_PEER_ID, PackedInt32Array([_spoofs % 400])
			)
			_spoofs += 1
		if _elapsed >= _play_seconds():
			_finish()
		return

	# Nothing to drive until the match is up.
	if !_in_match:
		if _elapsed > SETTLE_SECONDS * 20.0:
			Log.err("PROBE never got into a match")
			_finish()
		return

	if !_started:
		_started = true
		_elapsed = 0.0
		Log.warn("PROBE playing")
		return

	# A wedged machine sends NOTHING. Driving on would keep refreshing the
	# relay's liveness clock through `submit_order`, so the peer that has
	# visibly stopped playing would never be given up on - which is a fair
	# description of the machine but a useless simulation of one that has died.
	# `--drive-while-wedged` keeps pressing through a wedge, which is how the
	# 2026-09-10 give-up fix is exercised: a peer that has given up must not be
	# able to put another order on the wire however hard its player presses.
	_maybe_pause()
	# A paused world refuses every order but the pause pair, so driving through
	# one would only fill the log with refusals - and would test nothing the
	# gate in CommandService does not already answer.
	var drive_paused: bool = "--drive-while-paused" in OS.get_cmdline_user_args()
	var may_drive: bool = !_wedged || "--drive-while-wedged" in OS.get_cmdline_user_args()
	if (!_is_paused() || drive_paused) && may_drive:
		_drive()
	_maybe_corrupt()
	_maybe_wedge()
	_maybe_hitch()

	if _elapsed >= _play_seconds():
		_finish()


## DELIBERATELY pauses the match, on --pause <seconds>, and asks for it back
## `--pause-hold` seconds later. Run on the HOST only by default, so the peer
## that did not press anything is the one whose readings matter.
##
## **The positive control is `pause_turn` and `resume_turn` in the result line.**
## A run that reports -1 for either never reached the code under test, and two
## peers reporting different numbers have taken the pause on different turns -
## which is the one failure this whole design exists to prevent, and which a
## checksum alone would only catch later and blame on something else.
func _maybe_pause() -> void:
	var at: float = float(_int_argument("--pause", -1))
	if at < 0.0 || _role == "join":
		return

	if !_paused_asked && _elapsed >= at:
		_paused_asked = true
		Log.warn("PROBE pressing Pause")
		Commands.submit_player_action(Command.PlayerAction.PAUSE_MATCH)
		return

	var hold: float = float(_int_argument("--pause-hold", 4))
	if _paused_asked && !_resume_asked && _elapsed >= at + hold:
		_resume_asked = true
		Log.warn("PROBE pressing Unpause")
		Commands.submit_player_action(Command.PlayerAction.RESUME_MATCH)


func _is_paused() -> bool:
	var pause: MatchPause = References.match_pause
	return pause != null && pause.is_holding()


## Watches the world stop and start from OUTSIDE the class that stops it, on the
## turn boundary rather than on a frame, so the numbers two peers report are
## comparable at all.
func _watch_pause(turn: int) -> void:
	var now: bool = _is_paused()
	if now == _was_paused:
		return
	_was_paused = now
	if now:
		_pauses += 1
		if _pause_turn < 0:
			_pause_turn = turn
		Log.warn("PROBE saw the world stop", {"turn": turn})
		return
	if _resume_turn < 0:
		_resume_turn = turn
	Log.warn("PROBE saw the world move again", {"turn": turn})


## The test-only fault injectors, from the command line, on THIS process only:
##   --seal-loss <percent>   reliable seals thrown away on arrival
##   --echo-loss <percent>   echoes thrown away on arrival
##   --no-repair             seal repair switched off, for the paired run
##
## Applied every frame rather than once, because the config is a resource held by
## whichever scene is loaded, and the match scene is not the one the probe starts
## in. `--seal-loss 100 --echo-loss 20` is playtest 7's lost player on demand.
func _apply_faults() -> void:
	var config: NetworkConfig = References.network_config
	if config == null:
		return
	config.debug_seal_loss_percent = _int_argument("--seal-loss", 0)
	config.debug_echo_loss_percent = _int_argument("--echo-loss", 0)
	config.seal_repair_enabled = !("--no-repair" in OS.get_cmdline_user_args())


func _int_argument(flag: String, fallback: int) -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == flag && index + 1 < args.size():
			return int(args[index + 1])
	return fallback


## DELIBERATELY blocks this machine's whole main thread for most of a second, on
## --hitch <seconds>, repeatedly.
##
## **This is what playtest 1 actually measured**, and it is the scenario phase 4
## exists to fix: a peer whose FIRST spawn of each kind of content cost it
## 650-900 ms on the game thread, and which passed that freeze to the other
## player who was doing nothing wrong.
##
## `OS.delay_msec` blocks the thread rather than skipping a frame, so the engine
## really does miss its ticks the way a slow load does. A `set_physics_process`
## pause would not - the render frame would carry on and the rpcs would still
## flush, which is the opposite of what a stalled machine does.
##
## **The number that matters is the OTHER peer's `stalled_s`.** That asymmetry
## IS the design: the hitching machine must pay for its own hitch, and nobody
## else may pay anything at all.
func _maybe_hitch() -> void:
	var every: float = -1.0
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == "--hitch" && index + 1 < args.size():
			every = maxf(0.5, float(args[index + 1]))
	if every < 0.0 || _elapsed < every * float(_hitches + 1):
		return
	_hitches += 1
	Log.warn("PROBE hitching", {"ms": HITCH_MSEC, "n": _hitches})
	OS.delay_msec(HITCH_MSEC)


## DELIBERATELY wedges this peer's game loop while leaving its SOCKET open, on
## --wedge, which is the one failure the relay cannot see any other way.
##
## Stopping LockstepService's physics processing is an exact simulation of it:
## no heartbeat, no turn words, and the connection stays up because Godot polls
## the multiplayer API from the SceneTree rather than from any node. A hard kill
## does not reproduce this - ENet notices that in a few seconds and the relay
## starts speaking for the peer long before the silence timeout is reached, which
## is exactly why the bug this tests only showed up 2 runs in 5.
func _maybe_wedge() -> void:
	if _wedged:
		return
	var after: float = -1.0
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == "--wedge" && index + 1 < args.size():
			after = float(args[index + 1])
	if after < 0.0 || _elapsed < after:
		return
	_wedged = true
	Log.warn("PROBE wedging its game loop, socket left open")
	Lockstep.set_physics_process(false)


## DELIBERATELY breaks this machine's world, on --desync, so the desync PATH can
## be tested rather than hoped for.
##
## There is no other way to test it. A desync is by definition the thing that is
## not supposed to happen, so the only way to see what happens when it does is to
## cause one - and it has to be caused OUTSIDE the command road, or every peer
## would apply it identically and agree perfectly. One gold, on one machine, is
## enough: gold is in the world checksum.
func _maybe_corrupt() -> void:
	if _corrupted || !("--desync" in OS.get_cmdline_user_args()) || _elapsed < 12.0:
		return
	var manager: PlayerManager = References.player_manager
	var session: MatchSession = References.match_session
	if manager == null || session == null:
		return
	var state: PlayerState = manager.state_for(session.local_slot())
	if state == null:
		return
	_corrupted = true
	state.gold += 1
	Log.warn("PROBE deliberately corrupted this world", {"gold": state.gold})


## Orders, so the turns being exchanged carry something and the world diverges
## if anything is wrong. Cheats first: a fresh match has 40 gold and every creep
## behind its unlock delay, so nothing would send.
func _drive() -> void:
	var every: float = 1.0
	if _elapsed < every * float(_sent):
		return
	_sent += 1
	if Lockstep.has_given_up():
		_driven_after_giveup += 1

	if _sent <= 2:
		Commands.submit_player_action(Command.PlayerAction.CHEAT_GOLD)
		Commands.submit_player_action(Command.PlayerAction.CHEAT_UNLOCK_CREEPS)
		return
	_send_a_creep()


func _send_a_creep() -> void:
	var manager: PlayerManager = References.player_manager
	var session: MatchSession = References.match_session
	if manager == null || session == null:
		return
	var area: PlayerArea = manager.area_for(session.local_slot())
	if area == null:
		return

	var buildings: Array = area.send_buildings()
	if buildings.is_empty():
		return
	var building: SendBuilding = buildings[0] as SendBuilding
	if building == null || building.stats == null:
		return

	for entry: Variant in building.stats.abilities:
		if entry is SendCreepAbility:
			Commands.submit(entry as UnitAbility, [building], null)
			return


func _finish() -> void:
	Log.warn("PROBE RESULT", {
		"role": _role,
		"turns_run": _turns,
		"last_turn": _last_turn,
		"orders_applied": _orders,
		"stalls": _stalls,
		"stalled_s": snappedf(Lockstep.stalled_seconds(), 0.01),
		"desyncs": _desyncs,
		"hitches": _hitches,
		"drops_seen": _drops,
		"spoofs_sent": _spoofs,
		"driven_after_giveup": _driven_after_giveup,
		# The pause scenario. -1 means it never happened here; two peers must
		# report the same pair. See _maybe_pause.
		"pauses_seen": _pauses,
		"pause_turn": _pause_turn,
		"resume_turn": _resume_turn,
		# **The loading gate's positive controls.** `self_ready` false in a run
		# that was supposed to load means the gate was never reached, and
		# `reported_late` false on a `--ready-delay` probe means the delay was
		# never paid back - either way the run proves nothing about the gate,
		# however clean the rest of the line looks.
		"self_ready": _self_ready,
		"reported_late": _reported_late,
		# **The handoff's positive controls** (D44). `claims` above zero says a
		# seat was really claimed; `go_id` equal to `own_id` says the re-key ran,
		# and a run reporting 0 for either never exercised the handoff at all
		# however clean the rest of the line looks.
		"claims": _claims,
		"own_id": multiplayer.get_unique_id(),
		"go_id": _go_network_id,
		"move_attempts": Net.move_attempts(),
		"move_reason": _move_reason,
		"gave_up": Lockstep.has_given_up(),
		"lag_s": snappedf(Lockstep.sealed_lag_seconds(), 0.1),
		# **The positive control for the whole phase.** A run where `sealed` is
		# false measured nothing about the cutover however good the numbers
		# look, and `sealed_held` greater than zero is what proves seals were
		# actually being played rather than the flag merely being set.
		"sealed_held": Lockstep.sealed_held(),
		"echo": Lockstep.echo_recovery(),
		"echoes_dropped": Lockstep._echoes_dropped,
		# **The positive control for repair**: [asked, repaired]. A run that set out
		# to test repair and reports zero here never reached it.
		"repair": Lockstep.repair_counts(),
		"units": 0 if References.match_session == null \
			else References.match_session.unit_count(),
		# **Where this machine ended up, and what its status line says there** -
		# the positive control for a player thrown out of a match being TOLD why.
		# A lost server or a cancelled match must land in a menu whose status
		# still carries the reason after the browser has started dialling again.
		"scene": _scene_name(),
		"status": _status_text(),
	})
	get_tree().quit()


func _scene_name() -> String:
	var scene: Node = get_tree().current_scene
	return "" if scene == null else String(scene.name)


## The status line of whichever menu is on screen, on one line.
func _status_text() -> String:
	var scene: Node = get_tree().current_scene
	var label: Label = null
	var browser: LobbyBrowser = scene as LobbyBrowser
	if browser != null:
		label = browser._status_label
	var room: LobbyRoom = scene as LobbyRoom
	if room != null:
		label = room._status_label
	return "" if label == null else label.text.replace("\n", " | ")
