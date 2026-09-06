class_name MatchLoading
extends Control

## The screen between the lobby and the match: this machine loading the game
## scene, and everybody else doing the same.
##
## It loads the scene through `ResourceLoader.load_threaded_request` rather than
## a plain `load()`, so the bar moves and the window keeps answering. A frozen
## frame with a spinner painted on it is not a loading screen.
##
## **Loading is not building.** This screen gets the PackedScene into memory and
## says so; the world is created afterwards, when the server sends the final
## roster. That order is forced by D15 - the server may start without a client
## that never answered, and "no player area spawns for a missing player" can
## only be true if nothing was placed before we knew who was missing. See
## MatchStartService.
##
## **It also warms the content**, which is the slower half of what it does and
## the reason the screen exists at all rather than being a frame of black. Every
## scene and sound the match can spawn is loaded here, so that no turn in the
## match ever pays for a first instantiation - under lockstep that cost lands on
## both players at the same turn and freezes them together. See `ContentWarmer`
## and `Findings/2026-09-06-playtest-1-freezes.md`.
##
## Warming happens BEFORE this machine reports itself loaded, deliberately. The
## whole point is that nobody starts until everybody is warm; reporting first and
## warming afterwards would race the match start against the loading it exists to
## get out of the way.
##
## It owns no state of its own. Who is in the match and who has loaded both
## come off the `MatchStart` autoload, which outlives this scene and the next.

@export_group("References")
@export var _title_label: Label
@export var _subtitle_label: Label
@export var _progress_bar: ProgressBar
@export var _status_label: Label
## Parent for the player rows, rebuilt whenever the readiness list changes.
@export var _slot_list: VBoxContainer

@export_group("Settings")
## What loading the game scene is worth on the bar, with warming the content
## worth the rest. Roughly the measured split on the machine this was written
## on - a bar that spends most of its travel on the shorter half looks stuck.
@export_range(0.1, 0.9, 0.05) var scene_share: float = 0.4
## How long warming may take before the screen gives up and joins the match
## anyway. A warm that never finishes must not cost somebody their match: the
## worst case without this is that the server starts without them (D15), which
## is a far worse outcome than the freezes warming was avoiding.
@export var warm_timeout_seconds: float = 20.0

## The row prefab, shared with the lobby room: the same row, saying a different
## thing about the same player.
@export var _slot_scene: PackedScene

var _setup: MatchSetup = null
## Non-null only while warming, which is also what tells _process which of its
## two jobs it is doing.
var _warmer: ContentWarmer = null
var _warm_started_msec: int = 0
## Held so the scene stays in the cache until the change of scene, which would
## otherwise load it a second time.
var _scene: PackedScene = null
var _scene_path: String = ""

var _config: MenuConfig:
	get:
		return References.menu_config


func _ready() -> void:
	set_process(false)
	_setup = MatchStart.setup()
	if _setup == null:
		# Reachable by running this scene on its own from the editor. There is
		# nothing to load and nothing to wait for, so it says so and leaves.
		Log.warn("MatchLoading opened with no match, going back to the browser")
		MenuNavigation.to_lobby_browser(self)
		return

	MatchStart.readiness_changed.connect(_on_readiness_changed)
	MatchStart.match_cancelled.connect(_on_match_cancelled)
	Net.disconnected_from_server.connect(_on_server_disconnected)

	if _title_label != null:
		_title_label.text = "Loading Match"
	if _subtitle_label != null:
		_subtitle_label.text = "Free for all  -  %d players" % _setup.player_count()

	_build_rows()
	_set_progress(0.0)
	_begin_loading()


## Asks for the game scene in the background. A failure here is not fatal to
## anybody else: this client simply never reports loaded, and the server starts
## without it once the timeout runs out (D15).
func _begin_loading() -> void:
	if _config == null:
		Log.err("MatchLoading found no MenuConfig on References, it has nothing to load")
		_set_status("Cannot load the match: no menu configuration.")
		return

	_scene_path = _config.game_scene_path
	if !SceneUtil.exists(_scene_path):
		Log.err("MatchLoading cannot load the game scene", _scene_path)
		_set_status("Cannot load the match: the game scene is missing.")
		return

	var error: Error = ResourceLoader.load_threaded_request(_scene_path, "PackedScene")
	if error != OK:
		Log.err("MatchLoading could not start the load", {
			"path": _scene_path,
			"error": error,
		})
		_set_status("Cannot load the match: the load would not start.")
		return

	_set_status("Loading the match...")
	set_process(true)


