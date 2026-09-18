class_name SceneUtil

## Loading a scene that a resource named by PATH rather than held as a
## PackedScene.
##
## Resources name their scenes by path, never as a PackedScene @export. A
## PackedScene inside a .tres is a HARD load-time dependency, and Godot's text
## loader aborts the WHOLE resource when a single ext_resource is missing. One
## deleted projectile prefab therefore takes down the entire stats file that
## referenced it, and every property on it reads null - including, three levels
## up, an unrelated tower's stats. That failure is silent and points nowhere
## near the file that actually went missing.
##
## A path is a soft dependency: it fails loudly, on its own, at the point of
## use, and takes nothing else with it. It also makes a reference cycle
## impossible, which is what lets a stats resource name its own prefab while
## that prefab points back at the stats through its own @export.
##
## The cost is that the editor does NOT rewrite a path string when a scene is
## moved or renamed. That is what the validate() pass on the stats resources is
## for: every dead path is reported together at boot, rather than one at a time
## by whichever player first presses the button.
##
## NODES keep plain PackedScene @exports. A node's scenes are its own assets,
## they are wired in the same .tscn the editor maintains, and the editor does
## keep those references up to date.


## Scenes asked for BEFORE anybody needs them, held for the life of the process
## so that nothing loaded ahead of time is freed again before the button that
## wants it is pressed. Keyed by res:// path.
static var _prewarmed: Dictionary = {}
## Paths whose background load has been asked for and not yet collected.
static var _prewarming: Dictionary = {}


## Whether a path points at something that can actually be loaded. Empty reads
## as false, so an optional path has to be tested for emptiness first.
static func exists(path: String) -> bool:
	return !path.is_empty() && ResourceLoader.exists(path)


## The scene at a path, or null with one error naming whoever asked for it.
##
## Keeps no cache of its own. Callers that ask more than once hold the result,
## and Godot's ResourceLoader keeps a loaded scene alive while anything still
## references it, so a second caller for the same path pays nothing.
static func load_scene(path: String, owner_name: String = "") -> PackedScene:
	if path.is_empty():
		Log.err("Scene path is empty", owner_name)
		return null

	if !ResourceLoader.exists(path):
		Log.err("Scene path does not resolve", {"path": path, "owner": owner_name})
		return null

	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		Log.err("Scene path did not load as a PackedScene", {
			"path": path,
			"owner": owner_name,
		})
	return scene


## Starts loading a scene in the background, so whoever opens it later pays
## nothing for it.
##
## **This is what makes a menu button feel pressed.** `change_scene_to_file`
## loads the scene SYNCHRONOUSLY, inside the press, before a single pixel of the
## new screen can be drawn - so what a player sees after clicking Start is the
## OLD screen holding still for however long the disk takes, and the loading
## screen, the one thing that exists to say "something is happening", is the
## screen that arrives late. A loading screen cannot report its own loading.
##
## Warm on a dev machine that is tens of milliseconds and invisible. It is not
## invisible everywhere: `ContentWarmer` measured a tester reading a freshly
## downloaded build at a hundred times the per-asset cost of the machine it was
## written on, most likely a first read being scanned - and this is the one
## load in the game that is paid with nothing on screen.
##
## Asking early costs nothing and needs no ordering. Godot loads it on a worker
## thread, and `change_scene` for a path still in flight waits for that same
## load rather than starting a second one - so the worst case is exactly
## today's behaviour and the usual case is a swap that costs a frame.
static func prewarm(path: String) -> void:
	if path.is_empty() || _prewarmed.has(path) || _prewarming.has(path):
		return
	if !ResourceLoader.exists(path):
		Log.err("Cannot prewarm a scene that does not resolve", path)
		return

	var error: Error = ResourceLoader.load_threaded_request(path, "PackedScene")
	if error != OK:
		# Never fatal: the scene is simply loaded the old way when it is opened.
		Log.warn("Could not start a background load", {"path": path, "error": error})
		return
	_prewarming[path] = true


## Opens a scene, reporting every way it can fail rather than leaving the
## player looking at a screen whose buttons did nothing.
##
## One implementation, because there are now two callers with the same
## requirement: MenuNavigation for every menu button, and Boot for the very
## first scene change of the process. owner_name says who asked, since the
## caller is the useful half of the message.
static func change_scene(from: Node, path: String, owner_name: String = "") -> bool:
	if !exists(path):
		Log.err("Cannot open a scene that does not resolve", {
			"path": path,
			"owner": owner_name,
		})
		return false

	var tree: SceneTree = from.get_tree()
	if tree == null:
		Log.err("Cannot change scene, the caller is not in the tree", {
			"caller": from.name,
			"owner": owner_name,
		})
		return false

	# A scene asked for ahead of time is already in memory, so the press pays
	# nothing for it. Anything else is loaded here and now, which is what
	# change_scene_to_file was doing anyway.
	var error: Error = OK
	var ready_made: PackedScene = _take_prewarmed(path)
	if ready_made != null:
		error = tree.change_scene_to_packed(ready_made)
	else:
		error = tree.change_scene_to_file(path)
	if error != OK:
		Log.err("Failed to change scene", {
			"path": path,
			"error": error,
			"owner": owner_name,
		})
		return false
	return true


## The prewarmed scene for a path, or null if nobody asked for one.
##
## Collects a load that has not finished yet, which BLOCKS - deliberately. The
## caller is changing scene to it either way, so the choice is between waiting
## for a load already running and starting a second one beside it.
##
## Kept rather than handed over, because a screen is opened more than once: the
## way back to the main menu is the same swap as the way out of it.
static func _take_prewarmed(path: String) -> PackedScene:
	if _prewarmed.has(path):
		return _prewarmed[path] as PackedScene
	if !_prewarming.has(path):
		return null

	_prewarming.erase(path)
	var scene: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
	if scene == null:
		Log.err("A background load did not produce a PackedScene", path)
		return null
	_prewarmed[path] = scene
	return scene
