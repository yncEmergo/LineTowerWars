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
	return CommandLineUtil.has_flag(config.server_argument)


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
		_open("server", _server_scene_path(config))
	else:
		# Here rather than in the options screen alone, so a player who chose
		# fullscreen last time gets it before the menu's first frame instead of
		# watching a window flash and then resize. The server branch never asks:
		# it has no window, and nothing a player wrote in a file may reshape it.
		UserSettings.apply_window_mode()
		_open("client", _client_scene_path())


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