## Polling rather than a signal because that is the only interface a threaded
## load has. Deliberately _process and not _physics_process: there is no
## simulation on this screen, and the bar has to move on a render frame.
func _process(_delta: float) -> void:
	if _warmer != null:
		_advance_warming()
		return

	var progress: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(_scene_path, progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if !progress.is_empty():
				_set_progress(float(progress[0]) * scene_share)
		ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			_set_progress(scene_share)
			_scene = ResourceLoader.load_threaded_get(_scene_path) as PackedScene
			_on_scene_loaded()
		_:
			set_process(false)
			Log.err("MatchLoading failed to load the game scene", _scene_path)
			_set_status("Failed to load the match.")


func _on_scene_loaded() -> void:
	if _scene == null:
		Log.err("MatchLoading loaded the game scene as something that is not a PackedScene")
		_set_status("Failed to load the match.")
		return

	Log.info("Match scene loaded", {"match": _setup.match_id, "path": _scene_path})
	_begin_warming()


# --- warming the content --------------------------------------------------

## Loads everything the match can spawn, so the match itself never has to.
##
## A failure here is never fatal: every path out of this ends in
## `_report_loaded`, because a player who cannot warm should still get to play
## with the freezes rather than not play at all.
func _begin_warming() -> void:
	var content: ContentConfig = References.content_config
	if content == null:
		Log.err("MatchLoading found no ContentConfig on References, nothing can be warmed")
		_report_loaded({})
		return

	_warmer = ContentWarmer.new()
	_warm_started_msec = Time.get_ticks_msec()
	_warmer.begin(PackedStringArray([
		content.unit_stats_folder, content.shared_config_folder,
	]))
	_set_status("Preparing the world...")
	set_process(true)


func _advance_warming() -> void:
	_warmer.advance()
	_set_progress(scene_share + (1.0 - scene_share) * _warmer.ratio())

	var seconds: float = float(Time.get_ticks_msec() - _warm_started_msec) / 1000.0
	if !_warmer.is_finished() && seconds < warm_timeout_seconds:
		return

	if !_warmer.is_finished():
		Log.warn("Content warming did not finish in time, starting anyway", {
			"seconds": warm_timeout_seconds,
			"so_far": _warmer.report(),
		})

	set_process(false)
	var report: Dictionary = _warmer.report()
	_warmer = null
	_report_loaded(report)


## The one place this screen says it is ready, whatever happened on the way.
func _report_loaded(warm_report: Dictionary) -> void:
	_set_progress(1.0)
	SessionLog.note("match.warmed", warm_report)
	MatchStart.report_loaded()
	_set_status("Ready. Waiting for the other players...")
	_build_rows()


# --- the other players ----------------------------------------------------

func _on_readiness_changed(_ready_ids: PackedInt32Array) -> void:
	_build_rows()


func _build_rows() -> void:
	if _slot_list == null || _slot_scene == null:
		Log.err("MatchLoading cannot build rows, the list or the row prefab is missing")
		return

	for child in _slot_list.get_children():
		_slot_list.remove_child(child)
		child.queue_free()

	var ready_ids: PackedInt32Array = MatchStart.ready_ids()
	for player in _setup.players:
		if player == null:
			continue
		var slot: LobbySlot = _slot_scene.instantiate() as LobbySlot
		if slot == null:
			Log.err("MatchLoading row prefab root does not have a LobbySlot script")
			return
		_slot_list.add_child(slot)
		_fill_row(slot, player, ready_ids.has(player.network_id))


func _fill_row(slot: LobbySlot, player: MatchPlayer, is_loaded: bool) -> void:
	# Two client windows on one machine look identical, so say which is which.
	var label: String = player.display_name
	var is_local: bool = player.network_id == Net.peer_id()
	if is_local:
		label += "  (you)"
	slot.show_status(player.slot, label, "Ready" if is_loaded else "Loading...", is_local)


# --- the ways this screen ends other than by starting ---------------------

## Handled here as well as by MatchStart, because the message is worth showing
## for the frame before the scene changes.
func _on_match_cancelled(reason: String) -> void:
	set_process(false)
	_warmer = null
	_set_status(reason)


## Losing the server mid-load ends the match before it began. The browser is
## where every connection failure already lives (1.8), and it dials again on
## the way in.
func _on_server_disconnected() -> void:
	set_process(false)
	_warmer = null
	MenuNavigation.pending_notice = "Lost connection to the server while loading."
	MenuNavigation.to_lobby_browser(self)


func _set_progress(ratio: float) -> void:
	if _progress_bar != null:
		_progress_bar.value = clampf(ratio, 0.0, 1.0) * 100.0


func _set_status(text_value: String) -> void:
	if _status_label != null:
		_status_label.text = text_value
