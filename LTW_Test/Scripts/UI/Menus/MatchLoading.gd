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
## The row prefab, shared with the lobby room: the same row, saying a different
## thing about the same player.
@export var _slot_scene: PackedScene

var _setup: MatchSetup = null
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
	var progress: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(_scene_path, progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if !progress.is_empty():
				_set_progress(float(progress[0]))
		ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			_set_progress(1.0)
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
	_set_status(reason)


## Losing the server mid-load ends the match before it began. The browser is
## where every connection failure already lives (1.8), and it dials again on
## the way in.
func _on_server_disconnected() -> void:
	set_process(false)
	MenuNavigation.pending_notice = "Lost connection to the server while loading."
	MenuNavigation.to_lobby_browser(self)


func _set_progress(ratio: float) -> void:
	if _progress_bar != null:
		_progress_bar.value = clampf(ratio, 0.0, 1.0) * 100.0


func _set_status(text_value: String) -> void:
	if _status_label != null:
		_status_label.text = text_value
