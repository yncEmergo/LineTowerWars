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

	var error: Error = tree.change_scene_to_file(path)
	if error != OK:
		Log.err("Failed to change scene", {
			"path": path,
			"error": error,
			"owner": owner_name,
		})
		return false
	return true
