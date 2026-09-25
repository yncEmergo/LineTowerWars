class_name Boot
extends Control

## The first scene the process opens, and the only place that decides whether
## this process is a client or a dedicated server.
##
## One line of code makes that choice - OS.has_feature("dedicated_server") -
## and it reads the same in the editor and in an exported build. The editor's
## Debug > Customize Run Instances gives each instance its own feature tags, so
## tagging one instance dedicated_server boots it as the server with no
## if-debug-build special case anywhere. See multiplayer.md.
##
## Nothing downstream learns the choice was made. The menus never hear about a
## server, and the server never loads a menu.
##
## It is a Control rather than a plain Node only so the one frame before the
## real scene arrives is the menu's own background instead of the engine's
## default clear colour.

## The autoload name the godot_ai addon registers its runtime helper under. See
## _drop_editor_helper.
const EDITOR_HELPER_NAME: String = "_mcp_game_helper"

var _config: BootConfig:
	get:
		return References.boot_config

var _menus: MenuConfig:
	get:
		return References.menu_config


## Whether this process should run as a dedicated server.
##
## The feature tag is the real answer and the one an exported server build
## carries. The launch argument exists for the cases a tag cannot cover: a
## second server on another port, or forcing the role on a machine whose tags
## are not ours to set.
##
## How an argument actually reaches this process - the "--" separator, and the
## two spellings that have to be accepted - is CommandLineUtil's problem, not
## this one's.
static func is_dedicated_server(config: BootConfig) -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	if config == null:
		return false
	# A MATCH PROCESS is a dedicated server too, and has to be said separately:
	# `--match-server` does not match `--server`, so without this line a match
	# process would boot as a CLIENT and walk into the main menu.
	return config.is_match_server() || CommandLineUtil.has_flag(config.server_argument)


## Deferred by one idle frame, and it has to be: the tree is still in the middle
## of adding this scene while the root node's _ready runs, so replacing it right
## there makes Godot refuse the remove_child with "parent node is busy". The
## scene change still happens, but it complains on the way, and a boot that
## prints an error is a boot nobody trusts.
func _ready() -> void:
	_dispatch.call_deferred()


func _dispatch() -> void:
	var config: BootConfig = _config
	if config == null:
		Log.err("Boot found no BootConfig on References, this process can only be a client")
	else:
		# Once, here, rather than when the dispatch tries to open a dead path
		# and the process has nowhere to go.
		config.validate()

	if is_dedicated_server(config):
		# Before the scene, and for a match process too: the helper holds every
		# log line for a debugger that never attaches, which on a box running
		# many match processes is the same leak multiplied by the cap.
		_drop_editor_helper()
		if config != null && config.is_match_server():
			_open("match-server", config.match_server_scene_path)
		else:
			_open("server", _server_scene_path(config))
	else:
		# Here rather than in the options screen alone, so a player who chose
		# fullscreen last time gets it before the menu's first frame instead of
		# watching a window flash and then resize. The server branch never asks:
		# it has no window, and nothing a player wrote in a file may reshape it.
		UserSettings.apply_window_mode()
		# Same terms as the window above: a player who turned the music down
		# last time gets it down before the menu's first sound rather than
		# after it, and the server branch never asks because it has no output
		# device and nothing a player wrote in a file may quieten it.
		UserSettings.apply_volumes()
		_start_logging()
		var entry: String = _client_scene_path()
		_prewarm_menus(entry)
		_open("client", entry)


## Takes the godot_ai addon's runtime helper out of a dedicated server.
##
## **It is an editor tool, and on a server it is a memory leak anybody can
## drive.** The helper ferries this process's log to an attached editor and holds
## every line until one drains it - but it only drains while a debugger is
## attached, and a server under systemd never has one. So every log line, and
## every rpc the engine refuses from any connected peer, was kept for the life of
## the process: about a kilobyte a line and four to six per refusal, on a box
## with no swap. See Findings/2026-09-25-one-server-many-matches.md.
##
## Removed here, at runtime, because the addon puts its autoload back into
## project.godot every time the editor runs, so deleting the line would not
## stick. Freeing the node runs its own _exit_tree, which detaches the logger.
## Exports never had it: the addon strips it from them itself.
func _drop_editor_helper() -> void:
	var helper: Node = get_tree().root.get_node_or_null(EDITOR_HELPER_NAME)
	if helper == null:
		return
	helper.queue_free()
	Log.info("Editor helper removed from the dedicated server", {"node": EDITOR_HELPER_NAME})


## Every OTHER menu screen, loaded on a worker thread while this one opens the
## first of them.
##
## The point is the LOADING SCREEN and the press that opens it. A menu button is
## the one place in the game where a player gets no feedback whatsoever until
## the next screen is up, because the scene it opens is loaded inside the press
## - and the screen that arrives late is the one that would have said "loading".
## The rest of the menus ride along because they are the same swap and cost
## nothing to ask for. See SceneUtil.prewarm.
##
## The entry scene is skipped: it is loaded synchronously a line later, so
## asking a worker for it too would only add a handoff.
##
## A CLIENT ONLY. The server opens one scene, has no menus, and has nobody
## sitting in front of it waiting for a button to answer.
func _prewarm_menus(entry_path: String) -> void:
	if _menus == null:
		return
	for path: String in _menus.menu_scene_paths():
		if path == entry_path:
			continue
		SceneUtil.prewarm(path)


## What a client's logs record from here on. A client only: the server's log is
## the journal, which stamps every line itself.
##
## **Timestamps on the Godot log**, in milliseconds since the process began. It
## had none, so in playtest 8 the only lines that could be lined up with the
## session log beside it were the few that happened to carry a turn number. The
## session log's header writes the same clock's reading when it opens, which is
## what joins the two files.
##
## Stamped here rather than in project.godot so the editor, which keeps its own
## copy of the project settings, cannot quietly write it back out.
func _start_logging() -> void:
	Log.show_timestamps()
	Log.use_timestamp_type(Log.TimestampTypes.TICKS_MSEC)
	SessionLog.start_by_default()


## The server's entry scene, named by BootConfig.
func _server_scene_path(config: BootConfig) -> String:
	if config == null:
		return ""
	return config.server_scene_path


## The client's entry scene: the main menu, read from MenuConfig rather than
## copied into BootConfig, so a renamed menu scene has one file to fix.
func _client_scene_path() -> String:
	if _menus == null:
		Log.err("Boot found no MenuConfig on References, a client has nowhere to start")
		return ""
	return _menus.main_menu_scene_path


## The log line carries the EVIDENCE, not just the verdict. "role: client" on its
## own cannot tell you whether the tag was absent or the argument was misspelled,
## and that is exactly the question asked when an instance boots as the wrong
## thing. Both inputs are right there next to the answer.
func _open(role: String, path: String) -> void:
	Log.info("Boot dispatching", {
		"role": role,
		"scene": path,
		"tag": OS.has_feature("dedicated_server"),
		"args": OS.get_cmdline_user_args(),
		"headless": DisplayServer.get_name() == "headless",
	})
	if !SceneUtil.change_scene(self, path, "Boot"):
		Log.err("Boot could not open the entry scene, the process has nowhere to go", {
			"role": role,
			"scene": path,
		})
