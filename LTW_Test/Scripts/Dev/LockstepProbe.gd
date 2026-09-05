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
## Does NOTHING when --probe is absent, so the editor, the server and every
## other run are unaffected by its presence.

const ROLE_ARGUMENT: String = "--probe"

## Long enough for a lobby to exist and the server to notice it.
const SETTLE_SECONDS: float = 2.0
## How long to play before reporting, overridable with --play <seconds> so a
## test that has to outlast the disconnect grace can say so.
const PLAY_SECONDS: float = 25.0

var _role: String = ""
var _elapsed: float = 0.0
var _started: bool = false
var _requested: bool = false
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


func _ready() -> void:
	_role = _read_role()
	if _role.is_empty():
		queue_free()
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	Log.warn("LockstepProbe starting", {"role": _role})

	Lockstep.turn_ready.connect(_on_turn_ready)
	Lockstep.turn_stalled.connect(_on_turn_stalled)
	MatchStart.desync_detected.connect(_on_desync)
	Lobby.current_lobby_changed.connect(_on_lobby_changed)
	Lobby.request_refused.connect(_on_refused)
	MatchStart.match_starting.connect(_on_match_starting)

	Net.connected_to_server.connect(_on_connected)
	Net.connection_failed.connect(_on_connect_failed)
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
	Log.warn("PROBE connected, registering")
	Lobby.register_player("Probe " + _role)
	# The host makes the lobby. The joiner waits for it to appear in the list,
	# because a lobby that does not exist yet cannot be joined and the two
	# processes are started a second apart at best.
	if _role == "host":
		Lobby.create("Probe match", 2)
	else:
		Lobby.lobby_list_changed.connect(_on_lobby_list)


func _on_connect_failed(_result: NetworkService.Result) -> void:
	Log.err("PROBE could not reach the server")
	_finish()


## The joiner takes the first lobby it sees that is not full and not already
## playing.
func _on_lobby_list(lobbies: Array[LobbyInfo]) -> void:
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
	})
	# Only the host may start, and only once the second player is really in -
	# the server refuses a one player match, which is the rule doing its job.
	if Lobby.is_host() && !_requested && lobby.player_count() >= 2:
		_requested = true
		Log.warn("PROBE starting the match")
		Lobby.start()


func _on_refused(reason: String) -> void:
	Log.err("PROBE refused: " + reason)


func _on_match_starting(_setup: MatchSetup) -> void:
	Log.warn("PROBE match starting")
	_in_match = true


# --- watching it ------------------------------------------------------------

func _on_turn_ready(turn: int, commands: Array) -> void:
	_turns += 1
	_last_turn = turn
	_orders += commands.size()


func _on_turn_stalled(turn: int, missing: PackedInt32Array) -> void:
	_stalls += 1
	if _stalls <= 3:
		Log.warn("PROBE stall", {"turn": turn, "missing": missing})


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

	_drive()
	_maybe_corrupt()

	if _elapsed >= _play_seconds():
		_finish()


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
		"desyncs": _desyncs,
		"units": 0 if References.match_session == null \
			else References.match_session.unit_count(),
	})
	get_tree().quit()
